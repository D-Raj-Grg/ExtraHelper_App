import 'dart:async';

import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/data/sync/sync_providers.dart';
import 'package:extrahelper/features/tenant/app_drawer.dart';
import 'package:extrahelper/features/tenant/home_shell.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// What the shell says when it does not yet know who you are.
///
/// The bug: on a weak signal the identity reads had not landed, every
/// permission gate read false, and the app presented that as a verdict — an
/// empty drawer and a spinner that could sit there indefinitely with no word of
/// what it was waiting for. A waiter reads that as "I have been locked out".
/// None of these states may render a verdict, and none may be a dead end.

const _member = Membership(
  tenantId: 't1',
  name: 'The Sekuwa Station',
  slug: 'the-sekuwa-station',
  role: 'waiter',
  currency: 'NPR',
  timezone: 'Asia/Kathmandu',
);

enum _Identity { unknown, failed, readyWithPos, readyWithoutPos }

/// Built once and reused. A `GoRouter` constructed inside `build` is a new
/// router on every rebuild, which tears the previous one's screens down
/// mid-flight — the shell's `TabController` then trips on a deactivated
/// ancestor at teardown.
GoRouter _routerFor(Widget home) => GoRouter(
  routes: [GoRoute(path: '/', builder: (context, state) => home)],
);

Widget _shell(_Identity identity, {bool online = true}) {
  final memberships = switch (identity) {
    _Identity.unknown => null,
    _ => [_member],
  };
  final router = _routerFor(const HomeShell());

  return ProviderScope(
    overrides: [
      membershipsProvider.overrideWith(
        (ref) => switch (identity) {
          _Identity.unknown => Completer<List<Membership>?>().future,
          _ => memberships,
        },
      ),
      permissionsProvider.overrideWith(
        (ref) => switch (identity) {
          _Identity.unknown => Completer<Set<String>>().future,
          _Identity.failed => throw Exception('no route to host'),
          _Identity.readyWithPos => {'tables.view', 'order.create'},
          _Identity.readyWithoutPos => {'kds.view'},
        },
      ),
      isOnlineProvider.overrideWith((ref) => Stream.value(online)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('the shell never renders a verdict it cannot back', () {
    testWidgets('unknown says what it is waiting for, and offers a nudge', (
      tester,
    ) async {
      await tester.pumpWidget(_shell(_Identity.unknown));
      await tester.pump();

      expect(find.text('Checking what you can do here'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // The sentence the user reported. It is a verdict, and there is no
      // answer to base one on yet.
      expect(find.text('No ordering access'), findsNothing);
      expect(find.byType(TabBar), findsNothing);
    });

    testWidgets('a failed read explains itself instead of spinning', (
      tester,
    ) async {
      await tester.pumpWidget(_shell(_Identity.failed));
      await tester.pump();

      expect(
        find.text("Couldn't load your access for this restaurant."),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No ordering access'), findsNothing);
    });

    testWidgets('offline says the thing that is actually true', (tester) async {
      await tester.pumpWidget(_shell(_Identity.failed, online: false));
      await tester.pump();

      // Being offline is a state, not an error, and its remedy is different.
      expect(find.textContaining("You're offline"), findsOneWidget);
      expect(find.textContaining('Connect once'), findsOneWidget);
    });

    testWidgets('a real lockout still reads as one', (tester) async {
      await tester.pumpWidget(_shell(_Identity.readyWithoutPos));
      await tester.pump();

      // Kitchen role, permissions known: this verdict is earned.
      expect(find.text('No ordering access'), findsOneWidget);
    });

    testWidgets('a waiter with keys gets the POS', (tester) async {
      await tester.pumpWidget(_shell(_Identity.readyWithPos));
      await tester.pump();

      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('No ordering access'), findsNothing);
    });
  });

  group('the drawer does not let a gap speak for itself', () {
    Widget drawerApp(_Identity identity) {
      final router = _routerFor(
        const Scaffold(drawer: AppDrawer(), body: SizedBox.expand()),
      );
      return ProviderScope(
        overrides: [
          membershipsProvider.overrideWith(
            (ref) => switch (identity) {
              _Identity.unknown => Completer<List<Membership>?>().future,
              _ => [_member],
            },
          ),
          permissionsProvider.overrideWith(
            (ref) => switch (identity) {
              _Identity.unknown => Completer<Set<String>>().future,
              _Identity.failed => throw Exception('offline'),
              _ => {'tables.view', 'order.create'},
            },
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      );
    }

    testWidgets('unknown names the wait rather than hiding every door', (
      tester,
    ) async {
      await tester.pumpWidget(drawerApp(_Identity.unknown));
      await tester.pump();
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      // Not `pumpAndSettle`: the waiting row spins, so there is nothing to
      // settle to. Pump past the drawer's own opening animation instead.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Checking your access…'), findsOneWidget);
      // The ungated doors are still there — nothing about them depends on a
      // permission that has not arrived.
      expect(find.text('POS'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
      // And nothing gated has appeared, because a door that shows up late is
      // fine and one that vanishes under a thumb is not.
      expect(find.text('Kitchen'), findsNothing);
    });

    testWidgets('a failed read offers the way back', (tester) async {
      await tester.pumpWidget(drawerApp(_Identity.failed));
      await tester.pump();
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load your access"), findsOneWidget);
      expect(find.text('Tap to try again'), findsOneWidget);
    });

    testWidgets('a resolved drawer says none of that', (tester) async {
      await tester.pumpWidget(drawerApp(_Identity.readyWithPos));
      await tester.pump();
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('Checking your access…'), findsNothing);
      expect(find.text("Couldn't load your access"), findsNothing);
    });
  });
}
