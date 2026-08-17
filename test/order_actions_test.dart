import 'package:extrahelper/features/pos/guests_dialog.dart';
import 'package:extrahelper/features/pos/models.dart';
import 'package:extrahelper/features/pos/void_reason_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Orders board's newer actions: what a pin is, what a cancel asks for, and
/// what the guest stepper will let someone save.

PosOrder _order({DateTime? pinnedAt, int? guests, String status = 'placed'}) =>
    PosOrder(
      id: 'o1',
      status: status,
      orderType: 'dine_in',
      createdAt: DateTime(2026, 8, 14, 19),
      pinnedAt: pinnedAt,
      guests: guests,
    );

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  group('PosOrder', () {
    test('a pin is a timestamp, and absence of one is not pinned', () {
      expect(_order().isPinned, isFalse);
      expect(_order(pinnedAt: DateTime(2026, 8, 14)).isPinned, isTrue);
    });

    test('pinned_at reaches the model from the row', () {
      final order = PosOrder.fromRow({
        'id': 'o1',
        'status': 'placed',
        'order_type': 'dine_in',
        'created_at': '2026-08-14T13:00:00Z',
        'pinned_at': '2026-08-14T13:30:00Z',
        'guests': 4,
      });

      expect(order.isPinned, isTrue);
      expect(order.guests, 4);
    });

    test('an order with no pin column set is simply unpinned', () {
      // Every existing row predates the column, and a null must not read as
      // "pinned at the epoch" — which would float every old order to the top.
      final order = PosOrder.fromRow({
        'id': 'o1',
        'status': 'placed',
        'order_type': 'dine_in',
        'created_at': '2026-08-14T13:00:00Z',
      });

      expect(order.pinnedAt, isNull);
      expect(order.isPinned, isFalse);
    });

    test(
      'a cancelled order is settled, so nothing offers to cancel it twice',
      () {
        expect(_order(status: 'cancelled').isSettled, isTrue);
        expect(_order(status: 'billed').isSettled, isTrue);
        expect(_order().isSettled, isFalse);
      },
    );

    test('the bill\'s status rides in on the embed', () {
      final order = PosOrder.fromRow({
        'id': 'o1',
        'status': 'billed',
        'order_type': 'dine_in',
        'created_at': '2026-08-14T13:00:00Z',
        'bills': {'id': 'b1', 'status': 'open'},
      });

      expect(order.billId, 'b1');
      expect(order.billStatus, 'open');
      // Printed but unpaid: another round is still allowed.
      expect(order.isAmendable, isTrue);
    });

    test('a row fetched without the bills embed knows no bill status', () {
      // Older callers select the order alone. A missing embed must read as
      // "unknown", never as an open bill — that would offer to add items to
      // an order the server has already shut.
      final order = PosOrder.fromRow({
        'id': 'o1',
        'status': 'billed',
        'order_type': 'dine_in',
        'created_at': '2026-08-14T13:00:00Z',
      });

      expect(order.billStatus, isNull);
      expect(order.isAmendable, isFalse);
    });
  });

  group('cancel reason', () {
    testWidgets('an empty reason cannot be submitted', (tester) async {
      String? result;
      var returned = false;

      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showVoidReasonDialog(
                context: context,
                title: 'Cancel this order?',
                body: 'All 3 dishes will be voided.',
                confirmLabel: 'Cancel order',
                keepLabel: 'Keep order',
              );
              returned = true;
            },
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // `cancel_order` requires a reason and writes it to the audit row. A
      // blank one would be refused by the server, so the dialog refuses first.
      await tester.tap(find.text('Cancel order'));
      await tester.pumpAndSettle();

      expect(returned, isFalse, reason: 'the dialog should still be open');
      expect(result, isNull);
      expect(find.text('Cancel this order?'), findsOneWidget);
    });

    testWidgets('the labels say what is being cancelled, not "void line"', (
      tester,
    ) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showVoidReasonDialog(
              context: context,
              title: 'Cancel this order?',
              body: 'All 3 dishes on this order will be voided.',
              confirmLabel: 'Cancel order',
              keepLabel: 'Keep order',
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel order'), findsOneWidget);
      expect(find.text('Keep order'), findsOneWidget);
      // The consequence is named, per the destructive-action rule.
      expect(find.textContaining('will be voided'), findsOneWidget);
      expect(find.text('Void line'), findsNothing);
    });

    testWidgets('a reason comes back trimmed', (tester) async {
      String? result;

      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showVoidReasonDialog(
              context: context,
              title: 'Cancel this order?',
              body: 'body',
              confirmLabel: 'Cancel order',
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  walked out  ');
      await tester.tap(find.text('Cancel order'));
      await tester.pumpAndSettle();

      expect(result, 'walked out');
    });
  });

  group('guests', () {
    testWidgets('the stepper stops where the server clamps', (tester) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showGuestsDialog(context: context, current: 1),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // At the floor, "one fewer" is dead rather than silently doing nothing.
      final minus = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.remove),
      );
      expect(minus.onPressed, isNull);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('the count comes back, and backing out returns nothing', (
      tester,
    ) async {
      int? result;
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showGuestsDialog(context: context, current: 2),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result, 3);
    });
  });
}
