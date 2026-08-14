import 'package:extrahelper/features/pos/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Completed tab's arithmetic, which is the part that can be wrong without
/// looking wrong: a total that quietly counts a merged bill twice, or charges
/// for a line somebody voided.

Map<String, dynamic> _line({
  required int qty,
  required int unit,
  bool isVoid = false,
}) => {
  'id': 'l-$qty-$unit-$isVoid',
  'name_snapshot': 'Dal Bhat',
  'qty': qty,
  'unit_price_cents': unit,
  'is_void': isVoid,
};

PosCompletedOrder _order({
  String id = 'o1',
  String status = 'closed',
  String? billId,
  String? billStatus,
  int? billTotal,
  List<Map<String, dynamic>> lines = const [],
}) => PosCompletedOrder.fromRow({
  'id': id,
  'status': status,
  'order_type': 'dine_in',
  'created_at': '2026-08-14T13:05:00Z',
  'bill_id': billId,
  'restaurant_tables': {'label': '6'},
  'order_items': lines,
  if (billId != null)
    'bills': {'id': billId, 'status': billStatus, 'total_cents': billTotal},
});

void main() {
  group('one order', () {
    test('a voided line is not charged for, or counted', () {
      final order = _order(
        lines: [
          _line(qty: 2, unit: 45000),
          _line(qty: 1, unit: 38000, isVoid: true),
        ],
      );

      expect(order.lineTotalCents, 90000);
      expect(order.lineCount, 2);
    });

    test('the short id is the block staff read off the card', () {
      final order = _order(id: '3f02efb0-0482-444c-9137-1d05d6e839f4');
      expect(order.shortId, '3F02EFB0');
    });

    test('the bill total is read separately from the order total', () {
      // They differ whenever a discount, a charge or a merge is involved, and
      // showing one in place of the other is a figure a guest could argue with.
      final order = _order(
        billId: 'b1',
        billStatus: 'paid',
        billTotal: 120000,
        lines: [_line(qty: 1, unit: 100000)],
      );

      expect(order.lineTotalCents, 100000);
      expect(order.billTotalCents, 120000);
      expect(order.billStatus, 'paid');
    });

    test('an order with no bill carries no bill figures', () {
      final order = _order(status: 'cancelled');

      expect(order.billId, isNull);
      expect(order.billStatus, isNull);
      expect(order.isCancelled, isTrue);
    });
  });

  group('the takings line', () {
    // The tab sums each order's own lines rather than `bills.total_cents`,
    // exactly as the web does. These are that rule, stated twice over.
    int takings(List<PosCompletedOrder> orders) => orders
        .where((o) => !o.isCancelled)
        .fold(0, (sum, o) => sum + o.lineTotalCents);

    test('a cancelled order contributes nothing', () {
      final orders = [
        _order(lines: [_line(qty: 1, unit: 50000)]),
        _order(
          id: 'o2',
          status: 'cancelled',
          lines: [_line(qty: 4, unit: 90000)],
        ),
      ];

      expect(takings(orders), 50000);
    });

    test('two orders merged onto one bill are not counted twice', () {
      // Both rows carry the whole bill total (90000). Summing those would
      // report nearly double the money actually taken.
      final orders = [
        _order(
          id: 'o1',
          billId: 'b1',
          billStatus: 'paid',
          billTotal: 90000,
          lines: [_line(qty: 1, unit: 50000)],
        ),
        _order(
          id: 'o2',
          billId: 'b1',
          billStatus: 'paid',
          billTotal: 90000,
          lines: [_line(qty: 1, unit: 40000)],
        ),
      ];

      expect(takings(orders), 90000);
      expect(
        orders.fold(0, (sum, o) => sum + (o.billTotalCents ?? 0)),
        180000,
        reason: 'this is the wrong sum the line-based one avoids',
      );
    });
  });

  group('the status filter', () {
    List<PosCompletedOrder> shown(
      List<PosCompletedOrder> list,
      String? chosen,
    ) {
      final counts = <String, int>{};
      for (final o in list) {
        counts[o.status] = (counts[o.status] ?? 0) + 1;
      }
      final active = counts.containsKey(chosen) ? chosen : null;
      return active == null
          ? list
          : list.where((o) => o.status == active).toList();
    }

    test('a chosen status that has emptied falls back to All', () {
      // The last cancelled order of the evening gets billed instead, the chip
      // disappears, and the list must not go blank under the waiter.
      final list = [
        _order(status: 'closed'),
        _order(id: 'o2', status: 'billed'),
      ];

      expect(shown(list, 'cancelled').length, 2);
      expect(shown(list, 'billed').single.id, 'o2');
      expect(shown(list, null).length, 2);
    });
  });
}
