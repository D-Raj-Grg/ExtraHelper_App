import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format/labels.dart';
import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

/// Who is on the team, and what each role reaches.
///
/// Mirrors the web's `/team` page. The roster arrives from one RPC that unions
/// three sources — real members, pending signups, and invites for addresses
/// with no account yet — because an owner asking "who is on my team" does not
/// care which table the row came from.
///
/// **Network-only, deliberately.** The outbox (`lib/data/sync/outbox.dart`)
/// exists so a waiter's *order* survives a dead network. It must not be
/// extended here. A queued "remove member" replayed twenty minutes later
/// applies a security decision against a state nobody can see, and the
/// last-owner and self-removal guards are evaluated server-side at replay time,
/// when the actor has walked away. With no coverage this screen shows its error
/// state — the correct answer, because the answer is genuinely unknown.

/// One row of the roster.
class TeamMember {
  const TeamMember({
    required this.userId,
    required this.email,
    required this.baseRole,
    required this.roleId,
    required this.roleName,
    required this.status,
    required this.createdAt,
  });

  /// **Null means this is an invite** — `list_tenant_members` unions
  /// `null::uuid` for every `staff_invites` row. A non-null cast here crashes
  /// the roster the first time anyone is invited.
  final String? userId;

  final String email;
  final String baseRole;
  final String? roleId;
  final String? roleName;

  /// `active` | `pending` | `invited`.
  final String status;

  final DateTime createdAt;

  bool get isInvite => userId == null;
  bool get isPending => status == 'pending';
  bool get isOwner => baseRole == 'owner';

  /// A deleted role leaves `role_id` null and the `left join` misses, so the
  /// base role is what is left to say. Never render [roleName] directly.
  String get roleDisplay => roleName ?? roleLabel(baseRole);

  static TeamMember fromRow(Map<String, dynamic> row) => TeamMember(
    userId: row['user_id'] as String?,
    email: (row['email'] as String?) ?? '',
    // Default rather than throw: an enum value added server-side should
    // degrade readably, the way `roleLabel` already does.
    baseRole: (row['base_role'] as String?) ?? 'waiter',
    roleId: row['role_id'] as String?,
    roleName: _blankToNull(row['role_name']),
    status: (row['status'] as String?) ?? 'active',
    createdAt: _time(row['created_at']),
  );
}

/// A role as the editor sees it: identity, the base role that is the real RLS
/// floor, and the permission keys layered on top.
class TeamRole {
  const TeamRole({
    required this.id,
    required this.name,
    required this.description,
    required this.color,
    required this.baseRole,
    required this.isSystem,
    required this.permissions,
    this.memberCount = unknownCount,
  });

  /// How many people hold this role is only readable by someone who can read
  /// `user_tenants` for the tenant. When it cannot be read the screen says
  /// nothing rather than guessing — see [memberCount].
  static const unknownCount = -1;

  final String id;
  final String name;
  final String? description;

  /// `#rrggbb`. Free `text` server-side with only a default, so never trusted.
  final String color;

  final String baseRole;
  final bool isSystem;
  final Set<String> permissions;

  /// People holding this role, or [unknownCount] when it could not be read.
  final int memberCount;

  bool get countKnown => memberCount >= 0;

  TeamRole withCount(int count) => TeamRole(
    id: id,
    name: name,
    description: description,
    color: color,
    baseRole: baseRole,
    isSystem: isSystem,
    permissions: permissions,
    memberCount: count,
  );

  static TeamRole fromRow(Map<String, dynamic> row) {
    // PostgREST hands back the embed as `[{permission_key: ...}, ...]`, and as
    // `null` — not `[]` — when it declines to resolve it.
    final embedded = row['role_permissions'];
    final keys = <String>{
      if (embedded is List)
        for (final entry in embedded)
          if (entry is Map && entry['permission_key'] is String)
            entry['permission_key'] as String,
    };
    return TeamRole(
      id: row['id'] as String,
      name: (row['name'] as String?) ?? '',
      description: _blankToNull(row['description']),
      color: _hex(row['color']),
      baseRole: (row['base_role'] as String?) ?? 'waiter',
      isSystem: row['is_system'] == true,
      permissions: keys,
    );
  }
}

/// One row of the global permission catalog.
///
/// **Read live, never hardcoded.** The catalog has already grown twice by
/// migration since the original seed (`cash.approve`, `purchasing.delete`), so
/// a Dart constant would have shipped stale twice over.
class PermissionDef {
  const PermissionDef({
    required this.key,
    required this.grp,
    required this.label,
    required this.sort,
  });

  final String key;
  final String grp;
  final String label;
  final int sort;

  static PermissionDef fromJson(Map<String, dynamic> json) => PermissionDef(
    key: json['key'] as String,
    grp: (json['grp'] as String?) ?? 'Other',
    // Falls back to the key so an unlabelled permission added by migration
    // renders as `menu.edit` rather than an empty checkbox row.
    label: _blankToNull(json['label']) ?? (json['key'] as String),
    sort: _int(json['sort']),
  );
}

/// What the role editor is about to save.
class RoleDraft {
  const RoleDraft({
    required this.name,
    required this.description,
    required this.color,
    required this.baseRole,
    required this.permissions,
  });

  final String name;
  final String? description;
  final String color;
  final String baseRole;
  final Set<String> permissions;

  /// The one invariant the server also holds: an owner-based role that loses
  /// `staff.edit` locks every owner out of this screen for good, with SQL as
  /// the only way back.
  Set<String> get effectivePermissions =>
      baseRole == 'owner' ? {...permissions, 'staff.edit'} : permissions;
}

/// The base roles a custom role may sit on. Mirrors `BASE_ROLES` in the web's
/// `components/team/types.ts`, and the `app_role` enum behind both.
const kBaseRoles = <String>[
  'owner',
  'manager',
  'receptionist',
  'cashier',
  'waiter',
  'kitchen',
  'inventory',
];

/// Reads and writes for the team screen.
///
/// Members go through RPCs, which hold the owner-protection guards. Roles are
/// plain table work — the web has no RPC for them, and both clients must keep
/// calling the same thing.
class TeamRepository {
  const TeamRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  // --- reads ---------------------------------------------------------------

  /// The roster.
  ///
  /// Returns **zero rows, not an error**, to a caller without `staff.view` —
  /// the RPC filters rather than raises. The screen must never render "no team
  /// members" off the back of that.
  Future<List<TeamMember>> members() async {
    try {
      final data =
          await _client.rpc<dynamic>(
                'list_tenant_members',
                params: {'_tenant': _tenantId},
              )
              as List<dynamic>?;
      if (data == null) return const [];
      return [
        for (final row in data) TeamMember.fromRow(row as Map<String, dynamic>),
      ];
    } on PostgrestException catch (e) {
      throw PosFailure(friendlyTeamError(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't load your team just now.");
    }
  }

  /// Roles with their permission sets, system roles first then alphabetical —
  /// the same ordering the web uses, so the two clients list them alike.
  ///
  /// [withCounts] false when the caller cannot read `user_tenants`; every role
  /// then carries [TeamRole.unknownCount] and the screen says nothing about
  /// how many people hold it.
  Future<List<TeamRole>> roles({bool withCounts = true}) async {
    try {
      final rows = await _client
          .from('roles')
          .select(
            'id, name, description, color, base_role, is_system, '
            'role_permissions(permission_key)',
          )
          .eq('tenant_id', _tenantId)
          .order('is_system', ascending: false)
          .order('name');

      final roles = rows.map(TeamRole.fromRow).toList();
      if (!withCounts) return roles;

      final counts = await _memberCounts();
      return [for (final r in roles) r.withCount(counts[r.id] ?? 0)];
    } on PostgrestException catch (e) {
      throw PosFailure(friendlyTeamError(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't load your roles just now.");
    }
  }

  Future<Map<String, int>> _memberCounts() async {
    final rows = await _client
        .from('user_tenants')
        .select('role_id')
        .eq('tenant_id', _tenantId)
        .eq('status', 'active');
    final counts = <String, int>{};
    for (final row in rows) {
      final id = row['role_id'] as String?;
      if (id != null) counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  /// The global catalog, in sort order. The only read here without a tenant
  /// filter, and the only one that can be — it is the same rows for everyone.
  Future<List<PermissionDef>> permissionCatalog() async {
    try {
      final rows = await _client
          .from('permissions')
          .select('key, grp, label, sort')
          .order('sort');
      return rows.map(PermissionDef.fromJson).toList();
    } on PostgrestException catch (e) {
      throw PosFailure(friendlyTeamError(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't load the permission list.");
    }
  }

  // --- member writes (RPC) -------------------------------------------------

  /// Add someone by email. True when no account existed and an invite was
  /// held instead — the two outcomes read very differently to the person
  /// doing it, so the screen says which happened.
  Future<bool> addMember({
    required String email,
    required String roleId,
  }) async {
    final trimmed = email.trim();
    if (!_emailPattern.hasMatch(trimmed)) {
      throw const PosFailure('Enter a valid email address.');
    }
    if (roleId.isEmpty) {
      throw const PosFailure('Pick a role for the new member.');
    }
    return _run(() async {
      final result = await _client.rpc<dynamic>(
        'add_member_by_email',
        params: {'_tenant': _tenantId, '_email': trimmed, '_role_id': roleId},
      );
      final invited = result == 'invited';
      await _audit(
        entityType: 'user_tenant',
        metadata: {'event': invited ? 'invite' : 'add', 'email': trimmed},
      );
      return invited;
    }, "Couldn't add them just now. Nothing was changed.");
  }

  Future<void> setMemberRole({
    required String userId,
    required String roleId,
  }) => _run(() async {
    await _client.rpc<dynamic>(
      'set_member_role',
      params: {'_tenant': _tenantId, '_user_id': userId, '_role_id': roleId},
    );
    await _audit(
      entityType: 'user_tenant',
      entityId: userId,
      metadata: {'event': 'set_role', 'role_id': roleId},
    );
  }, "Couldn't change their role just now. Nothing was changed.");

  Future<void> approveMember(String userId) => _run(() async {
    await _client.rpc<dynamic>(
      'approve_member',
      params: {'_tenant': _tenantId, '_user_id': userId},
    );
  }, "Couldn't approve them just now. Nothing was changed.");

  Future<void> removeMember(String userId) => _run(() async {
    await _client.rpc<dynamic>(
      'remove_member',
      params: {'_tenant': _tenantId, '_user_id': userId},
    );
    await _audit(
      entityType: 'user_tenant',
      entityId: userId,
      metadata: {'event': 'remove'},
    );
  }, "Couldn't remove them just now. Nothing was changed.");

  Future<void> cancelInvite(String email) => _run(() async {
    await _client.rpc<dynamic>(
      'cancel_invite',
      params: {'_tenant': _tenantId, '_email': email.trim()},
    );
  }, "Couldn't cancel that invite just now. Nothing was changed.");

  /// An 8-character code someone can redeem to join. Null [roleId] leaves the
  /// server's default (waiter).
  Future<String> createJoinCode({String? roleId}) => _run(() async {
    final code = await _client.rpc<dynamic>(
      'create_join_code',
      params: {'_tenant': _tenantId, '_role_id': roleId},
    );
    await _audit(
      entityType: 'user_tenant',
      metadata: {'event': 'join_code', 'role_id': roleId},
    );
    return code as String;
  }, "Couldn't make a join code just now.");

  // --- role writes (plain table work) --------------------------------------

  Future<String> createRole(RoleDraft draft) async {
    final name = _requireName(draft);
    return _run(() async {
      final rows = await _client
          .from('roles')
          .insert({
            'tenant_id': _tenantId,
            'name': name,
            'description': draft.description?.trim().isEmpty ?? true
                ? null
                : draft.description!.trim(),
            'color': _hex(draft.color),
            'base_role': draft.baseRole,
            'is_system': false,
          })
          .select('id');
      if (rows.isEmpty) throw _refused;
      final id = rows.first['id'] as String;
      await _writePermissions(id, draft.effectivePermissions);
      await _audit(
        entityType: 'role',
        entityId: id,
        metadata: {'event': 'create', 'name': name},
      );
      return id;
    }, "Couldn't create that role. Nothing was changed.");
  }

  /// A **system role keeps its identity** — its name and base role are what the
  /// seeded RLS floor keys off — but its permission set is the restaurant's to
  /// tune, which is the whole point of the screen.
  Future<void> updateRole(String roleId, RoleDraft draft) async {
    final name = _requireName(draft);
    final existing = await _run(
      () => _client
          .from('roles')
          .select('is_system, base_role')
          .eq('id', roleId)
          .eq('tenant_id', _tenantId)
          .maybeSingle(),
      "Couldn't open that role just now.",
    );
    if (existing == null) {
      throw const PosFailure('That role is already gone. Pull to refresh.');
    }

    final isSystem = existing['is_system'] == true;
    if (!isSystem) {
      await _run(() async {
        final rows = await _client
            .from('roles')
            .update({
              'name': name,
              'description': draft.description?.trim().isEmpty ?? true
                  ? null
                  : draft.description!.trim(),
              'color': _hex(draft.color),
              'base_role': draft.baseRole,
            })
            .eq('id', roleId)
            .eq('tenant_id', _tenantId)
            .select('id');
        if (rows.isEmpty) throw _refused;
      }, "Couldn't save that role. Nothing was changed.");
    }

    // The pin follows the role's *real* base role, not the draft's — a system
    // role ignores the draft's base entirely.
    final base = isSystem ? existing['base_role'] as String? : draft.baseRole;
    final keys = {...draft.permissions, if (base == 'owner') 'staff.edit'};

    // Delete-then-insert, matching the web. **Not transactional**: a failure
    // between the two leaves the role with no permissions at all, so the copy
    // below says so rather than claiming nothing changed.
    await _run(
      () async {
        await _client.from('role_permissions').delete().eq('role_id', roleId);
        await _writePermissions(roleId, keys);
        await _audit(
          entityType: 'role',
          entityId: roleId,
          metadata: {'event': 'update', 'name': name},
        );
      },
      "That role's permissions may have been cleared. Open it and save again.",
    );
  }

  Future<void> deleteRole(TeamRole role) async {
    if (role.isSystem) {
      throw const PosFailure("Default roles can't be deleted.");
    }
    return _run(() async {
      final rows = await _client
          .from('roles')
          .delete()
          .eq('id', role.id)
          .eq('tenant_id', _tenantId)
          .select('id');
      if (rows.isEmpty) throw _refused;
      await _audit(
        entityType: 'role',
        entityId: role.id,
        metadata: {'event': 'delete', 'name': role.name},
      );
    }, "Couldn't delete that role. Nothing was changed.");
  }

  Future<void> _writePermissions(String roleId, Set<String> keys) async {
    if (keys.isEmpty) return;
    await _client.from('role_permissions').insert([
      for (final key in keys) {'role_id': roleId, 'permission_key': key},
    ]);
  }

  String _requireName(RoleDraft draft) {
    final name = draft.name.trim();
    if (name.isEmpty) throw const PosFailure('Give the role a name.');
    if (!kBaseRoles.contains(draft.baseRole)) {
      throw const PosFailure("That base role doesn't exist.");
    }
    return name;
  }

  /// Mirror the web's audit trail.
  ///
  /// The team RPCs write no audit rows — the web's server actions do it around
  /// them — so without this a role change made from the phone leaves the
  /// manager log looking like it never happened. `approve_member` and
  /// `cancel_invite` are deliberately not audited, matching the web exactly.
  ///
  /// Best effort: a logging failure must never report a successful role change
  /// as failed.
  Future<void> _audit({
    required String entityType,
    String? entityId,
    required Map<String, dynamic> metadata,
  }) async {
    try {
      final actor = _client.auth.currentUser?.id;
      if (actor == null) return;
      await _client.from('audit_logs').insert({
        'tenant_id': _tenantId,
        'actor_id': actor,
        'action': 'role_change',
        'entity_type': entityType,
        'entity_id': entityId,
        'metadata': metadata,
      });
    } catch (_) {
      // Intentionally swallowed — see above.
    }
  }

  /// The one error funnel. Server prose becomes staff copy, a refused write
  /// stays refused, and anything else is transient — the outbox distinction
  /// (`PLANNING.md` §2, rule 3) still matters even though nothing here queues.
  Future<T> _run<T>(Future<T> Function() body, String transient) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      throw PosFailure(friendlyTeamError(e.message));
    } on PosFailure {
      rethrow;
    } catch (_) {
      throw PosTransientFailure(transient);
    }
  }

  /// RLS refuses by matching zero rows, not by raising. Without a read-back
  /// and this failure, a refused save reports success.
  static const _refused = PosFailure(
    'Your role can see the team but not change it. Ask an owner for the '
    '"Manage team & roles" permission.',
  );
}

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Server prose → something the person holding the phone can act on.
///
/// Ordering is the whole point: the guards carry distinguishing text, and the
/// generic authorisation line is the widest net, so it is checked **last**. Put
/// it first and "cannot remove the last owner" silently becomes "ask an owner".
@visibleForTesting
String friendlyTeamError(String raw) {
  final m = raw.toLowerCase();

  // Owner protection and the last-owner guards (42501).
  if (m.contains('cannot demote the last owner')) {
    return 'This is the only owner. Make someone else an owner first, then '
        'change this one.';
  }
  if (m.contains('cannot remove the last owner')) {
    return 'This is the only owner — removing them would leave the restaurant '
        'with nobody in charge. Make someone else an owner first.';
  }
  if (m.contains('you cannot remove yourself')) {
    return "You can't remove your own access. Ask another owner to do it.";
  }
  if (m.contains('only an owner can assign the owner role')) {
    return 'Only an owner can hand out the Owner role.';
  }
  if (m.contains('only an owner can modify an owner')) {
    return "Only an owner can change another owner's role.";
  }
  if (m.contains('only an owner can remove an owner')) {
    return 'Only an owner can remove another owner.';
  }
  if (m.contains('only an owner can approve an owner')) {
    return 'Only an owner can approve someone joining as an owner.';
  }

  // Uniqueness (23505).
  if (m.contains('already a member')) {
    return "They're already on this team. Change their role instead of adding "
        'them again.';
  }
  if (m.contains('duplicate key') && m.contains('roles_tenant_id_name')) {
    return 'A role with that name already exists. Pick another name.';
  }
  if (m.contains('duplicate key')) {
    return "That's already been added.";
  }

  // Bad input (22023) and not-found (P0002).
  if (m.contains('invalid role') || m.contains('role not found')) {
    return 'That role no longer exists. Pull to refresh and pick again.';
  }
  if (m.contains('email required')) {
    return "Enter the person's email address.";
  }
  if (m.contains('member not found')) {
    return "They're no longer on this team. Pull to refresh.";
  }

  // Authorisation, generic (42501) — LAST, it is the widest net.
  if (m.contains('not authorized') ||
      m.contains('permission denied') ||
      m.contains('violates row-level security')) {
    return 'Your role can see the team but not change it. Ask an owner for '
        'the "Manage team & roles" permission.';
  }

  return raw;
}

String? _blankToNull(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// The column is free `text` with only a default, so a value written by an
/// older build must not reach `Color` inside a `ListView.builder`.
String _hex(Object? value) {
  const fallback = '#64748b';
  if (value is! String) return fallback;
  final trimmed = value.trim().toLowerCase();
  return RegExp(r'^#[0-9a-f]{6}$').hasMatch(trimmed) ? trimmed : fallback;
}

int _int(Object? value) => switch (value) {
  int i => i,
  num n => n.round(),
  String s => int.tryParse(s) ?? 0,
  _ => 0,
};

DateTime _time(Object? value) => switch (value) {
  DateTime d => d,
  String s => DateTime.tryParse(s)?.toLocal() ?? DateTime.now(),
  _ => DateTime.now(),
};

final teamRepositoryProvider = Provider.family<TeamRepository, String>(
  (ref, tenantId) => TeamRepository(ref.watch(supabaseProvider), tenantId),
);
