import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:extrahelper/data/sync/sync_providers.dart';
import 'package:extrahelper/features/pos/bill_models.dart';
import 'package:extrahelper/features/pos/bill_providers.dart';
import 'package:extrahelper/features/pos/checkout_screen.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the checkout screen offers, and to whom.
///
/// These are the tests worth having on this screen: every control here either
/// moves money or changes what a guest is charged, so a control that appears
/// for someone the server would refuse is a bug shaped like a security hole —
/// they tap it, the RPC says no, and they have already told the guest a number.
///
/// The permission keys are the same ones the RPCs check. The server is still
/// the boundary; this is about not offering a door that is locked.

const _billId = 'bill-1111-2222-3333-444444444444';

/// A fake that answers with a fixture and never touches Supabase.
class _FixedSnapshot extends BillSnapshotNotifier {
  _FixedSnapshot(this.value);

  final BillSnapshot value;

  @override
  Future<BillSnapshot> build(String billId) async => value;
}

BillSnapshot _snapshot({
  String status = 'open',
  int totalCents = 1000,
  int paidCents = 0,
  BillCustomer? customer,
}) => BillSnapshot(
  bill: Bill(
    id: _billId,
    status: status,
    createdAt: DateTime(2026, 8, 13),
    subtotalCents: totalCents,
    taxCents: 0,
    serviceChargeCents: 0,
    discountCents: 0,
    tipCents: 0,
    roundingCents: 0,
    totalCents: totalCents,
    tableLabel: 'A1',
  ),
  lines: const [
    BillLine(
      id: 'l1',
      orderItemId: 'oi1',
      description: 'Dal bhat',
      qty: 1,
      unitPriceCents: 1000,
      totalCents: 1000,
    ),
  ],
  payments: [
    if (paidCents > 0)
      PaymentRow(
        id: 'p1',
        method: 'cash',
        amountCents: paidCents,
        createdAt: DateTime(2026, 8, 13),
      ),
  ],
  charges: const [],
  discounts: const [],
  settings: const TenantMoneySettings(),
  customer: customer,
);

Widget _app({
  required Set<String> permissions,
  required BillSnapshot snapshot,
  bool online = true,
  String role = 'cashier',
}) {
  return ProviderScope(
    overrides: [
      membershipsProvider.overrideWith(
        (ref) => [
          Membership(
            tenantId: 't1',
            name: 'The Sekuwa Station',
            slug: 'sekuwa',
            role: role,
            currency: 'NPR',
            timezone: 'Asia/Kathmandu',
          ),
        ],
      ),
      permissionsProvider.overrideWith((ref) => permissions),
      isOnlineProvider.overrideWith((ref) => Stream.value(online)),
      // The family as a whole: an override per argument isn't a thing for a
      // family notifier, and this screen only ever asks for the one bill.
      billSnapshotProvider.overrideWith(() => _FixedSnapshot(snapshot)),
    ],
    child: const MaterialApp(home: CheckoutScreen(billId: _billId)),
  );
}

void main() {
  const cashier = {'checkout.view', 'payment.take'};
  const manager = {
    'checkout.view',
    'payment.take',
    'order.discount',
    'order.void',
    'payment.refund',
  };

  testWidgets('a cashier can take payment and split it', (tester) async {
    await tester.pumpWidget(_app(permissions: cashier, snapshot: _snapshot()));
    await tester.pumpAndSettle();

    expect(find.text('Take payment'), findsOneWidget);
    expect(find.text('Split the check'), findsOneWidget);
  });

  testWidgets('without payment.take there is no way to commit money', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(permissions: const {'checkout.view'}, snapshot: _snapshot()),
    );
    await tester.pumpAndSettle();

    // The bill is still readable — a waiter may need to quote the total.
    expect(find.text('Totals'), findsOneWidget);
    expect(find.text('Take payment'), findsNothing);
    expect(find.text('Split the check'), findsNothing);
  });

  testWidgets('a cashier without order.discount cannot adjust the bill', (
    tester,
  ) async {
    await tester.pumpWidget(_app(permissions: cashier, snapshot: _snapshot()));
    await tester.pumpAndSettle();

    // The adjustments sheet is where discounts, charges and complimentary
    // live. It opens on `order.discount` OR `payment.take` — a cashier holds
    // the latter, so the button is there…
    expect(find.text('Discounts, charges, tip'), findsOneWidget);
    await tester.tap(find.text('Discounts, charges, tip'));
    await tester.pumpAndSettle();

    // …but the manager-gated levers inside it are not.
    expect(find.text('Discount the whole bill'), findsNothing);
    expect(find.text('Extra charge'), findsNothing);
    expect(find.text('On the house'), findsNothing);
    // What a cashier does hold.
    expect(find.text('Coupon'), findsOneWidget);
    expect(find.text('Tip, round off and remark'), findsOneWidget);
  });

  testWidgets('a manager gets the discount levers', (tester) async {
    await tester.pumpWidget(
      _app(permissions: manager, snapshot: _snapshot(), role: 'manager'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Discounts, charges, tip'));
    await tester.pumpAndSettle();

    expect(find.text('Discount the whole bill'), findsOneWidget);
    expect(find.text('Extra charge'), findsOneWidget);
    expect(find.text('On the house'), findsOneWidget);
  });

  testWidgets(
    'the discount key alone is not enough — the RPC wants a manager too',
    (tester) async {
      // A restaurant can grant `order.discount` to a custom role. Both discount
      // RPCs also check `has_tenant_role(owner, manager)`, so the button would
      // fail every time with "discounts require a manager".
      await tester.pumpWidget(
        _app(permissions: manager, snapshot: _snapshot(), role: 'cashier'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Discounts, charges, tip'));
      await tester.pumpAndSettle();

      expect(find.text('Discount the whole bill'), findsNothing);
      // Charges and complimentary check the key and no role, so they stay.
      expect(find.text('Extra charge'), findsOneWidget);
      expect(find.text('On the house'), findsOneWidget);
    },
  );

  testWidgets('a refund needs the manager role as well as the key', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        permissions: manager,
        snapshot: _snapshot(status: 'paid', paidCents: 1000),
        role: 'cashier',
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Refund'), findsNothing);
  });

  testWidgets('a settled bill takes no more money, and can be refunded', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        permissions: manager,
        snapshot: _snapshot(status: 'paid', paidCents: 1000),
        role: 'manager',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Take payment'), findsNothing);
    expect(find.text('Split the check'), findsNothing);
    expect(find.text('Discounts, charges, tip'), findsNothing);
    expect(find.text('Settled'), findsOneWidget);

    // Refund sits at the foot of the page, deliberately past everything else.
    await tester.dragUntilVisible(
      find.text('Refund'),
      find.byType(ListView),
      const Offset(0, -80),
    );
    expect(find.text('Refund'), findsOneWidget);
  });

  testWidgets('no payment.refund, no refund button', (tester) async {
    await tester.pumpWidget(
      _app(
        permissions: cashier,
        snapshot: _snapshot(status: 'paid', paidCents: 1000),
      ),
    );
    await tester.pumpAndSettle();
    // Scroll to the foot: absent because the permission is missing, not
    // because it is below the fold.
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Refund'), findsNothing);
  });

  testWidgets('offline says so, and the button is dead rather than absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(permissions: cashier, snapshot: _snapshot(), online: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Offline — payment needs a connection.'), findsOneWidget);
    // Present but disabled: a missing button reads as "this bill can't be
    // paid", which is a different and wronger thing than "not right now".
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Take payment'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('a voided bill is not called settled', (tester) async {
    // Both stop the buttons, but this band is what a cashier reads to answer
    // "has this been paid?" — and a voided bill has not been.
    await tester.pumpWidget(
      _app(
        permissions: cashier,
        snapshot: _snapshot(status: 'void'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Voided'), findsOneWidget);
    expect(find.text('Settled'), findsNothing);
    expect(find.text('Take payment'), findsNothing);
  });

  testWidgets('the due figure is what is left, not the total', (tester) async {
    await tester.pumpWidget(
      _app(
        permissions: cashier,
        snapshot: _snapshot(status: 'partial', paidCents: 400),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Due'), findsOneWidget);
    expect(find.text('NPR 6.00'), findsOneWidget);
    expect(find.text('Part paid'), findsOneWidget);
  });
}
