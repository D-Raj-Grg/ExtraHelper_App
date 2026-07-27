import 'package:extrahelper/features/pos/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _variantKg = PosVariant(id: 'v-kg', name: 'KG', priceDeltaCents: 130000);
const _variantHalf = PosVariant(
  id: 'v-half',
  name: 'Half KG',
  priceDeltaCents: 70000,
);
const _achar = PosModifier(id: 'm1', name: 'Extra Achar', priceCents: 15000);
const _spicy = PosModifier(id: 'm2', name: 'Extra Spicy', priceCents: 5000);

const _sekuwa = PosMenuItem(
  id: 'i1',
  name: 'Buff Sekuwa',
  basePriceCents: 38000,
  categoryId: 'c1',
  is86: false,
  variants: [_variantHalf, _variantKg],
  modifiers: [_achar, _spicy],
);

const _dalBhat = PosMenuItem(
  id: 'i2',
  name: 'Dal Bhat',
  basePriceCents: 45000,
  categoryId: 'c1',
  is86: false,
);

void main() {
  group('priceRange', () {
    test('a variant dish spans its cheapest to dearest orderable price', () {
      final r = _sekuwa.priceRange;
      // NOT 38000 — with variants the base price is unbuyable, which is the
      // live bug the web tile had.
      expect(r.min, 108000);
      expect(r.max, 168000);
    });

    test('a dish without variants is a single price', () {
      final r = _dalBhat.priceRange;
      expect(r.min, 45000);
      expect(r.max, 45000);
    });

    test('add-ons are excluded — they are optional', () {
      expect(_sekuwa.priceRange.max, 168000); // not +20000 of add-ons
    });
  });

  group('CartLine pricing', () {
    test('matches the server: base + variant + add-ons', () {
      const line = CartLine(
        localId: 'l1',
        item: _sekuwa,
        qty: 1,
        variant: _variantKg,
        modifiers: [_achar, _spicy],
      );
      // The parity case verified against the RPC: 38000 + 130000 + 15000 + 5000
      expect(line.unitPriceCents, 188000);
      expect(line.title, 'Buff Sekuwa (KG)');
    });

    test('line total multiplies by quantity', () {
      const line = CartLine(
        localId: 'l1',
        item: _sekuwa,
        qty: 3,
        variant: _variantKg,
      );
      expect(line.lineTotalCents, 168000 * 3);
    });

    test('title folds the variant in, so two sizes are distinguishable', () {
      const kg = CartLine(
        localId: 'a',
        item: _sekuwa,
        qty: 1,
        variant: _variantKg,
      );
      const half = CartLine(
        localId: 'b',
        item: _sekuwa,
        qty: 1,
        variant: _variantHalf,
      );
      expect(kg.title, isNot(half.title));
    });
  });

  group('CartLine signature', () {
    test('same dish, variant, add-ons and note merge', () {
      const a = CartLine(
        localId: 'a',
        item: _sekuwa,
        qty: 1,
        variant: _variantKg,
        modifiers: [_achar, _spicy],
      );
      const b = CartLine(
        localId: 'b',
        item: _sekuwa,
        qty: 2,
        // Reversed order must not change identity.
        variant: _variantKg,
        modifiers: [_spicy, _achar],
      );
      expect(a.signature, b.signature);
    });

    test('a different variant is a different line', () {
      const a = CartLine(
        localId: 'a',
        item: _sekuwa,
        qty: 1,
        variant: _variantKg,
      );
      const b = CartLine(
        localId: 'b',
        item: _sekuwa,
        qty: 1,
        variant: _variantHalf,
      );
      expect(a.signature, isNot(b.signature));
    });

    test('a different note is a different line — the kitchen sees it', () {
      const a = CartLine(
        localId: 'a',
        item: _dalBhat,
        qty: 1,
        notes: 'no chilli',
      );
      const b = CartLine(localId: 'b', item: _dalBhat, qty: 1);
      expect(a.signature, isNot(b.signature));
    });

    test('the local id is NOT part of identity, so it can stay stable', () {
      const a = CartLine(localId: 'a', item: _dalBhat, qty: 1);
      const b = CartLine(localId: 'zzz', item: _dalBhat, qty: 1);
      expect(a.signature, b.signature);
    });
  });

  group('CartLine.toRpcJson', () {
    test('omits absent options rather than sending nulls', () {
      const line = CartLine(localId: 'l', item: _dalBhat, qty: 2);
      final json = line.toRpcJson();
      expect(json['item_id'], 'i2');
      expect(json['qty'], 2);
      expect(json.containsKey('variant_id'), isFalse);
      expect(json.containsKey('modifier_ids'), isFalse);
      expect(json.containsKey('notes'), isFalse);
    });

    test('sends variant and add-on ids the server can validate', () {
      const line = CartLine(
        localId: 'l',
        item: _sekuwa,
        qty: 1,
        variant: _variantKg,
        modifiers: [_achar],
        notes: '  well done  ',
      );
      final json = line.toRpcJson();
      expect(json['variant_id'], 'v-kg');
      expect(json['modifier_ids'], ['m1']);
      expect(json['notes'], 'well done'); // trimmed
    });
  });

  group('PosOrder', () {
    PosOrderLine line(
      String id,
      int qty,
      int price, {
      bool isVoid = false,
      String status = 'draft',
    }) => PosOrderLine(
      id: id,
      nameSnapshot: 'X',
      qty: qty,
      unitPriceCents: price,
      status: status,
      isVoid: isVoid,
    );

    test('a voided line leaves the total — it is off the bill', () {
      final order = PosOrder(
        id: 'o',
        status: 'in_kitchen',
        orderType: 'dine_in',
        createdAt: DateTime(2026),
        lines: [line('a', 2, 1000), line('b', 1, 5000, isVoid: true)],
      );
      expect(order.totalCents, 2000);
      expect(order.itemCount, 2);
    });

    test('canFire is true only while something is still unsent', () {
      final unsent = PosOrder(
        id: 'o',
        status: 'draft',
        orderType: 'dine_in',
        createdAt: DateTime(2026),
        lines: [line('a', 1, 100)],
      );
      final sent = PosOrder(
        id: 'o',
        status: 'in_kitchen',
        orderType: 'dine_in',
        createdAt: DateTime(2026),
        lines: [line('a', 1, 100, status: 'placed')],
      );
      expect(unsent.canFire, isTrue);
      expect(sent.canFire, isFalse);
    });

    test('a fired line is not deletable — it needs a reasoned void', () {
      expect(line('a', 1, 100, status: 'placed').isFired, isTrue);
      expect(line('a', 1, 100).isFired, isFalse);
    });

    test('billed, closed and cancelled orders are shut for edits', () {
      for (final s in ['billed', 'closed', 'cancelled']) {
        final o = PosOrder(
          id: 'o',
          status: s,
          orderType: 'dine_in',
          createdAt: DateTime(2026),
        );
        expect(o.isClosed, isTrue, reason: s);
      }
      for (final s in ['draft', 'in_kitchen', 'ready', 'served']) {
        final o = PosOrder(
          id: 'o',
          status: s,
          orderType: 'dine_in',
          createdAt: DateTime(2026),
        );
        expect(o.isClosed, isFalse, reason: s);
      }
    });
  });
}
