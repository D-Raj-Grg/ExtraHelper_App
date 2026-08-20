import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/format/labels.dart';
import '../../core/format/money.dart';
import '../../core/format/when.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/choice_chip.dart';
import '../../core/widgets/earlier_day_chip.dart';
import '../../data/print/reprint_actions.dart';
import '../../data/supabase/pos_repository.dart';
import '../../data/sync/sync_providers.dart';
import '../tenant/tenant_providers.dart';
import 'bill_models.dart';
import 'bill_providers.dart';
import 'completed_tab.dart';
import 'manager_ops.dart';
import 'models.dart';
import 'order_composer.dart';
import 'pos_providers.dart';
import 'void_reason_dialog.dart';

/// The POS: a **Tables** board, an **Orders** list and a **Bills** list.
///
/// Tapping a table opens its bill if one is waiting to be settled, then its live
/// order if one is open, and otherwise starts a new order seeded to that table.
/// One decision, made here, so the composer never has to ask which it is.
///
/// Bills need their own tab because opening one moves the order to `billed`,
/// which is exactly the status [PosRepository.activeOrders] filters out — a
/// part-paid bill would otherwise have no route back to it at all.
///
/// The `TabBar` itself belongs to the shell's app bar — the tabs and the bar
/// are one band — so the controller is passed in rather than owned here.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key, required this.tabs});

  final TabController tabs;

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

/// Tab order in the shell: Tables, Orders, Bills, Done.
const _billsTab = 2;

class _PosScreenState extends ConsumerState<PosScreen> {
  /// True while `create_bill_for_order` is in flight — see [_billOrder].
  bool _billing = false;

  @override
  void initState() {
    super.initState();
    // Warm the offline cache the moment the POS opens, not when a waiter first
    // taps a table. The menu has to already be on the phone *before* coverage
    // drops — fetching it at the moment it is needed is exactly too late.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(menuProvider);
      ref.read(categoriesProvider);
      ref.read(floorsProvider);
    });
  }

  /// Open the checkout screen for a bill, and refresh the board on the way back.
  ///
  /// Billing an order moves it to `billed`, which takes it off the Orders tab by
  /// design — so someone who backs out of a half-finished bill lands on a list
  /// their order just vanished from. Coming back to a bill that is still owed
  /// money therefore lands on **Bills**, which is where it now lives.
  Future<void> _openBill(String billId) async {
    await context.push(Routes.billPath(billId));
    if (!mounted) return;
    ref
      ..invalidate(activeOrdersProvider)
      ..invalidate(openBillsProvider)
      ..invalidate(filteredBillsProvider)
      ..invalidate(completedOrdersProvider);

    final stillOwed = await ref
        .read(openBillsProvider.future)
        .then(
          (bills) => bills.any((b) => b.id == billId),
          onError: (_, _) => false,
        );
    if (!mounted) return;
    if (stillOwed && widget.tabs.index != _billsTab) {
      widget.tabs.animateTo(_billsTab);
    }
    await ref.read(tablesProvider.notifier).refresh();
  }

  /// Open (or re-open) the bill for an order.
  ///
  /// `create_bill_for_order` is idempotent, so this is the same call whether the
  /// order has a bill already or not — but it is a *write*, and offline it would
  /// sit on a long HTTP timeout and read as a dead tap.
  ///
  /// Guarded synchronously: `setState` lands a frame later and a double-tap gets
  /// between, and because the RPC is idempotent both calls return the *same*
  /// bill — so the second push stacks an identical checkout screen, and backing
  /// out of one lands on a copy of it mid-service.
  Future<void> _billOrder(PosOrder order) async {
    if (_billing) return;
    final online = ref.read(isOnlineProvider).valueOrNull ?? true;
    if (!online) {
      _say(
        "No coverage — a bill can't be opened yet. The order is safe; settle "
        "it when you're back.",
      );
      return;
    }

    final repo = ref.read(billRepoProvider);
    if (repo == null) return;
    _billing = true;
    try {
      final billId = await repo.createBillForOrder(order.id);
      if (!mounted) return;
      await _openBill(billId);
    } on PosFailure catch (e) {
      if (!mounted) return;
      _say(e.message);
    } finally {
      _billing = false;
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openTable(PosTable table) async {
    // A table waiting on its bill has an order that is no longer *on* the
    // orders list — `create_bill_for_order` set it to `billed`. Ask about the
    // bill first, or the lookup below finds nothing and starts a second order
    // on a table that is mid-payment.
    if (table.state == 'bill_requested' &&
        (ref.read(isOnlineProvider).valueOrNull ?? true)) {
      final repo = ref.read(billRepoProvider);
      if (repo != null) {
        try {
          final billId = await repo
              .openBillIdForTable(table.id)
              .timeout(const Duration(seconds: 6));
          if (!mounted) return;
          if (billId != null) return _openBill(billId);
        } on Object {
          // Fall through to the order path. A slow lookup must not strand the
          // tap; the Bills tab is still a way in.
        }
      }
    }

    // AWAIT the orders, don't read them.
    //
    // The Tables tab never watches this provider, so on a fresh launch it is
    // unbuilt and `.valueOrNull` is null — which read as "no open order" and
    // started a SECOND order on an occupied table. Awaiting the future builds
    // it if needed, so the answer is real rather than merely available.
    //
    // Offline, don't await it at all: with no network the HTTP call sits on a
    // long timeout and the tap looks dead. Ask connectivity first, and cap the
    // wait even when there is a connection — a slow one must not freeze a tap
    // mid-service.
    final online = ref.read(isOnlineProvider).valueOrNull ?? true;
    List<PosOrder>? orders;
    if (online) {
      try {
        orders = await ref
            .read(activeOrdersProvider.future)
            .timeout(const Duration(seconds: 6));
      } on Object {
        orders = ref.read(activeOrdersProvider).valueOrNull;
      }
    } else {
      orders = ref.read(activeOrdersProvider).valueOrNull;
    }
    if (!mounted) return;

    // Offline, with no idea what is already on this table. A free table is
    // safe to start; an occupied one is not — guessing "no open order" is
    // exactly how you put a second order on a table that already has one.
    if (orders == null && !table.isFree) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              "No coverage — this table's existing order can't be opened yet. "
              'It will be there when the connection is back.',
            ),
          ),
        );
      return;
    }

    var open = (orders ?? const <PosOrder>[])
        .where((o) => o.tableId == table.id && !o.isSettled)
        .firstOrNull;

    // Last resort before starting a second order on a table that is mid-
    // payment. `activeOrders` excludes `billed` at the SQL level, so on a
    // `bill_requested` table the filter above finds nothing by construction —
    // and the bill lookup that should have caught it just missed, whether it
    // timed out, threw, or returned null. Falling through to
    // `OrderComposer(seedTable:)` here was only ever right when a billed order
    // couldn't be amended; now it is a duplicate order.
    //
    // `activeOrderIdForTable` is the query that deliberately finds billed
    // orders — it excludes closed and cancelled only. Capped the same six
    // seconds as everything else on this tap: a slow answer must not freeze a
    // waiter mid-service, and if it can't resolve either we are no worse off
    // than before.
    if (open == null && table.state == 'bill_requested' && online) {
      final posRepo = ref.read(posRepoProvider);
      if (posRepo != null) {
        try {
          final orderId = await posRepo
              .activeOrderIdForTable(table.id)
              .timeout(const Duration(seconds: 6));
          if (!mounted) return;
          if (orderId != null) {
            open = await posRepo
                .order(orderId)
                .timeout(const Duration(seconds: 6));
            if (!mounted) return;
          }
        } on Object {
          // Keep the existing behaviour: a new order on this table. The board
          // and the Bills tab both still show the truth.
        }
      }
    }

    // Copied to a final so the builder can promote it — a mutable local never
    // narrows inside a closure.
    final resolved = open;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => resolved != null
            ? OrderComposer(existingOrder: resolved)
            : OrderComposer(seedTable: table),
      ),
    );
    // The composer is gone; this screen may be too (tenant switch, sign-out).
    // `ref` after dispose throws, and it would throw from a Future nobody
    // awaits — an unhandled error rather than a visible one.
    if (!mounted) return;
    await ref.read(tablesProvider.notifier).refresh();
    if (!mounted) return;
    ref.invalidate(activeOrdersProvider);
  }

  Future<void> _openOrder(PosOrder order) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderComposer(existingOrder: order),
      ),
    );
    if (!mounted) return;
    ref.invalidate(activeOrdersProvider);
    await ref.read(tablesProvider.notifier).refresh();
  }

  Future<void> _newTakeaway() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const OrderComposer()));
    if (!mounted) return;
    ref.invalidate(activeOrdersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final canOrder = ref.watch(hasPermissionProvider('order.create'));
    final canCheckout = ref.watch(hasPermissionProvider('checkout.view'));

    return TabBarView(
      controller: widget.tabs,
      children: [
        _TablesTab(onOpen: canOrder ? _openTable : null),
        _OrdersTab(
          onOpen: _openOrder,
          onNewTakeaway: canOrder ? _newTakeaway : null,
          onBill: canCheckout ? _billOrder : null,
        ),
        _BillsTab(onOpen: canCheckout ? _openBill : null),
        CompletedTab(onOpenBill: canCheckout ? _openBill : null),
      ],
    );
  }
}

class _TablesTab extends ConsumerWidget {
  const _TablesTab({required this.onOpen});

  /// Null when the user lacks `order.create` — the board stays readable, the
  /// action doesn't exist. The server enforces the same thing.
  final void Function(PosTable)? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tables = ref.watch(tablesProvider);
    // Setting a table's state is ordinary floor work, not an owner's privilege:
    // `set_table_state` allows anyone who takes orders. Mirror that here rather
    // than hiding it behind `tables.edit`, which only owners and managers hold.
    final canSetState =
        ref.watch(hasPermissionProvider('tables.edit')) ||
        ref.watch(hasPermissionProvider('order.create'));
    final floors = ref.watch(floorsProvider).valueOrNull ?? const [];

    return RefreshIndicator(
      onRefresh: () => ref.read(tablesProvider.notifier).refresh(),
      child: tables.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          children: [
            const SizedBox(height: 80),
            _ErrorBlock(
              message: "Couldn't load the floor.",
              detail: '$e',
              onRetry: () => ref.read(tablesProvider.notifier).refresh(),
            ),
          ],
        ),
        data: (list) {
          if (list.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 60),
                PosEmptyState(
                  icon: Icons.table_restaurant,
                  title: 'No tables yet',
                  body:
                      'Add floors and tables on the web app under Tables, '
                      'then pull down to refresh.',
                ),
              ],
            );
          }

          final byFloor = <String?, List<PosTable>>{};
          for (final t in list) {
            byFloor.putIfAbsent(t.floorId, () => []).add(t);
          }
          final floorName = {for (final f in floors) f.id: f.name};

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final entry in byFloor.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                  child: Text(
                    floorName[entry.key] ?? 'Unassigned',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 140,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: entry.value.length,
                  itemBuilder: (context, i) {
                    final table = entry.value[i];
                    return TableCard(
                      table: table,
                      onTap: () => onOpen?.call(table),
                      onLongPress: canSetState
                          ? () => showTableActionsSheet(
                              context: context,
                              ref: ref,
                              table: table,
                            )
                          : null,
                    );
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _OrdersTab extends ConsumerWidget {
  const _OrdersTab({
    required this.onOpen,
    required this.onNewTakeaway,
    required this.onBill,
  });

  final void Function(PosOrder) onOpen;
  final VoidCallback? onNewTakeaway;

  /// Null without `checkout.view` — the card stays readable, the action doesn't
  /// exist. The RPC enforces the same thing.
  final void Function(PosOrder)? onBill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(activeOrdersProvider);
    final tenant = ref.watch(activeTenantProvider);
    final currency = tenant?.currency ?? 'USD';
    final canCancel = ref.watch(canCancelOrderProvider);
    final canPrintSlip = ref.watch(hasPermissionProvider('order.view'));
    // Kitchen reaches this board on `order.view` alone, and `accept_qr_order`
    // would refuse it — no permission means no control, never a dead button.
    final canFire = ref.watch(hasPermissionProvider('order.fire'));

    return Scaffold(
      floatingActionButton: onNewTakeaway == null
          ? null
          : FloatingActionButton.extended(
              onPressed: onNewTakeaway,
              icon: const Icon(Icons.add),
              label: const Text('Takeaway'),
            ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(activeOrdersProvider.notifier).refresh(),
        child: orders.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 80),
              _ErrorBlock(
                message: "Couldn't load orders.",
                detail: '$e',
                onRetry: () =>
                    ref.read(activeOrdersProvider.notifier).refresh(),
              ),
            ],
          ),
          data: (list) {
            if (list.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 60),
                  PosEmptyState(
                    icon: Icons.receipt_long,
                    title: 'No orders on the floor',
                    body:
                        'Tap a table to start one, or use Takeaway for a '
                        'walk-in. An order that has been billed moves to the '
                        'Bills tab until it is paid.',
                  ),
                ],
              );
            }

            // Chips are derived from what is actually on the board, so a
            // restaurant that never takes delivery never sees a Delivery chip
            // — and a chosen type that has just emptied falls back to All
            // rather than showing a board filtered to nothing.
            final types = <String>{for (final o in list) o.orderType}.toList()
              ..sort();
            final chosen = ref.watch(orderTypeFilterProvider);
            final active = types.contains(chosen) ? chosen : null;
            final shown = active == null
                ? list
                : list.where((o) => o.orderType == active).toList();

            return Column(
              children: [
                if (types.length > 1)
                  _OrderTypeChips(
                    types: types,
                    counts: {
                      for (final t in types)
                        t: list.where((o) => o.orderType == t).length,
                    },
                    total: list.length,
                    selected: active,
                    onSelect: (t) =>
                        ref.read(orderTypeFilterProvider.notifier).select(t),
                  ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _OrderCard(
                      order: shown[i],
                      currency: currency,
                      onTap: () => onOpen(shown[i]),
                      onDelivered: () => _markDelivered(context, ref, shown[i]),
                      onBill: onBill == null || !shown[i].canBill
                          ? null
                          : () => onBill!(shown[i]),
                      onPin: () => _togglePin(context, ref, shown[i]),
                      onPrintSlip: canPrintSlip
                          ? () => _printSlip(context, ref, shown[i])
                          : null,
                      onCancel: canCancel
                          ? () => _cancelOrder(context, ref, shown[i])
                          : null,
                      onAcceptQr: canFire && shown[i].awaitingQrAccept
                          ? () => _acceptQrOrder(context, ref, shown[i])
                          : null,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The chip row over the Orders board — All, then one chip per order type that
/// is actually on the floor.
class _OrderTypeChips extends StatelessWidget {
  const _OrderTypeChips({
    required this.types,
    required this.counts,
    required this.total,
    required this.selected,
    required this.onSelect,
  });

  final List<String> types;
  final Map<String, int> counts;
  final int total;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          AppChoiceChip(
            label: 'All',
            detail: '$total',
            selected: selected == null,
            showCheck: true,
            onSelect: () => onSelect(null),
          ),
          for (final type in types) ...[
            const SizedBox(width: 8),
            AppChoiceChip(
              label: orderTypeLabel(type),
              detail: '${counts[type] ?? 0}',
              selected: selected == type,
              showCheck: true,
              onSelect: () => onSelect(type),
            ),
          ],
        ],
      ),
    );
  }
}

/// Hold an order at the top of the board, or let it go.
///
/// Online-only and not queued: a pin is a preference about a list that only
/// exists with a connection, so there is nothing to replay it onto.
Future<void> _togglePin(
  BuildContext context,
  WidgetRef ref,
  PosOrder order,
) async {
  final repo = ref.read(posRepoProvider);
  if (repo == null) return;
  try {
    await repo.setPinned(orderId: order.id, pinned: !order.isPinned);
    // Guarded: a tenant switch or sign-out mid-write disposes the ref, and
    // `invalidate` would then throw from a future nobody awaits.
    if (!context.mounted) return;
    ref.invalidate(activeOrdersProvider);
  } on PosFailure catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(e.message)));
  }
}

Future<void> _printSlip(
  BuildContext context,
  WidgetRef ref,
  PosOrder order,
) async {
  final message = await reprintOrderSlip(ref, order.id);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Clear the whole order — the web's "Clear order".
///
/// Manager-gated by the server on role, reason required, and audited under the
/// name of whoever confirmed it. Not queued offline: `cancel_order` refuses an
/// order that has since been billed, so a replay would fail at the far end with
/// nothing left on screen to explain why.
Future<void> _cancelOrder(
  BuildContext context,
  WidgetRef ref,
  PosOrder order,
) async {
  final repo = ref.read(posRepoProvider);
  if (repo == null) return;

  final dishes = order.itemCount;
  final reason = await showVoidReasonDialog(
    context: context,
    title: 'Cancel this order?',
    body:
        '${dishes == 1 ? 'The one dish' : 'All $dishes dishes'} on this order '
        'will be voided and the order cancelled. Any stock it deducted is '
        'returned, the table is freed, and this is recorded against your name.',
    confirmLabel: 'Cancel order',
    keepLabel: 'Keep order',
    hint: 'e.g. guests left before ordering',
  );
  if (reason == null || !context.mounted) return;

  if (!(ref.read(isOnlineProvider).valueOrNull ?? true)) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            "No coverage — an order can't be cancelled yet. Try again when "
            "you're back.",
          ),
        ),
      );
    return;
  }

  String message;
  try {
    await repo.cancelOrder(orderId: order.id, reason: reason);
    message = 'Order cancelled.';
  } on PosFailure catch (e) {
    message = e.message;
  }
  if (!context.mounted) return;
  if (message == 'Order cancelled.') {
    ref
      ..invalidate(activeOrdersProvider)
      ..invalidate(completedOrdersProvider);
    unawaited(ref.read(tablesProvider.notifier).refresh());
  }
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// The waiter accepted a guest's QR order.
///
/// Only shown where the tenant asked for confirmation (`qr_auto_fire` off) —
/// otherwise the order is with the kitchen before it ever reaches this board.
/// Not queued offline: `accept_qr_order` is a kitchen action, and a ticket that
/// syncs half an hour later is worse than one the waiter re-sends on coverage.
Future<void> _acceptQrOrder(
  BuildContext context,
  WidgetRef ref,
  PosOrder order,
) async {
  final repo = ref.read(posRepoProvider);
  if (repo == null) return;

  if (!(ref.read(isOnlineProvider).valueOrNull ?? true)) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            "No coverage — the kitchen can't be reached yet. Try again when "
            "you're back.",
          ),
        ),
      );
    return;
  }

  String message;
  var sent = false;
  try {
    final kots = await repo.acceptQrOrder(order.id);
    sent = true;
    message = kots > 0
        ? 'Sent to the kitchen · $kots ticket${kots == 1 ? '' : 's'}.'
        : 'Already with the kitchen.';
  } on PosFailure catch (e) {
    message = e.message;
  }
  if (!context.mounted) return;
  if (sent) ref.invalidate(activeOrdersProvider);
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// The waiter carried the plate over.
///
/// `served` used to be set only as a side effect of the kitchen bumping the
/// last ticket, which meant it recorded when the food was *ready*, not when it
/// reached the guest. `mark_order_served` already allowed waiters; nothing
/// called it.
Future<void> _markDelivered(
  BuildContext context,
  WidgetRef ref,
  PosOrder order,
) async {
  final queue = ref.read(orderQueueProvider);
  if (queue == null) return;
  final outcome = await queue.markOrderServed(order.id);
  ref.invalidate(outboxStatusProvider);
  if (outcome.synced) {
    ref.invalidate(activeOrdersProvider);
    unawaited(ref.read(tablesProvider.notifier).refresh());
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          outcome.error ??
              (outcome.synced
                  ? 'Marked delivered.'
                  : "Saved on this phone. It syncs when you're back on "
                        'coverage.'),
        ),
      ),
    );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.currency,
    required this.onTap,
    required this.onDelivered,
    required this.onBill,
    required this.onPin,
    required this.onPrintSlip,
    required this.onCancel,
    required this.onAcceptQr,
  });

  final PosOrder order;
  final String currency;
  final VoidCallback onTap;
  final VoidCallback onDelivered;

  /// Null when the user can't check out, or when nothing has been fired yet —
  /// `create_bill_for_order` refuses an order the kitchen never saw.
  final VoidCallback? onBill;

  final VoidCallback onPin;

  /// Null without `order.view` / the manager role. **No permission means no
  /// control**, never a disabled one — a button that can only ever fail is
  /// worse than no button.
  final VoidCallback? onPrintSlip;
  final VoidCallback? onCancel;

  /// Null unless this is a guest's QR order still waiting to be accepted, and
  /// the user may fire — see [PosOrder.awaitingQrAccept].
  final VoidCallback? onAcceptQr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semantic;

    // One status, one colour, app-wide — and always beside the word.
    final statusColor = switch (order.status) {
      'draft' => semantic.neutral,
      'placed' => semantic.infoText,
      'in_kitchen' || 'preparing' => semantic.warningText,
      'ready' || 'served' => semantic.goodText,
      _ => semantic.neutral,
    };

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Tokens.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outline),
            borderRadius: BorderRadius.circular(Tokens.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    order.tableLabel != null
                        ? Icons.table_restaurant
                        : Icons.shopping_bag_outlined,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.tableLabel != null
                          ? 'Table ${order.tableLabel}'
                          : orderTypeLabel(order.orderType),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  // The pin is an icon, not a tint: a held order has to still
                  // read as held in greyscale.
                  if (order.isPinned) ...[
                    Icon(
                      Icons.push_pin,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                      semanticLabel: 'Pinned to the top',
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    money(order.totalCents, currency),
                    style: (theme.textTheme.titleMedium ?? const TextStyle())
                        .tabular,
                  ),
                  _OrderCardMenu(
                    pinned: order.isPinned,
                    onPin: onPin,
                    onPrintSlip: onPrintSlip,
                    onCancel: onCancel,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.circle, size: 9, color: statusColor),
                  const SizedBox(width: 6),
                  Text(
                    orderStatusLabel(order.status),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${order.itemCount} item${order.itemCount == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall,
                  ),
                  // Same reason as the bill card: an order left open overnight
                  // stays on the board by design, and nothing on it used to
                  // say which night it came from.
                  if (isEarlierDay(order.createdAt)) ...[
                    const SizedBox(width: 12),
                    Flexible(child: EarlierDayChip(at: order.createdAt)),
                  ],
                  if (order.guests != null) ...[
                    const SizedBox(width: 12),
                    Icon(
                      Icons.group_outlined,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${order.guests}',
                      style: (theme.textTheme.bodySmall ?? const TextStyle())
                          .tabular,
                      semanticsLabel:
                          '${order.guests} '
                          'guest${order.guests == 1 ? '' : 's'}',
                    ),
                  ],
                  if (order.canFire) ...[
                    const SizedBox(width: 12),
                    Icon(
                      Icons.local_fire_department,
                      size: 14,
                      color: semantic.attentionText,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Not sent',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: semantic.attentionText,
                      ),
                    ),
                  ],
                ],
              ),
              // The kitchen has plated it. This is the one status a waiter
              // should notice from across the room, so it gets a band of its
              // own rather than a dot in a row of grey text — and the action
              // that closes the loop sits inside it.
              if (order.status == 'ready') ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: semantic.good.withValues(alpha: 0.16),
                    border: Border.all(color: semantic.good),
                    borderRadius: BorderRadius.circular(Tokens.radiusMd),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.notifications_active,
                        size: 18,
                        color: semantic.goodText,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ready to run',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: semantic.goodText,
                          ),
                        ),
                      ),
                      FilledButton(
                        onPressed: onDelivered,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, Tokens.tapTarget),
                        ),
                        child: const Text('Delivered'),
                      ),
                    ],
                  ),
                ),
              ],
              // A guest ordered and nobody has told the kitchen yet. Same
              // shape as the "Ready to run" band, in the attention colour with
              // its own icon — the two must not read alike in greyscale.
              if (onAcceptQr != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: semantic.attention.withValues(alpha: 0.16),
                    border: Border.all(color: semantic.attention),
                    borderRadius: BorderRadius.circular(Tokens.radiusMd),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.qr_code_2,
                        size: 18,
                        color: semantic.attentionText,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Waiting for you',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: semantic.attentionText,
                          ),
                        ),
                      ),
                      FilledButton(
                        onPressed: onAcceptQr,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, Tokens.tapTarget),
                        ),
                        child: const Text('Send to kitchen'),
                      ),
                    ],
                  ),
                ),
              ],
              if (onBill != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: onBill,
                    icon: const Icon(Icons.point_of_sale, size: 18),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, Tokens.tapTarget),
                    ),
                    label: Text(order.billId == null ? 'Bill' : 'Open bill'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The order card's overflow: the actions that aren't worth a button each.
///
/// Nothing here is ever rendered disabled — an entry the server would refuse
/// simply isn't offered, which is the rule the web board follows too.
class _OrderCardMenu extends StatelessWidget {
  const _OrderCardMenu({
    required this.pinned,
    required this.onPin,
    required this.onPrintSlip,
    required this.onCancel,
  });

  final bool pinned;
  final VoidCallback onPin;
  final VoidCallback? onPrintSlip;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Order actions',
      icon: const Icon(Icons.more_vert),
      iconSize: 20,
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: onPin,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(pinned ? Icons.push_pin_outlined : Icons.push_pin),
            title: Text(pinned ? 'Unpin' : 'Pin to top'),
          ),
        ),
        if (onPrintSlip != null)
          PopupMenuItem(
            value: onPrintSlip,
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.receipt_long_outlined),
              title: Text('Print order slip'),
            ),
          ),
        if (onCancel != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: onCancel,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.cancel_outlined,
                color: theme.colorScheme.error,
              ),
              title: Text(
                'Cancel order',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Bills still owed money.
///
/// Not a convenience: opening a bill takes its order off the Orders tab, so
/// without this list a part-paid bill on a table nobody remembers is
/// unreachable from the phone.
class _BillsTab extends ConsumerWidget {
  const _BillsTab({required this.onOpen});

  /// Null without `checkout.view`. The tab still exists — a permission-shaped
  /// tab count would have to change after the permissions load, and a
  /// `TabController` whose length moves under it throws.
  final void Function(String billId)? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (onOpen == null) {
      return ListView(
        children: const [
          SizedBox(height: 60),
          PosEmptyState(
            icon: Icons.lock_outline,
            title: 'No checkout access',
            body:
                "Your role doesn't include taking payment. An owner or manager "
                'can change that on the web app under Team.',
          ),
        ],
      );
    }

    final filter = ref.watch(billFilterProvider);
    final bills = ref.watch(filteredBillsProvider);
    final currency = ref.watch(activeTenantProvider)?.currency ?? 'USD';

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              for (final f in BillFilter.values) ...[
                if (f != BillFilter.values.first) const SizedBox(width: 8),
                AppChoiceChip(
                  label: f.label,
                  selected: filter == f,
                  showCheck: true,
                  onSelect: () =>
                      ref.read(billFilterProvider.notifier).select(f),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(filteredBillsProvider),
            child: bills.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(
                children: [
                  const SizedBox(height: 80),
                  _ErrorBlock(
                    message: "Couldn't load the bills.",
                    detail: '$e',
                    onRetry: () => ref.invalidate(filteredBillsProvider),
                  ),
                ],
              ),
              data: (list) {
                if (list.isEmpty) {
                  return ListView(
                    children: [
                      const SizedBox(height: 60),
                      PosEmptyState(
                        icon: Icons.receipt_long,
                        title: filter == BillFilter.owed
                            ? 'Nothing to settle'
                            : 'Nothing here today',
                        body: filter == BillFilter.owed
                            ? 'Bills appear here once an order is billed, and '
                                  'move to Paid when they are settled in full.'
                            : 'Settled and written-off bills from today show '
                                  'up here — older ones live in the reports on '
                                  'the web app.',
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _BillCard(
                    bill: list[i],
                    currency: currency,
                    onTap: onOpen!,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({
    required this.bill,
    required this.currency,
    required this.onTap,
  });

  final OpenBillRow bill;
  final String currency;
  final void Function(String billId) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semantic;
    // Part paid is the one a cashier must not walk past. Colour plus the word,
    // always — settled and written-off have to survive greyscale too.
    final statusColor = switch (bill.status) {
      'partial' => semantic.attentionText,
      'paid' => semantic.goodText,
      'void' => scheme.error,
      _ => semantic.infoText,
    };

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Tokens.radiusLg),
      child: InkWell(
        onTap: () => onTap(bill.id),
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outline),
            borderRadius: BorderRadius.circular(Tokens.radiusLg),
          ),
          child: Row(
            children: [
              Icon(
                bill.tableLabel != null
                    ? Icons.table_restaurant
                    : Icons.shopping_bag_outlined,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bill.tableLabel != null
                          ? 'Table ${bill.tableLabel}'
                          : 'Takeaway',
                      style: theme.textTheme.titleMedium,
                    ),
                    Row(
                      children: [
                        Icon(Icons.circle, size: 9, color: statusColor),
                        const SizedBox(width: 6),
                        Text(
                          billStatusLabel(bill.status),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: statusColor,
                          ),
                        ),
                        // An unpaid bill deliberately outlives midnight — a
                        // debt from last night is still a debt this morning.
                        // Without a date on the card, though, it reads as one
                        // that "didn't clear".
                        if (isEarlierDay(bill.createdAt)) ...[
                          const SizedBox(width: 8),
                          // Flexible: at a large text size the chip's label is
                          // wider than what the status word leaves behind.
                          Flexible(child: EarlierDayChip(at: bill.createdAt)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                money(bill.totalCents, currency),
                style:
                    (theme.textTheme.titleMedium ?? const TextStyle()).tabular,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({
    required this.message,
    required this.detail,
    required this.onRetry,
  });

  final String message;
  final String detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 36, color: scheme.error),
          const SizedBox(height: 10),
          Text(message, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

/// Re-exported so the shell can show a POS-flavoured failure without importing
/// the composer's privates.
typedef PosFailureAlias = PosFailure;
