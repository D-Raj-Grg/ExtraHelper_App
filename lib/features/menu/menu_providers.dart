import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/supabase/menu_repository.dart';
import '../tenant/tenant_providers.dart';

/// The menu, as the editor sees it.
///
/// **Network-only, deliberately.** The till caches the menu so service survives
/// a dead network; editing does not get the same treatment, because every write
/// here needs the server anyway and a stale list would offer an owner a dish
/// that no longer exists.
final menuEditItemsProvider = FutureProvider<List<MenuEditItem>>((ref) async {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return const [];
  return ref.watch(menuRepositoryProvider(tenant.tenantId)).items();
});

/// What the owner typed into the search box.
final menuSearchProvider = StateProvider.autoDispose<String>((_) => '');

final visibleMenuItemsProvider = Provider.autoDispose<List<MenuEditItem>>((
  ref,
) {
  final all = ref.watch(menuEditItemsProvider).valueOrNull ?? const [];
  final q = ref.watch(menuSearchProvider).trim().toLowerCase();
  if (q.isEmpty) return all;
  return all
      .where(
        (i) =>
            i.name.toLowerCase().contains(q) ||
            (i.categoryName?.toLowerCase().contains(q) ?? false),
      )
      .toList();
});

/// Can this user change the menu? The RPCs and the table policies enforce the
/// same key — this only decides what is drawn, and defaults to false while
/// permissions load.
final canEditMenuProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider('menu.edit')),
);

/// Can this user even open the menu screen? `menu.view` is wider than
/// `menu.edit`, so a viewer gets the list without the controls.
final canSeeMenuProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider('menu.view')),
);
