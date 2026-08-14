/// Checkout domain models. Plain Dart — [BillRepository] maps PostgREST rows
/// into these so no screen ever touches a `Map<String, dynamic>`.
///
/// Every figure here is **cents from the server**. `recompute_bill` runs inside
/// every mutating RPC, so the client's job is to display what SQL decided, never
/// to arrive at a total of its own. The one exception is the per-line discount,
/// which the bill line does not carry — see [BillLine.discountCents] and
/// `bill_math.dart`.
library;

import 'bill_math.dart';

class Bill {
  const Bill({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.subtotalCents,
    required this.taxCents,
    required this.serviceChargeCents,
    required this.discountCents,
    required this.tipCents,
    required this.roundingCents,
    required this.totalCents,
    this.note,
    this.tableLabel,
  });

  final String id;

  /// `open | partial | paid | void`
  final String status;

  final DateTime createdAt;

  final int subtotalCents;
  final int taxCents;

  /// Service charge **and packaging fee** — `recompute_bill` writes both into
  /// this one column, which is why the totals card labels it "Service + pkg".
  final int serviceChargeCents;

  final int discountCents;
  final int tipCents;

  /// Signed. Rounding down to the whole unit is the common case, so this is
  /// usually negative. `set_bill_extras` caps it at ±99.
  final int roundingCents;

  final int totalCents;

  /// The remark that prints on the invoice.
  final String? note;

  /// Null for takeaway and delivery.
  final String? tableLabel;

  bool get isPaid => status == 'paid';
  bool get isVoid => status == 'void';

  /// Money can still move. Anything else is history.
  bool get isSettleable => status == 'open' || status == 'partial';

  static Bill fromRow(Map<String, dynamic> r) {
    final table = r['restaurant_tables'] as Map<String, dynamic>?;
    return Bill(
      id: r['id'] as String,
      status: (r['status'] as String?) ?? 'open',
      createdAt:
          DateTime.tryParse((r['created_at'] as String?) ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      subtotalCents: (r['subtotal_cents'] as int?) ?? 0,
      taxCents: (r['tax_cents'] as int?) ?? 0,
      serviceChargeCents: (r['service_charge_cents'] as int?) ?? 0,
      discountCents: (r['discount_cents'] as int?) ?? 0,
      tipCents: (r['tip_cents'] as int?) ?? 0,
      roundingCents: (r['rounding_cents'] as int?) ?? 0,
      totalCents: (r['total_cents'] as int?) ?? 0,
      note: r['note'] as String?,
      tableLabel: table?['label'] as String?,
    );
  }
}

class BillLineModifier {
  const BillLineModifier({
    required this.id,
    required this.name,
    required this.priceCents,
    required this.qty,
  });

  final String id;
  final String name;
  final int priceCents;
  final int qty;

  static BillLineModifier fromRow(Map<String, dynamic> r) => BillLineModifier(
    id: r['id'] as String,
    name: (r['name_snapshot'] as String?) ?? '',
    priceCents: (r['price_cents'] as int?) ?? 0,
    qty: (r['qty'] as int?) ?? 1,
  );
}

/// One `bill_items` row.
class BillLine {
  const BillLine({
    required this.id,
    required this.description,
    required this.qty,
    required this.unitPriceCents,
    required this.totalCents,
    this.orderItemId,
    this.discountCents = 0,
    this.modifiers = const [],
  });

  final String id;

  /// Null on a synthetic line — one `recompute_bill` wrote without an order
  /// item behind it. Such a line renders, but cannot be discounted or voided:
  /// both RPCs take an `order_item_id`.
  final String? orderItemId;

  final String description;
  final int qty;
  final int unitPriceCents;
  final int totalCents;

  /// Display only, derived from the `discounts` rows for this order item — the
  /// bill line itself carries no discount column. The bill's own
  /// `discount_cents` remains the only figure that reaches the total.
  final int discountCents;

  final List<BillLineModifier> modifiers;

  int get grossCents => unitPriceCents * qty;

  /// A line the per-line sheet can act on.
  bool get isAdjustable => orderItemId != null;

  static BillLine fromRow(
    Map<String, dynamic> r, {
    List<BillLineModifier> modifiers = const [],
    Iterable<DiscountRow> lineDiscounts = const [],
  }) {
    final qty = (r['qty'] as int?) ?? 1;
    final unit = (r['unit_price_cents'] as int?) ?? 0;
    return BillLine(
      id: r['id'] as String,
      orderItemId: r['order_item_id'] as String?,
      description: (r['description'] as String?) ?? '',
      qty: qty,
      unitPriceCents: unit,
      totalCents: (r['total_cents'] as int?) ?? unit * qty,
      discountCents: lineDiscountCents(
        lineGrossCents: unit * qty,
        forLine: lineDiscounts,
      ),
      modifiers: modifiers,
    );
  }
}

class PaymentRow {
  const PaymentRow({
    required this.id,
    required this.method,
    required this.amountCents,
    required this.createdAt,
  });

  final String id;

  /// `cash | card | online | wallet | points`
  final String method;

  final int amountCents;
  final DateTime createdAt;

  static PaymentRow fromRow(Map<String, dynamic> r) => PaymentRow(
    id: r['id'] as String,
    method: (r['method'] as String?) ?? 'cash',
    amountCents: (r['amount_cents'] as int?) ?? 0,
    createdAt:
        DateTime.tryParse((r['created_at'] as String?) ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class ChargeRow {
  const ChargeRow({
    required this.id,
    required this.label,
    required this.amountCents,
  });

  final String id;
  final String label;
  final int amountCents;

  static ChargeRow fromRow(Map<String, dynamic> r) => ChargeRow(
    id: r['id'] as String,
    label: (r['label'] as String?) ?? 'Charge',
    amountCents: (r['amount_cents'] as int?) ?? 0,
  );
}

/// A raw `discounts` row. Bill-level ones have a null [orderItemId].
class DiscountRow {
  const DiscountRow({
    required this.type,
    required this.value,
    this.orderItemId,
    this.couponCode,
    this.reason,
  });

  final String? orderItemId;

  /// `percent | flat`
  final String type;

  /// Percent points for `percent`, whole currency units for `flat` — **not**
  /// cents. `apply_bill_discount` takes it in the same shape.
  final num value;

  final String? couponCode;
  final String? reason;

  bool get isPercent => type == 'percent';

  static DiscountRow fromRow(Map<String, dynamic> r) => DiscountRow(
    orderItemId: r['order_item_id'] as String?,
    type: (r['type'] as String?) ?? 'flat',
    value: _numOf(r['value']),
    couponCode: r['coupon_code'] as String?,
    reason: r['reason'] as String?,
  );

  /// `numeric` arrives as a String over PostgREST when it exceeds what JSON can
  /// hold exactly — rare at these sizes, but a crash if unhandled.
  static num _numOf(Object? v) =>
      v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
}

class BillCustomer {
  const BillCustomer({
    required this.id,
    required this.points,
    this.name,
    this.phone,
  });

  final String id;
  final String? name;
  final String? phone;
  final int points;

  String get label => name ?? phone ?? 'Guest';
}

/// A fired order with no bill yet — a candidate for merging onto this one.
class MergeableOrder {
  const MergeableOrder({
    required this.id,
    required this.orderType,
    required this.status,
    this.tableLabel,
  });

  final String id;
  final String orderType;
  final String status;
  final String? tableLabel;

  static MergeableOrder fromRow(Map<String, dynamic> r) {
    final table = r['restaurant_tables'] as Map<String, dynamic>?;
    return MergeableOrder(
      id: r['id'] as String,
      orderType: (r['order_type'] as String?) ?? 'dine_in',
      status: (r['status'] as String?) ?? 'placed',
      tableLabel: table?['label'] as String?,
    );
  }
}

/// The slice of `tenant_settings` checkout needs.
///
/// Deliberately not the receipt template: the phone shows no invoice preview —
/// the receipt is built by the print stack from `/api/print/render`.
class TenantMoneySettings {
  const TenantMoneySettings({this.pointsValueCents = 1});

  /// What one loyalty point is worth. Zero would divide by zero in the redeem
  /// cap, so the reader clamps it — same as the web's `Math.max(1, …)`.
  final int pointsValueCents;

  static TenantMoneySettings fromRow(Map<String, dynamic>? r) =>
      TenantMoneySettings(
        pointsValueCents: (r?['points_value_cents'] as int?) ?? 1,
      );
}

/// A bill row as the Bills tab lists it — enough to choose one, no more.
class OpenBillRow {
  const OpenBillRow({
    required this.id,
    required this.status,
    required this.totalCents,
    required this.createdAt,
    this.tableLabel,
  });

  final String id;
  final String status;
  final int totalCents;
  final DateTime createdAt;
  final String? tableLabel;

  static OpenBillRow fromRow(Map<String, dynamic> r) {
    final table = r['restaurant_tables'] as Map<String, dynamic>?;
    return OpenBillRow(
      id: r['id'] as String,
      status: (r['status'] as String?) ?? 'open',
      totalCents: (r['total_cents'] as int?) ?? 0,
      createdAt:
          DateTime.tryParse((r['created_at'] as String?) ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      tableLabel: table?['label'] as String?,
    );
  }
}

/// Everything one checkout screen needs, read together.
///
/// Assembled in one place so no widget ever issues its own query and no two
/// parts of the screen can disagree about what is owed.
class BillSnapshot {
  const BillSnapshot({
    required this.bill,
    required this.lines,
    required this.payments,
    required this.charges,
    required this.discounts,
    required this.settings,
    this.customer,
    this.mergeable = const [],
    this.waiterName,
  });

  final Bill bill;
  final List<BillLine> lines;
  final List<PaymentRow> payments;
  final List<ChargeRow> charges;
  final List<DiscountRow> discounts;
  final TenantMoneySettings settings;
  final BillCustomer? customer;
  final List<MergeableOrder> mergeable;
  final String? waiterName;

  int get paidCents => payments.fold(0, (n, p) => n + p.amountCents);

  /// Never negative: an overpayment is change owed, not a bill that owes you.
  int get dueCents => (bill.totalCents - paidCents).clamp(0, bill.totalCents);

  /// The lines before any bill-level arithmetic — the "Item total" row.
  int get itemTotalCents => lines.fold(0, (n, l) => n + l.totalCents);

  /// Bill-level discounts only. Per-line ones are shown against their line.
  Iterable<DiscountRow> get billDiscounts =>
      discounts.where((d) => d.orderItemId == null);

  int get chargesCents => charges.fold(0, (n, c) => n + c.amountCents);

  /// Money can still be taken. A void bill can't, whatever it is owed.
  bool get canTakePayment => bill.isSettleable && dueCents > 0;
}
