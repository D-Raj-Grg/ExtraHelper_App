import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_providers.dart';

/// The owner dashboard, exactly as `dashboard_summary` computed it.
///
/// Every figure here was aggregated in Postgres in the tenant's timezone — this
/// class only reads the envelope. Nothing about money, days or thresholds is
/// decided in Dart (`CLAUDE.md` rule 1), because the web dashboard renders the
/// same RPC and the two must not drift.
class DashboardSummary {
  const DashboardSummary({
    required this.currency,
    required this.timezone,
    required this.days,
    required this.todayRevenueCents,
    required this.todayBills,
    required this.todayAvgCents,
    required this.yesterdayRevenueCents,
    required this.activeOrders,
    required this.openKots,
    required this.lowStockCount,
    required this.series,
    required this.lowStock,
    required this.reservations,
    required this.recentPayments,
  });

  final String currency;
  final String timezone;
  final int days;

  final int todayRevenueCents;
  final int todayBills;
  final int todayAvgCents;
  final int yesterdayRevenueCents;

  final int activeOrders;
  final int openKots;
  final int lowStockCount;

  final List<RevenueDay> series;
  final List<LowStockItem> lowStock;
  final List<UpcomingReservation> reservations;
  final List<RecentPayment> recentPayments;

  /// Today against yesterday, or null when yesterday sold nothing — a percentage
  /// against zero is not a comparison, it's a division by zero dressed up.
  /// Same rule as the web dashboard, so both read the same.
  double? get deltaPct => yesterdayRevenueCents > 0
      ? (todayRevenueCents - yesterdayRevenueCents) /
            yesterdayRevenueCents *
            100
      : null;

  /// True when the restaurant has no history at all in the window — the
  /// difference between "quiet day" and "nothing set up yet".
  bool get isEmpty =>
      todayBills == 0 &&
      activeOrders == 0 &&
      recentPayments.isEmpty &&
      series.every((d) => d.revenueCents == 0);

  static DashboardSummary fromJson(Map<String, dynamic> j) {
    final today = (j['today'] as Map<String, dynamic>?) ?? const {};
    List<T> list<T>(String key, T Function(Map<String, dynamic>) map) =>
        ((j[key] as List<dynamic>?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(map)
            .toList();

    return DashboardSummary(
      currency: (j['currency'] as String?) ?? 'USD',
      timezone: (j['timezone'] as String?) ?? 'UTC',
      days: _int(j['days']),
      todayRevenueCents: _int(today['revenue_cents']),
      todayBills: _int(today['bills']),
      todayAvgCents: _int(today['avg_cents']),
      yesterdayRevenueCents: _int(j['yesterday_revenue_cents']),
      activeOrders: _int(j['active_orders']),
      openKots: _int(j['open_kots']),
      lowStockCount: _int(j['low_stock_count']),
      series: list('series', RevenueDay.fromJson),
      lowStock: list('low_stock', LowStockItem.fromJson),
      reservations: list('reservations', UpcomingReservation.fromJson),
      recentPayments: list('recent_payments', RecentPayment.fromJson),
    );
  }
}

/// One day of the revenue series. Zero-filled by the RPC, so a quiet day is a
/// point at zero and not a gap the chart would draw straight through.
class RevenueDay {
  const RevenueDay({
    required this.day,
    required this.label,
    required this.revenueCents,
  });

  /// `YYYY-MM-DD` in the tenant's timezone.
  final String day;

  /// "Jul 30" — already formatted in the tenant's timezone.
  final String label;

  final int revenueCents;

  static RevenueDay fromJson(Map<String, dynamic> j) => RevenueDay(
    day: (j['day'] as String?) ?? '',
    label: (j['label'] as String?) ?? '',
    revenueCents: _int(j['revenue_cents']),
  );
}

class LowStockItem {
  const LowStockItem({
    required this.name,
    required this.uom,
    required this.currentQty,
    required this.reorderLevel,
  });

  final String name;
  final String uom;
  final double currentQty;
  final double reorderLevel;

  /// Below zero means it was sold past empty — a different problem from "low",
  /// and it gets a different word on screen.
  bool get isOversold => currentQty < 0;

  static LowStockItem fromJson(Map<String, dynamic> j) => LowStockItem(
    name: (j['name'] as String?) ?? '',
    uom: (j['uom'] as String?) ?? '',
    currentQty: _double(j['current_qty']),
    reorderLevel: _double(j['reorder_level']),
  );
}

class UpcomingReservation {
  const UpcomingReservation({
    required this.name,
    required this.partySize,
    required this.status,
    required this.atText,
    this.tableLabel,
  });

  final String name;
  final int partySize;

  /// `pending` | `confirmed` | `seated` — rendered through the label map.
  final String status;

  /// Already formatted in the tenant's timezone by Postgres.
  final String atText;

  final String? tableLabel;

  static UpcomingReservation fromJson(Map<String, dynamic> j) =>
      UpcomingReservation(
        name: (j['name'] as String?) ?? 'Guest',
        partySize: _int(j['party_size']),
        status: (j['status'] as String?) ?? '',
        atText: (j['at_text'] as String?) ?? '',
        tableLabel: j['table_label'] as String?,
      );
}

class RecentPayment {
  const RecentPayment({
    required this.billId,
    required this.totalCents,
    required this.atText,
    this.tableLabel,
  });

  final String billId;
  final int totalCents;

  /// Already formatted in the tenant's timezone by Postgres.
  final String atText;

  final String? tableLabel;

  static RecentPayment fromJson(Map<String, dynamic> j) => RecentPayment(
    billId: (j['bill_id'] as String?) ?? '',
    totalCents: _int(j['total_cents']),
    atText: (j['at_text'] as String?) ?? '',
    tableLabel: j['table_label'] as String?,
  );
}

int _int(Object? v) => switch (v) {
  int() => v,
  num() => v.round(),
  String() => int.tryParse(v) ?? 0,
  _ => 0,
};

double _double(Object? v) => switch (v) {
  num() => v.toDouble(),
  String() => double.tryParse(v) ?? 0,
  _ => 0,
};

/// The caller holds no `reports.view` in this restaurant.
///
/// The RPC answers null rather than raising, so this is a state to render, not
/// an error to shout about: a kitchen or inventory role opening the app is not
/// a fault.
class DashboardForbidden implements Exception {
  const DashboardForbidden();
}

class DashboardRepository {
  const DashboardRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  /// One round trip for the whole screen. `_days` is clamped server-side.
  Future<DashboardSummary> summary({int days = 14}) async {
    final res = await _client.rpc<dynamic>(
      'dashboard_summary',
      params: {'_tenant': _tenantId, '_days': days},
    );
    if (res == null) throw const DashboardForbidden();
    return DashboardSummary.fromJson(res as Map<String, dynamic>);
  }
}

final dashboardRepositoryProvider =
    Provider.family<DashboardRepository, String>(
      (ref, tenantId) =>
          DashboardRepository(ref.watch(supabaseProvider), tenantId),
    );
