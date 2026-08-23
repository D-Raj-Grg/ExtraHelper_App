import 'package:extrahelper/data/supabase/team_repository.dart';
import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/features/team/role_editor_screen.dart';
import 'package:extrahelper/features/team/team_providers.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The role editor, and the two invariants that make it safe to ship.
///
/// **The owner pin.** An owner-based role that loses `staff.edit` locks every
/// owner out of this screen permanently — the only way back is SQL. The pin is
/// held in three places on purpose (the checkbox, the group Clear, and
/// `RoleDraft.effectivePermissions`); the middle one is the easiest to lose in
/// a refactor, so it gets its own test.
///
/// **The identity lock.** A seeded role's name and base role are what the RLS
/// floor keys off, so they cannot move — but its permission set is the
/// restaurant's to tune, which is the entire reason the screen exists.

/// A miniature catalog. Deliberately not the real 37: the grouping is derived
/// from `sort` order rather than a Dart constant, and a hand-built list is how
/// you prove that.
final _catalog = [
  const PermissionDef(
    key: 'dashboard.view',
    grp: 'General',
    label: 'View dashboard',
    sort: 10,
  ),
  const PermissionDef(
    key: 'staff.view',
    grp: 'General',
    label: 'View team',
    sort: 60,
  ),
  const PermissionDef(
    key: 'staff.edit',
    grp: 'General',
    label: 'Manage team & roles',
    sort: 70,
  ),
  const PermissionDef(
    key: 'order.void',
    grp: 'Order',
    label: 'Void items',
    sort: 130,
  ),
  const PermissionDef(
    key: 'menu.edit',
    grp: 'Menu',
    label: 'Edit menu',
    sort: 230,
  ),
];

Widget _harness({TeamRole? role}) => ProviderScope(
  overrides: [
    membershipsProvider.overrideWith(
      (ref) => [
        const Membership(
          tenantId: 't1',
          name: 'The Sekuwa Station',
          slug: 'sekuwa',
          role: 'owner',
          currency: 'NPR',
          timezone: 'Asia/Kathmandu',
        ),
      ],
    ),
    permissionsProvider.overrideWith(
      (ref) => const {'staff.view', 'staff.edit'},
    ),
    permissionCatalogProvider.overrideWith((ref) async => _catalog),
  ],
  child: MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: '/edit',
      routes: [
        GoRoute(
          path: '/edit',
          builder: (_, _) => RoleEditorScreen(role: role),
        ),
      ],
    ),
  ),
);

TeamRole _role({
  String name = 'Shift Lead',
  String baseRole = 'waiter',
  bool isSystem = false,
  Set<String> permissions = const {'order.void'},
}) => TeamRole(
  id: 'r1',
  name: name,
  description: 'Runs the evening',
  color: '#059669',
  baseRole: baseRole,
  isSystem: isSystem,
  permissions: permissions,
  memberCount: 1,
);

/// Pump the editor on a tall surface.
///
/// The default 800x600 test viewport puts the permission groups below the fold,
/// and a `ListView` does not build what it cannot show — so a finder for a
/// group header finds nothing for reasons that have nothing to do with the
/// behaviour under test.
Future<void> _pump(WidgetTester tester, {TeamRole? role}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_harness(role: role));
  await tester.pumpAndSettle();
}

/// The checkbox for a permission, found via its row.
CheckboxListTile _tileFor(WidgetTester tester, String label) =>
    tester.widget<CheckboxListTile>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(CheckboxListTile),
      ),
    );

Future<void> _expandGeneral(WidgetTester tester) async {
  await tester.tap(find.text('General'));
  await tester.pumpAndSettle();
}

void main() {
  group('the owner pin', () {
    testWidgets('choosing Owner checks and locks staff.edit', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Owner'));
      await tester.pumpAndSettle();
      await _expandGeneral(tester);

      final tile = _tileFor(tester, 'Manage team & roles');
      expect(tile.value, isTrue);
      // Disabled, not merely checked — a tap must not be able to clear it.
      expect(tile.onChanged, isNull);
      expect(find.text('Always on for owners'), findsOneWidget);
    });

    testWidgets('Clear on the group leaves the pin standing', (tester) async {
      // The whole lockout scenario in one gesture.
      await _pump(tester);
      await tester.tap(find.text('Owner'));
      await tester.pumpAndSettle();
      await _expandGeneral(tester);

      await tester.tap(find.text('Select all').first);
      await tester.pumpAndSettle();
      expect(_tileFor(tester, 'View team').value, isTrue);

      await tester.tap(find.text('Clear').first);
      await tester.pumpAndSettle();

      expect(_tileFor(tester, 'View team').value, isFalse);
      expect(_tileFor(tester, 'Manage team & roles').value, isTrue);
    });

    testWidgets('moving off Owner hands the checkbox back', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Owner'));
      await tester.pumpAndSettle();
      await _expandGeneral(tester);
      expect(_tileFor(tester, 'Manage team & roles').onChanged, isNull);

      await tester.tap(find.text('Cashier'));
      await tester.pumpAndSettle();

      final tile = _tileFor(tester, 'Manage team & roles');
      expect(tile.onChanged, isNotNull);
      expect(tile.value, isFalse);
      expect(find.text('Always on for owners'), findsNothing);
    });
  });

  group('the identity lock', () {
    testWidgets('a default role freezes its name and base role', (
      tester,
    ) async {
      await _pump(tester, role: _role(name: 'Waiter', isSystem: true));

      expect(find.textContaining('A default role'), findsOneWidget);
      final name = tester.widget<TextField>(
        find.ancestor(of: find.text('Name'), matching: find.byType(TextField)),
      );
      expect(name.enabled, isFalse);
    });

    testWidgets('but its permissions stay editable', (tester) async {
      await _pump(tester, role: _role(name: 'Waiter', isSystem: true));
      await _expandGeneral(tester);

      // The entire point of the screen for a seeded role.
      expect(_tileFor(tester, 'View team').onChanged, isNotNull);
    });

    testWidgets('a custom role keeps its fields', (tester) async {
      await _pump(tester, role: _role());

      expect(find.textContaining('A default role'), findsNothing);
      final name = tester.widget<TextField>(
        find.ancestor(of: find.text('Name'), matching: find.byType(TextField)),
      );
      expect(name.enabled, isTrue);
    });
  });

  group('saving', () {
    testWidgets('a nameless role cannot be created', (tester) async {
      await _pump(tester);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Create role'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('typing a name enables it', (tester) async {
      await _pump(tester);

      await tester.enterText(find.byType(TextField).first, 'Shift Lead');
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Create role'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('whitespace is not a name', (tester) async {
      await _pump(tester);

      await tester.enterText(find.byType(TextField).first, '   ');
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Create role'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('an existing role offers Save, not Create', (tester) async {
      await _pump(tester, role: _role());

      expect(find.text('Save changes'), findsOneWidget);
      expect(find.text('Create role'), findsNothing);
    });
  });

  group('the catalog drives the groups', () {
    testWidgets('groups appear in sort order, named by the server', (
      tester,
    ) async {
      await _pump(tester);

      final general = tester.getTopLeft(find.text('General')).dy;
      final order = tester.getTopLeft(find.text('Order')).dy;
      final menu = tester.getTopLeft(find.text('Menu')).dy;
      expect(general, lessThan(order));
      expect(order, lessThan(menu));
    });

    testWidgets('a group holding a selection opens itself', (tester) async {
      await _pump(tester, role: _role(permissions: const {'order.void'}));

      // Order is expanded because something in it is on; General is not.
      expect(find.text('Void items'), findsOneWidget);
      expect(find.text('View team'), findsNothing);
    });

    testWidgets('each group counts what is on', (tester) async {
      await _pump(tester, role: _role(permissions: const {'order.void'}));

      expect(find.text('1 of 1'), findsOneWidget);
      expect(find.text('0 of 3'), findsOneWidget);
    });
  });
}
