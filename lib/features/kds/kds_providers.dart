import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase/kds_repository.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../data/sync/order_queue.dart';
import '../../data/sync/sync_providers.dart';
import '../tenant/tenant_providers.dart';
import 'kds_constants.dart';

final _kdsRepoProvider = Provider<KdsRepository?>((ref) {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return null;
  return ref.watch(kdsRepositoryProvider(tenant.tenantId));
});

final kitchenStationsProvider = FutureProvider<List<KitchenStation>>((
  ref,
) async {
  final repo = ref.watch(_kdsRepoProvider);
  if (repo == null) return const [];
  return repo.stations();
});

/// Which station this screen is showing.
///
/// Persisted per device, because a kitchen screen is bolted to one section: it
/// should reboot into the grill's board, not into "everything". `null` means
/// all stations; `expo` means the tickets with no station of their own.
const kdsAllStations = '';
const kdsExpo = 'expo';
const _stationKey = 'kds_station';

class KdsStationFilter extends Notifier<String> {
  @override
  String build() {
    ref.listen(_prefsProvider, (_, next) {
      final prefs = next.valueOrNull;
      if (prefs != null && state == kdsAllStations) {
        state = prefs.getString(_stationKey) ?? kdsAllStations;
      }
    }, fireImmediately: true);
    return kdsAllStations;
  }

  Future<void> select(String station) async {
    state = station;
    final prefs = await ref.read(_prefsProvider.future);
    await prefs.setString(_stationKey, station);
  }
}

final _prefsProvider = FutureProvider<SharedPreferences>(
  (ref) => SharedPreferences.getInstance(),
);

final kdsStationProvider = NotifierProvider<KdsStationFilter, String>(
  KdsStationFilter.new,
);

/// The board.
///
/// Live off the same authed socket as the rest of the app — the token must be
/// set or RLS drops every event and the board merely looks "not live". Events
/// are debounced into a scoped refetch rather than merged row by row: the query
/// joins stations, orders, tables and modifiers, so a payload row is not a
/// ticket.
class KdsTicketsNotifier extends AsyncNotifier<List<KdsTicket>> {
  RealtimeChannel? _channel;
  Timer? _debounce;

  @override
  Future<List<KdsTicket>> build() async {
    final repo = ref.watch(_kdsRepoProvider);
    if (repo == null) return const [];

    _subscribe(ref.watch(activeTenantProvider)!.tenantId);
    ref.onDispose(() {
      _debounce?.cancel();
      final channel = _channel;
      _channel = null;
      if (channel != null) unawaited(channel.unsubscribe());
    });

    return repo.tickets();
  }

  void _subscribe(String tenantId) {
    final client = ref.read(supabaseProvider);
    final token = client.auth.currentSession?.accessToken;
    if (token != null) client.realtime.setAuth(token);

    var channel = client.channel('kds_$tenantId');
    for (final table in const ['kots', 'kot_items', 'orders', 'order_items']) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'tenant_id',
          value: tenantId,
        ),
        callback: (_) => _scheduleRefresh(),
      );
    }
    _channel = channel.subscribe();
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), refresh);
  }

  Future<void> refresh() async {
    final repo = ref.read(_kdsRepoProvider);
    if (repo == null) return;
    try {
      state = AsyncData(await repo.tickets());
    } catch (e, st) {
      // A board already on screen must not blank out because one refetch
      // failed — the cook is mid-service and the tickets are still true.
      if (state.valueOrNull?.isNotEmpty ?? false) return;
      state = AsyncError(e, st);
    }
  }

  /// Paint the tap, then queue the write.
  ///
  /// The ticket is re-derived locally with the same rank ladder the server
  /// uses, so the optimistic answer matches what comes back and the card does
  /// not flick between two states.
  void patchLine(String kotItemId, KotStatus status) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([
      for (final t in current)
        if (t.lines.any((l) => l.id == kotItemId))
          _rederive(
            t.copyWith(
              lines: [
                for (final l in t.lines)
                  if (l.id == kotItemId) l.copyWith(status: status) else l,
              ],
            ),
          )
        else
          t,
    ]);
  }

  void patchTicket(String kotId, KotStatus status) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([
      for (final t in current)
        if (t.id == kotId)
          t.copyWith(
            status: status,
            lines: [
              for (final l in t.lines)
                if (l.isVoid) l else l.copyWith(status: status),
            ],
          )
        else
          t,
    ]);
  }

  KdsTicket _rederive(KdsTicket t) => t.copyWith(status: t.derived);
}

final kdsTicketsProvider =
    AsyncNotifierProvider<KdsTicketsNotifier, List<KdsTicket>>(
      KdsTicketsNotifier.new,
    );

/// What the board shows after the station filter, split into the two sections
/// a cook reads differently: work in hand, and recently-bumped tickets that can
/// still be pulled back.
class KdsBoard {
  const KdsBoard({required this.live, required this.recallable});

  final List<KdsTicket> live;
  final List<KdsTicket> recallable;
}

final kdsBoardProvider = Provider<KdsBoard>((ref) {
  final all = ref.watch(kdsTicketsProvider).valueOrNull ?? const <KdsTicket>[];
  final station = ref.watch(kdsStationProvider);

  final visible = all.where((t) {
    if (station == kdsAllStations) return true;
    if (station == kdsExpo) return t.stationId == null;
    return t.stationId == station;
  }).toList();

  return KdsBoard(
    live: visible.where((t) => t.status != KotStatus.served).toList(),
    recallable: visible.where((t) => t.status == KotStatus.served).toList(),
  );
});

/// All-day counts: how many of each dish the visible tickets still owe.
///
/// Quantities, not line counts — "6 momo" is what the pass batches, and two
/// tickets asking for three each is one pan.
final kdsDishRailProvider = Provider<List<DishTally>>((ref) {
  final board = ref.watch(kdsBoardProvider);
  final tally = <String, int>{};
  for (final ticket in board.live) {
    for (final line in ticket.live) {
      if (line.status == KotStatus.served) continue;
      tally.update(line.name, (q) => q + line.qty, ifAbsent: () => line.qty);
    }
  }
  final rows = tally.entries.map((e) => DishTally(e.key, e.value)).toList()
    ..sort((a, b) => b.qty != a.qty ? b.qty - a.qty : a.name.compareTo(b.name));
  return rows;
});

class DishTally {
  const DishTally(this.name, this.qty);

  final String name;
  final int qty;
}

/// Writes. Optimistic first, then the outbox — so a tap lands instantly and
/// still reaches the server when the kitchen's wifi comes back.
class KdsActions {
  const KdsActions(this._ref);

  final Ref _ref;

  Future<String?> setLineStatus(String kotItemId, KotStatus status) async {
    _ref.read(kdsTicketsProvider.notifier).patchLine(kotItemId, status);
    return _queue(
      (q) => q.setKotLineStatus(
        kotItemId: kotItemId,
        status: kotStatusWire(status),
      ),
    );
  }

  Future<String?> setTicketStatus(String kotId, KotStatus status) async {
    _ref.read(kdsTicketsProvider.notifier).patchTicket(kotId, status);
    return _queue(
      (q) => q.setKotStatus(kotId: kotId, status: kotStatusWire(status)),
    );
  }

  Future<String?> recall(String kotId) =>
      setTicketStatus(kotId, KotStatus.recalled);

  /// Returns null when it went through (or is safely queued), or a message the
  /// cook can act on when the server refused.
  Future<String?> _queue(Future<QueueOutcome> Function(OrderQueue) call) async {
    final queue = _ref.read(orderQueueProvider);
    if (queue == null) return 'Not signed into a restaurant.';

    final outcome = await call(queue);
    _ref.invalidate(outboxStatusProvider);

    if (outcome.error != null) {
      // The server said no — put the board back to the truth rather than
      // leaving the optimistic paint standing.
      await _ref.read(kdsTicketsProvider.notifier).refresh();
      return outcome.error;
    }
    // Queued-but-owed is a success; the sync strip is already saying so, and
    // refetching would overwrite the optimistic paint with stale server state.
    if (!outcome.synced) return null;

    await _ref.read(kdsTicketsProvider.notifier).refresh();
    return null;
  }
}

final kdsActionsProvider = Provider<KdsActions>(KdsActions.new);
