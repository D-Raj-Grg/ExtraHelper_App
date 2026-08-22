import 'package:extrahelper/features/pos/day_summary_bar.dart';
import 'package:extrahelper/features/pos/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// `MapEntry` has no `==`, so two identical entries are not equal — compare the
/// pairs, and assert ordering on its own where it matters.
Map<String, int> _split(List<PosCompletedOrder> orders) =>
    Map.fromEntries(paymentSplit(orders));

/// One completed order as PostgREST hands it back, bill embed and all.
Map<String, dynamic> _row({
  required String id,
  String? billId,
  String status = 'closed',
  List<Map<String, dynamic>> payments = const [],
  List<Map<String, dynamic>> items = const [],
}) => {
  'id': id,
  'order_type': 'dine_in',
  'status': status,
  'created_at': '2026-08-22T10:00:00+00:00',
  'guests': 2,
  'bill_id': billId,
  'restaurant_tables': null,
  'order_items': items,
  'bills': billId == null
      ? null
      : {
          'id': billId,
          'status': 'paid',
          'total_cents': 50000,
          'payments': payments,
        },
};

Map<String, dynamic> _pay(String method, int cents, [String s = 'completed']) =>
    {'method': method, 'amount_cents': cents, 'status': s};

Map<String, dynamic> _item(int qty, int unit, {bool isVoid = false}) => {
  'id': 'l${qty}_$unit${isVoid ? 'v' : ''}',
  'name_snapshot': 'Sekuwa',
  'qty': qty,
  'unit_price_cents': unit,
  'is_void': isVoid,
};

void main() {
  group('paymentSplit', () {
    test('sums a method across bills', () {
      final orders = [
        _row(id: 'a', billId: 'b1', payments: [_pay('cash', 30000)]),
        _row(id: 'b', billId: 'b2', payments: [_pay('cash', 20000)]),
      ].map(PosCompletedOrder.fromRow).toList();

      expect(_split(orders), {'cash': 50000});
    });

    test('a merged bill is counted once, not once per order on it', () {
      // add_order_to_bill merges tables, so both orders carry the same bill's
      // payments. Summing them straight would report 120,000 for 60,000 taken.
      final payments = [_pay('cash', 60000)];
      final orders = [
        _row(id: 'a', billId: 'shared', payments: payments),
        _row(id: 'b', billId: 'shared', payments: payments),
      ].map(PosCompletedOrder.fromRow).toList();

      expect(_split(orders), {'cash': 60000});
    });

    test('only completed payments count', () {
      final orders = [
        _row(
          id: 'a',
          billId: 'b1',
          payments: [
            _pay('cash', 10000),
            _pay('card', 99999, 'pending'),
            _pay('card', 88888, 'failed'),
          ],
        ),
      ].map(PosCompletedOrder.fromRow).toList();

      expect(_split(orders), {'cash': 10000});
    });

    test('an order with no bill contributes nothing and does not throw', () {
      final orders = [
        _row(id: 'a', billId: null),
        _row(id: 'b', billId: 'b1', payments: [_pay('esewa', 4000)]),
      ].map(PosCompletedOrder.fromRow).toList();

      expect(_split(orders), {'esewa': 4000});
    });

    test('biggest method first, so the till reads top-down', () {
      final orders = [
        _row(id: 'a', billId: 'b1', payments: [_pay('wallet', 1000)]),
        _row(id: 'b', billId: 'b2', payments: [_pay('cash', 90000)]),
        _row(id: 'c', billId: 'b3', payments: [_pay('card', 5000)]),
      ].map(PosCompletedOrder.fromRow).toList();

      expect(paymentSplit(orders).map((e) => e.key), [
        'cash',
        'card',
        'wallet',
      ]);
    });

    test('no payments at all is empty, not a zero row', () {
      final orders = [
        _row(id: 'a', billId: 'b1'),
      ].map(PosCompletedOrder.fromRow).toList();
      expect(paymentSplit(orders), isEmpty);
    });
  });

  group('takings', () {
    // The same rule the bar applies: each order's own lines, never the bill
    // total, and cancellations excluded.
    int takings(List<PosCompletedOrder> orders) => orders
        .where((o) => !o.isCancelled)
        .fold(0, (sum, o) => sum + o.lineTotalCents);

    test('a merged bill does not double-count its total', () {
      final orders = [
        _row(id: 'a', billId: 'shared', items: [_item(1, 30000)]),
        _row(id: 'b', billId: 'shared', items: [_item(1, 20000)]),
      ].map(PosCompletedOrder.fromRow).toList();

      // bills.total_cents is 50000 on *both* rows; the lines are the truth.
      expect(takings(orders), 50000);
      expect(orders.first.billTotalCents, 50000);
    });

    test('cancelled orders and voided lines take no money', () {
      final orders = [
        _row(id: 'a', billId: 'b1', items: [_item(2, 10000)]),
        _row(
          id: 'b',
          billId: 'b2',
          status: 'cancelled',
          items: [_item(1, 90000)],
        ),
        _row(
          id: 'c',
          billId: 'b3',
          items: [_item(1, 10000), _item(1, 70000, isVoid: true)],
        ),
      ].map(PosCompletedOrder.fromRow).toList();

      expect(takings(orders), 30000);
    });
  });
}
