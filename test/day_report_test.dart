import 'dart:convert';

import 'package:extrahelper/data/supabase/day_report_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real `daily_report` response, captured from the live database for
/// 2026-08-22 and trimmed only in the length of `top_items`.
///
/// Worth keeping verbatim: this is the day whose payments (838,000) genuinely
/// exceed its revenue (577,000), because 261,000 of what was taken settled
/// bills raised earlier. That gap is the feature's most confusing number and
/// the reason `carried_cents` exists, so the fixture that proves it should be
/// the real one rather than something invented to be tidy.
Map<String, dynamic> _payload() =>
    jsonDecode('''
{
  "day": "2026-08-22",
  "day_label": "Saturday, Aug 22, 2026",
  "from": "2026-08-21T18:15:00+00:00",
  "to": "2026-08-22T18:15:00+00:00",
  "currency": "NPR",
  "timezone": "Asia/Kathmandu",
  "cutoff_minutes": 0,
  "sales": {
    "bills": 2,
    "avg_cents": 288500,
    "tax_cents": 0,
    "tip_cents": 0,
    "revenue_cents": 577000,
    "service_cents": 0,
    "tables_served": 2,
    "discount_cents": 0,
    "rounding_cents": 0,
    "subtotal_cents": 577000
  },
  "payments": [
    {"count": 2, "method": "cash", "amount_cents": 760000},
    {"count": 1, "method": "wallet", "amount_cents": 78000}
  ],
  "payments_total_cents": 838000,
  "carried_cents": 261000,
  "refunds": {"count": 0, "cash_cents": 0, "total_cents": 0},
  "voids": {"count": 0, "lines": 0, "value_cents": 0},
  "cancellations": {"count": 0, "value_cents": 0},
  "void_bills": 0,
  "cash": {
    "totals": {
      "sessions": 0, "float_cents": 0, "counted_cents": 0, "paid_in_cents": 0,
      "payouts_cents": 0, "expected_cents": 0, "variance_cents": 0
    },
    "sessions": [],
    "open_count": 0
  },
  "top_items": [
    {"qty": 2, "description": "Buff Sekuwa (Half Kg)", "revenue_cents": 120000},
    {"qty": 5, "description": "Coke (glass)", "revenue_cents": 50000}
  ]
}
''')
        as Map<String, dynamic>;

/// The cash block from tenant 6a290e99 on 2026-08-16 — a real short drawer,
/// and the only closed session in the database. Kept because the drawer is the
/// half of the sheet the sales figures cannot check.
Map<String, dynamic> _cash() =>
    jsonDecode('''
{
  "totals": {
    "sessions": 1, "float_cents": 432000, "counted_cents": 377500,
    "paid_in_cents": 0, "payouts_cents": 0, "expected_cents": 432000,
    "variance_cents": -54500
  },
  "sessions": [
    {
      "id": "1ad23178-4922-4fa1-8bf3-a47c13f8aa9a",
      "cashier": "@clixacom_a132",
      "closed_at": "2026-08-16T03:35:28.999968+00:00",
      "opened_at": "2026-08-16T03:35:14.308149+00:00",
      "cashier_id": "a1328472-0beb-464e-b07a-595305ffc368",
      "counted_cents": 377500,
      "paid_in_cents": 0,
      "payouts_cents": 0,
      "expected_cents": 432000,
      "variance_cents": -54500,
      "auto_approved_count": 0,
      "opening_float_cents": 432000
    }
  ],
  "open_count": 1
}
''')
        as Map<String, dynamic>;

void main() {
  group('DayReport.fromJson', () {
    test('reads a real payload', () {
      final r = DayReport.fromJson(_payload());

      expect(r.day, '2026-08-22');
      expect(r.dayLabel, 'Saturday, Aug 22, 2026');
      expect(r.currency, 'NPR');
      expect(r.timezone, 'Asia/Kathmandu');
      expect(r.cutoffMinutes, 0);

      expect(r.sales.revenueCents, 577000);
      expect(r.sales.bills, 2);
      expect(r.sales.avgCents, 288500);
      expect(r.sales.tablesServed, 2);

      expect(r.payments.map((p) => p.method), ['cash', 'wallet']);
      expect(r.payments.first.amountCents, 760000);
      expect(r.payments.first.count, 2);
      expect(r.paymentsTotalCents, 838000);

      expect(r.topItems.first.description, 'Buff Sekuwa (Half Kg)');
      expect(r.topItems.first.qty, 2);
      expect(r.isQuiet, isFalse);
    });

    test('the window is the report\'s own, and it is a full day', () {
      final r = DayReport.fromJson(_payload());
      expect(r.to.difference(r.from), const Duration(days: 1));
      // 18:15Z is Kathmandu midnight (+05:45) — the boundary came from
      // Postgres, and nothing in Dart is allowed to recompute it.
      expect(r.from.toUtc().hour, 18);
      expect(r.from.toUtc().minute, 15);
    });

    test('carried money is kept as its own figure, both ways round', () {
      final over = DayReport.fromJson(_payload());
      expect(over.carriedCents, 261000);
      expect(
        over.paymentsTotalCents - over.sales.revenueCents,
        over.carriedCents,
        reason: 'the gap the sheet explains must be the gap the sheet shows',
      );

      final under = DayReport.fromJson({
        ..._payload(),
        'carried_cents': -261000,
        'payments_total_cents': 316000,
      });
      expect(under.carriedCents, -261000);
    });

    test('a short drawer keeps its sign', () {
      final r = DayReport.fromJson({..._payload(), 'cash': _cash()});

      expect(r.cash.openCount, 1);
      expect(r.cash.sessions, hasLength(1));
      expect(r.cash.totals.sessions, 1);

      final s = r.cash.sessions.single;
      expect(s.cashier, '@clixacom_a132');
      expect(s.openingFloatCents, 432000);
      expect(s.expectedCents, 432000);
      expect(s.countedCents, 377500);
      expect(s.varianceCents, -54500);
      expect(s.autoApprovedCount, 0);
      expect(s.closedAt, isNotNull);
    });

    test('bigints arriving as strings are parsed, not dropped', () {
      // count(*) is a bigint, and a bigint can reach Dart either way.
      final r = DayReport.fromJson({
        ..._payload(),
        'payments_total_cents': '838000',
        'carried_cents': '261000',
        'sales': {'revenue_cents': '577000', 'bills': '2'},
        'top_items': [
          {'qty': '5', 'description': 'Coke (glass)', 'revenue_cents': '50000'},
        ],
      });

      expect(r.paymentsTotalCents, 838000);
      expect(r.carriedCents, 261000);
      expect(r.sales.revenueCents, 577000);
      expect(r.sales.bills, 2);
      expect(r.topItems.single.qty, 5);
    });

    test('a missing key never throws — an older build must still render', () {
      final r = DayReport.fromJson(const {});

      expect(r.currency, 'USD');
      expect(r.timezone, 'UTC');
      expect(r.day, '');
      expect(r.sales.revenueCents, 0);
      expect(r.payments, isEmpty);
      expect(r.cash.sessions, isEmpty);
      expect(r.cash.totals.varianceCents, 0);
      expect(r.topItems, isEmpty);
      expect(r.isQuiet, isTrue);
    });

    test('a quiet day is a real answer, not an empty one', () {
      final r = DayReport.fromJson({
        ..._payload(),
        'sales': {'bills': 0, 'revenue_cents': 0},
        'payments': [],
        'top_items': [],
      });

      expect(r.isQuiet, isTrue);
      expect(r.dayLabel, isNotEmpty, reason: 'the day still has a name');
    });
  });
}
