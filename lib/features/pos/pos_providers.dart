import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local/pos_cache.dart';
import '../../data/supabase/pos_repository.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../data/sync/sync_providers.dart';
import '../tenant/tenant_providers.dart';
import 'models.dart';

/// The POS repository for the active restaurant. Null-tenant is impossible
/// here — the router only reaches POS screens once a tenant resolved.
final posRepoProvider = Provider<PosRepository?>((ref) {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return null;
  return ref.watch(posRepositoryProvider(tenant.tenantId));
});

/// A read that must work on dead wifi.
///
/// **Cache first, network second** (`CLAUDE.md` rule 5): if there are cached
/// rows the screen gets them immediately and a refresh runs behind it; if there
/// are none there is nothing to show but the fetch. A failed refresh never
/// replaces good cached data with an error — the waiter would rather see this
/// morning's menu than a red box.
///
/// [adoptTenant] runs first on every build, so a tenant switch wipes before a
/// single row is read.
abstract class _CachedList<T> extends AsyncNotifier<List<T>> {
  /// Set once this notifier is torn down, so a refresh still in flight doesn't
  /// assign to a dead element.
  bool _disposed = false;

  Future<List<T>> readCache(PosCache cache, String tenantId);

  Future<List<T>> fetch(PosRepository repo);

  Future<void> writeCache(PosCache cache, String tenantId, List<T> rows);

  @override
  Future<List<T>> build() async {
    final repo = ref.watch(posRepoProvider);
    final tenant = ref.watch(activeTenantProvider);
    if (repo == null || tenant == null) return const [];

    _disposed = false;
    ref.onDispose(() => _disposed = true);

    final cache = ref.watch(posCacheProvider);
    await cache.adoptTenant(tenant.tenantId);

    final cached = await readCache(cache, tenant.tenantId);
    if (cached.isNotEmpty) {
      // Refresh behind the cache with the values **this build already
      // resolved** — never through `ref`.
      //
      // `refresh()` reads providers, and reading one while `build` is still on
      // the stack trips riverpod's outdated-dependency assertion. Because the
      // call is unawaited, that assertion surfaced as an unhandled error and
      // the refresh silently died — so the cache was written once and never
      // again. A phone then orders from a menu that is weeks old: it cost a
      // real bill, where a dish whose price had moved to a variant was added
      // at the stale flat price on screen and snapshotted server-side at zero.
      unawaited(_refreshWith(repo, cache, tenant.tenantId));
      return cached;
    }

    // Nothing cached and no coverage. Say that, immediately — a fetch with no
    // network sits on a long HTTP timeout, and a spinner that never resolves
    // reads as a broken app rather than a missing one.
    if (!await ref.read(connectivityProvider).isOnline()) {
      throw const PosFailure(
        "No coverage, and this hasn't been saved to this phone yet. Connect "
        'once and it will be here next time.',
      );
    }
    return _fetchAndSave(repo, cache, tenant.tenantId);
  }

  Future<List<T>> _fetchAndSave(
    PosRepository repo,
    PosCache cache,
    String tenantId,
  ) async {
    final fresh = await fetch(repo);
    await writeCache(cache, tenantId, fresh);
    return fresh;
  }

  /// Pull-to-refresh, and anything else that asks from outside a build.
  Future<void> refresh() async {
    final repo = ref.read(posRepoProvider);
    final tenant = ref.read(activeTenantProvider);
    if (repo == null || tenant == null) return;
    return _refreshWith(repo, ref.read(posCacheProvider), tenant.tenantId);
  }

  /// The refresh itself, touching no providers — so it is safe to start from
  /// inside [build].
  Future<void> _refreshWith(
    PosRepository repo,
    PosCache cache,
    String tenantId,
  ) async {
    try {
      final fresh = await _fetchAndSave(repo, cache, tenantId);
      if (_disposed) return;
      state = AsyncData(fresh);
    } catch (e, st) {
      // Keep what we have. Only an empty screen becomes an error screen.
      if (_disposed) return;
      if (state.valueOrNull?.isNotEmpty ?? false) return;
      state = AsyncError(e, st);
    }
  }
}

/// The menu, cached and kept live.
///
/// A dish going sold out has to reach every other waiter's phone — that is the
/// whole point of an 86, and a board that learns about it on the next pull is
/// a board that keeps taking orders for a dish the kitchen hasn't got.
class MenuNotifier extends _CachedList<PosMenuItem> {
  RealtimeChannel? _channel;

  @override
  Future<List<PosMenuItem>> build() async {
    final tenant = ref.watch(activeTenantProvider);
    if (tenant != null) {
      _subscribe(tenant.tenantId);
      ref.onDispose(() {
        final channel = _channel;
        _channel = null;
        if (channel != null) unawaited(channel.unsubscribe());
      });
    }
    return super.build();
  }

  void _subscribe(String tenantId) {
    final client = ref.read(supabaseProvider);
    // Same rule as the board: without the JWT, RLS drops every event.
    final token = client.auth.currentSession?.accessToken;
    if (token != null) client.realtime.setAuth(token);

    _channel = client
        .channel('pos_menu_$tenantId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'menu_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty) return;
            final id = row['id'] as String?;
            final is86 = row['is_86'] as bool?;
            if (id == null || is86 == null) return;

            unawaited(
              ref.read(posCacheProvider).setCachedItem86(tenantId, id, is86),
            );
            final current = state.valueOrNull;
            if (current == null) return;
            state = AsyncData([
              for (final item in current)
                if (item.id == id) item.copyWith(is86: is86) else item,
            ]);
          },
        )
        .subscribe();
  }

  @override
  Future<List<PosMenuItem>> readCache(PosCache cache, String tenantId) =>
      cache.menu(tenantId);

  @override
  Future<List<PosMenuItem>> fetch(PosRepository repo) => repo.menu();

  @override
  Future<void> writeCache(
    PosCache cache,
    String tenantId,
    List<PosMenuItem> rows,
  ) => cache.saveMenu(tenantId, rows);
}

final menuProvider = AsyncNotifierProvider<MenuNotifier, List<PosMenuItem>>(
  MenuNotifier.new,
);

class CategoriesNotifier extends _CachedList<PosCategory> {
  @override
  Future<List<PosCategory>> readCache(PosCache cache, String tenantId) =>
      cache.categories(tenantId);

  @override
  Future<List<PosCategory>> fetch(PosRepository repo) => repo.categories();

  @override
  Future<void> writeCache(
    PosCache cache,
    String tenantId,
    List<PosCategory> rows,
  ) => cache.saveCategories(tenantId, rows);
}

final categoriesProvider =
    AsyncNotifierProvider<CategoriesNotifier, List<PosCategory>>(
      CategoriesNotifier.new,
    );

class FloorsNotifier extends _CachedList<PosFloor> {
  @override
  Future<List<PosFloor>> readCache(PosCache cache, String tenantId) =>
      cache.floors(tenantId);

  @override
  Future<List<PosFloor>> fetch(PosRepository repo) => repo.floors();

  @override
  Future<void> writeCache(
    PosCache cache,
    String tenantId,
    List<PosFloor> rows,
  ) => cache.saveFloors(tenantId, rows);
}

final floorsProvider = AsyncNotifierProvider<FloorsNotifier, List<PosFloor>>(
  FloorsNotifier.new,
);

/// Tables, cached and kept live.
///
/// Realtime is a freshness optimization layered on the cache — the board must
/// render correctly from cache alone (`CLAUDE.md` rule 5). Changed rows are
/// merged in place *and written through to the cache*, so a cold start doesn't
/// show a state the waiter already watched change.
class TablesNotifier extends _CachedList<PosTable> {
  RealtimeChannel? _channel;

  @override
  Future<List<PosTable>> readCache(PosCache cache, String tenantId) =>
      cache.tables(tenantId);

  @override
  Future<List<PosTable>> fetch(PosRepository repo) => repo.tables();

  @override
  Future<void> writeCache(
    PosCache cache,
    String tenantId,
    List<PosTable> rows,
  ) => cache.saveTables(tenantId, rows);

  @override
  Future<List<PosTable>> build() async {
    final tenant = ref.watch(activeTenantProvider);
    if (tenant != null) {
      _subscribe(tenant.tenantId);
      ref.onDispose(() {
        final channel = _channel;
        _channel = null;
        if (channel != null) unawaited(channel.unsubscribe());
      });
    }
    return super.build();
  }

  void _subscribe(String tenantId) {
    final client = ref.read(supabaseProvider);

    // The socket must carry the user JWT or RLS silently drops every event and
    // the board merely looks "not live". Set it on connect AND on refresh —
    // this cost real debugging time on the web.
    final token = client.auth.currentSession?.accessToken;
    if (token != null) client.realtime.setAuth(token);

    _channel = client
        .channel('pos_tables_$tenantId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'restaurant_tables',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty) return;
            final changed = PosTable.fromRow(row);
            unawaited(
              ref.read(posCacheProvider).upsertTable(tenantId, changed),
            );
            final current = state.valueOrNull;
            if (current == null) return;
            state = AsyncData([
              for (final t in current)
                if (t.id == changed.id) changed else t,
            ]);
          },
        )
        .subscribe();
  }
}

final tablesProvider = AsyncNotifierProvider<TablesNotifier, List<PosTable>>(
  TablesNotifier.new,
);

/// Active orders, kept live off the same authed socket.
///
/// Not cached: an order list is the one screen where stale is worse than
/// absent, and an offline waiter's own orders live in the outbox, which the
/// composer reads directly.
class ActiveOrdersNotifier extends AsyncNotifier<List<PosOrder>> {
  RealtimeChannel? _channel;
  Timer? _debounce;

  @override
  Future<List<PosOrder>> build() async {
    final repo = ref.watch(posRepoProvider);
    final tenant = ref.watch(activeTenantProvider);
    if (repo == null || tenant == null) return const [];

    // Say it, don't spin. This list is the one screen that genuinely needs the
    // server — a waiter's own queued orders are in the outbox, and the board
    // still works — so with no coverage it explains itself and offers a retry.
    if (!await ref.read(connectivityProvider).isOnline()) {
      throw const PosFailure(
        'No coverage — the order list needs a connection. The tables board and '
        'new orders still work.',
      );
    }

    _subscribe(tenant.tenantId);
    ref.onDispose(() {
      _debounce?.cancel();
      final channel = _channel;
      _channel = null;
      if (channel != null) unawaited(channel.unsubscribe());
    });

    return repo.activeOrders();
  }

  void _subscribe(String tenantId) {
    final client = ref.read(supabaseProvider);
    final token = client.auth.currentSession?.accessToken;
    if (token != null) client.realtime.setAuth(token);

    // Orders and their lines both move; a scoped, debounced refetch is simpler
    // than merging two tables in place and still well inside "feels live".
    _channel = client
        .channel('pos_orders_$tenantId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (_) => _scheduleRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      refresh();
      // An order billed at the till leaves this list and joins the other one.
      // Sharing the socket means the Completed tab is live without a second
      // subscription — and without a waiter having to pull to find out.
      ref.invalidate(completedOrdersProvider);
    });
  }

  Future<void> refresh() async {
    final repo = ref.read(posRepoProvider);
    if (repo == null) return;
    try {
      state = AsyncData(await repo.activeOrders());
    } catch (e, st) {
      // Offline is not an error state here if we already have a list.
      if (state.valueOrNull?.isNotEmpty ?? false) return;
      state = AsyncError(e, st);
    }
  }
}

final activeOrdersProvider =
    AsyncNotifierProvider<ActiveOrdersNotifier, List<PosOrder>>(
      ActiveOrdersNotifier.new,
    );

/// Today's finished orders.
///
/// **Not cached**, for the same reason the active list isn't and more so: a
/// completed list from ten minutes ago invites reprinting the wrong receipt.
/// Offline it says so and offers a retry.
///
/// `autoDispose` because it is a tab someone visits, not a board they live on —
/// leaving it should stop holding a few hundred orders in memory.
final completedOrdersProvider =
    FutureProvider.autoDispose<List<PosCompletedOrder>>((ref) async {
      final repo = ref.watch(posRepoProvider);
      if (repo == null) return const [];

      if (!await ref.read(connectivityProvider).isOnline()) {
        throw const PosFailure(
          "No coverage — today's finished orders need a connection. The "
          'tables board and new orders still work.',
        );
      }
      return repo.completedOrders();
    });

/// Which finished status the Completed tab is showing, or null for all.
final completedFilterProvider = NotifierProvider<CompletedFilter, String?>(
  CompletedFilter.new,
);

class CompletedFilter extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? status) => state = status;
}

/// Clearing an order is manager work.
///
/// `cancel_order` gates on `has_tenant_role(owner, manager)` and **not** on a
/// permission key, so this asks the role rather than `order.void` — a custom
/// role granted `order.void` would otherwise be shown a button that fails every
/// time with "only a manager can cancel an order".
final canCancelOrderProvider = Provider<bool>(
  (ref) => ref.watch(isManagerProvider),
);

/// Which order type the Orders tab is showing, or null for all of them.
///
/// Client-side, over the list already in hand: a phone's board is small enough
/// that refetching per filter would cost a network round trip to hide four
/// cards. Reset to null whenever the chosen type empties, so a waiter is never
/// left staring at a board filtered to nothing.
final orderTypeFilterProvider = NotifierProvider<OrderTypeFilter, String?>(
  OrderTypeFilter.new,
);

class OrderTypeFilter extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? orderType) => state = orderType;
}

/// A single order, refetched on demand — what the composer edits in amend mode.
final orderProvider = FutureProvider.family<PosOrder?, String>((
  ref,
  orderId,
) async {
  final repo = ref.watch(posRepoProvider);
  if (repo == null) return null;
  return repo.order(orderId);
});
