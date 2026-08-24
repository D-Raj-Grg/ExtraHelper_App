import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/prefs.dart';
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
///
/// **Null means "not known yet", an empty list means "no restaurant".** They
/// are different answers and the router acts on them differently. Returning an
/// empty list while auth was still settling is what put an owner on the "Join a
/// restaurant" screen on a restored session, and took the identity cache with
/// it: several rebuilds run at once on a cold start (auth stream, connectivity,
/// prefs) and whichever finished last decided the shell.
final membershipsProvider = FutureProvider<List<Membership>?>((ref) async {
  final auth = ref.watch(authStateProvider);
  final user = ref.watch(currentUserProvider);
  final cache = ref.watch(identityCacheProvider);

  if (user == null) {
    // Auth has not spoken yet: unknown. Do not answer for it, and above all do
    // not clear the cache — that is the offline identity of a signed-in user.
    if (!auth.hasValue) return null;
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
  /// The chosen restaurant once anything has decided it.
  ///
  /// Returned from `build()`, never assigned to `state` from inside it — see
  /// [PrintEnabled] for the failure that shape caused once storage began
  /// resolving before the first frame. Here it meant someone with two
  /// restaurants was silently put back into the first one on every launch.
  String? _value;

  @override
  String? build() {
    final decided = _value;
    if (decided != null) return decided;

    // Load the stored choice once prefs resolve; until then the first
    // membership is used, which is the same answer for the single-tenant case.
    final prefs = ref.watch(sharedPreferencesProvider).valueOrNull;
    if (prefs == null) return null;

    return _value = prefs.getString(_activeTenantKey);
  }

  Future<void> select(String tenantId) async {
    _value = tenantId;
    state = tenantId;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setString(_activeTenantKey, tenantId);
  }

  Future<void> clear() async {
    _value = null;
    state = null;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.remove(_activeTenantKey);
  }
}

final activeTenantSelectionProvider =
    NotifierProvider<ActiveTenantSelection, String?>(ActiveTenantSelection.new);

/// The active restaurant, or null when the user belongs to none.
///
/// **Null here does not mean "no restaurant".** It also covers memberships
/// still loading or failed, because this provider answers one question — which
/// restaurant am I in — and roughly fifty call sites read `?.tenantId` off it.
/// Anything that needs to tell "nowhere" from "not yet" reads
/// [identityStatusProvider], which takes it from [membershipsProvider] direct.
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

/// A future that never completes, so a provider with nothing honest to say
/// stays in [AsyncLoading] instead of resolving to a lie.
///
/// The same rule `app/redirect.dart` keeps for memberships: **unknown is not an
/// answer.** An error would be wrong here — an error must say the recovery, and
/// there is no recovery from "auth has not spoken yet, wait a frame". Holding
/// is the honest state, and the provider rebuilds the moment memberships move,
/// which discards this.
///
/// Holds no timer, so it does not keep `pumpAndSettle` awake. Do note that
/// `await ref.read(permissionsProvider.future)` with no override will now wait
/// forever rather than resolving to `{}` — which is the point, but it is a
/// footgun worth knowing about.
Future<T> _unknown<T>() => Completer<T>().future;

/// Granular permissions for the active tenant, straight from the server —
/// cached only so the app still draws the right surfaces with no coverage. The
/// RPCs enforce the same keys, so this is never the boundary.
final permissionsProvider = FutureProvider<Set<String>>((ref) async {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) {
    // A null tenant has two very different causes and they must not share an
    // answer. Genuinely in no restaurant is a fact — no restaurant, no keys —
    // and `redirect.dart` is already sending them to `/join`. Everything else
    // (memberships loading, auth not settled, the read failed) is *unknown*,
    // and answering `{}` for unknown is what emptied the drawer and put the
    // shell on a permanent spinner every time coverage was poor: an empty set
    // reads to all 43 gates as "loaded, and you may do nothing".
    final known = ref.watch(membershipsProvider).valueOrNull;
    if (known != null && known.isEmpty) return const {};
    return _unknown();
  }
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
    cached: () async => cache.permissionsIfFetched(tenant.tenantId),
  );
});

/// What the shell actually knows about who this person is.
///
/// [hasPermissionProvider] is fail-closed and stays that way — for an *action*,
/// "we don't know" and "you may not" lead to the same correct behaviour, and a
/// door that appears a moment late beats one that vanishes under a thumb.
///
/// For a **surface** they are not the same at all. A screen that renders "No
/// ordering access" because a read has not landed yet is lying to a waiter
/// mid-service, and one that spins forever is worse: it gives them nothing to
/// do about it. Whole-screen verdicts read this instead.
enum IdentityStatus {
  /// Still resolving. Say so, and never draw a verdict.
  unknown,

  /// Signed in, belonging to no restaurant. `redirect.dart` owns this one.
  noRestaurant,

  /// A read failed. There is nothing cached to fall back on, so this needs a
  /// person: say what happened and offer the retry.
  unavailable,

  /// Memberships and permissions have both answered.
  ready,
}

/// Derived from the two identity reads — deliberately **not** from
/// [activeTenantProvider], whose null is ambiguous and which at least one test
/// overrides directly.
final identityStatusProvider = Provider<IdentityStatus>((ref) {
  final memberships = ref.watch(membershipsProvider);
  final permissions = ref.watch(permissionsProvider);

  // A failure outranks everything: it is the only state with a recovery.
  if (memberships.hasError || permissions.hasError) {
    return IdentityStatus.unavailable;
  }

  final known = memberships.valueOrNull;
  if (known == null) return IdentityStatus.unknown;
  if (known.isEmpty) return IdentityStatus.noRestaurant;
  if (permissions.valueOrNull == null) return IdentityStatus.unknown;
  return IdentityStatus.ready;
});

/// The failure behind [IdentityStatus.unavailable], for a screen that wants to
/// print the detail the way the account screen does.
final identityErrorProvider = Provider<Object?>((ref) {
  return ref.watch(membershipsProvider).error ??
      ref.watch(permissionsProvider).error;
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

/// Owner or manager in the active restaurant.
///
/// Several RPCs gate on the **role** rather than on a permission key —
/// `cancel_order` and `transfer_order` check `has_tenant_role(...)` outright,
/// and checkout's discount, void and refund calls want the role *as well as*
/// their key. The seeded roles only ever hand those keys to owners and
/// managers, which is why the two look interchangeable; permissions are
/// editable per restaurant, so they are not.
///
/// `user_tenants.role` is what `has_tenant_role` reads and `Membership.role` is
/// that same column, so this asks exactly what the server will.
final isManagerProvider = Provider<bool>((ref) {
  final role = ref.watch(activeTenantProvider)?.role;
  return role == 'owner' || role == 'manager';
});
