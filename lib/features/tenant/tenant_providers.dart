import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/local/cache_backed.dart';
import '../../data/local/identity_cache.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../data/supabase/tenant_repository.dart';
import '../../data/sync/sync_providers.dart';

/// Which restaurant the user is working in right now.
///
/// The web keeps this in a cookie; here it's a preference key. Either way the
/// stored id is **validated against live memberships** before it's used — a
/// stale id from a membership that was revoked must never select a tenant.
const _activeTenantKey = 'active_tenant_id';

final _prefsProvider = FutureProvider<SharedPreferences>(
  (ref) => SharedPreferences.getInstance(),
);

final identityCacheProvider = Provider<IdentityCache>(
  (ref) => IdentityCache(ref.watch(appDatabaseProvider)),
);

/// Restaurants the user can work in. Refetched whenever auth changes, so a
/// sign-out can't leave another user's memberships in the cache, and again
/// when coverage returns, so a shift started offline picks up the real answer.
///
/// **Cache first**: a cold start with no coverage must still land the waiter in
/// their restaurant. A failed refresh keeps the cached answer rather than
/// signing them out of a shift.
final membershipsProvider = FutureProvider<List<Membership>>((ref) async {
  ref.watch(authStateProvider);
  final user = ref.watch(currentUserProvider);
  final cache = ref.watch(identityCacheProvider);
  if (user == null) {
    await cache.clear();
    return const [];
  }
  final isOnline = _connectivity(ref);
  return cacheBackedRead<List<Membership>>(
    isOnline: isOnline,
    fetch: () async {
      final fresh = await ref
          .watch(tenantRepositoryProvider)
          .activeMemberships();
      await cache.saveMemberships(fresh);
      return fresh;
    },
    cached: () async {
      final rows = await cache.memberships();
      return rows.isEmpty ? null : rows;
    },
  );
});

/// Connectivity for the identity reads, resolved **before** the first await so
/// the dependency is registered at build time rather than across an async gap.
///
/// Watched, not read: when coverage returns the provider re-runs and the shell
/// stops living on the cache. The direct check is the fallback for the first
/// frame, before the stream has produced anything.
Future<bool> Function() _connectivity(Ref ref) {
  final known = ref.watch(isOnlineProvider).valueOrNull;
  final watcher = ref.watch(connectivityProvider);
  return () async => known ?? await watcher.isOnline();
}

/// Memberships awaiting owner approval — the difference between "ask for a
/// code" and "wait for approval".
final pendingMembershipsProvider = FutureProvider<List<PendingMembership>>((
  ref,
) async {
  ref.watch(authStateProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.watch(tenantRepositoryProvider).pendingMemberships();
});

/// The user's explicit tenant choice, if any. Null means "not chosen" — which
/// resolves to the first membership, not to "no tenant".
class ActiveTenantSelection extends Notifier<String?> {
  @override
  String? build() {
    // Load the stored choice once prefs resolve; until then the first
    // membership is used, which is the same answer for the single-tenant case.
    ref.listen(_prefsProvider, (_, next) {
      final prefs = next.valueOrNull;
      if (prefs != null && state == null) {
        state = prefs.getString(_activeTenantKey);
      }
    }, fireImmediately: true);
    return null;
  }

  Future<void> select(String tenantId) async {
    state = tenantId;
    final prefs = await ref.read(_prefsProvider.future);
    await prefs.setString(_activeTenantKey, tenantId);
  }

  Future<void> clear() async {
    state = null;
    final prefs = await ref.read(_prefsProvider.future);
    await prefs.remove(_activeTenantKey);
  }
}

final activeTenantSelectionProvider =
    NotifierProvider<ActiveTenantSelection, String?>(ActiveTenantSelection.new);

/// The active restaurant, or null when the user belongs to none.
///
/// A stored selection that no longer matches a live membership falls back to
/// the first one rather than selecting nothing — being dropped from a
/// restaurant should not look like being signed out.
final activeTenantProvider = Provider<Membership?>((ref) {
  final memberships = ref.watch(membershipsProvider).valueOrNull ?? const [];
  if (memberships.isEmpty) return null;

  final chosen = ref.watch(activeTenantSelectionProvider);
  if (chosen == null) return memberships.first;

  for (final m in memberships) {
    if (m.tenantId == chosen) return m;
  }
  return memberships.first;
});

/// Granular permissions for the active tenant, straight from the server —
/// cached only so the app still draws the right surfaces with no coverage. The
/// RPCs enforce the same keys, so this is never the boundary.
final permissionsProvider = FutureProvider<Set<String>>((ref) async {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return const {};
  final cache = ref.watch(identityCacheProvider);
  final isOnline = _connectivity(ref);
  return cacheBackedRead<Set<String>>(
    isOnline: isOnline,
    fetch: () async {
      final fresh = await ref
          .watch(tenantRepositoryProvider)
          .permissions(tenant.tenantId);
      await cache.savePermissions(tenant.tenantId, fresh);
      return fresh;
    },
    cached: () async {
      final keys = await cache.permissions(tenant.tenantId);
      return keys.isEmpty ? null : keys;
    },
  );
});

/// Whether the user holds a permission key in the active tenant.
///
/// Defaults to **false while loading** — a screen must not flash an action the
/// user then loses. The server enforces the same keys inside the sensitive
/// RPCs, so this is a UI affordance, not the security boundary.
final hasPermissionProvider = Provider.family<bool, String>((ref, key) {
  final perms = ref.watch(permissionsProvider).valueOrNull;
  return perms?.contains(key) ?? false;
});
