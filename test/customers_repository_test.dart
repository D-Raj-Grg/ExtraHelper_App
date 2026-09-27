import 'package:extrahelper/data/supabase/customers_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrmCustomer.fromRow', () {
    test('reads points and tier off the embedded loyalty account', () {
      final c = CrmCustomer.fromRow({
        'id': 'c1',
        'name': 'Max',
        'phone': '9767288510',
        'email': null,
        'loyalty_accounts': [
          {'points_balance': 120, 'tier': 'gold'},
        ],
      });
      expect(c.id, 'c1');
      expect(c.name, 'Max');
      expect(c.phone, '9767288510');
      expect(c.email, isNull);
      expect(c.points, 120);
      expect(c.tier, 'gold');
      expect(c.owesCents, 0);
      expect(c.unpaidBills, 0);
      expect(c.owes, isFalse);
    });

    test('a guest with no loyalty account has zero points on bronze', () {
      final c = CrmCustomer.fromRow({
        'id': 'c2',
        'name': null,
        'phone': '9800000000',
        'email': 'a@b.c',
        'loyalty_accounts': <dynamic>[],
      });
      expect(c.points, 0);
      expect(c.tier, 'bronze');

      final missingKey = CrmCustomer.fromRow({'id': 'c3', 'name': 'Ana'});
      expect(missingKey.points, 0);
      expect(missingKey.tier, 'bronze');
    });

    test('blank strings become null', () {
      final c = CrmCustomer.fromRow({
        'id': 'c4',
        'name': '  ',
        'phone': '',
        'email': ' x@y.z ',
      });
      expect(c.name, isNull);
      expect(c.phone, isNull);
      expect(c.email, 'x@y.z');
    });

    test('withCredit keeps identity and sets the debt', () {
      const c = CrmCustomer(id: 'c1', name: 'Max', points: 5, tier: 'silver');
      final owing = c.withCredit(owesCents: 1500, unpaidBills: 2);
      expect(owing.id, 'c1');
      expect(owing.name, 'Max');
      expect(owing.points, 5);
      expect(owing.tier, 'silver');
      expect(owing.owesCents, 1500);
      expect(owing.unpaidBills, 2);
      expect(owing.owes, isTrue);
    });
  });

  group('CrmCustomer label and describe', () {
    test('label falls back name -> phone -> email -> Guest', () {
      expect(const CrmCustomer(id: 'a', name: 'Max', phone: '1').label, 'Max');
      expect(const CrmCustomer(id: 'a', phone: '1', email: 'e').label, '1');
      expect(const CrmCustomer(id: 'a', email: 'e@x.y').label, 'e@x.y');
      expect(const CrmCustomer(id: 'a').label, 'Guest');
    });

    test('describe is "Max · 9767288510"', () {
      expect(
        const CrmCustomer(id: 'a', name: 'Max', phone: '9767288510').describe,
        'Max · 9767288510',
      );
    });

    test('describe uses email when there is no phone', () {
      expect(
        const CrmCustomer(id: 'a', name: 'Max', email: 'max@x.y').describe,
        'Max · max@x.y',
      );
    });

    test('describe never repeats the label', () {
      expect(const CrmCustomer(id: 'a', name: 'Max').describe, 'Max');
      expect(const CrmCustomer(id: 'a', phone: '1').describe, '1');
      expect(
        const CrmCustomer(id: 'a', phone: '1', email: 'e@x.y').describe,
        '1 · e@x.y',
      );
      expect(const CrmCustomer(id: 'a').describe, 'Guest');
    });
  });

  group('CustomerBillRow.fromRow', () {
    test('parses bigints that arrive as strings', () {
      final r = CustomerBillRow.fromRow({
        'bill_id': 'b1',
        'created_at': '2026-09-27T10:00:00+00:00',
        'status': 'partial',
        'total_cents': '150000',
        'paid_cents': '50000',
        'outstanding_cents': '100000',
        'table_label': 'T4',
        'items_summary': 'Momo, Sekuwa',
      });
      expect(r.billId, 'b1');
      expect(r.createdAt, DateTime.utc(2026, 9, 27, 10));
      expect(r.status, 'partial');
      expect(r.totalCents, 150000);
      expect(r.paidCents, 50000);
      expect(r.outstandingCents, 100000);
      expect(r.tableLabel, 'T4');
      expect(r.itemsSummary, 'Momo, Sekuwa');
      expect(r.unpaid, isTrue);
    });

    test('accepts numeric ints and nulls', () {
      final r = CustomerBillRow.fromRow({
        'bill_id': 'b2',
        'created_at': '2026-09-27T10:00:00Z',
        'status': 'paid',
        'total_cents': 900,
        'paid_cents': 900.0,
        'outstanding_cents': null,
        'table_label': null,
        'items_summary': '',
      });
      expect(r.totalCents, 900);
      expect(r.paidCents, 900);
      expect(r.outstandingCents, 0);
      expect(r.tableLabel, isNull);
      expect(r.itemsSummary, isNull);
      expect(r.unpaid, isFalse);
    });
  });

  group('CustomerFeedback.fromRow', () {
    test('reads the embedded customer name', () {
      final f = CustomerFeedback.fromRow({
        'id': 'f1',
        'rating': 4,
        'comment': 'Great sekuwa',
        'created_at': '2026-09-26T18:30:00Z',
        'customers': {'name': 'Max'},
      });
      expect(f.id, 'f1');
      expect(f.rating, 4);
      expect(f.comment, 'Great sekuwa');
      expect(f.createdAt, DateTime.utc(2026, 9, 26, 18, 30));
      expect(f.customerName, 'Max');
    });

    test('tolerates a null customer and a null rating', () {
      final f = CustomerFeedback.fromRow({
        'id': 'f2',
        'rating': null,
        'comment': null,
        'created_at': '2026-09-26T18:30:00Z',
        'customers': null,
      });
      expect(f.rating, isNull);
      expect(f.comment, isNull);
      expect(f.customerName, isNull);
    });
  });

  group('CrmOverview.debtorsFirst', () {
    test('debtors lead, biggest debt first, everyone else in list order', () {
      const list = [
        CrmCustomer(id: 'a', name: 'A'),
        CrmCustomer(id: 'b', name: 'B', owesCents: 500, unpaidBills: 1),
        CrmCustomer(id: 'c', name: 'C'),
        CrmCustomer(id: 'd', name: 'D', owesCents: 2000, unpaidBills: 2),
        CrmCustomer(id: 'e', name: 'E', owesCents: 500, unpaidBills: 1),
        CrmCustomer(id: 'f', name: 'F'),
      ];
      final sorted = CrmOverview.debtorsFirst(list);
      expect(sorted.map((c) => c.id).toList(), ['d', 'b', 'e', 'a', 'c', 'f']);
    });

    test('an empty or debt-free list is untouched', () {
      expect(CrmOverview.debtorsFirst(const []), isEmpty);
      const list = [CrmCustomer(id: 'x'), CrmCustomer(id: 'y')];
      expect(CrmOverview.debtorsFirst(list).map((c) => c.id).toList(), [
        'x',
        'y',
      ]);
    });
  });
}
