import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/supabase/supabase_providers.dart';
import '../../data/supabase/team_repository.dart';
import '../tenant/tenant_providers.dart';

/// Reads for the team screen.
///
/// All network-only and `autoDispose`, for the reason spelled out at the top of
/// `team_repository.dart`: a cached roster is how you approve someone who was
/// already removed. The exception is the permission catalog, which is the same
/// rows for every restaurant and never changes between launches.

final teamMembersProvider = FutureProvider.autoDispose<List<TeamMember>>((
  ref,
) async {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return const [];
  return ref.watch(teamRepositoryProvider(tenant.tenantId)).members();
});

final teamRolesProvider = FutureProvider.autoDispose<List<TeamRole>>((
  ref,
) async {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return const [];
  // Counting people per role means reading `user_tenants`, which only a
  // `staff.view` holder can do. Without it every role reports an unknown count
  // and the screen says nothing rather than reporting 1.
  final canCount = ref.watch(canSeeTeamProvider);
  return ref
      .watch(teamRepositoryProvider(tenant.tenantId))
      .roles(withCounts: canCount);
});

/// The global catalog. **Not** `autoDispose` and not tenant-keyed: 37 rows that
/// are identical for every restaurant, so refetching them each time the editor
/// opens is pure latency on a phone.
final permissionCatalogProvider = FutureProvider<List<PermissionDef>>((
  ref,
) async {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return const [];
  return ref.watch(teamRepositoryProvider(tenant.tenantId)).permissionCatalog();
});

/// One group of the catalog, for the editor.
typedef PermissionGroup = ({String grp, List<PermissionDef> items});

/// The catalog grouped in first-appearance-by-sort order, matching the web.
///
/// Derived rather than folded inside the widget so a 37-row grouping does not
/// re-run on every checkbox tap — and so a group added server-side lands in the
/// right place without a Dart change.
final permissionGroupsProvider = Provider.autoDispose<List<PermissionGroup>>((
  ref,
) {
  final defs = ref.watch(permissionCatalogProvider).valueOrNull ?? const [];
  final order = <String>[];
  final byGroup = <String, List<PermissionDef>>{};
  for (final def in defs) {
    final items = byGroup.putIfAbsent(def.grp, () {
      order.add(def.grp);
      return <PermissionDef>[];
    });
    items.add(def);
  }
  return [for (final grp in order) (grp: grp, items: byGroup[grp]!)];
});

/// What the add-member, role-picker and join-code sheets all offer.
typedef RoleOption = ({String id, String name});

final roleOptionsProvider = Provider.autoDispose<List<RoleOption>>((ref) {
  final roles = ref.watch(teamRolesProvider).valueOrNull ?? const [];
  return [for (final role in roles) (id: role.id, name: role.name)];
});

/// Can this person open the Team screen at all?
final canSeeTeamProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider('staff.view')),
);

/// Can this person change the team?
///
/// `staff.edit` **alone**, deliberately. It used to need `isManagerProvider` as
/// well, because every server-side check asked
/// `has_tenant_role(tenant,'owner','manager')` while the app asked for the key
/// — so a custom role granted `staff.edit` saw the controls and was then
/// refused, silently for the table writes and with a bare 42501 for the RPCs.
/// The `team_permission_gating` migration moved the server onto the same
/// question, which is what makes custom roles usable here at all. Do not
/// re-add the base-role test: it would put the gap back the other way round.
final canEditTeamProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider('staff.edit')),
);

/// `remove_member` refuses self-removal, so the row for the person holding the
/// phone must not offer the button in the first place.
final myUserIdProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider)?.id,
);

/// Active owners, from the roster.
///
/// Lets the last-owner control be simply absent rather than failing after the
/// tap. The roster can be seconds stale and two managers can race, so the
/// server's guards are still what actually holds — this is only courtesy.
final ownerCountProvider = Provider.autoDispose<int>((ref) {
  final members = ref.watch(teamMembersProvider).valueOrNull ?? const [];
  return members.where((m) => m.isOwner && m.status == 'active').length;
});
