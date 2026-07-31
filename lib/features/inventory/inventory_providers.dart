import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/supabase/inventory_repository.dart';
import '../../data/sync/sync_providers.dart';
import '../tenant/tenant_providers.dart';

/// The store room.
///
/// **Cache-first on failure**, unlike the dashboard. A count is a job someone
/// walks into a back room or a walk-in to do, and the list of what to count does
/// not go stale in the ten minutes they are in there. The dashboard is a glance
/// at money, where a stale figure misleads; this is a worklist, where no list at
/// all just stops the work.
final inventoryItemsProvider = FutureProvider<List<InventoryItem>>((ref) async {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return const [];
  final repo = ref.watch(inventoryRepositoryProvider(tenant.tenantId));
  final cache = ref.watch(posCacheProvider);
  try {
    final fresh = await repo.items();
    await cache.saveInventory(tenant.tenantId, fresh);
    return fresh;
  } on Object {
    final cached = await cache.inventory(tenant.tenantId);
    if (cached.isNotEmpty) return cached;
    rethrow;
  }
});

/// What the store keeper typed into the search box. Matches name **or** barcode,
/// so a code read off a label by eye finds the same row the camera would.
final inventorySearchProvider = StateProvider.autoDispose<String>((_) => '');

/// Low stock first, then everything else — the reason someone opened this
/// screen is usually the short list, not the alphabet.
final visibleInventoryProvider = Provider.autoDispose<List<InventoryItem>>((
  ref,
) {
  final all = ref.watch(inventoryItemsProvider).valueOrNull ?? const [];
  final q = ref.watch(inventorySearchProvider).trim().toLowerCase();
  final matched = q.isEmpty
      ? all
      : all
            .where(
              (i) =>
                  i.name.toLowerCase().contains(q) ||
                  (i.barcode?.toLowerCase().contains(q) ?? false),
            )
            .toList();
  final low = matched.where((i) => i.isLow).toList();
  final rest = matched.where((i) => !i.isLow).toList();
  return [...low, ...rest];
});

/// The count in progress, if there is one.
final openCountProvider = FutureProvider<StockCount?>((ref) async {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return null;
  return ref.watch(inventoryRepositoryProvider(tenant.tenantId)).openCount();
});

/// The lines of one count. Network-only: a count that cannot be read cannot be
/// counted honestly, and the numbers already queued are held by the outbox
/// rather than by this list.
final countLinesProvider = FutureProvider.family<List<StockCountLine>, String>((
  ref,
  countId,
) async {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return const [];
  return ref
      .watch(inventoryRepositoryProvider(tenant.tenantId))
      .countLines(countId);
});

/// Can this user change stock? The RPCs enforce the same key — this only
/// decides what is drawn, and defaults to false while permissions load.
final canEditInventoryProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider('inventory.edit')),
);

final canViewInventoryProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider('inventory.view')),
);
