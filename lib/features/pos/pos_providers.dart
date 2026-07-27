import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase/pos_repository.dart';
import '../../data/supabase/supabase_providers.dart';
import '../tenant/tenant_providers.dart';
import 'models.dart';

/// The POS repository for the active restaurant. Null-tenant is impossible
/// here — the router only reaches POS screens once a tenant resolved.
final posRepoProvider = Provider<PosRepository?>((ref) {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return null;
  return ref.watch(posRepositoryProvider(tenant.tenantId));
});

final menuProvider = FutureProvider<List<PosMenuItem>>((ref) async {
  final repo = ref.watch(posRepoProvider);
  if (repo == null) return const [];
  return repo.menu();
});

final categoriesProvider = FutureProvider<List<PosCategory>>((ref) async {
  final repo = ref.watch(posRepoProvider);
  if (repo == null) return const [];
  return repo.categories();
});

final floorsProvider = FutureProvider<List<PosFloor>>((ref) async {
  final repo = ref.watch(posRepoProvider);
  if (repo == null) return const [];
  return repo.floors();
});

/// Tables, kept live.
///
/// Realtime is a freshness optimization layered on the fetch — the screen must
/// render correctly from the fetch alone (`CLAUDE.md` rule 5). Changed rows are
/// merged in place rather than refetching the world, so a table's state flips
/// without the board flickering.
class TablesNotifier extends AsyncNotifier<List<PosTable>> {
  RealtimeChannel? _channel;

  @override
  Future<List<PosTable>> build() async {
    final repo = ref.watch(posRepoProvider);
    final tenant = ref.watch(activeTenantProvider);
    if (repo == null || tenant == null) return const [];

    _subscribe(tenant.tenantId);
    ref.onDispose(() {
      final channel = _channel;
      _channel = null;
      if (channel != null) unawaited(channel.unsubscribe());
    });

    return repo.tables();
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

  Future<void> refresh() async {
    final repo = ref.read(posRepoProvider);
    if (repo == null) return;
    state = AsyncData(await repo.tables());
  }
}

final tablesProvider = AsyncNotifierProvider<TablesNotifier, List<PosTable>>(
  TablesNotifier.new,
);

/// Active orders, kept live off the same authed socket.
class ActiveOrdersNotifier extends AsyncNotifier<List<PosOrder>> {
  RealtimeChannel? _channel;
  Timer? _debounce;

  @override
  Future<List<PosOrder>> build() async {
    final repo = ref.watch(posRepoProvider);
    final tenant = ref.watch(activeTenantProvider);
    if (repo == null || tenant == null) return const [];

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
    _debounce = Timer(const Duration(milliseconds: 350), refresh);
  }

  Future<void> refresh() async {
    final repo = ref.read(posRepoProvider);
    if (repo == null) return;
    try {
      state = AsyncData(await repo.activeOrders());
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final activeOrdersProvider =
    AsyncNotifierProvider<ActiveOrdersNotifier, List<PosOrder>>(
      ActiveOrdersNotifier.new,
    );

/// A single order, refetched on demand — what the composer edits in amend mode.
final orderProvider = FutureProvider.family<PosOrder?, String>((
  ref,
  orderId,
) async {
  final repo = ref.watch(posRepoProvider);
  if (repo == null) return null;
  return repo.order(orderId);
});
