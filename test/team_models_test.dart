import 'package:extrahelper/data/supabase/team_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parsing the team roster and the role list.
///
/// The shapes here are not hypothetical. `list_tenant_members` unions three
/// sources, and one of them has no `user_id` at all — a non-null cast crashes
/// the roster the first time anyone is invited. The rest guard values the
/// database is free to hand back: a role deleted out from under a member, a
/// colour column that is plain `text`, an embed PostgREST declined to resolve.

Map<String, dynamic> _member({
  Object? userId = 'u1',
  Object? email = 'a@b.co',
  Object? baseRole = 'waiter',
  Object? roleId,
  Object? roleName,
  Object? status = 'active',
  Object? createdAt = '2026-08-23T04:00:00Z',
}) => {
  'user_id': userId,
  'email': email,
  'base_role': baseRole,
  'role_id': roleId,
  'role_name': roleName,
  'status': status,
  'created_at': createdAt,
};

Map<String, dynamic> _role({
  Object? id = 'r1',
  Object? name = 'Shift Lead',
  Object? description,
  Object? color = '#059669',
  Object? baseRole = 'waiter',
  Object? isSystem = false,
  Object? permissions,
}) => {
  'id': id,
  'name': name,
  'description': description,
  'color': color,
  'base_role': baseRole,
  'is_system': isSystem,
  'role_permissions': permissions,
};

void main() {
  group('TeamMember', () {
    test('an invite has no user id and says so', () {
      final m = TeamMember.fromRow(
        _member(userId: null, status: 'invited', email: 'new@hire.co'),
      );
      expect(m.userId, isNull);
      expect(m.isInvite, isTrue);
      expect(m.email, 'new@hire.co');
    });

    test('a member with no custom role still names one', () {
      final m = TeamMember.fromRow(_member(baseRole: 'cashier'));
      expect(m.roleId, isNull);
      expect(m.roleName, isNull);
      // Never blank: the base role is what is left to say.
      expect(m.roleDisplay, 'Cashier');
    });

    test('a custom role name wins over the base role', () {
      final m = TeamMember.fromRow(
        _member(roleId: 'r1', roleName: 'Shift Lead'),
      );
      expect(m.roleDisplay, 'Shift Lead');
    });

    test('an unknown base role degrades instead of throwing', () {
      final m = TeamMember.fromRow(_member(baseRole: 'sommelier'));
      expect(m.baseRole, 'sommelier');
      expect(m.roleDisplay, 'Sommelier');
    });

    test('a missing base role falls back rather than crashing the roster', () {
      expect(TeamMember.fromRow(_member(baseRole: null)).baseRole, 'waiter');
    });

    test('pending and owner are readable off the row', () {
      final m = TeamMember.fromRow(
        _member(status: 'pending', baseRole: 'owner'),
      );
      expect(m.isPending, isTrue);
      expect(m.isOwner, isTrue);
    });

    test('a blank role name is the same as none', () {
      final m = TeamMember.fromRow(_member(roleId: 'r1', roleName: '  '));
      expect(m.roleName, isNull);
      expect(m.roleDisplay, 'Waiter');
    });

    test('an unparseable timestamp does not throw', () {
      expect(
        () => TeamMember.fromRow(_member(createdAt: 'not a date')),
        returnsNormally,
      );
    });
  });

  group('TeamRole', () {
    test('the permission embed becomes a key set', () {
      final r = TeamRole.fromRow(
        _role(
          permissions: [
            {'permission_key': 'order.void'},
            {'permission_key': 'staff.view'},
          ],
        ),
      );
      expect(r.permissions, {'order.void', 'staff.view'});
    });

    test('an unresolved embed is null, not an empty list', () {
      expect(TeamRole.fromRow(_role(permissions: null)).permissions, isEmpty);
    });

    test('a junk entry in the embed is skipped, not fatal', () {
      final r = TeamRole.fromRow(
        _role(
          permissions: [
            {'permission_key': 'menu.edit'},
            {'something_else': 1},
            'nonsense',
          ],
        ),
      );
      expect(r.permissions, {'menu.edit'});
    });

    test('a colour that is not #rrggbb falls back to the server default', () {
      for (final bad in <Object?>[null, 'red', '#fff', '#ffffffff', 42]) {
        expect(TeamRole.fromRow(_role(color: bad)).color, '#64748b');
      }
    });

    test('a valid colour is kept, lowercased', () {
      expect(TeamRole.fromRow(_role(color: '#D97706')).color, '#d97706');
    });

    test('the member count is unknown until it is set', () {
      final r = TeamRole.fromRow(_role());
      expect(r.countKnown, isFalse);
      expect(r.withCount(3).memberCount, 3);
      expect(r.withCount(0).countKnown, isTrue);
    });

    test('withCount keeps everything else', () {
      final r = TeamRole.fromRow(
        _role(
          isSystem: true,
          permissions: [
            {'permission_key': 'staff.edit'},
          ],
        ),
      ).withCount(2);
      expect(r.isSystem, isTrue);
      expect(r.permissions, {'staff.edit'});
      expect(r.name, 'Shift Lead');
    });
  });

  group('PermissionDef', () {
    test('an unlabelled permission renders as its key', () {
      final d = PermissionDef.fromJson({
        'key': 'menu.edit',
        'grp': 'Menu',
        'label': null,
        'sort': 230,
      });
      expect(d.label, 'menu.edit');
      expect(d.sort, 230);
    });

    test('a sort that arrives as a string still sorts', () {
      final d = PermissionDef.fromJson({
        'key': 'menu.edit',
        'grp': 'Menu',
        'label': 'Edit menu',
        'sort': '230',
      });
      expect(d.sort, 230);
    });
  });

  group('RoleDraft', () {
    test('an owner-based role always keeps staff.edit', () {
      const draft = RoleDraft(
        name: 'Owner',
        description: null,
        color: '#dc2626',
        baseRole: 'owner',
        // Deliberately cleared — this is the lockout the pin exists to stop.
        permissions: {'menu.view'},
      );
      expect(draft.effectivePermissions, contains('staff.edit'));
    });

    test('every other base role is left alone', () {
      const draft = RoleDraft(
        name: 'Shift Lead',
        description: null,
        color: '#059669',
        baseRole: 'waiter',
        permissions: {'menu.view'},
      );
      expect(draft.effectivePermissions, {'menu.view'});
    });
  });
}
