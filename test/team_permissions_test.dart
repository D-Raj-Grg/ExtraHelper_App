import 'package:extrahelper/data/supabase/team_repository.dart';
import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/features/team/team_providers.dart';
import 'package:extrahelper/features/team/team_screen.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Who gets the controls on the Team screen.
///
/// Two things are worth a test here more than anything else on this screen.
///
/// One: `staff.edit` alone must be enough, whatever base role the person sits
/// on. It did not used to be — every server-side check asked
/// `has_tenant_role(tenant,'owner','manager')` while the app asked for the key,
/// so a custom role granted `staff.edit` saw the buttons and was then refused,
/// silently for the table writes. The `team_permission_gating` migration put
/// the server on the same question; this is the test that keeps it there.
///
/// Two: an empty roster means two different things. `list_tenant_members`
/// filters rather than raises, so someone who cannot read it gets `[]` —
/// identical on the wire to a restaurant with nobody in it. Saying "no one here
/// yet" to a viewer repeats a lie the server told by omission.

const _me = 'user-me';

Membership _membership(String role) => Membership(
  tenantId: 't1',
  name: 'The Sekuwa Station',
  slug: 'sekuwa',
  role: role,
  currency: 'NPR',
  timezone: 'Asia/Kathmandu',
);

TeamMember _member({
  String? userId = 'u1',
  String email = 'cook@sekuwa.co',
  String baseRole = 'waiter',
  String status = 'active',
  String? roleName,
}) => TeamMember(
  userId: userId,
  email: email,
  baseRole: baseRole,
  roleId: roleName == null ? null : 'r-custom',
  roleName: roleName,
  status: status,
  createdAt: DateTime(2026, 8, 23),
);

TeamRole _role({
  String id = 'r1',
  String name = 'Waiter',
  String baseRole = 'waiter',
  bool isSystem = true,
}) => TeamRole(
  id: id,
  name: name,
  description: null,
  color: '#64748b',
  baseRole: baseRole,
  isSystem: isSystem,
  permissions: const {'order.create'},
  memberCount: 2,
);

Widget _harness({
  required Set<String> permissions,
  String role = 'owner',
  List<TeamMember>? roster,
  List<TeamRole>? roles,
}) => ProviderScope(
  overrides: [
    membershipsProvider.overrideWith((ref) => [_membership(role)]),
    permissionsProvider.overrideWith((ref) => permissions),
    teamMembersProvider.overrideWith((ref) async => roster ?? [_member()]),
    teamRolesProvider.overrideWith((ref) async => roles ?? [_role()]),
    // The screen reads this to hide Remove on your own row; there is no auth
    // session in a widget test, so it is supplied directly.
    myUserIdProvider.overrideWith((ref) => _me),
  ],
  // `AppScaffold` reaches for `GoRouterState` to decide whether back returns to
  // the POS, so the screen needs a real router above it, not a bare MaterialApp.
  child: MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: '/team',
      routes: [
        GoRoute(path: '/team', builder: (_, _) => const TeamScreen()),
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: SizedBox.expand()),
        ),
      ],
    ),
  ),
);

Future<void> _openMenu(WidgetTester tester, String email) async {
  await tester.tap(find.byTooltip('Actions for $email'));
  await tester.pumpAndSettle();
}

void main() {
  group('who gets in at all', () {
    testWidgets('no staff.view gets a locked screen and no tabs', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(permissions: const {'order.create'}));
      await tester.pumpAndSettle();

      expect(find.text('The team is not yours to see'), findsOneWidget);
      expect(find.text('Staff'), findsNothing);
      expect(find.text('Roles'), findsNothing);
    });

    testWidgets('staff.view alone gets the roster, read-only', (tester) async {
      await tester.pumpWidget(_harness(permissions: const {'staff.view'}));
      await tester.pumpAndSettle();

      // Worth seeing without being able to change: a manager checking who is on
      // tonight should not have to be able to remove them.
      expect(find.text('cook@sekuwa.co'), findsOneWidget);
      expect(find.textContaining('not change it'), findsOneWidget);
      expect(find.text('Add member'), findsNothing);
      expect(find.byTooltip('Actions for cook@sekuwa.co'), findsNothing);
    });
  });

  group('staff.edit is enough on its own', () {
    testWidgets('an owner gets the controls', (tester) async {
      await tester.pumpWidget(
        _harness(permissions: const {'staff.view', 'staff.edit'}),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add member'), findsOneWidget);
      expect(find.text('Join code'), findsOneWidget);
      expect(find.byTooltip('Actions for cook@sekuwa.co'), findsOneWidget);
      expect(find.textContaining('not change it'), findsNothing);
    });

    testWidgets('so does a custom role sitting on waiter', (tester) async {
      // The whole point of the migration. Before it, this person saw the
      // controls and every write was refused.
      await tester.pumpWidget(
        _harness(
          permissions: const {'staff.view', 'staff.edit'},
          role: 'waiter',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add member'), findsOneWidget);
      expect(find.byTooltip('Actions for cook@sekuwa.co'), findsOneWidget);
      expect(find.textContaining('not change it'), findsNothing);
    });
  });

  group('the empty roster is two different facts', () {
    testWidgets('an editor is told how to fill it', (tester) async {
      await tester.pumpWidget(
        _harness(
          permissions: const {'staff.view', 'staff.edit'},
          roster: const [],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No one here yet'), findsOneWidget);
    });

    testWidgets('a viewer is told it is hidden, not that it is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(permissions: const {'staff.view'}, roster: const []),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining("isn't shown to your role"), findsOneWidget);
      expect(find.text('No one here yet'), findsNothing);
    });
  });

  group('the actions a row offers', () {
    const editor = {'staff.view', 'staff.edit'};

    testWidgets('an invite can only be cancelled', (tester) async {
      await tester.pumpWidget(
        _harness(
          permissions: editor,
          roster: [
            _member(userId: null, email: 'new@hire.co', status: 'invited'),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await _openMenu(tester, 'new@hire.co');

      expect(find.text('Cancel invite'), findsOneWidget);
      expect(find.text('Change role'), findsNothing);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Remove'), findsNothing);
    });

    testWidgets('someone waiting can be approved', (tester) async {
      await tester.pumpWidget(
        _harness(
          permissions: editor,
          roster: [_member(email: 'waiting@sekuwa.co', status: 'pending')],
        ),
      );
      await tester.pumpAndSettle();
      await _openMenu(tester, 'waiting@sekuwa.co');

      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Change role'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('you are never offered a way to remove yourself', (
      tester,
    ) async {
      // `remove_member` refuses it outright, so offering it can only fail.
      await tester.pumpWidget(
        _harness(
          permissions: editor,
          roster: [_member(userId: _me, email: 'me@sekuwa.co')],
        ),
      );
      await tester.pumpAndSettle();
      await _openMenu(tester, 'me@sekuwa.co');

      expect(find.text('Remove'), findsNothing);
      expect(find.text('Change role'), findsOneWidget);
    });

    testWidgets('the last owner cannot be removed', (tester) async {
      await tester.pumpWidget(
        _harness(
          permissions: editor,
          roster: [
            _member(userId: 'u9', email: 'boss@sekuwa.co', baseRole: 'owner'),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await _openMenu(tester, 'boss@sekuwa.co');

      expect(find.text('Remove'), findsNothing);
    });

    testWidgets('one of two owners can be', (tester) async {
      await tester.pumpWidget(
        _harness(
          permissions: editor,
          roster: [
            _member(userId: 'u9', email: 'boss@sekuwa.co', baseRole: 'owner'),
            _member(
              userId: 'u8',
              email: 'cofounder@sekuwa.co',
              baseRole: 'owner',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await _openMenu(tester, 'boss@sekuwa.co');

      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('removing names the consequence, not "are you sure"', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(permissions: editor));
      await tester.pumpAndSettle();
      await _openMenu(tester, 'cook@sekuwa.co');
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('lose access'), findsOneWidget);
      expect(find.textContaining('past orders'), findsOneWidget);
      expect(find.text('Keep'), findsOneWidget);
    });
  });

  group('the roles tab', () {
    const editor = {'staff.view', 'staff.edit'};

    testWidgets('a default role cannot be deleted, a custom one can', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          permissions: editor,
          roles: [
            _role(name: 'Waiter'),
            _role(id: 'r2', name: 'Shift Lead', isSystem: false),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roles'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Delete Waiter'), findsNothing);
      expect(find.byTooltip('Delete Shift Lead'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
    });

    testWidgets('a viewer gets no delete control at all', (tester) async {
      await tester.pumpWidget(
        _harness(
          permissions: const {'staff.view'},
          roles: [_role(id: 'r2', name: 'Shift Lead', isSystem: false)],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roles'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Delete Shift Lead'), findsNothing);
    });
  });
}
