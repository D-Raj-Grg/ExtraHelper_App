import 'package:extrahelper/data/supabase/customers_repository.dart';
import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/data/sync/sync_providers.dart';
import 'package:extrahelper/features/loyalty/customer_detail_screen.dart';
import 'package:extrahelper/features/loyalty/loyalty_providers.dart';
import 'package:extrahelper/features/loyalty/loyalty_screen.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// What the Customers screens show, and to whom.
///
/// "Collect" moves money, so it is offered only on `payment.take` — the same
/// key the checkout RPCs check. The server is still the boundary; this is
/// about not drawing a door that is locked.

const _ramesh = CrmCustomer(
  id: 'c-ramesh',
  name: 'Ramesh Thapa',
  phone: '9841000000',
  points: 120,
  tier: 'silver',
  owesCents: 241500,
  unpaidBills: 1,
);

const _sita = CrmCustomer(
  id: 'c-sita',
  name: 'Sita Rai',
  email: 'sita@example.com',
  points: 40,
  tier: 'bronze',
);

const _overview = CrmOverview(
  customers: [_ramesh, _sita],
  totalOwedCents: 241500,
  debtors: 1,
  feedback: [],
);

final _history = [
  CustomerBillRow(
    billId: 'bill-1',
    createdAt: DateTime(2026, 9, 20, 19, 30),
    status: 'partial',
    totalCents: 300000,
    paidCents: 58500,
    outstandingCents: 241500,
    tableLabel: 'A1',
    itemsSummary: 'Sekuwa set ×2, Momo ×1',
  ),
  // Open, but nothing left on it — still an unpaid bill by status, so it is
  // listed for closing rather than hidden as if it were paid.
  CustomerBillRow(
    billId: 'bill-settled',
    createdAt: DateTime(2026, 9, 10, 12, 0),
    status: 'open',
    totalCents: 50000,
    paidCents: 50000,
    outstandingCents: 0,
  ),
  CustomerBillRow(
    billId: 'bill-void',
    createdAt: DateTime(2026, 9, 5, 12, 0),
    status: 'void',
    totalCents: 9900,
    paidCents: 0,
    outstandingCents: 0,
    itemsSummary: 'Voided sekuwa',
  ),
  CustomerBillRow(
    billId: 'bill-0',
    createdAt: DateTime(2026, 9, 1, 20, 0),
    status: 'paid',
    totalCents: 120000,
    paidCents: 120000,
    outstandingCents: 0,
    itemsSummary: 'Dal bhat ×2',
  ),
];

Widget _app({required Set<String> permissions, required Widget home}) {
  return ProviderScope(
    overrides: [
      membershipsProvider.overrideWith(
        (ref) => [
          Membership(
            tenantId: 't1',
            name: 'The Sekuwa Station',
            slug: 'sekuwa',
            role: 'manager',
            currency: 'NPR',
            timezone: 'Asia/Kathmandu',
          ),
        ],
      ),
      permissionsProvider.overrideWith((ref) => permissions),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      crmOverviewProvider.overrideWith((ref) async => _overview),
      // The detail resolves its guest by id, never off the overview list —
      // a search on the list must not blank the page behind it.
      customerProvider.overrideWith(
        (ref, id) async => switch (id) {
          'c-ramesh' => _ramesh,
          'c-sita' => _sita,
          _ => null,
        },
      ),
      customerHistoryProvider.overrideWith((ref, id) async => _history),
    ],
    // AppScaffold reads the router for its back handling, so the screen
    // must sit under a GoRoute even in a test.
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [GoRoute(path: '/', builder: (_, _) => home)],
      ),
    ),
  );
}

void main() {
  testWidgets('the list shows every customer and flags the one who owes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(permissions: const {'loyalty.view'}, home: const LoyaltyScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ramesh Thapa'), findsOneWidget);
    expect(find.text('Sita Rai'), findsOneWidget);
    expect(find.textContaining('Owes'), findsOneWidget);
    expect(find.text('1 unpaid bill'), findsOneWidget);
    // The banner totals the tab across the restaurant.
    expect(
      find.textContaining(
        'Outstanding credit · NPR 2,415.00 across 1 customer',
      ),
      findsOneWidget,
    );
  });

  testWidgets('without loyalty.view the screen is a locked door', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(permissions: const {'order.view'}, home: const LoyaltyScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('No customer access'), findsOneWidget);
    expect(find.text('Ramesh Thapa'), findsNothing);
  });

  testWidgets('a cashier with payment.take can collect an unpaid bill', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        permissions: const {'loyalty.view', 'payment.take'},
        home: const CustomerDetailScreen(customerId: 'c-ramesh'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ramesh Thapa'), findsOneWidget);
    expect(find.text('Silver'), findsOneWidget);
    // Two open/partial bills, Collect on each — the settled-but-open one
    // says so instead of quoting a debt, and the void one is not shown.
    expect(find.text('Collect'), findsNWidgets(2));
    expect(find.textContaining('owes NPR 2,415.00'), findsOneWidget);
    expect(find.textContaining('nothing left to collect'), findsOneWidget);
    expect(find.text('Voided sekuwa'), findsNothing);
    // Points controls need loyalty.edit, which this person lacks.
    expect(find.text('Earn'), findsNothing);
  });

  testWidgets('the detail is found by id, not by scanning the list', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        permissions: const {'loyalty.view'},
        home: const CustomerDetailScreen(customerId: 'c-sita'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sita Rai'), findsOneWidget);
    expect(find.text('sita@example.com'), findsOneWidget);
  });

  testWidgets('an unknown id says so instead of spinning', (tester) async {
    await tester.pumpWidget(
      _app(
        permissions: const {'loyalty.view'},
        home: const CustomerDetailScreen(customerId: 'c-nobody'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Customer not found'), findsOneWidget);
  });

  testWidgets('the detail is the same locked door without loyalty.view', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        permissions: const {'order.view'},
        home: const CustomerDetailScreen(customerId: 'c-ramesh'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No customer access'), findsOneWidget);
    expect(find.text('Silver'), findsNothing);
  });

  testWidgets('without payment.take there is no Collect button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        permissions: const {'loyalty.view', 'loyalty.edit'},
        home: const CustomerDetailScreen(customerId: 'c-ramesh'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Collect'), findsNothing);
    // The bill is still listed — a manager may need to quote the figure.
    expect(find.textContaining('owes NPR 2,415.00'), findsOneWidget);
    expect(find.text('Earn'), findsOneWidget);
    expect(find.text('Redeem'), findsOneWidget);
  });
}
