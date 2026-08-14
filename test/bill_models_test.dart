import 'dart:convert';

import 'package:extrahelper/features/pos/bill_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parsing, against the row shapes PostgREST actually returns for the queries in
/// `BillRepository.snapshot`.
///
/// The shapes that matter here are the awkward ones: a takeaway bill has no
/// table, a synthetic bill line has no order item behind it, and `numeric`
/// discount values can arrive as strings.
void main() {
  group('Bill.fromRow', () {
    test('a dine-in bill', () {
      final row =
          jsonDecode('''
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "status": "partial",
          "created_at": "2026-08-13T04:15:00+00:00",
          "subtotal_cents": 10000,
          "tax_cents": 1300,
          "service_charge_cents": 1000,
          "discount_cents": 500,
          "tip_cents": 200,
          "rounding_cents": -0,
          "total_cents": 12000,
          "note": "No onions on the table's order",
          "restaurant_tables": {"label": "A1"}
        }
      ''')
              as Map<String, dynamic>;

      final bill = Bill.fromRow(row);
      expect(bill.status, 'partial');
      expect(bill.tableLabel, 'A1');
      expect(bill.totalCents, 12000);
      expect(bill.isSettleable, isTrue);
      expect(bill.isPaid, isFalse);
    });

    test('a takeaway bill has no table and may have no remark', () {
      final row =
          jsonDecode('''
        {
          "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
          "status": "paid",
          "created_at": "2026-08-13T04:15:00+00:00",
          "subtotal_cents": 500,
          "tax_cents": 0,
          "service_charge_cents": 0,
          "discount_cents": 0,
          "tip_cents": 0,
          "rounding_cents": 0,
          "total_cents": 500,
          "note": null,
          "restaurant_tables": null
        }
      ''')
              as Map<String, dynamic>;

      final bill = Bill.fromRow(row);
      expect(bill.tableLabel, isNull);
      expect(bill.note, isNull);
      expect(bill.isPaid, isTrue);
      expect(bill.isSettleable, isFalse);
    });
  });

  group('BillLine.fromRow', () {
    test('carries its modifiers and its share of the discounts', () {
      final row =
          jsonDecode('''
        {
          "id": "line-1",
          "order_item_id": "oi-1",
          "description": "Buff Sekuwa (KG)",
          "qty": 2,
          "unit_price_cents": 1000,
          "total_cents": 2000
        }
      ''')
              as Map<String, dynamic>;

      final line = BillLine.fromRow(
        row,
        modifiers: [
          BillLineModifier.fromRow(
            jsonDecode(
                  '{"id":"m1","name_snapshot":"Extra chilli","price_cents":50,"qty":2}',
                )
                as Map<String, dynamic>,
          ),
        ],
        lineDiscounts: const [
          DiscountRow(orderItemId: 'oi-1', type: 'percent', value: 10),
        ],
      );

      expect(line.grossCents, 2000);
      expect(line.discountCents, 200);
      expect(line.isAdjustable, isTrue);
      expect(line.modifiers.single.qty, 2);
    });

    test('a synthetic line renders but cannot be adjusted', () {
      // `recompute_bill` can write a line with no order item behind it; both
      // `apply_item_discount` and `void_order_item` take an order-item id, so
      // the sheet must not offer them.
      final row =
          jsonDecode('''
        {
          "id": "line-2",
          "order_item_id": null,
          "description": "Corkage",
          "qty": 1,
          "unit_price_cents": 300,
          "total_cents": 300
        }
      ''')
              as Map<String, dynamic>;

      final line = BillLine.fromRow(row);
      expect(line.isAdjustable, isFalse);
      expect(line.discountCents, 0);
      expect(line.modifiers, isEmpty);
    });
  });

  test('a numeric discount value that arrives as a string still parses', () {
    final row =
        jsonDecode('{"order_item_id":null,"type":"flat","value":"12.50"}')
            as Map<String, dynamic>;
    expect(DiscountRow.fromRow(row).value, 12.5);
  });

  group('BillSnapshot', () {
    BillSnapshot snapshotWith({
      required int totalCents,
      List<PaymentRow> payments = const [],
      String status = 'open',
    }) => BillSnapshot(
      bill: Bill(
        id: 'b1',
        status: status,
        createdAt: DateTime(2026, 8, 13),
        subtotalCents: totalCents,
        taxCents: 0,
        serviceChargeCents: 0,
        discountCents: 0,
        tipCents: 0,
        roundingCents: 0,
        totalCents: totalCents,
      ),
      lines: const [
        BillLine(
          id: 'l1',
          description: 'Dal bhat',
          qty: 1,
          unitPriceCents: 500,
          totalCents: 500,
        ),
      ],
      payments: payments,
      charges: const [],
      discounts: const [],
      settings: const TenantMoneySettings(),
    );

    PaymentRow paid(int cents) => PaymentRow(
      id: 'p$cents',
      method: 'cash',
      amountCents: cents,
      createdAt: DateTime(2026, 8, 13),
    );

    test('due is total less what has been taken', () {
      final s = snapshotWith(totalCents: 1000, payments: [paid(400)]);
      expect(s.paidCents, 400);
      expect(s.dueCents, 600);
      expect(s.canTakePayment, isTrue);
    });

    test('an overpayment is change owed, never a negative due', () {
      final s = snapshotWith(totalCents: 1000, payments: [paid(1200)]);
      expect(s.dueCents, 0);
      expect(s.canTakePayment, isFalse);
    });

    test('a settled bill takes no more money, whatever it shows', () {
      final s = snapshotWith(totalCents: 1000, status: 'paid');
      expect(s.canTakePayment, isFalse);
    });

    test('item total is the lines, before any bill-level arithmetic', () {
      expect(snapshotWith(totalCents: 1300).itemTotalCents, 500);
    });
  });
}
