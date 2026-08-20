import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/app_scaffold.dart';
import '../../app/router.dart';
import '../../core/format/labels.dart';
import '../../core/format/money.dart';
import '../../core/format/when.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/print/reprint_actions.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../../data/sync/sync_providers.dart';
import '../tenant/tenant_providers.dart';
import 'bill_grouping.dart';
import 'bill_math.dart';
import 'bill_models.dart';
import 'bill_providers.dart';
import 'checkout_adjust_sheet.dart';
import 'checkout_customer_sheet.dart';
import 'checkout_line_sheet.dart';
import 'checkout_payment_sheet.dart';
import 'checkout_split_sheet.dart';
import 'models.dart' show PosOrder;
import 'order_composer.dart';
import 'pos_providers.dart';
import 'void_reason_dialog.dart';

/// The bill: what is on it, what it comes to, and what has been paid.
///
/// The web lays this out as levers on the left and a sticky invoice on the
/// right. On a phone there is one column, and the sticky half becomes the bar
/// along the bottom — which is also the **only** place money is ever committed,
/// the same invariant the web's payment panel holds.
///
/// Nothing here computes a total. Every figure is `recompute_bill`'s, re-read
/// after each change, so the phone and the counter can never quote a guest
/// different numbers.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, required this.billId});

  final String billId;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  /// One key per amount, held for the life of this screen.
  ///
  /// A cashier whose payment timed out retries it, and the retry must carry the
  /// **same** key or `record_payment` records a second one. Minting per tap —
  /// or worse, per rebuild — is the double-charge this exists to prevent.
  final _keys = PaymentKeyRing(const Uuid().v4);

  /// A ring of its own for points.
  ///
  /// Sharing one with [_keys] looked harmless and was not: a payment that timed
  /// out deliberately *keeps* its key so a retry dedups, and a redeem landing in
  /// between would have called `clear()` and thrown that key away. The retry
  /// would then mint a fresh one and — if the first `record_payment` had
  /// committed before the socket died — charge the guest twice.
  final _redeemKeys = PaymentKeyRing(const Uuid().v4);

  /// Synchronous, because `setState` only lands on the next frame and a fast
  /// double-tap gets between. The web guards the same call the same way.
  bool _busy = false;

  String? _error;

  Future<void> _takePayment(BillSnapshot snapshot, String currency) async {
    if (_busy) return;

    final intent = await showPaymentSheet(
      context: context,
      snapshot: snapshot,
      currency: currency,
      canLeaveOnTab: snapshot.customer != null,
    );
    if (intent == null || !mounted) return;

    // Nothing is collected on credit, but something still has to be written:
    // the guest has left, so the *table* has to go back to free. Leaving that
    // to a toast is what parked live tables on `bill_requested` for days.
    if (intent.isCredit) {
      final name = snapshot.customer?.label;
      if (name == null) {
        setState(
          () => _error = 'Attach a guest before leaving this bill unpaid.',
        );
        return;
      }
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        await ref
            .read(billSnapshotProvider(widget.billId).notifier)
            .mutate((repo) => repo.leaveOnCredit(billId: widget.billId));
      } on PosFailure catch (e) {
        if (!mounted) return;
        setState(() => _error = e.message);
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      if (!mounted) return;
      unawaited(Navigator.of(context).maybePop());
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text("Left unpaid on $name's tab.")));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final key = _keys.keyFor(intent.amountCents);
    try {
      var status = 'partial';
      await ref.read(billSnapshotProvider(widget.billId).notifier).mutate((
        repo,
      ) async {
        status = await repo.recordPayment(
          billId: widget.billId,
          method: intent.method,
          amountCents: intent.amountCents,
          idempotencyKey: key,
          reference: intent.reference,
        );
      });
      // It landed. The next payment is a genuinely new one, even for the same
      // amount, so the key must not be reused.
      _keys.clear();
      if (!mounted) return;
      _say(
        status == 'paid'
            ? 'Paid in full. The receipt is on its way to the printer.'
            : 'Took ${money(intent.amountCents, currency)}.',
      );
    } on PosFailure catch (e) {
      // Covers PaymentUncertainFailure: its key is deliberately *kept*, so a
      // retry dedups rather than charging twice.
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Put the bill in front of the guest, before a rupee moves.
  ///
  /// The step this screen used to skip: paper only ever came out *after* the
  /// payment landed, which is the wrong way round at every table in the world.
  /// `enqueue_print_job` stamps what the slip said as it queues, so the refresh
  /// afterwards is what lets the bar know if the bill moves on from here.
  Future<void> _printBill() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await printBillEstimate(ref, widget.billId);
      if (!mounted) return;
      _say(message);
      // Unawaited: a read must never hold up the person at the table, and the
      // bar renders fine from what it already has until this lands.
      unawaited(
        ref.read(billSnapshotProvider(widget.billId).notifier).refresh(),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A second copy of a settled bill. History, so nothing is stamped.
  Future<void> _printReceipt() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final message = await reprintBill(ref, widget.billId);
      if (mounted) _say(message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Perform one adjustment and re-read the bill.
  ///
  /// The sheets decide, this performs — so every write on the page shares one
  /// busy guard, one error surface and one refresh, and no sheet has to know
  /// how any of that works.
  Future<void> _apply(BillAdjustment adjustment) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(billSnapshotProvider(widget.billId).notifier)
          .mutate(
            (repo) => switch (adjustment) {
              DiscountAdjustment(:final orderItemId?) => repo.applyItemDiscount(
                orderItemId: orderItemId,
                type: adjustment.type,
                value: adjustment.value,
                reason: adjustment.reason,
              ),
              DiscountAdjustment() => repo.applyBillDiscount(
                billId: widget.billId,
                type: adjustment.type,
                value: adjustment.value,
                reason: adjustment.reason,
              ),
              RemoveDiscountAdjustment(:final orderItemId?) =>
                repo.removeItemDiscount(orderItemId: orderItemId),
              RemoveDiscountAdjustment() => repo.removeBillDiscount(
                billId: widget.billId,
              ),
              CouponAdjustment(:final code) => repo.applyCoupon(
                billId: widget.billId,
                code: code,
              ),
              ChargeAdjustment(:final label, :final amountCents) =>
                repo.addCharge(
                  billId: widget.billId,
                  label: label,
                  amountCents: amountCents,
                ),
              RemoveChargeAdjustment(:final chargeId) => repo.removeCharge(
                chargeId,
              ),
              ExtrasAdjustment(
                :final tipCents,
                :final roundingCents,
                :final note,
              ) =>
                repo.setExtras(
                  billId: widget.billId,
                  tipCents: tipCents,
                  roundingCents: roundingCents,
                  note: note,
                ),
              ComplimentaryAdjustment(:final reason) => repo.setComplimentary(
                billId: widget.billId,
                reason: reason,
              ),
              // The one write that doesn't belong to the bill repository: voiding
              // a line is the same RPC the composer already calls, and one
              // implementation of it is enough.
              VoidLineAdjustment(:final orderItemId, :final reason) =>
                ref
                    .read(posRepoProvider)!
                    .voidLine(lineId: orderItemId, reason: reason),
            },
          );
    } on PosFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _adjust(BillSnapshot snapshot, String currency) async {
    final adjustment = await showAdjustmentsSheet(
      context: context,
      snapshot: snapshot,
      currency: currency,
      canDiscount: ref.read(canDiscountProvider),
      canCharge: ref.read(canChargeProvider),
      canTakePayment: ref.read(hasPermissionProvider('payment.take')),
    );
    if (adjustment == null || !mounted) return;
    await _apply(adjustment);
  }

  /// Split the check.
  ///
  /// The sheet stays open across shares and calls back for each one, so the
  /// balance it shows comes from the server after every share — never from a
  /// local subtraction, which would drift the moment another terminal touched
  /// the bill.
  Future<void> _split(String currency) async {
    await showSplitSheet(
      context: context,
      currency: currency,
      snapshot: () =>
          ref.read(billSnapshotProvider(widget.billId)).requireValue,
      onPay: (share) async {
        try {
          await ref
              .read(billSnapshotProvider(widget.billId).notifier)
              .mutate(
                (repo) => repo.recordPayment(
                  billId: widget.billId,
                  method: share.method,
                  amountCents: share.amountCents,
                  idempotencyKey: share.idempotencyKey,
                ),
              );
          return null;
        } on PosFailure catch (e) {
          return e.message;
        }
      },
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _guest(BillSnapshot snapshot, String currency) async {
    // Read once, outside the sheet: the sheet only asks, and a repo that isn't
    // there yet (no tenant) simply means no picker, not a broken sheet.
    final repo = ref.read(billRepoProvider);
    final action = await showCustomerSheet(
      context: context,
      snapshot: snapshot,
      currency: currency,
      search: repo == null
          ? null
          : (query) => repo.searchCustomers(query: query),
    );
    if (action == null || !mounted) return;

    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(billSnapshotProvider(widget.billId).notifier)
          .mutate(
            (repo) => switch (action) {
              AttachCustomerAction(:final name, :final phone) =>
                repo.attachCustomer(
                  billId: widget.billId,
                  name: name,
                  phone: phone,
                ),
              // By id, so a guest with no phone on file comes back as
              // themselves rather than as a fresh duplicate.
              PickCustomerAction(:final customerId) => repo.attachCustomerById(
                billId: widget.billId,
                customerId: customerId,
              ),
              // Keyed like a payment, because it records one: a replayed redeem
              // under the same key must not burn the points twice.
              RedeemPointsAction(:final points) => repo.redeemPoints(
                billId: widget.billId,
                points: points,
                idempotencyKey: _redeemKeys.keyFor(points),
              ),
            },
          );
      if (action is RedeemPointsAction) _redeemKeys.clear();
    } on PosFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One more round on a bill that has already been printed.
  ///
  /// The only way back to the composer for a `billed` order: creating the bill
  /// drops it out of `activeOrders`, so the POS board can no longer reach it and
  /// this screen is where the table's next drink has to start from.
  ///
  /// The order is read fresh rather than carried on the snapshot — the composer
  /// needs the lines, and the bill screen deliberately doesn't hold them.
  Future<void> _addItems(BillSnapshot snapshot) async {
    final orderId = snapshot.orderId;
    final repo = ref.read(posRepoProvider);
    if (orderId == null || repo == null || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    PosOrder? order;
    try {
      // Capped like every other tap on this screen: a waiter mid-service must
      // never be left holding a dead button on a slow connection.
      order = await repo.order(orderId).timeout(const Duration(seconds: 6));
    } on PosFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            "Couldn't open that order. Check the connection and try again.";
      });
      return;
    }
    if (!mounted) return;

    final loaded = order;
    if (loaded == null) {
      // Deleted, or moved onto another bill between the read and the tap.
      // Refusing beats pushing a composer with nothing in it.
      setState(() {
        _busy = false;
        _error =
            'That order is no longer there. Pull down to refresh this bill.';
      });
      return;
    }

    // The server has the final say, but there is no point pushing a composer
    // whose every tap will bounce: `isAmendable` is the same rule the RPC
    // applies, read off the row we just fetched rather than off the snapshot
    // that may predate a payment on another terminal.
    if (!loaded.isAmendable) {
      setState(() {
        _busy = false;
        _error =
            'This bill has already been paid — start a new order for the table.';
      });
      return;
    }

    // `_busy` deliberately stays set across the push and the refresh below.
    // Clearing it here would re-enable "Take payment" while the screen is still
    // showing the pre-amend total, and the payment sheet seeds its amount from
    // that figure — so a quick tap on return would charge the guest the old
    // total and settle the bill short.

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderComposer(existingOrder: loaded),
      ),
    );
    // Back from the composer, and this screen may be gone (tenant switch,
    // sign-out) — `ref` after dispose throws from a Future nobody is watching.
    if (!mounted) return;
    try {
      // Awaited, unlike the post-print refresh: an added line changes
      // `bills.total_cents` via `recompute_bill`, so until this lands the
      // totals card and the due bar are quoting a figure the guest is no longer
      // being charged. `refresh()` keeps the old data on screen while it reads,
      // which is exactly why the screen has to stay busy until it returns.
      await ref.read(billSnapshotProvider(widget.billId).notifier).refresh();
      if (!mounted) return;
      ref.invalidate(activeOrdersProvider);
    } finally {
      // In a finally so a failed refresh can't strand the screen busy with
      // every control dead.
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _merge(MergeableOrder order) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(billSnapshotProvider(widget.billId).notifier)
          .mutate(
            (repo) =>
                repo.addOrderToBill(billId: widget.billId, orderId: order.id),
          );
      if (mounted) ref.invalidate(activeOrdersProvider);
    } on PosFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refund(BillSnapshot snapshot, String currency) async {
    final result = await showRefundSheet(
      context: context,
      paidCents: snapshot.paidCents,
      currency: currency,
    );
    if (result == null || !mounted || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(billSnapshotProvider(widget.billId).notifier)
          .mutate(
            (repo) => repo.refund(
              billId: widget.billId,
              amountCents: result.amountCents,
              reason: result.reason,
            ),
          );
      if (mounted) _say('Refunded ${money(result.amountCents, currency)}.');
    } on PosFailure catch (e) {
      if (!mounted) return;
      // No retry offered on purpose: `refund_payment` has no idempotency key,
      // so a second attempt after a lost answer refunds the guest twice.
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openLine(BillLine line, String currency) async {
    final adjustment = await showLineSheet(
      context: context,
      line: line,
      currency: currency,
      canDiscount: ref.read(canDiscountProvider),
      canVoid: ref.read(canVoidLineProvider),
    );
    if (adjustment == null || !mounted) return;
    await _apply(adjustment);
  }

  /// Remove one line straight from the list.
  ///
  /// The sheet already offers this, but a wrongly-added item is the single most
  /// common correction mid-service and it should not need two taps and a read.
  /// Same RPC, same mandatory reason — `void_order_item` is the only path.
  Future<void> _voidLine(BillLine line) async {
    final orderItemId = line.orderItemId;
    if (orderItemId == null) return;

    final reason = await showVoidReasonDialog(
      context: context,
      title: 'Remove ${line.description}?',
      // `void_order_item` takes the line, not a quantity — on a line of three
      // all three go. Say so rather than let someone find out after the fact.
      body:
          '${line.qty > 1 ? 'All ${line.qty} come off this bill' : 'The line comes off this bill'} '
          'and the kitchen is told to drop it. '
          'Stock already deducted is returned.',
      confirmLabel: 'Remove it',
    );
    if (reason == null || !mounted) return;
    await _apply(VoidLineAdjustment(orderItemId: orderItemId, reason: reason));
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(billSnapshotProvider(widget.billId));
    final currency = ref.watch(activeTenantProvider)?.currency ?? 'USD';
    final canPay = ref.watch(hasPermissionProvider('payment.take'));
    // The key both amend RPCs check. Same one the composer's own screen wants,
    // so a waiter who can start a round can add to one.
    final canOrder = ref.watch(hasPermissionProvider('order.create'));
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;

    return AppScaffold(
      title: 'Checkout',
      subtitle: snapshot.valueOrNull?.bill.tableLabel is String
          ? 'Table ${snapshot.valueOrNull!.bill.tableLabel}'
          : null,
      showDrawer: false,
      // The document, before any paper is burnt. No permission of its own for
      // the same reason printing has none: it reads the bill this screen is
      // already showing.
      actions: [
        IconButton(
          icon: const Icon(Icons.receipt_long_outlined),
          tooltip: 'View bill',
          onPressed: snapshot.valueOrNull == null
              ? null
              : () => context.push(Routes.billViewPath(widget.billId)),
        ),
      ],
      bottomNavigationBar: snapshot.valueOrNull == null
          ? null
          : _DueBar(
              snapshot: snapshot.value!,
              currency: currency,
              online: online,
              busy: _busy,
              onTake: !canPay || !snapshot.value!.canTakePayment
                  ? null
                  : () => _takePayment(snapshot.value!, currency),
              // No permission of its own: `enqueue_print_job` wants
              // `checkout.view` for a bill, which is what opened this screen. A
              // waiter can hand a table its slip without holding the key to
              // charge for it. A voided bill is the one that prints nothing —
              // there is no document to give anybody.
              onPrint: snapshot.value!.bill.isVoid
                  ? null
                  : snapshot.value!.bill.isPaid
                  ? _printReceipt
                  : _printBill,
            ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(billSnapshotProvider(widget.billId).notifier).refresh(),
        child: snapshot.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 80),
              CheckoutErrorBlock(
                message: "Couldn't open that bill.",
                detail: '$e',
                onRetry: () =>
                    ref.invalidate(billSnapshotProvider(widget.billId)),
              ),
            ],
          ),
          data: (s) {
            // Adjusting a settled bill is not a thing: `add_bill_charge` and
            // friends refuse anything that isn't open or partial.
            final live = s.bill.isSettleable && online && !_busy;
            return _Body(
              snapshot: s,
              currency: currency,
              error: _error,
              onAdjust: live ? () => _adjust(s, currency) : null,
              onLine: live ? (line) => _openLine(line, currency) : null,
              onVoidLine: live && ref.watch(canVoidLineProvider)
                  ? _voidLine
                  : null,
              onSplit: live && canPay && s.canTakePayment
                  ? () => _split(currency)
                  : null,
              onGuest: live && canPay ? () => _guest(s, currency) : null,
              onMerge: live ? _merge : null,
              // Not `live`: that admits `partial`, which both amend RPCs
              // refuse. Online is its own condition — an amend queued offline
              // against a bill someone may settle in the meantime resolves as a
              // dead outbox row, and the guest has already been handed a total.
              // Eligibility and readiness are separate on purpose: the card
              // shows whenever this bill could take another round, and only the
              // button goes dead while something else is running. Folding
              // `_busy` into the first test made the whole card come and go
              // during a print, shifting everything under it.
              canAddItems: s.canAddItems && online && canOrder,
              onAddItems: s.canAddItems && online && !_busy && canOrder
                  ? () => _addItems(s)
                  : null,
              onRefund:
                  s.bill.isPaid &&
                      online &&
                      !_busy &&
                      ref.watch(canRefundProvider)
                  ? () => _refund(s, currency)
                  : null,
            );
          },
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.snapshot,
    required this.currency,
    required this.error,
    required this.onAdjust,
    required this.onLine,
    required this.onVoidLine,
    required this.onSplit,
    required this.onGuest,
    required this.onMerge,
    required this.canAddItems,
    required this.onAddItems,
    required this.onRefund,
  });

  final BillSnapshot snapshot;
  final String currency;

  /// The last failed write. Kept on the page rather than in a snackbar: a
  /// refused payment is something the cashier needs to still be reading when
  /// they look back up from the card machine.
  final String? error;

  /// Null while busy, offline, or once the bill is settled.
  final VoidCallback? onAdjust;
  final void Function(BillLine)? onLine;

  /// Also null without `order.void_item` — the row hides the button rather than
  /// offering one the RPC will refuse.
  final void Function(BillLine)? onVoidLine;
  final VoidCallback? onSplit;
  final VoidCallback? onGuest;
  final void Function(MergeableOrder)? onMerge;

  /// Whether this bill could take another round at all: unpaid, one order,
  /// online, and the user holds `order.create`. Decides whether the card is on
  /// screen — not whether it is tappable right now.
  final bool canAddItems;

  /// Another round onto this same order. Null while something else is running,
  /// so the button disables without the card moving.
  final VoidCallback? onAddItems;

  /// The mirror image: only on a bill that *is* settled, and only with
  /// `payment.refund`.
  final VoidCallback? onRefund;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        _StatusBand(snapshot: snapshot),
        if (error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(Tokens.radiusMd),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _LinesCard(
          snapshot: snapshot,
          currency: currency,
          onLine: onLine,
          onVoidLine: onVoidLine,
        ),
        const SizedBox(height: 12),
        _TotalsCard(snapshot: snapshot, currency: currency, onAdjust: onAdjust),
        if (onSplit != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onSplit,
              icon: const Icon(Icons.call_split, size: 18),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, Tokens.tapTarget),
              ),
              label: const Text('Split the check'),
            ),
          ),
        ],
        if (snapshot.payments.isNotEmpty) ...[
          const SizedBox(height: 12),
          _PaymentsCard(snapshot: snapshot, currency: currency),
        ],
        const SizedBox(height: 12),
        _CustomerCard(snapshot: snapshot, currency: currency, onGuest: onGuest),
        // Above the merge card on purpose: "another round for this table" is
        // the everyday intent, and merging a *different* table's order onto
        // this ticket is the rarer one.
        if (canAddItems) ...[
          const SizedBox(height: 12),
          CheckoutCard(
            title: 'More for this table',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'The items go on this same bill, and the total changes — the '
                  'guest will need the bill again.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onAddItems,
                  icon: const Icon(Icons.add_shopping_cart, size: 18),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, Tokens.tapTarget),
                  ),
                  label: const Text('Add items'),
                ),
              ],
            ),
          ),
        ],
        if (snapshot.mergeable.isNotEmpty && onMerge != null) ...[
          const SizedBox(height: 12),
          CheckoutCard(
            title: 'Add another order',
            child: MergeCard(orders: snapshot.mergeable, onMerge: onMerge),
          ),
        ],
        if (onRefund != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onRefund,
              icon: const Icon(Icons.undo, size: 18),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, Tokens.tapTarget),
                foregroundColor: theme.colorScheme.error,
              ),
              label: const Text('Refund'),
            ),
          ),
        ],
      ],
    );
  }
}

/// Paid / part paid / unpaid, said in a word and a colour — never the colour
/// alone.
class _StatusBand extends StatelessWidget {
  const _StatusBand({required this.snapshot});

  final BillSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final bill = snapshot.bill;

    final (Color color, IconData icon) = switch (bill.status) {
      'paid' => (semantic.goodText, Icons.check_circle_outline),
      'partial' => (semantic.attentionText, Icons.timelapse),
      'void' => (semantic.neutral, Icons.block),
      _ => (semantic.infoText, Icons.receipt_long),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              billStatusLabel(bill.status),
              style: theme.textTheme.labelLarge?.copyWith(color: color),
            ),
          ),
          // Flexible: the date is the widest thing in this band once someone
          // turns their text size up, and an unconstrained column would push
          // it off the edge of the card.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  // The web prints an 8-character bill number; a guest
                  // querying a charge quotes this, so the two clients must
                  // agree on it.
                  '#${bill.id.substring(0, 8).toUpperCase()}',
                  textAlign: TextAlign.end,
                  style:
                      (theme.textTheme.labelSmall ?? const TextStyle()).tabular,
                ),
                // The printed slip has always carried a Date row; the screen
                // did not, which is how a bill left over from last night
                // looked the same as one opened ten minutes ago.
                Text(
                  billDateTime(bill.createdAt),
                  textAlign: TextAlign.end,
                  style: (theme.textTheme.labelSmall ?? const TextStyle())
                      .copyWith(color: theme.colorScheme.onSurfaceVariant)
                      .tabular,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinesCard extends StatelessWidget {
  const _LinesCard({
    required this.snapshot,
    required this.currency,
    required this.onLine,
    required this.onVoidLine,
  });

  final BillSnapshot snapshot;
  final String currency;
  final void Function(BillLine)? onLine;
  final void Function(BillLine)? onVoidLine;

  /// Which of the rows behind a grouped line the cashier means.
  ///
  /// Rows are folded for reading — "Tuborg ×2", not two lines of one — but
  /// every write behind this card takes a single `order_item_id`. So a tap on a
  /// folded row asks first, and a tap on a plain one goes straight through, as
  /// it always has.
  Future<BillLine?> _pick(
    BuildContext context,
    GroupedBillLine group, {
    required String verb,
  }) async {
    if (group.soleSource case final line?) return line;
    return showModalBottomSheet<BillLine>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  '$verb which ${group.description}?',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'This item was rung up ${group.sources.length} times. '
                  'Pick the one to change.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final (i, line) in group.sources.indexed)
                ListTile(
                  minTileHeight: Tokens.tapTarget,
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text('${i + 1}', style: theme.textTheme.labelMedium),
                  ),
                  title: Text(
                    '${line.qty} × ${money(line.unitPriceCents, currency)}',
                  ),
                  subtitle: line.discountCents > 0
                      ? Text('− ${money(line.discountCents, currency)} off')
                      : null,
                  trailing: Text(
                    money(line.totalCents, currency),
                    style: (theme.textTheme.bodyMedium ?? const TextStyle())
                        .tabular,
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(line),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _tap(BuildContext context, GroupedBillLine group) async {
    final line = await _pick(context, group, verb: 'Adjust');
    if (line != null) onLine?.call(line);
  }

  Future<void> _remove(BuildContext context, GroupedBillLine group) async {
    final line = await _pick(context, group, verb: 'Remove');
    if (line != null) onVoidLine?.call(line);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;

    // Folded for reading, exactly as the printed slip already folds them:
    // three teas rung up in three rounds are three `bill_items` rows, and a
    // guest counting three separate lines at one price each reads it as an
    // overcharge.
    final rows = groupBillLines(snapshot.lines);

    return CheckoutCard(
      title: 'Items',
      child: Column(
        children: [
          for (final row in rows)
            InkWell(
              // A whole-row target rather than a discount box in a cell: at
              // 360dp the cell the web uses is smaller than a fingertip.
              onTap: onLine == null ? null : () => _tap(context, row),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.description,
                            style: theme.textTheme.bodyMedium,
                          ),
                          for (final m in row.modifiers)
                            Text(
                              '↳ ${m.name}${m.qty > 1 ? ' ×${m.qty}' : ''}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          Text(
                            '${row.qty} × ${money(row.unitPriceCents, currency)}'
                            '${row.isGrouped ? ' · ${row.sources.length} rounds' : ''}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (row.discountCents > 0)
                            Text(
                              '− ${money(row.discountCents, currency)} off',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: semantic.goodText,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        money(row.totalCents, currency),
                        textAlign: TextAlign.end,
                        style: (theme.textTheme.bodyMedium ?? const TextStyle())
                            .tabular,
                      ),
                    ),
                    // A line `recompute_bill` wrote with no order item behind
                    // it has nothing for `void_order_item` to take, so it gets
                    // no button — but it keeps the gutter, or the money column
                    // would step in and out down the card.
                    if (onVoidLine != null && !row.isAdjustable)
                      const SizedBox(width: 4 + Tokens.tapTarget),
                    if (onVoidLine != null && row.isAdjustable) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        color: theme.colorScheme.error,
                        constraints: const BoxConstraints(
                          minWidth: Tokens.tapTarget,
                          minHeight: Tokens.tapTarget,
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.standard,
                        tooltip: 'Remove ${row.description}',
                        onPressed: () => _remove(context, row),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Nothing on this bill.',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.snapshot,
    required this.currency,
    required this.onAdjust,
  });

  final BillSnapshot snapshot;
  final String currency;
  final VoidCallback? onAdjust;

  @override
  Widget build(BuildContext context) {
    final bill = snapshot.bill;

    // Row visibility mirrors the web's totals panel exactly: a zero line is not
    // a line. A bill with no tax should not carry a row saying so.
    return CheckoutCard(
      title: 'Totals',
      child: Column(
        children: [
          MoneyRow(
            label: 'Item total',
            cents: snapshot.itemTotalCents,
            currency: currency,
            muted: true,
          ),
          MoneyRow(
            label: 'Sub total',
            cents: bill.subtotalCents,
            currency: currency,
          ),
          if (bill.serviceChargeCents > 0)
            MoneyRow(
              label: 'Service + packaging',
              cents: bill.serviceChargeCents,
              currency: currency,
              muted: true,
            ),
          if (bill.taxCents > 0)
            MoneyRow(
              label: 'Tax',
              cents: bill.taxCents,
              currency: currency,
              muted: true,
            ),
          for (final c in snapshot.charges)
            MoneyRow(
              label: c.label,
              cents: c.amountCents,
              currency: currency,
              muted: true,
            ),
          if (bill.discountCents > 0)
            MoneyRow(
              label: 'Discount',
              cents: -bill.discountCents,
              currency: currency,
              muted: true,
            ),
          if (bill.tipCents > 0)
            MoneyRow(
              label: 'Tip',
              cents: bill.tipCents,
              currency: currency,
              muted: true,
            ),
          if (bill.roundingCents != 0)
            MoneyRow(
              label: 'Round off',
              cents: bill.roundingCents,
              currency: currency,
              muted: true,
            ),
          const Divider(height: 18),
          MoneyRow(
            label: 'Total',
            cents: bill.totalCents,
            currency: currency,
            strong: true,
          ),
          if (onAdjust != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAdjust,
                icon: const Icon(Icons.tune, size: 18),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, Tokens.tapTarget),
                ),
                label: const Text('Discounts, charges, tip'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentsCard extends StatelessWidget {
  const _PaymentsCard({required this.snapshot, required this.currency});

  final BillSnapshot snapshot;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return CheckoutCard(
      title: 'Payments taken',
      child: Column(
        children: [
          for (final p in snapshot.payments)
            MoneyRow(
              // Time, not date: the bill's own date is already in the status
              // band above, and two payments an hour apart on one bill is the
              // thing a cashier reconciling a drawer needs to tell apart.
              label:
                  '${paymentMethodLabel(p.method)} · ${clockTime(p.createdAt)}',
              cents: p.amountCents,
              currency: currency,
            ),
        ],
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.snapshot,
    required this.currency,
    required this.onGuest,
  });

  final BillSnapshot snapshot;
  final String currency;
  final VoidCallback? onGuest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = snapshot.customer;
    final note = snapshot.bill.note;

    return CheckoutCard(
      title: 'Guest',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            customer == null
                ? 'Nobody attached. A tab left unpaid needs a name on it.'
                : '${customer.label} · ${customer.points} pts',
            style: theme.textTheme.bodyMedium,
          ),
          if (note != null && note.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(note, style: theme.textTheme.bodySmall),
          ],
          if (onGuest != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onGuest,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, Tokens.tapTarget),
                ),
                child: Text(
                  customer == null
                      ? 'Attach a guest'
                      : 'Guest and loyalty points',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What is still owed, and the one button that commits money.
///
/// Every other control on this screen changes what the bill *is*; only this bar
/// takes payment. Keeping that in one place is the same invariant the web's
/// payment panel holds, and it is what makes "did I charge them?" answerable.
class _DueBar extends StatelessWidget {
  const _DueBar({
    required this.snapshot,
    required this.currency,
    required this.online,
    required this.busy,
    required this.onTake,
    required this.onPrint,
  });

  final BillSnapshot snapshot;
  final String currency;
  final bool online;
  final bool busy;

  /// Null without `payment.take`, or when there is nothing left to take.
  final VoidCallback? onTake;

  /// Null only for a voided bill — there is no document to hand anybody.
  final VoidCallback? onPrint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semantic;
    // Void and settled both stop the buttons, but they are not the same fact —
    // and this band is the one a cashier reads to answer "has this been paid?".
    // Calling a voided bill "Settled" answers it wrongly.
    final voided = snapshot.bill.isVoid;
    final settled = !snapshot.canTakePayment;
    final label = voided
        ? 'Voided'
        : settled
        ? 'Settled'
        : 'Due';

    // Same threshold the bill view uses to drop its columns. Beside the total,
    // a scaled-up "Reprint bill" both overflows sideways and forces the row so
    // tall that the payment button below it falls off the bottom of the bar.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final printButton = onPrint == null
        ? null
        : OutlinedButton.icon(
            onPressed: busy || !online ? null : onPrint,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, Tokens.tapTarget),
            ),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: Text(
              snapshot.bill.isPaid
                  ? 'Print receipt'
                  : snapshot.bill.wasPrinted
                  ? 'Reprint bill'
                  : 'Print bill',
            ),
          );

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border(top: BorderSide(color: scheme.outline)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Checkout is online-only in this version: there is nothing useful
            // to queue, because a payment nobody can see is worse than a
            // payment nobody took.
            if (!online && !settled) ...[
              Row(
                children: [
                  Icon(Icons.wifi_off, size: 16, color: semantic.warningText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Offline — payment needs a connection.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: semantic.warningText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            // The bill changed after the guest was handed it. Not a gate — a
            // table that orders another round is ordinary — but charging
            // someone a total they never read is not.
            if (snapshot.bill.printedTotalIsStale && !settled) ...[
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: semantic.warningText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The bill changed after it was printed — the guest has '
                      'an old total.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: semantic.warningText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: voided
                              ? semantic.neutral
                              : settled
                              ? semantic.goodText
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        money(snapshot.dueCents, currency),
                        style: (theme.textTheme.titleLarge ?? const TextStyle())
                            .tabular,
                      ),
                    ],
                  ),
                ),
                // Print sits beside the figure it prints, and payment goes
                // full-width beneath: top to bottom that is the order of the
                // real transaction — the guest reads the bill, then pays it.
                // Stacking both would push the bar over the controls it sits
                // under, on exactly the small phones this bar exists for.
                //
                // Unless the text is scaled up, where "Reprint bill" beside
                // a four-figure total is wider than the phone: then it drops
                // to its own full-width line rather than being clipped.
                if (printButton != null && !stacked) printButton,
              ],
            ),
            if (printButton != null && stacked) ...[
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: printButton),
            ],
            if (onTake != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy || !online ? null : onTake,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, Tokens.tapTarget),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Take payment'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A labelled money row. Negative amounts keep their sign, because a discount
/// that reads as a positive number is a discount somebody will add twice.
class MoneyRow extends StatelessWidget {
  const MoneyRow({
    super.key,
    required this.label,
    required this.cents,
    required this.currency,
    this.muted = false,
    this.strong = false,
    this.trailing,
  });

  final String label;
  final int cents;
  final String currency;
  final bool muted;
  final bool strong;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = strong
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyMedium;
    final color = muted ? theme.colorScheme.onSurfaceVariant : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: base?.copyWith(color: color)),
          ),
          ?trailing,
          // Flexible: at a large text size "Service + packaging" and its
          // figure together are wider than a 320dp phone, and an
          // unconstrained amount clips the last digits of a price rather than
          // wrapping. Losing a digit off a total is the worst failure this
          // screen has.
          Flexible(
            child: Text(
              cents < 0
                  ? '− ${money(-cents, currency)}'
                  : money(cents, currency),
              textAlign: TextAlign.end,
              style: (base ?? const TextStyle()).copyWith(color: color).tabular,
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled panel. The web's `<Card>` with one less layer.
class CheckoutCard extends StatelessWidget {
  const CheckoutCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// The POS error block, in the shape checkout needs it. Kept here rather than
/// imported so the POS screen's private one stays private.
class CheckoutErrorBlock extends StatelessWidget {
  const CheckoutErrorBlock({
    super.key,
    required this.message,
    required this.detail,
    required this.onRetry,
  });

  final String message;
  final String detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 36, color: theme.colorScheme.error),
          const SizedBox(height: 10),
          Text(message, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
