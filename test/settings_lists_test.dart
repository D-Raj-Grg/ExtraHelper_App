import 'package:extrahelper/data/print/print_models.dart';
import 'package:extrahelper/data/supabase/branches_repository.dart';
import 'package:extrahelper/data/supabase/settings_repository.dart';
import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/features/settings/branches_screen.dart';
import 'package:extrahelper/features/settings/printers_screen.dart';
import 'package:extrahelper/features/settings/receipt_settings_screen.dart';
import 'package:extrahelper/features/settings/settings_providers.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Membership _member(String role) => Membership(
  tenantId: 't1',
  name: 'The Sekuwa Station',
  slug: 'sekuwa',
  role: role,
  currency: 'NPR',
  timezone: 'Asia/Kathmandu',
);

const _branches = [
  Branch(id: 'b1', name: 'Lakeside', address: 'Baidam', isDefault: true),
  Branch(id: 'b2', name: 'Airport'),
];

final _printers = [
  const PrinterRegistryRow(
    printer: PrintPrinter(
      id: 'p1',
      name: 'Counter',
      connection: PrinterConnection.network,
      host: '192.168.1.50',
      port: 9100,
      paperWidth: 80,
      renderMode: PrinterRenderMode.text,
      isActive: true,
    ),
    docs: [
      PrinterDocAssignment(doc: 'bill', copies: 2),
      PrinterDocAssignment(doc: 'day_report', copies: 1),
    ],
  ),
  const PrinterRegistryRow(
    printer: PrintPrinter(
      id: 'p2',
      name: 'Back office',
      connection: PrinterConnection.usb,
      port: 9100,
      paperWidth: 80,
      renderMode: PrinterRenderMode.text,
      isActive: true,
    ),
    docs: [],
  ),
];

Widget _harness({
  required Widget child,
  required Set<String> permissions,
  String role = 'owner',
  TenantSettings settings = const TenantSettings(),
}) => ProviderScope(
  overrides: [
    membershipsProvider.overrideWith((ref) => [_member(role)]),
    permissionsProvider.overrideWith((ref) => permissions),
    branchesProvider.overrideWith((ref) async => _branches),
    printerRegistryProvider.overrideWith((ref) async => _printers),
    printerLimitProvider.overrideWith((ref) async => 10),
    tenantSettingsProvider.overrideWith((ref) async => settings),
  ],
  child: MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: '/',
      routes: [GoRoute(path: '/', builder: (_, _) => child)],
    ),
  ),
);

void main() {
  group('branches', () {
    testWidgets('the default branch cannot be deleted', (tester) async {
      await tester.pumpWidget(
        _harness(
          child: const BranchesScreen(),
          permissions: const {'settings.view', 'settings.edit'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lakeside'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
      // Two branches, one delete button: everything without a branch of its
      // own belongs to the default one.
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));
    });

    testWidgets('a non-manager gets a list and no controls', (tester) async {
      await tester.pumpWidget(
        _harness(
          child: const BranchesScreen(),
          role: 'waiter',
          permissions: const {'settings.view'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Airport'), findsOneWidget);
      expect(find.text('Add branch'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });
  });

  group('printers', () {
    testWidgets('the list is read-only whoever is looking', (tester) async {
      await tester.pumpWidget(
        _harness(
          child: const PrintersScreen(),
          permissions: const {'settings.view', 'settings.edit'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Counter'), findsOneWidget);
      // A phone cannot enumerate USB devices or print queues, so an editor
      // here could only ever create a printer nothing can drive.
      expect(find.text('Add printer'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('the count is shown against the plan', (tester) async {
      await tester.pumpWidget(
        _harness(
          child: const PrintersScreen(),
          permissions: const {'settings.view'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 of 10'), findsOneWidget);
    });

    testWidgets('assigned documents are named, in staff words', (tester) async {
      await tester.pumpWidget(
        _harness(
          child: const PrintersScreen(),
          permissions: const {'settings.view'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bill ×2'), findsOneWidget);
      expect(find.text('Day close (Z)'), findsOneWidget);
      // Assigning a document is the auto-print switch; a printer with none
      // still exists and can be picked by hand.
      expect(
        find.text('Fires nothing on its own — pick it by hand to print to it.'),
        findsOneWidget,
      );
    });

    testWidgets('a printer this phone cannot drive says so', (tester) async {
      await tester.pumpWidget(
        _harness(
          child: const PrintersScreen(),
          permissions: const {'settings.view'},
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('This phone cannot drive it — a computer prints this one.'),
        findsOneWidget,
      );
    });

    testWidgets('only settings.edit is offered a test page', (tester) async {
      await tester.pumpWidget(
        _harness(
          child: const PrintersScreen(),
          role: 'waiter',
          permissions: const {'settings.view'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test print'), findsNothing);
      expect(
        find.text('An owner or manager can send a test page.'),
        findsWidgets,
      );
    });
  });

  group('receipt branding', () {
    const withLogo = TenantSettings(
      receipt: ReceiptTemplate(
        header: 'Sekuwa Station',
        logoUrl: 'https://cdn.example/logo.png',
        printAssets: {
          'logo': {
            '384': {'w': 384, 'h': 96, 'data': 'AAA='},
            '416': {'w': 416, 'h': 104, 'data': 'BBB='},
            '576': {'w': 576, 'h': 144, 'data': 'CCC='},
          },
        },
      ),
    );

    testWidgets('an uploaded logo names the rolls it is prepared for', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          child: const ReceiptSettingsScreen(),
          permissions: const {'settings.view', 'settings.edit'},
          settings: withLogo,
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Prepared for 58mm, 76mm, 80mm paper.'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Prepared for 58mm, 76mm, 80mm paper.'),
        findsOneWidget,
      );
      expect(find.text('Replace'), findsWidgets);
    });

    testWidgets('a picture with no baked bytes admits it prints nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          child: const ReceiptSettingsScreen(),
          permissions: const {'settings.view', 'settings.edit'},
          settings: const TenantSettings(
            receipt: ReceiptTemplate(logoUrl: 'https://cdn.example/old.png'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final finder = find.text(
        'Uploaded, but not prepared for printing — upload it again to fix that.',
      );
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(finder, findsOneWidget);
    });

    testWidgets('a waiter is offered no branding controls', (tester) async {
      await tester.pumpWidget(
        _harness(
          child: const ReceiptSettingsScreen(),
          role: 'waiter',
          permissions: const {'settings.view'},
          settings: withLogo,
        ),
      );
      await tester.pumpAndSettle();

      // The bucket policy lets any member write into the tenant folder, so the
      // gate that actually holds is `merge_receipt_template` — owner|manager.
      // Ask the same question here rather than offering a refused control.
      expect(find.text('Replace'), findsNothing);
      expect(find.text('Remove'), findsNothing);
      expect(find.text('An owner or manager can change these.'), findsOneWidget);
    });
  });
}
