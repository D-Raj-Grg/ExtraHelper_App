import 'dart:convert';

import 'package:extrahelper/data/supabase/dashboard_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// A trimmed copy of a real `dashboard_summary` response, including the shapes
/// Postgres actually emits: bigints as JSON numbers, numerics as strings with
/// trailing zeros (`"3.750"`), and nulls for a takeaway bill's table.
Map<String, dynamic> _payload({
  int todayRevenue = 115000,
  int todayBills = 2,
  int yesterday = 113400,
}) =>
    jsonDecode('''
{
  "currency": "NPR",
  "timezone": "Asia/Kathmandu",
  "days": 7,
  "today": {"revenue_cents": $todayRevenue, "bills": $todayBills, "avg_cents": 57500},
  "yesterday_revenue_cents": $yesterday,
  "active_orders": 4,
  "open_kots": 9,
  "low_stock_count": 3,
  "series": [
    {"day": "2026-07-29", "label": "Jul 29", "revenue_cents": $yesterday},
    {"day": "2026-07-30", "label": "Jul 30", "revenue_cents": $todayRevenue}
  ],
  "low_stock": [
    {"name": "Buffalo", "uom": "kg", "current_qty": "3.750", "reorder_level": "8.000"},
    {"name": "Mutton", "uom": "kg", "current_qty": "-2.000", "reorder_level": "10.000"}
  ],
  "reservations": [
    {"name": "Guest", "party_size": 4, "table_label": "A1", "status": "confirmed",
     "at": "2026-07-30T12:00:00+00:00", "at_text": "Jul 30, 2026, 5:45 PM"}
  ],
  "recent_payments": [
    {"bill_id": "e8b4bd7d-24e9-4321-b71e-be10bcfad9ef", "table_label": null,
     "total_cents": 85000, "at": "2026-07-30T02:42:17+00:00", "at_text": "Jul 30, 2026, 8:27 AM"}
  ]
}
''')
        as Map<String, dynamic>;

void main() {
  group('DashboardSummary.fromJson', () {
    test('reads the envelope the RPC actually sends', () {
      final s = DashboardSummary.fromJson(_payload());

      expect(s.currency, 'NPR');
      expect(s.timezone, 'Asia/Kathmandu');
      expect(s.todayRevenueCents, 115000);
      expect(s.todayBills, 2);
      expect(s.activeOrders, 4);
      expect(s.openKots, 9);
      expect(s.lowStockCount, 3);
      expect(s.series.length, 2);
      expect(s.series.last.label, 'Jul 30');
      expect(s.reservations.single.tableLabel, 'A1');
      // A takeaway bill has no table — null must survive, not become "null".
      expect(s.recentPayments.single.tableLabel, isNull);
    });

    test('numerics arriving as strings are parsed, not dropped', () {
      final s = DashboardSummary.fromJson(_payload());
      expect(s.lowStock.first.currentQty, 3.75);
      expect(s.lowStock.first.reorderLevel, 8);
    });

    test('a negative quantity reads as oversold, not merely low', () {
      final s = DashboardSummary.fromJson(_payload());
      expect(s.lowStock.first.isOversold, isFalse);
      expect(s.lowStock.last.isOversold, isTrue);
    });

    test('a missing key never throws — an older build must still render', () {
      final s = DashboardSummary.fromJson(const {});
      expect(s.currency, 'USD');
      expect(s.todayRevenueCents, 0);
      expect(s.series, isEmpty);
      expect(s.recentPayments, isEmpty);
    });
  });

  group('deltaPct', () {
    test('matches the web formula', () {
      final s = DashboardSummary.fromJson(
        _payload(todayRevenue: 200, yesterday: 100),
      );
      expect(s.deltaPct, 100);
    });

    test('is null when yesterday sold nothing — not infinity, not 100%', () {
      final s = DashboardSummary.fromJson(
        _payload(todayRevenue: 5000, yesterday: 0),
      );
      expect(s.deltaPct, isNull);
    });

    test('goes negative on a worse day', () {
      final s = DashboardSummary.fromJson(
        _payload(todayRevenue: 50, yesterday: 100),
      );
      expect(s.deltaPct, -50);
    });
  });

  group('isEmpty', () {
    test('a restaurant with history is not empty', () {
      expect(DashboardSummary.fromJson(_payload()).isEmpty, isFalse);
    });

    test('no bills, no orders, no history reads as nothing-yet', () {
      final blank = DashboardSummary.fromJson(const {
        'today': {'revenue_cents': 0, 'bills': 0, 'avg_cents': 0},
        'active_orders': 0,
        'series': [
          {'day': '2026-07-30', 'label': 'Jul 30', 'revenue_cents': 0},
        ],
        'recent_payments': <Map<String, dynamic>>[],
      });
      expect(blank.isEmpty, isTrue);
    });
  });
}
