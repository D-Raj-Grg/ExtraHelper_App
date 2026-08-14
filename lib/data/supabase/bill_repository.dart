import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/pos/bill_models.dart';
import 'pos_repository.dart' show PosFailure, PosTransientFailure;
import 'supabase_providers.dart';

/// A money write that got no answer.
///
/// Deliberately **not** a [PosTransientFailure]. A transient failure means the
/// write did not happen; this means nobody knows. `record_payment` may have
/// committed before the socket died, so the only honest thing to say is "check
/// the bill" — never "money wasn't taken", which is what a cashier would read
/// into the ordinary transient copy.
///
/// The key is carried so a retry can reuse it: `record_payment` dedups on
/// `unique(tenant_id, idempotency_key)`, which makes resending the *same* key
/// safe and resending a new one a double charge.
class PaymentUncertainFailure extends PosFailure {
  const PaymentUncertainFailure(super.message, {required this.idempotencyKey});

  final String idempotencyKey;
}

/// Reads and writes for checkout.
///
/// Every figure on a bill is decided by `recompute_bill`, which runs inside each
/// of the RPCs below and is revoked from `authenticated` — so this class can
/// only ever ask the server to change something and then read back what it
/// decided. There is no client-side total.
///
/// Plain reads go through PostgREST under RLS **plus an explicit tenant filter**
/// as defense in depth (rule 2), matching [PosRepository].
class BillRepository {
  const BillRepository(this._client, this._tenantId);

  final SupabaseClient _client;
  final String _tenantId;

  // --- Reads ---------------------------------------------------------------

  static const _billSelect =
      'id, status, created_at, subtotal_cents, tax_cents, service_charge_cents, '
      'discount_cents, tip_cents, rounding_cents, total_cents, note, '
      'restaurant_tables(label)';

  /// Everything the checkout screen needs, in two passes.
  ///
  /// Two rather than one because modifiers and per-line discounts hang off the
  /// **order** item, not the bill line, so their ids only exist once the lines
  /// are back. Same shape as the web's `bill/[billId]/page.tsx`, which is what
  /// keeps the two screens showing the same bill.
  Future<BillSnapshot> snapshot(String billId) async {
    final Map<String, dynamic>? billRow;
    final List<Map<String, dynamic>> itemRows;
    final List<Map<String, dynamic>> paymentRows;
    final List<Map<String, dynamic>> chargeRows;
    final List<Map<String, dynamic>> discountRows;
    final Map<String, dynamic>? orderRow;
    final Map<String, dynamic>? settingsRow;

    try {
      // Explicitly `dynamic`: PostgREST's builders are each a differently-typed
      // Future, and inference lands on `Object` and refuses the list.
      final results = await Future.wait<dynamic>([
        _client
            .from('bills')
            .select(_billSelect)
            .eq('id', billId)
            .eq('tenant_id', _tenantId)
            .maybeSingle(),
        _client
            .from('bill_items')
            .select(
              'id, order_item_id, description, qty, unit_price_cents, total_cents',
            )
            .eq('bill_id', billId)
            .eq('tenant_id', _tenantId),
        _client
            .from('payments')
            .select('id, method, amount_cents, created_at')
            .eq('bill_id', billId)
            .eq('tenant_id', _tenantId)
            .eq('status', 'completed')
            .order('created_at'),
        _client
            .from('bill_charges')
            .select('id, label, amount_cents')
            .eq('bill_id', billId)
            .eq('tenant_id', _tenantId)
            .order('created_at'),
        _client
            .from('discounts')
            .select('order_item_id, type, value, coupon_code, reason')
            .eq('bill_id', billId)
            .eq('tenant_id', _tenantId),
        _client
            .from('orders')
            .select(
              'id, created_at, waiter_id, '
              'customers(id, name, phone, loyalty_accounts(points_balance))',
            )
            .eq('bill_id', billId)
            .eq('tenant_id', _tenantId)
            .order('created_at')
            .limit(1)
            .maybeSingle(),
        _client
            .from('tenant_settings')
            .select('points_value_cents')
            .eq('tenant_id', _tenantId)
            .maybeSingle(),
      ]);

      billRow = results[0] as Map<String, dynamic>?;
      itemRows = _rows(results[1]);
      paymentRows = _rows(results[2]);
      chargeRows = _rows(results[3]);
      discountRows = _rows(results[4]);
      orderRow = results[5] as Map<String, dynamic>?;
      settingsRow = results[6] as Map<String, dynamic>?;
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw const PosTransientFailure("Couldn't load that bill.");
    }

    if (billRow == null) {
      throw const PosFailure(
        "That bill doesn't exist, or belongs to another restaurant.",
      );
    }
    final bill = Bill.fromRow(billRow);

    final orderItemIds = itemRows
        .map((r) => r['order_item_id'] as String?)
        .nonNulls
        .toSet()
        .toList();

    final discounts = discountRows.map(DiscountRow.fromRow).toList();

    // Pass two. Modifiers need the order-item ids; the mergeable list is only
    // worth asking for while the bill can still take one.
    List<Map<String, dynamic>> modifierRows = const [];
    List<Map<String, dynamic>> mergeableRows = const [];
    String? waiterName;
    try {
      final results = await Future.wait<dynamic>([
        if (orderItemIds.isEmpty)
          Future<List<Map<String, dynamic>>>.value(const [])
        else
          _client
              .from('order_item_modifiers')
              .select('id, order_item_id, name_snapshot, price_cents, qty')
              .inFilter('order_item_id', orderItemIds)
              .eq('tenant_id', _tenantId),
        if (!bill.isSettleable)
          Future<List<Map<String, dynamic>>>.value(const [])
        else
          _client
              .from('orders')
              .select(
                'id, order_type, status, '
                'restaurant_tables!orders_table_id_fkey(label)',
              )
              .eq('tenant_id', _tenantId)
              .isFilter('bill_id', null)
              .inFilter('status', const [
                'in_kitchen',
                'preparing',
                'ready',
                'served',
              ])
              .order('created_at', ascending: false),
      ]);
      modifierRows = _rows(results[0]);
      mergeableRows = _rows(results[1]);

      // The FK points at `auth.users`, which PostgREST cannot embed through to
      // `profiles` — same second query the audit log needs.
      final waiterId = orderRow?['waiter_id'] as String?;
      if (waiterId != null) {
        final profile = await _client
            .from('profiles')
            .select('full_name, username')
            .eq('id', waiterId)
            .maybeSingle();
        waiterName =
            (profile?['full_name'] as String?) ??
            (profile?['username'] as String?);
      }
    } catch (_) {
      // Trimmings. A bill that renders without its add-on names beats a red
      // screen mid-service, and the money is all in pass one.
    }

    final modsByItem = <String, List<BillLineModifier>>{};
    for (final m in modifierRows) {
      final itemId = m['order_item_id'] as String?;
      if (itemId == null) continue;
      modsByItem.putIfAbsent(itemId, () => []).add(BillLineModifier.fromRow(m));
    }

    final lines = itemRows.map((r) {
      final orderItemId = r['order_item_id'] as String?;
      return BillLine.fromRow(
        r,
        modifiers: orderItemId == null
            ? const []
            : (modsByItem[orderItemId] ?? const []),
        lineDiscounts: orderItemId == null
            ? const []
            : discounts.where((d) => d.orderItemId == orderItemId),
      );
    }).toList();

    return BillSnapshot(
      bill: bill,
      lines: lines,
      payments: paymentRows.map(PaymentRow.fromRow).toList(),
      charges: chargeRows.map(ChargeRow.fromRow).toList(),
      discounts: discounts,
      settings: TenantMoneySettings.fromRow(settingsRow),
      customer: _customerOf(orderRow),
      mergeable: mergeableRows.map(MergeableOrder.fromRow).toList(),
      waiterName: waiterName,
    );
  }

  /// The unsettled bill on this table, if there is one.
  ///
  /// Asked *before* the composer opens: `create_bill_for_order` moves the order
  /// to `billed`, which drops it out of [PosRepository.activeOrders], so
  /// without this a tap on a table awaiting its bill would start a second order.
  Future<String?> openBillIdForTable(String tableId) async {
    try {
      final row = await _client
          .from('bills')
          .select('id')
          .eq('tenant_id', _tenantId)
          .eq('table_id', tableId)
          .inFilter('status', const ['open', 'partial'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return row?['id'] as String?;
    } catch (_) {
      throw const PosTransientFailure("Couldn't check that table's bill.");
    }
  }

  /// Bills still owed money — the Bills tab.
  ///
  /// This list is the only way back to a billed order: creating a bill takes the
  /// order off the POS board by design.
  Future<List<OpenBillRow>> openBills({int limit = 300}) =>
      bills(statuses: const ['open', 'partial'], limit: limit);

  /// Bills by status, and optionally only since a given instant.
  ///
  /// The two halves want different windows, which is why [since] is a parameter
  /// rather than always today:
  ///
  /// * **Owed** (`open`, `partial`) is never date-bound. A debt from last night
  ///   is still a debt this morning, and a bill that vanished at midnight would
  ///   be money nobody could collect.
  /// * **Settled** (`paid`, `void`) is capped to today, the same boundary the
  ///   Completed tab draws — otherwise this query grows for the life of the
  ///   restaurant to serve a question the reports answer better.
  ///
  /// `refunded` is deliberately absent: it is a *label* the app can render but
  /// not a `bill_status` value — the enum is open/partial/paid/void — and
  /// filtering on one Postgres doesn't have is a runtime 22P02.
  Future<List<OpenBillRow>> bills({
    required List<String> statuses,
    DateTime? since,
    int limit = 300,
  }) async {
    try {
      var query = _client
          .from('bills')
          .select(
            'id, status, total_cents, created_at, restaurant_tables(label)',
          )
          .eq('tenant_id', _tenantId)
          .inFilter('status', statuses);
      if (since != null) {
        query = query.gte('created_at', since.toUtc().toIso8601String());
      }
      final rows = await query
          .order('created_at', ascending: false)
          .limit(limit);
      return rows.map(OpenBillRow.fromRow).toList();
    } catch (_) {
      throw const PosTransientFailure("Couldn't load the bills.");
    }
  }

  // --- Writes --------------------------------------------------------------

  /// Open the bill for an order, or return the one it already has.
  ///
  /// Idempotent server-side (`orders.bill_id` short-circuits it), so a
  /// double-tap cannot produce two bills for one table.
  Future<String> createBillForOrder(String orderId) async {
    try {
      final id = await _client.rpc<dynamic>(
        'create_bill_for_order',
        params: {'_order_id': orderId},
      );
      if (id is! String) {
        throw const PosFailure("The bill couldn't be opened.");
      }
      return id;
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } on PosFailure {
      rethrow;
    } catch (_) {
      throw const PosTransientFailure(
        "Couldn't reach the server. The bill wasn't opened.",
      );
    }
  }

  /// Take a percentage or a flat amount off the whole bill.
  ///
  /// [value] is in the RPC's own shape — percentage points for `percent`, whole
  /// currency units for `flat`. Not cents: `apply_bill_discount` takes a
  /// `numeric` and the web sends the same thing.
  Future<void> applyBillDiscount({
    required String billId,
    required String type,
    required num value,
    String? reason,
  }) {
    if (value <= 0) {
      throw const PosFailure('A discount has to be more than nothing.');
    }
    if (type == 'percent' && value > 100) {
      throw const PosFailure("A percentage discount can't be more than 100%.");
    }
    return _write('apply_bill_discount', {
      '_bill_id': billId,
      '_type': type,
      '_value': value,
      '_reason': reason?.trim(),
    }, "Couldn't apply that discount.");
  }

  /// Take it off one line instead. The line must be on a bill already, which is
  /// why this exists on the checkout screen and nowhere else.
  Future<void> applyItemDiscount({
    required String orderItemId,
    required String type,
    required num value,
    String? reason,
  }) {
    if (value <= 0) {
      throw const PosFailure('A discount has to be more than nothing.');
    }
    if (type == 'percent' && value > 100) {
      throw const PosFailure("A percentage discount can't be more than 100%.");
    }
    return _write('apply_item_discount', {
      '_order_item_id': orderItemId,
      '_type': type,
      '_value': value,
      '_reason': reason?.trim(),
    }, "Couldn't apply that discount.");
  }

  /// Redeem a coupon code. Existence, expiry and the usage cap are all checked
  /// inside the RPC, atomically — the client only refuses an empty box.
  Future<void> applyCoupon({required String billId, required String code}) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) throw const PosFailure('Enter a coupon code.');
    return _write('apply_coupon', {
      '_bill_id': billId,
      '_code': trimmed,
    }, "Couldn't apply that coupon.");
  }

  Future<void> addCharge({
    required String billId,
    required String label,
    required int amountCents,
  }) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) throw const PosFailure('Give the charge a name.');
    if (amountCents <= 0) {
      throw const PosFailure('A charge has to be more than nothing.');
    }
    return _write('add_bill_charge', {
      '_bill_id': billId,
      // Trimmed to what the RPC will store, so the label on screen after the
      // refresh is the label that was typed.
      '_label': trimmed.length > 60 ? trimmed.substring(0, 60) : trimmed,
      '_amount_cents': amountCents,
    }, "Couldn't add that charge.");
  }

  Future<void> removeCharge(String chargeId) => _write('remove_bill_charge', {
    '_charge_id': chargeId,
  }, "Couldn't remove that charge.");

  /// Tip, round-off and the invoice remark, in one gated call.
  ///
  /// The rounding cap is the server's rule mirrored: anything a whole unit or
  /// more is a discount, and a discount needs a manager and a reason.
  Future<void> setExtras({
    required String billId,
    required int tipCents,
    required int roundingCents,
    String? note,
  }) {
    if (tipCents < 0) throw const PosFailure("A tip can't be negative.");
    if (roundingCents.abs() > 99) {
      throw const PosFailure(
        'Round off must be under one whole currency unit. Anything bigger is a '
        'discount.',
      );
    }
    final trimmed = note?.trim();
    if (trimmed != null && trimmed.length > 500) {
      throw const PosFailure('That remark is too long for the invoice.');
    }
    return _write('set_bill_extras', {
      '_bill_id': billId,
      '_tip_cents': tipCents,
      '_rounding_cents': roundingCents,
      '_note': trimmed,
    }, "Couldn't save that.");
  }

  /// On the house. Records a discount equal to the whole bill, with a reason —
  /// it is an audited write, not a way to make a bill disappear.
  Future<void> setComplimentary({
    required String billId,
    required String reason,
  }) {
    if (reason.trim().isEmpty) {
      throw const PosFailure('A complimentary bill needs a reason.');
    }
    return _write('set_bill_complimentary', {
      '_bill_id': billId,
      '_reason': reason.trim(),
    }, "Couldn't make that complimentary.");
  }

  /// Take money.
  ///
  /// Returns the bill's **new status**, so the caller learns that the last
  /// share rolled it to `paid` without racing a re-read against the trigger
  /// that queues the receipt.
  ///
  /// [idempotencyKey] is the caller's, always. `record_payment` dedups on
  /// `unique(tenant_id, idempotency_key)` and clamps the amount to what is
  /// outstanding, which together are what make a retry safe and a *new* key on
  /// a retry a double charge. Never mint one here.
  Future<String> recordPayment({
    required String billId,
    required String method,
    required int amountCents,
    required String idempotencyKey,
  }) async {
    if (amountCents <= 0) {
      throw const PosFailure('Enter an amount to take.');
    }
    try {
      final status = await _client.rpc<dynamic>(
        'record_payment',
        params: {
          '_bill_id': billId,
          '_method': method,
          '_amount_cents': amountCents,
          '_idempotency_key': idempotencyKey,
        },
      );
      return status is String ? status : 'partial';
    } on PostgrestException catch (e) {
      // The server answered and said no. That is final, and it is not money in
      // doubt — the write did not happen.
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw PaymentUncertainFailure(
        "We didn't get an answer from the server. Pull down to refresh this "
        'bill before taking it again.',
        idempotencyKey: idempotencyKey,
      );
    }
  }

  /// Put another fired order onto this bill — one tab across several rounds.
  Future<void> addOrderToBill({
    required String billId,
    required String orderId,
  }) => _write('add_order_to_bill', {
    '_bill_id': billId,
    '_order_id': orderId,
  }, "Couldn't add that order to the bill.");

  /// Put two tables on one bill, and return the bill they now share.
  ///
  /// Composed rather than a single RPC because that is what merging *is*: open
  /// the primary table's bill, then add the other order to it. The web's
  /// `mergeTables` sequences exactly these two calls, and a third function that
  /// did the same thing slightly differently is how the two clients drift.
  ///
  /// `create_bill_for_order` is idempotent, so merging onto a table that
  /// already has a bill re-uses it rather than opening a second one.
  Future<String> mergeOrders({
    required String primaryOrderId,
    required String otherOrderId,
  }) async {
    if (primaryOrderId == otherOrderId) {
      throw const PosFailure('Pick a different table to merge with.');
    }
    final billId = await createBillForOrder(primaryOrderId);
    await addOrderToBill(billId: billId, orderId: otherOrderId);
    return billId;
  }

  /// Name the guest this bill belongs to.
  Future<void> attachCustomer({
    required String billId,
    String? name,
    String? phone,
  }) {
    final n = name?.trim();
    final p = phone?.trim();
    if ((n == null || n.isEmpty) && (p == null || p.isEmpty)) {
      throw const PosFailure('Enter a name or a phone number.');
    }
    return _write('attach_bill_customer', {
      '_bill_id': billId,
      '_name': (n == null || n.isEmpty) ? null : n,
      '_phone': (p == null || p.isEmpty) ? null : p,
    }, "Couldn't attach that guest.");
  }

  /// Burn loyalty points against the balance.
  ///
  /// Keyed like a payment, because it *is* one: the RPC records a `points`
  /// payment and decrements the balance in one transaction, so a replayed call
  /// with the same key must not burn the points twice.
  Future<void> redeemPoints({
    required String billId,
    required int points,
    required String idempotencyKey,
  }) {
    if (points <= 0) throw const PosFailure('Enter how many points to use.');
    return _write('redeem_points_for_bill', {
      '_bill_id': billId,
      '_points': points,
      '_idempotency_key': idempotencyKey,
    }, "Couldn't redeem those points.");
  }

  /// Give money back.
  ///
  /// **`refund_payment` takes no idempotency key**, so this is the one write on
  /// the checkout screen that a blind retry can double. The UI's job is a
  /// confirm dialog and a busy guard; on a lost connection it must say to check
  /// the payments rather than offering a one-tap retry.
  Future<void> refund({
    required String billId,
    required int amountCents,
    String? reason,
  }) {
    if (amountCents <= 0) {
      throw const PosFailure('Enter how much to refund.');
    }
    return _write(
      'refund_payment',
      {
        '_bill_id': billId,
        '_amount_cents': amountCents,
        '_reason': reason?.trim(),
      },
      "We didn't get an answer. Check this bill's payments before refunding "
          'again.',
    );
  }

  // --- Helpers -------------------------------------------------------------

  /// One shape for every RPC that changes a bill but takes no money.
  ///
  /// A server *reject* and a lost connection are different things and must stay
  /// different: the first is final and worth reading, the second is worth
  /// retrying. None of these carry an idempotency key, so none of them is a
  /// [PaymentUncertainFailure] — but none of them moves money either, and
  /// `recompute_bill` makes a repeat of the same discount visible on the next
  /// refresh.
  Future<void> _write(
    String fn,
    Map<String, dynamic> params,
    String transient,
  ) async {
    try {
      await _client.rpc<dynamic>(fn, params: params);
    } on PostgrestException catch (e) {
      throw PosFailure(_friendly(e.message));
    } catch (_) {
      throw PosTransientFailure(transient);
    }
  }

  static List<Map<String, dynamic>> _rows(Object? result) =>
      (result as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

  static BillCustomer? _customerOf(Map<String, dynamic>? orderRow) {
    final c = orderRow?['customers'];
    if (c is! Map<String, dynamic>) return null;
    final loyalty = (c['loyalty_accounts'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .firstOrNull;
    return BillCustomer(
      id: c['id'] as String,
      name: c['name'] as String?,
      phone: c['phone'] as String?,
      points: (loyalty?['points_balance'] as int?) ?? 0,
    );
  }

  /// Turn the RPCs' SQL prose into something a cashier can act on.
  ///
  /// Anything unmapped passes through — an opaque message beats a swallowed
  /// one, and the coupon and points errors already name the thing that failed.
  static String _friendly(String message) {
    final m = message.toLowerCase();
    if (m.contains('not authorized') || m.contains('not permitted')) {
      return "You don't have permission to do that.";
    }
    if (m.contains('already paid') || m.contains('bill is not open')) {
      return 'This bill is already settled. Pull down to refresh it.';
    }
    if (m.contains('rounding')) {
      return 'Round off must be under one whole currency unit.';
    }
    if (m.contains('no customer')) {
      return 'Attach a customer before redeeming points.';
    }
    if (m.contains('not fired') || m.contains('no items')) {
      return 'Send the order to the kitchen before billing it.';
    }
    if (m.contains('percent')) {
      return "A percentage discount can't be more than 100%.";
    }
    return message.split('\n').first;
  }
}

final billRepositoryProvider = Provider.family<BillRepository, String>(
  (ref, tenantId) => BillRepository(ref.watch(supabaseProvider), tenantId),
);
