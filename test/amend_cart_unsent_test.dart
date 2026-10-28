import 'package:extrahelper/data/supabase/pos_repository.dart';
import 'package:extrahelper/data/sync/order_queue.dart';
import 'package:extrahelper/features/pos/cart_controller.dart';
import 'package:extrahelper/features/pos/models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeQueue extends Fake implements OrderQueue {}

class _FakeRepo extends Fake implements PosRepository {}

PosOrderLine _line(
  String id,
  String status, {
  bool isVoid = false,
  bool isHeld = false,
}) => PosOrderLine(
  id: id,
  nameSnapshot: 'Dish $id',
  qty: 1,
  unitPriceCents: 1000,
  status: status,
  isVoid: isVoid,
  isHeld: isHeld,
);

AmendCart _cart(List<PosOrderLine> lines) => AmendCart(
  queue: _FakeQueue(),
  repository: _FakeRepo(),
  order: PosOrder(
    id: 'o1',
    status: 'in_kitchen',
    orderType: 'dine_in',
    createdAt: DateTime(2026, 10, 28),
    lines: lines,
  ),
);

void main() {
  group('AmendCart.hasUnsent', () {
    test('sent lines never count, whatever the kitchen did with them', () {
      final cart = _cart([
        _line('a', 'in_kitchen'),
        _line('b', 'preparing'),
        _line('c', 'ready'),
        _line('d', 'served'),
      ]);
      expect(cart.lines, isNotEmpty);
      expect(cart.hasUnsent, isFalse);
    });

    test('a voided line is ignored', () {
      expect(_cart([_line('a', 'draft', isVoid: true)]).hasUnsent, isFalse);
    });

    test('a draft line is unsent', () {
      expect(
        _cart([_line('a', 'served'), _line('b', 'draft')]).hasUnsent,
        isTrue,
      );
    });

    test('a placed line is unsent — a QR guest line awaiting accept', () {
      expect(
        _cart([_line('a', 'in_kitchen'), _line('b', 'placed')]).hasUnsent,
        isTrue,
      );
    });

    test('a held line does not block, as on the web', () {
      expect(
        _cart([
          _line('a', 'served'),
          _line('b', 'draft', isHeld: true),
        ]).hasUnsent,
        isFalse,
      );
    });

    test('an empty order has nothing unsent', () {
      expect(_cart(const []).hasUnsent, isFalse);
    });
  });
}
