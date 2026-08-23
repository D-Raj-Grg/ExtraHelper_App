import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/data/sync/outbox.dart';
import 'package:extrahelper/data/sync/sync_providers.dart';
import 'package:extrahelper/features/tenant/app_drawer.dart';
import 'package:extrahelper/features/tenant/sync_status_bar.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The shell chrome: which doors the drawer offers, and what the sync strip
/// says. Both are permission- and state-driven, and both were wrong in the
/// same way before — a surface offered to someone the server would refuse, and
/// a status that vanished instead of staying put.

Membership _membership(String id, String name, String role) => Membership(
  tenantId: id,
  name: name,
  slug: name.toLowerCase().replaceAll(' ', '-'),
  role: role,
  currency: 'NPR',
  timezone: 'Asia/Kathmandu',
);

/// Everything an owner holds, trimmed to the keys the drawer asks about.
const _owner = {
  'tables.view',
  'order.create',
  'order.void',
  'reports.view',
  'inventory.view',
  'settings.view',
};

/// A waiter takes orders and sees the floor. Nothing else.
const _waiter = {'tables.view', 'order.create'};

Widget _drawerApp({
  required Set<String> permissions,
  List<Membership> memberships = const [],
}) {
  final ms = memberships.isEmpty
      ? [_membership('t1', 'The Sekuwa Station', 'owner')]
      : memberships;

  Widget host(String title) => Scaffold(
    appBar: AppBar(title: Text(title)),
    drawer: const AppDrawer(),
    body: const SizedBox.expand(),
  );

  return ProviderScope(
    overrides: [
      membershipsProvider.overrideWith((ref) => ms),
      permissionsProvider.overrideWith((ref) => permissions),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => host('POS')),
          GoRoute(path: '/account', builder: (_, _) => host('Account')),
          GoRoute(path: '/dashboard', builder: (_, _) => host('Dashboard')),
        ],
      ),
    ),
  );
}

Future<void> _openDrawer(WidgetTester tester) async {
  tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await tester.pumpAndSettle();
}

Widget _stripApp({
  required bool online,
  int pending = 0,
  List<OutboxEntry> dead = const [],
}) {
  return ProviderScope(
    overrides: [
      isOnlineProvider.overrideWith((ref) => Stream.value(online)),
      outboxStatusProvider.overrideWith(
        (ref) => OutboxStatus(pending: pending, dead: dead),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: SyncStrip())),
  );
}

void main() {
  group('drawer destinations', () {
    testWidgets('an owner is offered every surface', (tester) async {
      await tester.pumpWidget(_drawerApp(permissions: _owner));
      await tester.pumpAndSettle();
      await _openDrawer(tester);

      expect(find.text('POS'), findsWidgets);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Store room'), findsOneWidget);
      expect(find.text('Manager log'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
    });

    testWidgets('a waiter is offered no door the server would shut', (
      tester,
    ) async {
      await tester.pumpWidget(_drawerApp(permissions: _waiter));
      await tester.pumpAndSettle();
      await _openDrawer(tester);

      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);
      expect(find.text('Store room'), findsNothing);
      expect(find.text('Manager log'), findsNothing);
      // `settings.view` is owner and manager by default. Printing stays
      // ungated beside it: whether this phone drives a printer is a property
      // of the phone, not of the person holding it.
      expect(find.text('Settings'), findsNothing);
      expect(find.text('Printing'), findsOneWidget);
    });

    testWidgets('tapping a destination navigates to it', (tester) async {
      await tester.pumpWidget(_drawerApp(permissions: _owner));
      await tester.pumpAndSettle();
      await _openDrawer(tester);

      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Dashboard'), findsOneWidget);
    });
  });

  group('drawer header', () {
    testWidgets('one restaurant offers no switch', (tester) async {
      await tester.pumpWidget(_drawerApp(permissions: _owner));
      await tester.pumpAndSettle();
      await _openDrawer(tester);

      expect(find.text('The Sekuwa Station'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      // A picker with one option is a decision that isn't one.
      expect(find.byIcon(Icons.expand_more), findsNothing);
    });

    testWidgets('two restaurants expand to a list', (tester) async {
      await tester.pumpWidget(
        _drawerApp(
          permissions: _owner,
          memberships: [
            _membership('t1', 'The Sekuwa Station', 'owner'),
            _membership('t2', 'Momo House', 'manager'),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await _openDrawer(tester);

      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.text('Momo House'), findsNothing);

      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();

      expect(find.text('Momo House'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  });

  group('sync strip', () {
    testWidgets('online with nothing owed says nothing', (tester) async {
      await tester.pumpWidget(_stripApp(online: true));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.cloud_off), findsNothing);
      expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
    });

    testWidgets('offline says so, and says where the orders went', (
      tester,
    ) async {
      await tester.pumpWidget(_stripApp(online: false));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.textContaining('Offline'), findsOneWidget);
      expect(find.textContaining('saved on this phone'), findsOneWidget);
    });

    testWidgets('offline with a queue carries the count', (tester) async {
      await tester.pumpWidget(_stripApp(online: false, pending: 2));
      await tester.pumpAndSettle();

      expect(find.textContaining('Offline · 2 waiting'), findsOneWidget);
    });

    testWidgets('online with a queue is a count, not an alarm', (tester) async {
      await tester.pumpWidget(_stripApp(online: true, pending: 3));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
      expect(find.text('3 waiting to send'), findsOneWidget);
    });

    testWidgets('a refused write outranks the queue and asks for a person', (
      tester,
    ) async {
      await tester.pumpWidget(
        _stripApp(
          online: true,
          pending: 4,
          dead: [
            OutboxEntry(
              id: 1,
              tenantId: 't1',
              kind: OutboxKind.order,
              orderRef: 'draft:1',
              payload: const {},
              idempotencyKey: 'k1',
              attempts: 5,
              state: OutboxState.dead,
              lastError: 'Item is 86ed',
              createdAt: DateTime.utc(2026),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.report_gmailerrorred_outlined), findsOneWidget);
      expect(find.textContaining('1 write refused'), findsOneWidget);
    });
  });
}
