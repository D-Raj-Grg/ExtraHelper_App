import 'package:extrahelper/features/pos/bill_models.dart';
import 'package:extrahelper/features/pos/checkout_payment_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the cashier can be handed, and what travels back out of the sheet.
///
/// The wallet methods are record-only: nothing is charged, so the sheet can
/// offer them the way it offers cash. `online` is the one that must stay off
/// the phone — the web charges it through a gateway adapter with no RPC behind
/// it, so a phone offering it would log money nobody collected.
///
/// The reference is the other half. It is the guest's transaction id, and it
/// has to belong to the method that was actually selected — a cashier who
/// types an eSewa id, changes their mind and takes cash must not have that id
/// land on the cash payment.

const _billId = 'bill-1111-2222-3333-444444444444';

BillSnapshot _snapshot({int totalCents = 45000}) => BillSnapshot(
  bill: Bill(
    id: _billId,
    status: 'open',
    createdAt: DateTime(2026, 8, 14),
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
      unitPriceCents: 45000,
      totalCents: 45000,
    ),
  ],
  payments: const [],
  charges: const [],
  discounts: const [],
  settings: const TenantMoneySettings(),
);

/// Opens the sheet and hands back whatever it popped.
Future<PaymentIntent?> _open(WidgetTester tester) async {
  PaymentIntent? intent;
  var opened = false;

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              opened = true;
              intent = await showPaymentSheet(
                context: context,
                snapshot: _snapshot(),
                currency: 'NPR',
                canLeaveOnTab: true,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(opened, isTrue);
  return intent;
}

Future<PaymentIntent?> _openAndSettle(
  WidgetTester tester,
  Future<void> Function() act,
) async {
  PaymentIntent? intent;

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              intent = await showPaymentSheet(
                context: context,
                snapshot: _snapshot(),
                currency: 'NPR',
                canLeaveOnTab: true,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await act();
  await tester.pumpAndSettle();
  return intent;
}

void main() {
  group('payment methods', () {
    testWidgets('every record-only method is offered, online is not', (
      tester,
    ) async {
      await _open(tester);

      for (final label in [
        'Cash',
        'Card',
        'eSewa',
        'FonePay',
        'Bank transfer',
        'Wallet',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label is missing');
      }
      // The gateway method has no RPC behind it on the phone.
      expect(find.text('Card (online)'), findsNothing);
    });

    test('the catalogue and the reference set agree', () {
      expect(paymentMethods, isNot(contains('online')));
      expect(paymentMethods, isNot(contains('points')));
      // Cash is handed over in the room; there is nothing to reconcile.
      expect(paymentMethodTakesReference('cash'), isFalse);
      for (final m in ['card', 'esewa', 'fonepay', 'bank', 'wallet']) {
        expect(paymentMethodTakesReference(m), isTrue, reason: m);
      }
    });
  });

  group('reference', () {
    testWidgets('appears for a wallet and not for cash', (tester) async {
      await _open(tester);

      // Cash is selected by default — no reference, but the change field.
      expect(find.text('Reference (optional)'), findsNothing);
      expect(find.text('Cash received (optional)'), findsOneWidget);

      await tester.tap(find.text('eSewa'));
      await tester.pumpAndSettle();

      expect(find.text('Reference (optional)'), findsOneWidget);
      expect(find.text('Cash received (optional)'), findsNothing);
    });

    testWidgets('travels out with the method that was selected', (
      tester,
    ) async {
      final intent = await _openAndSettle(tester, () async {
        await tester.tap(find.text('FonePay'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Reference (optional)'),
          '  0092XXXXXX  ',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Take NPR 450.00'));
      });

      expect(intent, isNotNull);
      expect(intent!.method, 'fonepay');
      expect(intent.amountCents, 45000);
      // Trimmed on the way out, so the server stores what was read off the
      // guest's screen and nothing else.
      expect(intent.reference, '0092XXXXXX');
    });

    testWidgets('does not follow a switch back to cash', (tester) async {
      final intent = await _openAndSettle(tester, () async {
        await tester.tap(find.text('eSewa'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Reference (optional)'),
          '0092XXXXXX',
        );
        await tester.pumpAndSettle();
        // Changed their mind — the guest paid cash after all.
        await tester.tap(find.text('Cash'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Take NPR 450.00'));
      });

      expect(intent, isNotNull);
      expect(intent!.method, 'cash');
      expect(intent.reference, isNull);
    });

    testWidgets('a blank field is no reference, not an empty one', (
      tester,
    ) async {
      final intent = await _openAndSettle(tester, () async {
        await tester.tap(find.text('Bank transfer'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Take NPR 450.00'));
      });

      expect(intent, isNotNull);
      expect(intent!.method, 'bank');
      expect(intent.reference, isNull);
    });
  });
}
