import 'dart:async';

import 'package:extrahelper/data/supabase/settings_repository.dart';
import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/features/settings/general_settings_screen.dart';
import 'package:extrahelper/features/settings/settings_hub_screen.dart';
import 'package:extrahelper/features/settings/settings_providers.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Settings on the phone.
///
/// Every write behind these screens is gated again by RLS, so what is tested
/// here is honesty: nobody is offered a control the server will refuse, and
/// nobody is told something saved when it did not.

Membership _member(String role) => Membership(
  tenantId: 't1',
  name: 'The Sekuwa Station',
  slug: 'sekuwa',
  role: role,
  currency: 'NPR',
  timezone: 'Asia/Kathmandu',
);

const _settings = TenantSettings(
  currency: 'NPR',
  timezone: 'Asia/Kathmandu',
  dayCutoffMinutes: 240,
  serviceCharge: 10,
  packagingFee: 25.5,
  paymentGateway: 'manual',
);

Widget _harness({
  required Widget child,
  required Set<String> permissions,
  String role = 'owner',
  bool permissionsPending = false,
}) => ProviderScope(
  overrides: [
    membershipsProvider.overrideWith((ref) => [_member(role)]),
    permissionsProvider.overrideWith((ref) async {
      // A future that never completes stands in for the real gap between
      // launch and `get_my_permissions` answering.
      if (permissionsPending) return Completer<Set<String>>().future;
      return permissions;
    }),
    tenantSettingsProvider.overrideWith((ref) async => _settings),
  ],
  // A real router, because `AppScaffold` hangs the drawer off `GoRouterState`
  // and the hub's rows push routes.
  child: MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: '/',
      routes: [GoRoute(path: '/', builder: (_, _) => child)],
    ),
  ),
);

/// Scrolls the list until [finder] is on screen. A settings screen is taller
/// than a test viewport, and `findsNothing` on something below the fold says
/// nothing about whether it exists.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 120, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  group('the hub only offers doors that open', () {
    testWidgets('an owner sees every section', (tester) async {
      await tester.pumpWidget(
        _harness(
          child: const SettingsHubScreen(),
          permissions: const {'settings.view', 'settings.edit'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('General'), findsOneWidget);
      expect(find.text('Charges & tax'), findsOneWidget);
      expect(find.text('Receipt & branding'), findsOneWidget);
      expect(find.text('Branches'), findsOneWidget);
      expect(find.text('Printers'), findsOneWidget);
      expect(find.text('Plan & usage'), findsOneWidget);
      await _reveal(tester, find.text('Dangerous area'));
      expect(find.text('Dangerous area'), findsOneWidget);
    });

    testWidgets('a manager gets everything but the dangerous area', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          child: const SettingsHubScreen(),
          role: 'manager',
          permissions: const {'settings.view', 'settings.edit'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('General'), findsOneWidget);
      expect(find.text('Plan & usage'), findsOneWidget);
      // Reset, transfer and delete are the owner's alone, and every RPC
      // behind them re-checks that.
      expect(find.text('Dangerous area'), findsNothing);
    });

    testWidgets('a waiter sees only what belongs to them and the device', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          child: const SettingsHubScreen(),
          role: 'waiter',
          permissions: const {'checkout.view'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('General'), findsNothing);
      expect(find.text('Charges & tax'), findsNothing);
      expect(find.text('Printers'), findsNothing);
      // Their own profile and this phone's appearance are nobody else's
      // business to gate.
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
    });

    testWidgets('while permissions load the screen is not empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          child: const SettingsHubScreen(),
          permissions: const {},
          permissionsPending: true,
        ),
      );
      await tester.pump();

      // `hasPermissionProvider` answers false while loading, so reading it
      // here would draw a blank page that then pops rows in under the thumb
      // already moving towards one.
      expect(find.byType(ListTile), findsWidgets);
      expect(find.text('General'), findsNothing);
    });
  });

  group('General', () {
    testWidgets('an owner can rename the restaurant', (tester) async {
      await tester.pumpWidget(
        _harness(
          child: const GeneralSettingsScreen(),
          permissions: const {'settings.view', 'settings.edit'},
        ),
      );
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'The Sekuwa Station'),
      );
      expect(field.enabled, isTrue);
      expect(find.text('Only the owner can rename the restaurant.'), findsNothing);
    });

    testWidgets('a manager is told the name is not theirs to change', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          child: const GeneralSettingsScreen(),
          role: 'manager',
          permissions: const {'settings.view', 'settings.edit'},
        ),
      );
      await tester.pumpAndSettle();

      // `tenants_owner_update` is stricter than `tenant_settings_owner_write`,
      // and a rename that matches zero rows returns 200 — so the field is
      // disabled rather than silently ignored.
      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'The Sekuwa Station'),
      );
      expect(field.enabled, isFalse);
      expect(
        find.text('Only the owner can rename the restaurant.'),
        findsOneWidget,
      );
    });

    testWidgets('view without edit gets no save button at all', (tester) async {
      await tester.pumpWidget(
        _harness(
          child: const GeneralSettingsScreen(),
          role: 'manager',
          permissions: const {'settings.view'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
      expect(find.text('An owner or manager can change these.'), findsOneWidget);
    });

    testWidgets('moving the day cutoff warns before it saves', (tester) async {
      await tester.pumpWidget(
        _harness(
          child: const GeneralSettingsScreen(),
          permissions: const {'settings.view', 'settings.edit'},
        ),
      );
      await tester.pumpAndSettle();

      await _reveal(tester, find.text('Midnight'));
      await tester.tap(find.text('Midnight'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Retroactive, not destructive — which surprises people more.
      expect(find.text('Start the day at Midnight?'), findsOneWidget);
      expect(find.textContaining('re-buckets every past day'), findsOneWidget);
    });

    testWidgets('the current settings are shown as chosen', (tester) async {
      await tester.pumpWidget(
        _harness(
          child: const GeneralSettingsScreen(),
          permissions: const {'settings.view', 'settings.edit'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NPR'), findsOneWidget);
      expect(find.text('4:00 am'), findsOneWidget);
      await _reveal(tester, find.text('Manual / cash-terminal'));
      expect(find.text('Manual / cash-terminal'), findsOneWidget);
    });
  });
}
