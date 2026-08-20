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
  DateTime? printedAt,
  int? printedTotalCents,
  // Null by default, which is what a merged tab reads as: the screen then
  // offers nothing rather than putting one table's round on another's order.
  String? orderId,
  List<BillLine>? lines,
}) => BillSnapshot(
  orderId: orderId,
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
    printedAt: printedAt,
    printedTotalCents: printedTotalCents,
  ),
  lines:
      lines ??
      const [
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
    // Down the page, and the body is lazy: on a short screen the split button
    // has not been built until it is scrolled to.
    await tester.scrollUntilVisible(find.text('Split the check'), 200);
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

  testWidgets('a wrongly-added item can be taken off from the list', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(permissions: manager, snapshot: _snapshot(), role: 'manager'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove Dal bhat'));
    await tester.pumpAndSettle();

    // The reason is the server's requirement, not a nicety: `void_order_item`
    // refuses without one.
    expect(find.text('Remove Dal bhat?'), findsOneWidget);
  });

  testWidgets('without order.void there is no delete button on a line', (
    tester,
  ) async {
    await tester.pumpWidget(_app(permissions: cashier, snapshot: _snapshot()));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Remove Dal bhat'), findsNothing);
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

  // --- another round on a bill that is out but unpaid ---------------------
  //
  // The slip is printed, the guest asks for one more beer, and nobody has paid
  // yet. `amend_order_add_item` allows exactly that, and only that: once money
  // has moved the order is shut and the round belongs on a fresh one. A button
  // offered a moment later than the server allows is a waiter promising a
  // guest something the RPC is about to refuse.

  /// Walks to the foot of the lazy list, so a `findsNothing` means the control
  /// is absent rather than merely unbuilt.
  Future<void> toFoot(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
    }
  }

  const orderTaker = {'checkout.view', 'payment.take', 'order.create'};

  testWidgets('an unpaid bill for one table can still take another round', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        permissions: orderTaker,
        snapshot: _snapshot(orderId: 'order-1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Add items'),
      find.byType(ListView),
      const Offset(0, -80),
    );
    expect(find.text('Add items'), findsOneWidget);
    expect(find.text('More for this table'), findsOneWidget);
  });

  testWidgets('without order.create the round is somebody else\'s job', (
    tester,
  ) async {
    // The same fixture as above but for the one key. If this passed with the
    // cashier set, the test above would be proving nothing.
    await tester.pumpWidget(
      _app(
        permissions: cashier,
        snapshot: _snapshot(orderId: 'order-1'),
      ),
    );
    await tester.pumpAndSettle();
    await toFoot(tester);

    expect(find.text('Add items'), findsNothing);
  });

  testWidgets('once a payment has landed the round goes on a new order', (
    tester,
  ) async {
    // record_payment rolls the bill to `partial`, and the RPC refuses it with
    // "this bill has already taken a payment".
    await tester.pumpWidget(
      _app(
        permissions: orderTaker,
        snapshot: _snapshot(
          status: 'partial',
          paidCents: 400,
          orderId: 'order-1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await toFoot(tester);

    expect(find.text('Add items'), findsNothing);
  });

  testWidgets('a paid bill is finished, however much the table wants', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        permissions: orderTaker,
        snapshot: _snapshot(
          status: 'paid',
          paidCents: 1000,
          orderId: 'order-1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await toFoot(tester);

    expect(find.text('Add items'), findsNothing);
  });

  testWidgets('a voided bill takes no more food either', (tester) async {
    await tester.pumpWidget(
      _app(
        permissions: orderTaker,
        snapshot: _snapshot(status: 'void', orderId: 'order-1'),
      ),
    );
    await tester.pumpAndSettle();
    await toFoot(tester);

    expect(find.text('Add items'), findsNothing);
  });

  testWidgets('offline the round is not offered at all', (tester) async {
    // Unlike payment and printing, this one is absent rather than disabled: an
    // amend queued offline against a bill someone settles in the meantime
    // resolves as a dead outbox row, after the guest has been given a total.
    await tester.pumpWidget(
      _app(
        permissions: orderTaker,
        snapshot: _snapshot(orderId: 'order-1'),
        online: false,
      ),
    );
    await tester.pumpAndSettle();
    await toFoot(tester);

    expect(find.text('Add items'), findsNothing);
  });

  testWidgets('a merged tab cannot say whose round it would be', (
    tester,
  ) async {
    // Two tables on one ticket. Picking either order sends table 6's beer to
    // table 5 — the web shipped exactly that. Staff add it from the floor.
    await tester.pumpWidget(
      _app(permissions: orderTaker, snapshot: _snapshot()),
    );
    await tester.pumpAndSettle();
    await toFoot(tester);

    expect(find.text('Add items'), findsNothing);
  });

  // --- presenting the bill -------------------------------------------------
  //
  // The guest reads the slip, then pays it. Until this existed the only paper a
  // bill produced came *after* the money had already moved, which is the wrong
  // way round at every table in the world.

  testWidgets('the bill can be printed before a rupee moves', (tester) async {
    await tester.pumpWidget(_app(permissions: cashier, snapshot: _snapshot()));
    await tester.pumpAndSettle();

    expect(find.text('Print bill'), findsOneWidget);
    // Above payment, not beside it: the order of the buttons is the order of
    // the transaction.
    final print = tester.getCenter(find.text('Print bill'));
    final pay = tester.getCenter(find.text('Take payment'));
    expect(print.dy, lessThan(pay.dy));
  });

  testWidgets('reading the bill needs no key to charge for it', (tester) async {
    // A waiter can hand a table its slip. Taking the money is another matter,
    // and `enqueue_print_job` only wants `checkout.view` for a bill.
    await tester.pumpWidget(
      _app(permissions: const {'checkout.view'}, snapshot: _snapshot()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Print bill'), findsOneWidget);
    expect(find.text('Take payment'), findsNothing);
  });

  testWidgets('a settled bill offers the receipt, not the bill', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        permissions: cashier,
        snapshot: _snapshot(status: 'paid', paidCents: 1000),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Print bill'), findsNothing);
    expect(find.text('Print receipt'), findsOneWidget);
  });

  testWidgets('a bill printed once offers a reprint, not a first print', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        permissions: cashier,
        snapshot: _snapshot(
          printedAt: DateTime(2026, 8, 13, 20, 15),
          printedTotalCents: 1000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reprint bill'), findsOneWidget);
    expect(find.text('Print bill'), findsNothing);
    // Nothing has changed since, so nothing to warn about.
    expect(find.textContaining('changed after it was printed'), findsNothing);
  });

  testWidgets('another round after the slip went out is said out loud', (
    tester,
  ) async {
    // Nothing is locked by printing — a table that orders again is normal. What
    // is not normal is charging a guest a total they never saw.
    await tester.pumpWidget(
      _app(
        permissions: cashier,
        snapshot: _snapshot(
          totalCents: 1600,
          printedAt: DateTime(2026, 8, 13, 20, 15),
          printedTotalCents: 1000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('changed after it was printed'), findsOneWidget);
    expect(find.text('Reprint bill'), findsOneWidget);
    // Still payable: this is a warning, not a gate.
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Take payment'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('offline, printing is dead rather than absent', (tester) async {
    // Same reasoning as the payment button: a missing one reads as "this bill
    // cannot be printed", which is a different and wronger thing.
    await tester.pumpWidget(
      _app(permissions: cashier, snapshot: _snapshot(), online: false),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Print bill'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('the same beer rung up twice reads as one line of two', (
    tester,
  ) async {
    // Two `bill_items` rows is what a second round actually produces —
    // `amend_order_add_item` inserts one per tap. The guest counts drinks, not
    // rows, so the card folds them the way the printed slip already does.
    await tester.pumpWidget(
      _app(
        permissions: cashier,
        snapshot: _snapshot(
          totalCents: 90000,
          lines: const [
            BillLine(
              id: 'l1',
              orderItemId: 'oi1',
              description: 'Tuborg',
              qty: 1,
              unitPriceCents: 45000,
              totalCents: 45000,
            ),
            BillLine(
              id: 'l2',
              orderItemId: 'oi2',
              description: 'Tuborg',
              qty: 1,
              unitPriceCents: 45000,
              totalCents: 45000,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tuborg'), findsOneWidget);
    expect(find.textContaining('2 × '), findsOneWidget);
    expect(find.textContaining('2 rounds'), findsOneWidget);
  });

  testWidgets('removing from a folded line asks which one first', (
    tester,
  ) async {
    // Every write behind this card takes a single `order_item_id`. Folding is
    // for reading; the moment someone wants to change one, they have to say
    // which of the rows they mean.
    await tester.pumpWidget(
      _app(
        permissions: manager,
        role: 'manager',
        snapshot: _snapshot(
          totalCents: 90000,
          lines: const [
            BillLine(
              id: 'l1',
              orderItemId: 'oi1',
              description: 'Tuborg',
              qty: 1,
              unitPriceCents: 45000,
              totalCents: 45000,
            ),
            BillLine(
              id: 'l2',
              orderItemId: 'oi2',
              description: 'Tuborg',
              qty: 1,
              unitPriceCents: 45000,
              totalCents: 45000,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove Tuborg'));
    await tester.pumpAndSettle();

    expect(find.text('Remove which Tuborg?'), findsOneWidget);
    expect(find.textContaining('rung up 2 times'), findsOneWidget);
  });

  testWidgets('the bill says when it was opened', (tester) async {
    // An unpaid bill outlives midnight on purpose. Without a date on it, one
    // left from last night looks exactly like one opened ten minutes ago.
    await tester.pumpWidget(_app(permissions: cashier, snapshot: _snapshot()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Aug 13, 2026'), findsOneWidget);
  });
}
