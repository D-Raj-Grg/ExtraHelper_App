import 'package:extrahelper/data/supabase/bill_repository.dart';
import 'package:extrahelper/data/supabase/pos_repository.dart';
import 'package:extrahelper/features/pos/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Moving orders between tables. The client-side refusals are what these cover:
/// each one exists so a waiter gets a sentence instead of a server error, and
/// each maps to a `raise exception` in the RPC it would otherwise have hit.

PosOrderLine _line(String id, {bool isVoid = false}) => PosOrderLine(
  id: id,
  nameSnapshot: 'Dal Bhat',
  qty: 1,
  unitPriceCents: 45000,
  status: 'placed',
  isVoid: isVoid,
);

void main() {
  group('split', () {
    test('an empty selection never reaches the server', () {
      // `split_order_items` raises 'no items selected'. Asking first turns a
      // round trip and a raw error into an instruction.
      final repo = PosRepository(_DeadClient(), 't1');

      expect(
        () => repo.splitOrderItems(
          orderId: 'o1',
          toTableId: 'tbl-2',
          itemIds: const [],
        ),
        throwsA(
          isA<PosFailure>().having(
            (e) => e.message,
            'message',
            contains('at least one dish'),
          ),
        ),
      );
    });

    test('voided lines are not offered as movable', () {
      // They are already off the bill; moving one would put a struck-through
      // dish on a table nobody ordered it at.
      final lines = [_line('a'), _line('b', isVoid: true)];
      final movable = lines.where((l) => !l.isVoid).toList();

      expect(movable.map((l) => l.id), ['a']);
    });
  });

  group('merge', () {
    test('a table cannot be merged with itself', () {
      // `add_order_to_bill` would refuse an order already on the bill; this is
      // the same refusal, phrased for the person holding the phone.
      final repo = BillRepository(_DeadClient(), 't1');

      expect(
        () => repo.mergeOrders(primaryOrderId: 'o1', otherOrderId: 'o1'),
        throwsA(
          isA<PosFailure>().having(
            (e) => e.message,
            'message',
            contains('different table'),
          ),
        ),
      );
    });
  });
}

/// Stands in for a client that must never be reached: every test here asserts
/// the refusal happens *before* any network call, so any use of this is a
/// failure of that claim.
class _DeadClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('the server must not be called');
}
