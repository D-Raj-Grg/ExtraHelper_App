import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/pos/pos_providers.dart';
import '../../features/tenant/tenant_providers.dart';
import '../local/database.dart';
import '../local/drift_outbox_store.dart';
import '../local/pos_cache.dart';
import '../supabase/inventory_repository.dart';
import 'connectivity.dart';
import 'order_queue.dart';
import 'outbox.dart';
import 'replay_engine.dart';
import 'supabase_transport.dart';

/// Opened once in `main` and overridden into the scope — the outbox surviving a
/// crash is the entire point of rule 4, so this is never a lazily-created
/// in-memory stand-in.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw StateError('appDatabaseProvider must be overridden in main()'),
);

final posCacheProvider = Provider<PosCache>(
  (ref) => PosCache(ref.watch(appDatabaseProvider)),
);

final outboxStoreProvider = Provider<OutboxStore>(
  (ref) => DriftOutboxStore(ref.watch(appDatabaseProvider)),
);

final connectivityProvider = Provider<ConnectivityWatcher>(
  (ref) => ConnectivityWatcher(),
);

/// True when there is a network interface up. Drives the offline banner.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final watcher = ref.watch(connectivityProvider);
  yield await watcher.isOnline();
  yield* watcher.onChange;
});

final replayEngineProvider = Provider<ReplayEngine?>((ref) {
  final repo = ref.watch(posRepoProvider);
  final tenant = ref.watch(activeTenantProvider);
  if (repo == null || tenant == null) return null;
  final watcher = ref.watch(connectivityProvider);
  return ReplayEngine(
    store: ref.watch(outboxStoreProvider),
    transport: SupabaseTransport(
      repo,
      ref.watch(inventoryRepositoryProvider(tenant.tenantId)),
    ),
    isOnline: watcher.isOnline,
  );
});

/// The only way an order write leaves this app. Null before a tenant resolves.
final orderQueueProvider = Provider<OrderQueue?>((ref) {
  final tenant = ref.watch(activeTenantProvider);
  final engine = ref.watch(replayEngineProvider);
  if (tenant == null || engine == null) return null;
  return OrderQueue(
    store: ref.watch(outboxStoreProvider),
    engine: engine,
    tenantId: tenant.tenantId,
  );
});

/// How much the app still owes the server, and what it gave up on.
///
/// Recomputed on demand rather than watched: sqlite has no change stream here,
/// and the moments that matter — a write queued, a drain finishing, coverage
/// returning — all invalidate it explicitly.
class OutboxStatus {
  const OutboxStatus({required this.pending, required this.dead});

  final int pending;
  final List<OutboxEntry> dead;

  bool get isClean => pending == 0 && dead.isEmpty;
}

final outboxStatusProvider = FutureProvider<OutboxStatus>((ref) async {
  final store = ref.watch(outboxStoreProvider);
  return OutboxStatus(
    pending: await store.pendingCount(),
    dead: await store.deadEntries(),
  );
});

/// Drains the outbox when coverage returns and when the app comes forward, and
/// keeps the badge honest afterwards.
///
/// Rule 5 lives here as much as in the engine: every drain is one serial pass,
/// and nothing else in the app calls the transport directly.
class SyncLoop extends ConsumerStatefulWidget {
  const SyncLoop({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SyncLoop> createState() => _SyncLoopState();
}

class _SyncLoopState extends ConsumerState<SyncLoop>
    with WidgetsBindingObserver {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A slow heartbeat as well as the event triggers: a queue that is owed
    // something must never sit still just because no event happened to fire.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _drain());
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _drain();
  }

  Future<void> _drain() async {
    final engine = ref.read(replayEngineProvider);
    if (engine == null || engine.isRunning) return;
    final completed = await engine.run();
    if (!mounted) return;
    // Receipts for orders that landed a week ago are not work.
    unawaited(
      ref
          .read(outboxStoreProvider)
          .pruneSettled(DateTime.now().subtract(const Duration(days: 7))),
    );
    ref.invalidate(outboxStatusProvider);
    if (completed > 0) {
      // Something landed: the board and the order list are now stale.
      ref.invalidate(activeOrdersProvider);
      unawaited(ref.read(tablesProvider.notifier).refresh());
    }
  }

  /// Coverage came back. Anything that failed *because* it was offline is still
  /// showing that failure — an `AsyncError` is sticky, so without this the
  /// order list keeps saying "No coverage" over a live LTE connection and the
  /// only way out is the waiter tapping "Try again".
  ///
  /// Rebuilding also re-subscribes Realtime, which the offline build skipped.
  void _recoverFromOffline() {
    if (!mounted) return;
    ref.invalidate(activeOrdersProvider);
    unawaited(ref.read(tablesProvider.notifier).refresh());
    unawaited(ref.read(menuProvider.notifier).refresh());
    unawaited(ref.read(categoriesProvider.notifier).refresh());
    unawaited(ref.read(floorsProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(isOnlineProvider, (previous, next) {
      if (next.valueOrNull != true) return;
      // Owed writes first, then the screens that gave up while there was no
      // network. Order matters only for tidiness — both are safe to repeat.
      _drain();
      if (previous?.valueOrNull == false) _recoverFromOffline();
    });
    return widget.child;
  }
}
