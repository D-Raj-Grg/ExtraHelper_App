import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/pos/models.dart';
import 'pos_repository.dart';
import 'supabase_providers.dart';

/// One trading day, closed off — exactly as `daily_report` computed it.
///
/// The Z-report: what was sold, what was tendered, what went in the drawer.
/// Every figure was aggregated in Postgres in the tenant's timezone, and this
/// class only reads the envelope. The web's day-close sheet renders the *same*
/// RPC, so paper, phone and browser cannot disagree about a day.
///
/// **Nothing here computes a day boundary**, and nothing may start. `intl`
/// carries no IANA database (see `lib/core/format/when.dart`), so the day, its
/// label and its window all arrive already resolved — the same reason
/// `PosRepository.tenantDayStart` is a round trip instead of arithmetic.
class DayReport {
  const DayReport({
    required this.day,
    required this.dayLabel,
    required this.from,
    required this.to,
    required this.currency,
    required this.timezone,
    required this.cutoffMinutes,
    required this.sales,
    required this.payments,
    required this.paymentsTotalCents,
    required this.carriedCents,
    required this.refunds,
    required this.voids,
    required this.cancellations,
    required this.voidBills,
    required this.cash,
    required this.topItems,
  });

  /// `YYYY-MM-DD`, the business day this report covers. Server-resolved: ask
  /// for a null day and this comes back as the tenant's *current* trading day,
  /// which is the only way the app can learn what "today" is.
  final String day;

  /// "Saturday, Aug 22, 2026" — formatted by Postgres, printed as-is.
  final String dayLabel;

  /// The window, inclusive of [from] and exclusive of [to]. The orders list is
  /// bounded by these and never by a locally computed day, so the ledger and
  /// the totals above it always describe the same day.
  final DateTime from;
  final DateTime to;

  final String currency;
  final String timezone;

  /// Minutes after local midnight at which the trading day turns over.
  /// 240 = 4am, so a sale at 01:30 belongs to the night before. 0 = midnight.
  final int cutoffMinutes;

  final DaySales sales;

  final List<DayPayment> payments;
  final int paymentsTotalCents;

  /// Tendered minus settled, and it is routinely non-zero — **not** a bug.
  ///
  /// Revenue buckets on the bill's date and payments on the payment's date, so
  /// cash taken today against yesterday's bill lands in one and not the other.
  /// Positive: today's takings are settling older bills. Negative: today's
  /// bills have not been tendered yet. The screen says which, in words.
  final int carriedCents;

  final DayRefunds refunds;
  final DayVoids voids;
  final DayCancels cancellations;

  /// Bills voided outright — a different failure from a voided line.
  final int voidBills;

  final DayCash cash;
  final List<DayTopItem> topItems;

  /// A day on which nothing was billed. Still a real answer, so the sheet
  /// renders in full with zeros rather than collapsing to an empty state.
  bool get isQuiet => sales.bills == 0;

  static DayReport fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> obj(String key) =>
        (j[key] as Map<String, dynamic>?) ?? const {};

    return DayReport(
      day: (j['day'] as String?) ?? '',
      dayLabel: (j['day_label'] as String?) ?? '',
      from: _time(j['from']),
      to: _time(j['to']),
      currency: (j['currency'] as String?) ?? 'USD',
      timezone: (j['timezone'] as String?) ?? 'UTC',
      cutoffMinutes: _int(j['cutoff_minutes']),
      sales: DaySales.fromJson(obj('sales')),
      payments: _list(j['payments'], DayPayment.fromJson),
      paymentsTotalCents: _int(j['payments_total_cents']),
      carriedCents: _int(j['carried_cents']),
      refunds: DayRefunds.fromJson(obj('refunds')),
      voids: DayVoids.fromJson(obj('voids')),
      cancellations: DayCancels.fromJson(obj('cancellations')),
      voidBills: _int(j['void_bills']),
      cash: DayCash.fromJson(obj('cash')),
      topItems: _list(j['top_items'], DayTopItem.fromJson),
    );
  }
}

/// The money, all of it from `bills` alone.
///
/// Never from `bills join orders`: `add_order_to_bill` merges tables, so a
/// merged bill would be multiplied by the number of orders sharing it. The RPC
/// is careful about this and so is the takings line on the POS.
class DaySales {
  const DaySales({
    required this.revenueCents,
    required this.subtotalCents,
    required this.taxCents,
    required this.serviceCents,
    required this.discountCents,
    required this.tipCents,
    required this.roundingCents,
    required this.bills,
    required this.tablesServed,
    required this.avgCents,
  });

  /// What was settled: paid bills, at bill totals, after tax and discounts.
  final int revenueCents;

  final int subtotalCents;
  final int taxCents;
  final int serviceCents;

  /// A positive magnitude. Shown negated, because it came *off* the bill.
  final int discountCents;

  final int tipCents;
  final int roundingCents;

  final int bills;
  final int tablesServed;
  final int avgCents;

  static DaySales fromJson(Map<String, dynamic> j) => DaySales(
    revenueCents: _int(j['revenue_cents']),
    subtotalCents: _int(j['subtotal_cents']),
    taxCents: _int(j['tax_cents']),
    serviceCents: _int(j['service_cents']),
    discountCents: _int(j['discount_cents']),
    tipCents: _int(j['tip_cents']),
    roundingCents: _int(j['rounding_cents']),
    bills: _int(j['bills']),
    tablesServed: _int(j['tables_served']),
    avgCents: _int(j['avg_cents']),
  );
}

class DayPayment {
  const DayPayment({
    required this.method,
    required this.amountCents,
    required this.count,
  });

  /// `cash` | `card` | `esewa` | … — rendered through `paymentMethodLabel`.
  final String method;

  final int amountCents;
  final int count;

  static DayPayment fromJson(Map<String, dynamic> j) => DayPayment(
    method: (j['method'] as String?) ?? '',
    amountCents: _int(j['amount_cents']),
    count: _int(j['count']),
  );
}

class DayRefunds {
  const DayRefunds({
    required this.totalCents,
    required this.cashCents,
    required this.count,
  });

  final int totalCents;

  /// Refunded in cash specifically — the part that left the drawer.
  final int cashCents;

  final int count;

  static DayRefunds fromJson(Map<String, dynamic> j) => DayRefunds(
    totalCents: _int(j['total_cents']),
    cashCents: _int(j['cash_cents']),
    count: _int(j['count']),
  );
}

class DayVoids {
  const DayVoids({
    required this.count,
    required this.lines,
    required this.valueCents,
  });

  /// Void *events*, from the audit log — this is what the web's Sales tab
  /// counts, so the two agree.
  final int count;

  /// Voided order lines. Not the same number as [count], on purpose.
  final int lines;

  final int valueCents;

  static DayVoids fromJson(Map<String, dynamic> j) => DayVoids(
    count: _int(j['count']),
    lines: _int(j['lines']),
    valueCents: _int(j['value_cents']),
  );
}

class DayCancels {
  const DayCancels({required this.count, required this.valueCents});

  final int count;

  /// Priced from each cancelled order's own non-void lines.
  final int valueCents;

  static DayCancels fromJson(Map<String, dynamic> j) =>
      DayCancels(count: _int(j['count']), valueCents: _int(j['value_cents']));
}

class DayCash {
  const DayCash({
    required this.openCount,
    required this.sessions,
    required this.totals,
  });

  /// Drawers opened in this window and still open. A Z-report printed with a
  /// drawer open has to say so — the reconciliation below covers closed
  /// sessions only, and a manager who doesn't know that will chase a phantom.
  final int openCount;

  final List<DayCashSession> sessions;
  final DayCashTotals totals;

  static DayCash fromJson(Map<String, dynamic> j) => DayCash(
    openCount: _int(j['open_count']),
    sessions: _list(j['sessions'], DayCashSession.fromJson),
    totals: DayCashTotals.fromJson(
      (j['totals'] as Map<String, dynamic>?) ?? const {},
    ),
  );
}

class DayCashSession {
  const DayCashSession({
    required this.id,
    required this.openingFloatCents,
    required this.payoutsCents,
    required this.paidInCents,
    required this.expectedCents,
    required this.countedCents,
    required this.varianceCents,
    required this.autoApprovedCount,
    this.cashier,
    this.closedAt,
  });

  final String id;

  /// The cashier's name, or their `@username` when they have no full name.
  /// Null when the profile is gone — shown as "Unknown cashier".
  final String? cashier;

  final int openingFloatCents;

  /// Cash taken *out* of the drawer (approved payouts).
  final int payoutsCents;

  /// Cash put *in* beyond the float.
  final int paidInCents;

  final int expectedCents;
  final int countedCents;

  /// Counted minus expected. Negative is short, positive is over.
  final int varianceCents;

  /// Movements the close approved on the manager's behalf. Worth surfacing:
  /// it means nobody signed them off individually.
  final int autoApprovedCount;

  final DateTime? closedAt;

  static DayCashSession fromJson(Map<String, dynamic> j) => DayCashSession(
    id: (j['id'] as String?) ?? '',
    cashier: j['cashier'] as String?,
    openingFloatCents: _int(j['opening_float_cents']),
    payoutsCents: _int(j['payouts_cents']),
    paidInCents: _int(j['paid_in_cents']),
    expectedCents: _int(j['expected_cents']),
    countedCents: _int(j['counted_cents']),
    varianceCents: _int(j['variance_cents']),
    autoApprovedCount: _int(j['auto_approved_count']),
    closedAt: j['closed_at'] == null ? null : _time(j['closed_at']),
  );
}

class DayCashTotals {
  const DayCashTotals({
    required this.floatCents,
    required this.payoutsCents,
    required this.paidInCents,
    required this.expectedCents,
    required this.countedCents,
    required this.varianceCents,
    required this.sessions,
  });

  final int floatCents;
  final int payoutsCents;
  final int paidInCents;
  final int expectedCents;
  final int countedCents;
  final int varianceCents;

  /// How many closed sessions these totals cover.
  final int sessions;

  static DayCashTotals fromJson(Map<String, dynamic> j) => DayCashTotals(
    floatCents: _int(j['float_cents']),
    payoutsCents: _int(j['payouts_cents']),
    paidInCents: _int(j['paid_in_cents']),
    expectedCents: _int(j['expected_cents']),
    countedCents: _int(j['counted_cents']),
    varianceCents: _int(j['variance_cents']),
    sessions: _int(j['sessions']),
  );
}

class DayTopItem {
  const DayTopItem({
    required this.description,
    required this.qty,
    required this.revenueCents,
  });

  final String description;
  final int qty;
  final int revenueCents;

  static DayTopItem fromJson(Map<String, dynamic> j) => DayTopItem(
    description: (j['description'] as String?) ?? '',
    qty: _int(j['qty']),
    revenueCents: _int(j['revenue_cents']),
  );
}

/// The day's orders, and whether there were more than we asked for.
class DayOrdersPage {
  const DayOrdersPage({required this.orders, required this.truncated});

  final List<PosCompletedOrder> orders;

  /// The cap was hit. Say so — a partial list that reads as complete is worse
  /// than no list, and the web sheet is where the full day lives.
  final bool truncated;

  /// What the day's orders came to at menu prices, cancellations excluded.
  ///
  /// **Not** revenue, and it will not match it: this is what was *ordered*,
  /// whether or not anyone paid, before tax, service and discounts. Summed from
  /// each order's own lines rather than its bill, because a merged bill reports
  /// its whole total against every order on it.
  int get orderedCents => orders
      .where((o) => !o.isCancelled)
      .fold(0, (sum, o) => sum + o.lineTotalCents);
}

/// Everything numeric goes through this.
///
/// jsonb `bigint` reaches Dart as a plain number *or* as a string depending on
/// magnitude and driver, and `count(*)` is a bigint. Parsing defensively costs
/// nothing; guessing wrong shows a zero where the money was.
int _int(Object? v) => switch (v) {
  int() => v,
  num() => v.round(),
  String() => int.tryParse(v) ?? 0,
  _ => 0,
};

DateTime _time(Object? v) =>
    DateTime.tryParse(v is String ? v : '')?.toLocal() ??
    DateTime.fromMillisecondsSinceEpoch(0);

List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) map) =>
    ((v as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(map)
        .toList();

/// The caller holds no `reports.view` in this restaurant.
///
/// `daily_report` answers null rather than raising, exactly as
/// `dashboard_summary` does, so this is a state to render and not an error to
/// shout about — a waiter opening the drawer entry is not a fault.
class DayReportForbidden implements Exception {
  const DayReportForbidden();
}

class DayReportRepository {
  const DayReportRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  /// The whole sheet in one round trip.
  ///
  /// [day] is `YYYY-MM-DD`, or null for **the tenant's current trading day** —
  /// which the server resolves through `business_day(now(), tz, cutoff)`. Null
  /// is the only way to ask "what day is it?", because the phone cannot work it
  /// out: the answer comes back as [DayReport.day].
  Future<DayReport> report({String? day}) async {
    final res = await _client.rpc<dynamic>(
      'daily_report',
      params: {'_tenant': _tenantId, '_day': day},
    );
    if (res == null) throw const DayReportForbidden();
    return DayReport.fromJson(res as Map<String, dynamic>);
  }

  /// The day's orders, bounded by the report's own window.
  ///
  /// [from]/[to] come straight off the payload rather than being recomputed, so
  /// this list and the totals above it cannot end up describing different days.
  ///
  /// Every order, not just the finished ones — the Completed tab answers "what
  /// have I closed?", and this answers "what happened that day?", which
  /// includes the ones still open at the close.
  Future<DayOrdersPage> orders({
    required DateTime from,
    required DateTime to,
    int limit = 300,
  }) async {
    final rows = await _client
        .from('orders')
        .select(PosRepository.completedSelect)
        .eq('tenant_id', _tenantId)
        .gte('created_at', from.toUtc().toIso8601String())
        .lt('created_at', to.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        // Lines in the order they were rung up, so the detail sheet reads like
        // the ticket did. Without this the embed comes back unordered and the
        // same order can list its items differently on two openings.
        .order('created_at', referencedTable: 'order_items')
        // One over the cap, so a full page can be told from an exact fit.
        .limit(limit + 1);

    final all = rows.map(PosCompletedOrder.fromRow).toList();
    return DayOrdersPage(
      orders: all.length > limit ? all.sublist(0, limit) : all,
      truncated: all.length > limit,
    );
  }
}

final dayReportRepositoryProvider =
    Provider.family<DayReportRepository, String>(
      (ref, tenantId) =>
          DayReportRepository(ref.watch(supabaseProvider), tenantId),
    );
