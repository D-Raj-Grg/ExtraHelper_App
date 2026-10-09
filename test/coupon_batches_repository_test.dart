import 'package:extrahelper/data/supabase/coupon_batches_repository.dart';
import 'package:flutter_test/flutter_test.dart';

RunDraft _draft({
  String name = 'Dashain flyers',
  int count = 100,
  String prefix = 'dashain',
  String type = 'percent',
  double value = 10,
  DateTime? from,
  DateTime? to,
  bool dineIn = false,
}) => RunDraft(
  name: name,
  count: count,
  prefix: prefix,
  type: type,
  value: value,
  validFrom: from,
  validTo: to,
  dineInOnly: dineIn,
);

void main() {
  group('rows', () {
    test('a batch row parses string bigints and numerics', () {
      final b = CouponBatch.fromRow({
        'id': 'b1',
        'name': ' Dashain ',
        'type': 'flat',
        'value': '200.00',
        'valid_from': null,
        'valid_to': '2026-10-20T18:15:00+00:00',
        'created_at': '2026-10-01T00:00:00+00:00',
        'issued': '100',
        'redeemed': 7,
        'active': '100',
        'shared': '40',
        'design_id': null,
      });
      expect(b.name, 'Dashain');
      expect(b.isPercent, isFalse);
      expect(b.value, 200);
      expect(b.issued, 100);
      expect(b.shared, 40);
      expect(b.unused, 53);
      expect(b.isPaused, isFalse);
      expect(b.validTo, isNotNull);
    });

    test('no active codes in a non-empty run is a paused run', () {
      final b = CouponBatch.fromRow({
        'id': 'b1',
        'name': 'x',
        'type': 'percent',
        'value': 10,
        'created_at': '2026-10-01T00:00:00+00:00',
        'issued': 5,
        'active': 0,
      });
      expect(b.isPaused, isTrue);
    });

    test('stats parse and total', () {
      final s = CouponStats.fromRow({
        'active': '3',
        'scheduled': 1,
        'expired': 2,
        'used_up': 0,
        'paused': 1,
        'redemptions': '12',
        'discount_given_cents': '61200',
      });
      expect(s.total, 7);
      expect(s.discountGivenCents, 61200);
    });

    test('a code row defaults missing flags', () {
      final c = BatchCode.fromRow({'code': ' ab-12 '});
      expect(c.code, 'AB-12');
      expect(c.redeemed, isFalse);
      expect(c.shared, isFalse);
      expect(c.isActive, isTrue);
    });
  });

  group('RunDraft.validate', () {
    final now = DateTime(2026, 10, 9);

    test('a good draft passes', () {
      expect(_draft().validate(now: now), isNull);
    });

    test('name, count, prefix, value', () {
      expect(_draft(name: ' ').validate(now: now), 'Give the run a name.');
      expect(_draft(count: 0).validate(now: now), 'A run is 1 to 1000 codes.');
      expect(
        _draft(count: 1001).validate(now: now),
        'A run is 1 to 1000 codes.',
      );
      expect(
        _draft(prefix: 'A').validate(now: now),
        'The prefix is 2 to 8 letters or digits.',
      );
      expect(
        _draft(prefix: 'TOOLONGPFX').validate(now: now),
        'The prefix is 2 to 8 letters or digits.',
      );
      expect(
        _draft(value: 0).validate(now: now),
        'Enter a discount above zero.',
      );
      expect(
        _draft(value: 101).validate(now: now),
        "A discount can't be more than 100%.",
      );
      expect(_draft(type: 'flat', value: 500).validate(now: now), isNull);
    });

    test('dates', () {
      expect(
        _draft(
          from: DateTime(2026, 11, 2),
          to: DateTime(2026, 11, 1),
        ).validate(now: now),
        'The coupon must end after it starts.',
      );
      expect(
        _draft(to: DateTime(2026, 10, 1)).validate(now: now),
        'That end date has already passed.',
      );
    });
  });

  test('create params match the web call', () {
    final p = _draft(
      from: DateTime.utc(2026, 10, 10),
      to: DateTime.utc(2026, 10, 20),
      dineIn: true,
    ).toRpcParams('t1');
    expect(p['_tenant'], 't1');
    expect(p['_prefix'], 'DASHAIN');
    expect(p['_count'], 100);
    expect(p['_type'], 'percent');
    expect(p['_valid_from'], '2026-10-10T00:00:00.000Z');
    expect(p['_valid_to'], '2026-10-20T00:00:00.000Z');
    expect(p['_min_subtotal_cents'], 0);
    expect(p['_once_per_customer'], isFalse);
    expect(p['_order_types'], ['dine_in']);
    expect(_draft().toRpcParams('t1')['_order_types'], isNull);
  });

  test('RunEdit needs a name and an end after the start', () {
    expect(const RunEdit(name: '').validate(), 'Give the run a name.');
    expect(
      RunEdit(
        name: 'x',
        validFrom: DateTime(2026, 11, 2),
        validTo: DateTime(2026, 11, 1),
      ).validate(),
      'The coupon must end after it starts.',
    );
    expect(const RunEdit(name: 'x').validate(), isNull);
  });
}
