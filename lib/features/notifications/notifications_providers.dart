import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/prefs.dart';
import '../../data/notifications/app_notification.dart';
import '../../data/notifications/local_notifier.dart';
import '../../data/supabase/notifications_repository.dart';
import '../../data/supabase/supabase_providers.dart';
import '../tenant/tenant_providers.dart';

/// The server's key for the order feed. Kitchen and inventory roles are seeded
/// without it — they have the KDS and the store room, not the floor.
const notificationsViewKey = 'notifications.view';

final canSeeNotificationsProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider(notificationsViewKey)),
);

// --- Device preferences ------------------------------------------------------
//
// Per device, like printing: a manager's phone and the counter tablet share an
// account, and only one of them should be buzzing.

const _mutedKey = 'notifications_muted';
const _promptAnsweredKey = 'notifications_prompt_answered';
const _denialsKey = 'notifications_denials';

/// Silence this phone without touching the OS permission. The feed and the
/// bell keep working; only the banner and sound stop.
///
/// Same shape as `PrintEnabled`: `build()` returns the decided value and never
/// assigns `state` from inside itself.
class AlertsMuted extends Notifier<bool> {
  bool? _value;

  @override
  bool build() {
    final decided = _value;
    if (decided != null) return decided;
    final prefs = ref.watch(sharedPreferencesProvider).valueOrNull;
    if (prefs == null) return false;
    return _value = prefs.getBool(_mutedKey) ?? false;
  }

  Future<void> set(bool value) async {
    _value = value;
    state = value;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setBool(_mutedKey, value);
  }
}

final alertsMutedProvider = NotifierProvider<AlertsMuted, bool>(
  AlertsMuted.new,
);

/// The OS permission as it stands. Invalidated on resume — the user may be
/// coming back from the phone's settings having flipped it.
final alertPermissionProvider = FutureProvider<AlertPermission>((ref) async {
  final notifier = ref.watch(localNotifierProvider);
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return resolveAlertPermission(
    enabled: await notifier.isEnabled(),
    denials: prefs.getInt(_denialsKey) ?? 0,
    isIOS: Platform.isIOS,
  );
});

/// Asking for, and remembering answers about, the OS permission.
class AlertSetup {
  const AlertSetup(this._ref);

  final Ref _ref;

  /// Whether this device has already had the "turn on alerts?" question,
  /// either answer. Asked once — Settings → Notifications is the way back
  /// after that, so nobody is nagged on every launch.
  Future<bool> promptAnswered() async {
    final prefs = await _ref.read(sharedPreferencesProvider.future);
    return prefs.getBool(_promptAnsweredKey) ?? false;
  }

  Future<void> markPromptAnswered() async {
    final prefs = await _ref.read(sharedPreferencesProvider.future);
    await prefs.setBool(_promptAnsweredKey, true);
  }

  /// Ask the OS. Counts a refusal so the next check knows whether the OS will
  /// still show its prompt, and records that the question has been asked.
  Future<AlertPermission> request() async {
    final prefs = await _ref.read(sharedPreferencesProvider.future);
    final granted = await _ref.read(localNotifierProvider).requestPermission();
    if (!granted) {
      await prefs.setInt(_denialsKey, (prefs.getInt(_denialsKey) ?? 0) + 1);
    }
    await prefs.setBool(_promptAnsweredKey, true);
    _ref.invalidate(alertPermissionProvider);
    return _ref.read(alertPermissionProvider.future);
  }

  /// "Turn on" from settings: the OS prompt while it will still show, the
  /// phone's own settings once it will not.
  Future<AlertPermission> enable() async {
    final current = await _ref.read(alertPermissionProvider.future);
    if (current == AlertPermission.granted) return current;
    if (current == AlertPermission.notAsked) {
      final after = await request();
      if (after != AlertPermission.blocked) return after;
    }
    await _ref.read(localNotifierProvider).openSettings();
    return AlertPermission.blocked;
  }
}

final alertSetupProvider = Provider<AlertSetup>(AlertSetup.new);

// --- The feed ----------------------------------------------------------------

class NotificationFeed {
  const NotificationFeed({required this.items, this.lastReadAt, this.userId});

  static const empty = NotificationFeed(items: []);

  /// Newest first, capped at 50.
  final List<AppNotification> items;

  /// This user's cursor. Anything newer is unread.
  final DateTime? lastReadAt;

  /// Whose feed this is — their own actions never count as unread.
  final String? userId;

  int get unread => unreadCount(items, lastReadAt, userId: userId);

  bool isUnreadRow(AppNotification n) =>
      isUnread(n, lastReadAt, userId: userId);

  NotificationFeed copyWith({
    List<AppNotification>? items,
    DateTime? lastReadAt,
  }) => NotificationFeed(
    items: items ?? this.items,
    lastReadAt: lastReadAt ?? this.lastReadAt,
    userId: userId,
  );
}

/// The later of two cursors — a refetch that read the cursor before a "Mark
/// all read" committed must not put the badge back.
DateTime? laterCursor(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}

/// The feed for the active restaurant, and the thing that raises OS alerts.
///
/// Long-lived: `NotifyLoop` keeps it listened above the router, so it runs
/// whichever screen is open. It rebuilds — closing the old channel and opening
/// a new one — only when the tenant id, the user id, or the permission moves.
/// It watches ids via `select`, not whole objects: `Membership` is rebuilt on
/// every token refresh and connectivity flip, and rebuilding on those tore the
/// channel down mid-service. The token itself needs no rebuild — supabase-dart
/// calls `realtime.setAuth` on refresh.
///
/// Every async write is tagged with the build generation it belongs to, so a
/// slow response from a previous tenant (or a superseded build) is dropped
/// rather than painted over the current feed.
///
/// Only Realtime arrivals alert. The initial fetch is history, not news.
class NotificationFeedNotifier extends AsyncNotifier<NotificationFeed> {
  /// Ids already raised on this device, so a reconnect replay or a rebuild
  /// does not buzz twice for one event. Survives rebuilds: Riverpod keeps the
  /// notifier instance.
  final _alerted = <String>{};

  /// Arrivals that beat the first successful fetch. Merged in once one lands.
  final _early = <AppNotification>[];
  bool _loaded = false;
  int _gen = 0;

  @override
  Future<NotificationFeed> build() async {
    final tenantId = ref.watch(activeTenantProvider.select((m) => m?.tenantId));
    final userId = ref.watch(currentUserProvider.select((u) => u?.id));
    final allowed = ref.watch(canSeeNotificationsProvider);
    final gen = ++_gen;
    _loaded = false;
    _early.clear();
    if (_alerted.length > 500) _alerted.clear();
    if (tenantId == null || userId == null || !allowed) {
      return NotificationFeed.empty;
    }

    final repo = ref.watch(notificationsRepositoryProvider(tenantId));

    // Subscribe before fetching, so alerts work even when the fetch fails
    // (poor coverage mid-service) and nothing lands in the gap between them.
    final sub = repo
        .inserts(onRejoin: () => unawaited(refresh()))
        .listen((n) => _onInsert(n, gen: gen, userId: userId));
    ref.onDispose(sub.cancel);

    final (items, lastReadAt) = await (
      repo.latest(),
      repo.lastReadAt(userId),
    ).wait;
    if (gen != _gen) return NotificationFeed.empty; // Superseded; discarded.

    return _land(items, lastReadAt, userId);
  }

  /// A successful fetch: fold in whatever arrived meanwhile, and from here on
  /// merge arrivals straight into state.
  NotificationFeed _land(
    List<AppNotification> fetched,
    DateTime? lastReadAt,
    String userId,
  ) {
    var merged = fetched;
    for (final n in _early) {
      merged = mergeIncoming(merged, n);
    }
    _early.clear();
    _loaded = true;
    return NotificationFeed(
      items: merged,
      lastReadAt: lastReadAt,
      userId: userId,
    );
  }

  void _onInsert(
    AppNotification n, {
    required int gen,
    required String userId,
  }) {
    if (gen != _gen) return;
    if (_alerted.add(n.id) &&
        shouldAlert(n, currentUserId: userId) &&
        !ref.read(alertsMutedProvider)) {
      // Currency read at alert time: it is not a rebuild trigger.
      final currency = ref.read(activeTenantProvider)?.currency ?? '';
      unawaited(
        ref.read(localNotifierProvider).show(n, detail: n.detail(currency)),
      );
    }

    final current = state.valueOrNull;
    if (!_loaded || current == null) {
      if (_early.length < 50) _early.add(n);
      return;
    }
    state = AsyncData(current.copyWith(items: mergeIncoming(current.items, n)));
  }

  /// Re-read the list and the cursor without tearing down the channel —
  /// pull-to-refresh, resuming after iOS suspended the socket, and a realtime
  /// rejoin. Merges rather than replaces, so arrivals and an optimistic "mark
  /// read" made while it was in flight survive.
  Future<void> refresh() async {
    final gen = _gen;
    final tenantId = ref.read(activeTenantProvider)?.tenantId;
    final userId = ref.read(currentUserProvider)?.id;
    if (tenantId == null || userId == null) return;
    if (!ref.read(canSeeNotificationsProvider)) return;
    final repo = ref.read(notificationsRepositoryProvider(tenantId));
    try {
      final (items, lastReadAt) = await (
        repo.latest(),
        repo.lastReadAt(userId),
      ).wait;
      if (gen != _gen) return;
      final current = state.valueOrNull;
      if (!_loaded || current == null) {
        // First success after a failed build: this is the initial load.
        state = AsyncData(_land(items, lastReadAt, userId));
        return;
      }
      var merged = items;
      for (final n in current.items.reversed) {
        merged = mergeIncoming(merged, n);
      }
      state = AsyncData(
        NotificationFeed(
          items: merged,
          lastReadAt: laterCursor(current.lastReadAt, lastReadAt),
          userId: userId,
        ),
      );
    } catch (e, st) {
      if (gen != _gen) return;
      // A feed already on screen stays: the rows are still true.
      if (state.hasValue) return;
      state = AsyncError(e, st);
    }
  }

  /// Everything read. Painted at once; the server's timestamp replaces the
  /// optimistic one when it answers. A failure puts only the cursor back —
  /// rows that arrived meanwhile stay — and rethrows so the screen can say so.
  Future<void> markAllRead() async {
    final gen = _gen;
    final tenantId = ref.read(activeTenantProvider)?.tenantId;
    final before = state.valueOrNull;
    if (tenantId == null || before == null || before.items.isEmpty) return;

    state = AsyncData(
      before.copyWith(lastReadAt: before.items.first.createdAt),
    );
    try {
      final at = await ref
          .read(notificationsRepositoryProvider(tenantId))
          .markAllRead();
      if (gen != _gen) return;
      final now = state.valueOrNull;
      if (now != null) state = AsyncData(now.copyWith(lastReadAt: at));
    } catch (_) {
      if (gen != _gen) rethrow;
      final now = state.valueOrNull;
      if (now != null) {
        state = AsyncData(
          NotificationFeed(
            items: now.items,
            lastReadAt: before.lastReadAt,
            userId: now.userId,
          ),
        );
      }
      rethrow;
    }
  }
}

final notificationFeedProvider =
    AsyncNotifierProvider<NotificationFeedNotifier, NotificationFeed>(
      NotificationFeedNotifier.new,
    );

/// The badge on the bell. Zero while loading or without the key — a bell
/// that flickers a number it then loses is worse than one that is quiet.
final unreadNotificationsProvider = Provider<int>((ref) {
  if (!ref.watch(canSeeNotificationsProvider)) return 0;
  return ref.watch(notificationFeedProvider).valueOrNull?.unread ?? 0;
});
