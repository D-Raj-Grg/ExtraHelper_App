import 'package:extrahelper/features/pos/models.dart';
import 'package:flutter_test/flutter_test.dart';

PosOrder _order(String status, {String? billStatus, String? billId}) =>
    PosOrder(
      id: 'o1',
      status: status,
      orderType: 'dine_in',
      createdAt: DateTime(2026, 10, 28),
      billStatus: billStatus,
      billId: billId,
    );

void main() {
  group('PosOrder.canCancel mirrors cancel_order', () {
    test('an order still on the floor can be cancelled', () {
      expect(_order('in_kitchen').canCancel, isTrue);
    });

    test('a billed order with an open bill can', () {
      expect(_order('billed', billStatus: 'open').canCancel, isTrue);
    });

    test('a billed order whose bill was refunded in full can', () {
      expect(_order('billed', billStatus: 'void').canCancel, isTrue);
    });

    test('money still held means refund first', () {
      expect(_order('billed', billStatus: 'partial').canCancel, isFalse);
      expect(_order('billed', billStatus: 'paid').canCancel, isFalse);
    });

    test('closed and cancelled are over', () {
      expect(_order('closed').canCancel, isFalse);
      expect(_order('cancelled').canCancel, isFalse);
    });
  });

  group('PosOrder.canOpenBill', () {
    test('a billed order with every dish voided can still reach its bill', () {
      // The live case: part-paid, nothing left on it, money to refund.
      expect(
        _order('billed', billStatus: 'partial', billId: 'b1').canOpenBill,
        isTrue,
      );
    });

    test('an order that was never billed and sent nothing cannot', () {
      expect(_order('draft').canOpenBill, isFalse);
    });
  });
}
