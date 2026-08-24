import 'package:drift/drift.dart';

import '../supabase/tenant_repository.dart';
import 'database.dart';

/// Who the user is and what they may do, held locally.
///
/// Without this a cold start with no coverage renders "No ordering access":
/// memberships and permissions are network reads, so the shell has no tenant
/// and no keys. A waiter who restarts their phone mid-service must find the app
/// as they left it — that is rule 5 applied to the shell, not just the board.
///
/// **This is not a security boundary.** Every key here is enforced again inside
/// the RPCs; caching them only decides what gets drawn.
class IdentityCache {
  IdentityCache(this._db);

  final AppDatabase _db;

  Future<void> saveMemberships(List<Membership> rows) =>
      _db.transaction(() async {
        await _db.delete(_db.cachedMemberships).go();
        await _db.batch((b) {
          for (var i = 0; i < rows.length; i++) {
            final m = rows[i];
            b.insert(
              _db.cachedMemberships,
              CachedMembershipsCompanion.insert(
                tenantId: m.tenantId,
                name: m.name,
                slug: m.slug,
                role: m.role,
                currency: m.currency,
                timezone: m.timezone,
                // Order matters: "the first membership" is the fallback tenant.
                sortIndex: i,
              ),
              mode: InsertMode.insertOrReplace,
            );
          }
        });
      });

  Future<List<Membership>> memberships() async {
    final rows = await (_db.select(
      _db.cachedMemberships,
    )..orderBy([(t) => OrderingTerm.asc(t.sortIndex)])).get();
    return rows
        .map(
          (r) => Membership(
            tenantId: r.tenantId,
            name: r.name,
            slug: r.slug,
            role: r.role,
            currency: r.currency,
            timezone: r.timezone,
          ),
        )
        .toList();
  }

  Future<void> savePermissions(String tenantId, Set<String> keys) =>
      _db.transaction(() async {
        await (_db.delete(
          _db.cachedPermissions,
        )..where((t) => t.tenantId.equals(tenantId))).go();
        await _db.batch((b) {
          for (final key in keys) {
            b.insert(
              _db.cachedPermissions,
              CachedPermissionsCompanion.insert(tenantId: tenantId, key: key),
              mode: InsertMode.insertOrReplace,
            );
          }
        });
        // Stamped inside the same transaction as the keys, so the marker can
        // never claim an answer the rows do not back.
        await _db
            .into(_db.cachedPermissionMeta)
            .insertOnConflictUpdate(
              CachedPermissionMetaCompanion.insert(
                tenantId: tenantId,
                fetchedAt: DateTime.now(),
              ),
            );
      });

  /// The raw cached keys. Empty means no rows — which is *not* the same as
  /// "this user holds no keys"; see [permissionsIfFetched].
  Future<Set<String>> permissions(String tenantId) async {
    final rows = await (_db.select(
      _db.cachedPermissions,
    )..where((t) => t.tenantId.equals(tenantId))).get();
    return rows.map((r) => r.key).toSet();
  }

  /// The cached keys, or **null when this phone has never been told**.
  ///
  /// The distinction the shell turns on. A user who genuinely holds no keys and
  /// a restaurant this device has never been online for both store zero rows,
  /// and reading them the same way is what let an offline cold start decide
  /// that everyone may do nothing. An empty set from here is an answer and
  /// gets served; null is absence and lets the read say so.
  Future<Set<String>?> permissionsIfFetched(String tenantId) async {
    final marker = await (_db.select(
      _db.cachedPermissionMeta,
    )..where((t) => t.tenantId.equals(tenantId))).getSingleOrNull();
    if (marker == null) return null;
    return permissions(tenantId);
  }

  /// Sign-out clears identity. Leaving it would let the next user of this phone
  /// see the previous one's restaurants.
  Future<void> clear() => _db.transaction(() async {
    await _db.delete(_db.cachedMemberships).go();
    await _db.delete(_db.cachedPermissions).go();
    // The marker goes with the keys. Left behind, it would tell the next person
    // to sign in on this phone that their empty permission set was a real
    // answer, and hand them an app with every door shut.
    await _db.delete(_db.cachedPermissionMeta).go();
  });
}
