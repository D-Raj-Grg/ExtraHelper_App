import 'package:extrahelper/data/supabase/inventory_repository.dart';
import 'package:extrahelper/features/inventory/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('quantities', () {
    test('trailing zeros are noise on a shelf label', () {
      expect(qty(3.75), '3.75');
      expect(qty(12), '12');
      expect(qty(0.5), '0.5');
      expect(qty(0), '0');
    });

    test('a quantity always carries its unit', () {
      expect(qtyWithUom(3.75, 'kg'), '3.75 kg');
      expect(qtyWithUom(2, 'each'), '2 each');
    });

    test('a change always carries its sign, with a real minus', () {
      expect(signedQty(2, 'kg'), '+2 kg');
      // U+2212, not a hyphen: it lines up in tabular figures and reads as a
      // sign rather than a dash.
      expect(signedQty(-2, 'kg'), '−2 kg');
      expect(signedQty(0, 'kg'), '0 kg');
    });
  });

  group('inventory rows', () {
    test(
      'numerics arriving as strings parse — PostgREST sends them that way',
      () {
        final item = InventoryItem.fromJson({
          'id': 'i1',
          'name': 'Buffalo',
          'uom': 'kg',
          'current_qty': '3.750',
          'reorder_level': '5.000',
          'cost_cents': 42000,
        });
        expect(item.currentQty, 3.75);
        expect(item.reorderLevel, 5);
        expect(item.isLow, isTrue);
      },
    );

    test('a missing barcode stays null rather than becoming empty', () {
      final item = InventoryItem.fromJson({
        'id': 'i1',
        'name': 'Rice',
        'uom': 'kg',
        'current_qty': '59.8',
        'reorder_level': '10',
        'cost_cents': 0,
      });
      expect(item.barcode, isNull);
      expect(item.isLow, isFalse);
    });

    test('an uncounted line is null, not zero — they are different facts', () {
      final line = StockCountLine.fromJson({
        'id': 'l1',
        'inventory_item_id': 'i1',
        'theoretical_qty': '4.000',
        'actual_qty': null,
        'inventory_items': {'name': 'Pork', 'uom': 'kg', 'barcode': null},
      });
      expect(line.actualQty, isNull);
      expect(line.isCounted, isFalse);
      expect(line.variance, isNull, reason: 'nothing to compare against yet');
    });

    test('variance is signed: over is positive, short is negative', () {
      final over = StockCountLine.fromJson({
        'id': 'l1',
        'inventory_item_id': 'i1',
        'theoretical_qty': '4',
        'actual_qty': '6.5',
        'inventory_items': {'name': 'Pork', 'uom': 'kg'},
      });
      expect(over.variance, 2.5);
      expect(signedQty(over.variance!, over.uom), '+2.5 kg');

      final short = over.copyWith(actualQty: 1);
      expect(short.variance, -3);
      expect(signedQty(short.variance!, short.uom), '−3 kg');
    });

    test('an empty shelf counted as zero is a real count, not a blank', () {
      final line = StockCountLine.fromJson({
        'id': 'l1',
        'inventory_item_id': 'i1',
        'theoretical_qty': '4',
        'actual_qty': 0,
        'inventory_items': {'name': 'Gas', 'uom': 'cylinder'},
      });
      expect(line.isCounted, isTrue);
      expect(line.variance, -4);
    });

    test('a posted count is closed to editing', () {
      expect(
        StockCount.fromJson({'id': 'c1', 'posted_at': null}).isOpen,
        isTrue,
      );
      expect(
        StockCount.fromJson({
          'id': 'c1',
          'posted_at': '2026-07-30T09:00:00Z',
        }).isOpen,
        isFalse,
      );
    });
  });

  group('movement types', () {
    test('only a write-off demands a reason', () {
      expect(StockMovementType.wastage.needsReason, isTrue);
      expect(StockMovementType.purchase.needsReason, isFalse);
      expect(StockMovementType.adjustment.needsReason, isFalse);
    });

    test('wire values match the stock_movement_type enum exactly', () {
      expect(StockMovementType.values.map((t) => t.wire).toList(), [
        'purchase',
        'wastage',
        'staff_meal',
        'transfer',
        'adjustment',
      ]);
    });

    test('staff never see a raw enum value', () {
      for (final t in StockMovementType.values) {
        expect(t.label, isNot(contains('_')));
        expect(t.label, isNot(equals(t.wire)));
      }
    });
  });
}
