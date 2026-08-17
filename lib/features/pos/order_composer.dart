import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scaffold.dart';
import '../../app/router.dart';
import '../../core/format/labels.dart';
import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/choice_chip.dart';
import '../../core/widgets/menu_tile.dart';
import '../../core/widgets/table_glyph.dart';
import '../../data/supabase/pos_repository.dart';
import '../../data/sync/sync_providers.dart';
import '../tenant/tenant_providers.dart';
import 'bill_providers.dart';
import 'cart_controller.dart';
import 'custom_item_sheet.dart';
import 'guests_dialog.dart';
import 'item_options_sheet.dart';
import 'manager_ops.dart';
import 'models.dart';
import 'pos_providers.dart';
import 'void_reason_dialog.dart';

/// The order composer — **one surface for create and amend**.
///
/// Below this widget everything reads a [CartController] and asks about
/// capabilities (`canDelete`, `needsVoidReason`, `hasPendingCommit`), never a
/// mode flag. This file is the only one that knows the two are different, which
/// is the arrangement the web arrived at after splitting them was worse.
class OrderComposer extends ConsumerStatefulWidget {
  const OrderComposer({super.key, this.existingOrder, this.seedTable});

  /// Amend an order that already exists.
  final PosOrder? existingOrder;

  /// Create a new order seeded to this table.
  final PosTable? seedTable;

  @override
  ConsumerState<OrderComposer> createState() => _OrderComposerState();
}

class _OrderComposerState extends ConsumerState<OrderComposer> {
  late CartController _cart;
  String? _categoryId;
  String _search = '';
  bool _busy = false;

  bool get _isAmend => widget.existingOrder != null;

  /// The guest is holding a printed slip, or is about to be.
  ///
  /// The server now takes new lines on a `billed` order while its bill is
  /// still open, and a trigger keeps the bill's total in step. That is the
  /// right behaviour — a table that orders one more round shouldn't need a
  /// second order — but it means a tap in here silently reprices a total
  /// somebody has already read. Everything gated on this exists to say so.
  bool get _isBilled => widget.existingOrder?.status == 'billed';

  @override
  void initState() {
    super.initState();
    final repo = ref.read(posRepoProvider)!;
    final queue = ref.read(orderQueueProvider)!;
    _cart = _isAmend
        ? AmendCart(
            queue: queue,
            repository: repo,
            order: widget.existingOrder!,
          )
        : CreateCart(
            queue: queue,
            orderType: widget.seedTable == null ? 'pickup' : 'dine_in',
            tableId: widget.seedTable?.id,
          );
  }

  bool get _isDineIn => _isAmend
      ? widget.existingOrder!.orderType == 'dine_in'
      : widget.seedTable != null;

  int? get _guests => _isAmend
      ? (_guestsOverride ?? widget.existingOrder!.guests)
      : (_cart as CreateCart).guests;

  /// The amended order is a snapshot taken when the composer opened, so a
  /// guest count saved here has to be remembered locally too — otherwise the
  /// badge reverts the moment the dialog closes.
  int? _guestsOverride;

  /// How many people are eating.
  ///
  /// On create it rides along in `place_staff_order`, which is why nothing is
  /// written here. On amend it is a direct column update: covers decide no
  /// money and no access, and the web action does exactly the same.
  Future<void> _editGuests() async {
    final chosen = await showGuestsDialog(context: context, current: _guests);
    if (chosen == null || !mounted) return;

    if (!_isAmend) {
      setState(() => (_cart as CreateCart).guests = chosen);
      return;
    }

    final repo = ref.read(posRepoProvider);
    if (repo == null) return;
    if (!(ref.read(isOnlineProvider).valueOrNull ?? true)) {
      _toast(
        "No coverage — the guest count can't be saved yet. The order is safe.",
        error: true,
      );
      return;
    }
    try {
      await repo.setGuests(orderId: widget.existingOrder!.id, guests: chosen);
      if (!mounted) return;
      setState(() => _guestsOverride = chosen);
      ref.invalidate(activeOrdersProvider);
    } on PosFailure catch (e) {
      _toast(e.message, error: true);
    }
  }

  /// Clear the whole order and leave the composer.
  ///
  /// Manager-gated on role by `cancel_order`, reason required, audited. Not
  /// queued offline — the RPC refuses an order that has since been billed, so a
  /// replay would fail with the composer long gone.
  Future<void> _cancelOrder() async {
    final order = widget.existingOrder!;
    final repo = ref.read(posRepoProvider);
    if (repo == null) return;

    final dishes = order.itemCount;
    final reason = await showVoidReasonDialog(
      context: context,
      title: 'Cancel this order?',
      body:
          '${dishes == 1 ? 'The one dish' : 'All $dishes dishes'} on this order '
          'will be voided and the order cancelled. Any stock it deducted is '
          'returned, the table is freed, and this is recorded against your '
          'name.',
      confirmLabel: 'Cancel order',
      keepLabel: 'Keep order',
      hint: 'e.g. guests left before ordering',
    );
    if (reason == null || !mounted) return;

    if (!(ref.read(isOnlineProvider).valueOrNull ?? true)) {
      _toast(
        "No coverage — an order can't be cancelled yet. Try again when you're "
        'back.',
        error: true,
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await repo.cancelOrder(orderId: order.id, reason: reason);
      if (!mounted) return;
      ref.invalidate(activeOrdersProvider);
      unawaited(ref.read(tablesProvider.notifier).refresh());
      Navigator.of(context).pop();
    } on PosFailure catch (e) {
      if (!mounted) return;
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Open this order's bill and leave the composer behind it.
  ///
  /// The write needs a connection: offline it would sit on a long HTTP timeout
  /// and read as a dead tap, and there is nothing useful to queue — a bill with
  /// no id is a screen nobody can open.
  Future<void> _openBill() async {
    if (_busy) return;
    if (!(ref.read(isOnlineProvider).valueOrNull ?? true)) {
      _toast(
        "No coverage — a bill can't be opened yet. The order is safe; settle "
        "it when you're back.",
        error: true,
      );
      return;
    }
    final repo = ref.read(billRepoProvider);
    if (repo == null) return;

    setState(() => _busy = true);
    try {
      final billId = await repo.createBillForOrder(widget.existingOrder!.id);
      if (!mounted) return;
      await context.push(Routes.billPath(billId));
    } on PosFailure catch (e) {
      if (!mounted) return;
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                error ? Icons.error_outline : Icons.check_circle_outline,
                color: error ? scheme.onError : null,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: error ? scheme.error : null,
        ),
      );
  }

  /// A line that isn't on the menu — a plating charge, today's special.
  ///
  /// The price is typed, so it goes through the same `add` as any dish and
  /// lands on a server RPC that clamps it and audits it. Nothing here decides
  /// what it costs beyond passing on what was typed.
  Future<void> _addCustom(String currency) async {
    final line = await showCustomItemSheet(
      context: context,
      currency: currency,
    );
    if (line == null || !mounted) return;
    await _commitLine(line);
  }

  Future<void> _addDish(PosMenuItem item, String currency) async {
    CartLine? line;
    if (item.optionCount > 0) {
      line = await showItemOptionsSheet(
        context: context,
        item: item,
        currency: currency,
      );
    } else {
      line = CartLine(
        localId: DateTime.now().microsecondsSinceEpoch.toString(),
        item: item,
        qty: 1,
      );
    }
    if (line == null) return;
    await _commitLine(line);
  }

  /// Put a line into the cart, whether it came from the menu or was typed.
  ///
  /// Optimistic in create mode (it's local anyway). In amend mode the server is
  /// the source of truth, so we await it and surface a failure honestly rather
  /// than showing a line the kitchen never got.
  Future<void> _commitLine(CartLine line) async {
    try {
      await _cart.add(line);
      if (_isAmend) await _refreshAmend();
      if (mounted) setState(() {});
    } on PosFailure catch (e) {
      _toast(e.message, error: true);
    }
  }

  /// Pull server truth back into the cart after an amend.
  ///
  /// Offline this simply fails, and that is fine: the queued line is already
  /// drawn from the outbox, so the waiter sees their dish either way. Never let
  /// a failed *read* undo a durable *write*.
  Future<void> _refreshAmend() async {
    final cart = _cart;
    if (cart is! AmendCart) return;
    await cart.reconcilePending();
    try {
      final fresh = await ref.read(posRepoProvider)!.order(cart.order.id);
      if (fresh != null) cart.update(fresh);
    } on Object {
      return;
    } finally {
      ref.invalidate(activeOrdersProvider);
      ref.invalidate(outboxStatusProvider);
    }
  }

  Future<void> _removeLine(CartDisplayLine line) async {
    String? reason;
    if (_cart.needsVoidReason(line.id)) {
      reason = await _askVoidReason(line);
      if (reason == null) return;
    }
    try {
      await _cart.remove(line.id, reason: reason);
      if (_isAmend) await _refreshAmend();
      if (mounted) setState(() {});
    } on PosFailure catch (e) {
      _toast(e.message, error: true);
    }
  }

  /// A fired line is on a kitchen ticket. The server demands a reason and
  /// audits it — this dialog exists so the waiter supplies one, and it names
  /// the real consequence rather than asking "are you sure?".
  Future<String?> _askVoidReason(CartDisplayLine line) {
    return showVoidReasonDialog(
      context: context,
      title: 'Void this line?',
      body:
          '${line.qty} × ${line.title} is already with the kitchen. '
          'Voiding it removes it from the bill and records who did it and why.',
    );
  }

  Future<void> _setQty(CartDisplayLine line, int qty) async {
    if (qty <= 0) {
      await _removeLine(line);
      return;
    }
    try {
      await _cart.setQty(line.id, qty);
      if (_isAmend) await _refreshAmend();
      if (mounted) setState(() {});
    } on PosFailure catch (e) {
      _toast(e.message, error: true);
    }
  }

  /// Commit the order and send it to the kitchen. There is no save-without-
  /// firing path: an order the kitchen can't see isn't an order anyone placed,
  /// and the two-button version had waiters saving drafts that never cooked.
  Future<void> _commitAndFire() async {
    // Read before the commit: the toast fires after this widget has popped, and
    // the wording depends on what the order was when the waiter tapped.
    final billed = _isBilled;
    setState(() => _busy = true);
    try {
      final result = await _cart.commit(fire: true);
      ref.invalidate(activeOrdersProvider);
      ref.invalidate(outboxStatusProvider);
      // NOT awaited: the write is already durable, and with no coverage this
      // read sits on a long HTTP timeout. Making a saved order wait on a
      // refresh is how a queue that works looks broken.
      unawaited(ref.read(tablesProvider.notifier).refresh());
      if (!mounted) return;
      Navigator.of(context).pop();

      // Queued-but-not-sent is a success. Say what happened plainly, and never
      // leave a waiter wondering whether the kitchen has it.
      //
      // On a billed order the bill moved too — a trigger resyncs its total the
      // moment the lines land — and the slip in the guest's hand is now wrong.
      // Naming the reprint here is the difference between a corrected charge
      // and an argument at the till.
      _toast(
        result.synced
            ? (billed
                  ? 'Sent to the kitchen. The bill was updated — reprint it.'
                  : 'Sent to the kitchen.')
            : billed
            ? 'Saved. It goes to the kitchen and updates the bill the moment '
                  "you're back on coverage — reprint the bill after that."
            : "Saved. It goes to the kitchen the moment you're back on "
                  'coverage.',
      );
    } on PosFailure catch (e) {
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(activeTenantProvider);
    final currency = tenant?.currency ?? 'USD';
    final menu = ref.watch(menuProvider);
    final can86 = ref.watch(hasPermissionProvider('menu.edit'));
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];

    final destination = _isAmend
        ? (widget.existingOrder!.tableLabel != null
              ? 'Table ${widget.existingOrder!.tableLabel}'
              : orderTypeLabel(widget.existingOrder!.orderType))
        : (widget.seedTable != null
              ? 'Table ${widget.seedTable!.label}'
              : 'Takeaway');

    return AppScaffold(
      title: _isAmend ? 'Add to order' : 'New order',
      // Which table this lands on is the one fact worth carrying in the frame.
      // It used to be a second line inside the title, which clips as soon as
      // someone raises their text size.
      subtitle: destination,
      showDrawer: false,
      // Only in amend mode, and only once something has been fired: this is the
      // waiter who has just been asked for the bill, and `create_bill_for_order`
      // refuses an order the kitchen never saw.
      actions: [
        // Covers are a dine-in fact: a takeaway bag has no guests, and asking
        // would be a field nobody can answer.
        if (_isDineIn)
          IconButton(
            onPressed: _busy ? null : _editGuests,
            icon: Badge(
              isLabelVisible: _guests != null,
              label: Text('$_guests'),
              child: const Icon(Icons.group_outlined),
            ),
            tooltip: _guests == null
                ? 'How many guests?'
                : '$_guests guest${_guests == 1 ? '' : 's'}',
          ),
        if (_isAmend &&
            widget.existingOrder!.canBill &&
            ref.watch(hasPermissionProvider('checkout.view')))
          IconButton(
            onPressed: _busy ? null : _openBill,
            icon: const Icon(Icons.point_of_sale),
            // Once the order has a bill, `create_bill_for_order` is idempotent
            // and hands back the one that exists — so this taps through to a
            // bill rather than making one. Saying "Bill this order" there would
            // promise a second bill that nothing will ever create.
            tooltip: widget.existingOrder!.billId != null
                ? 'Open bill'
                : 'Bill this order',
          ),
        // Beside the search box, because "it isn't on the menu" is what a
        // waiter concludes after searching for it and not finding it.
        IconButton(
          onPressed: _busy ? null : () => _addCustom(currency),
          icon: const Icon(Icons.post_add),
          tooltip: 'Something off the menu',
        ),
        // Only in amend mode: a create-mode order has nothing on the server to
        // cancel — backing out is what discards it.
        // Deliberately `isSettled`, not `isAmendable`: adding to a billed order
        // is now allowed, but `cancel_order` still refuses one outright. Widen
        // this to `isAmendable` and a billed order grows a Cancel entry that
        // can only ever end in a server error.
        if (_isAmend &&
            !widget.existingOrder!.isSettled &&
            ref.watch(canCancelOrderProvider))
          PopupMenuButton<void>(
            tooltip: 'Order actions',
            itemBuilder: (_) => [
              PopupMenuItem<void>(
                onTap: _busy ? null : _cancelOrder,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.cancel_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Cancel order',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
      body: Column(
        children: [
          // Above the search box, not beside the send button: the waiter has to
          // know before they start tapping dishes, not after.
          if (_isBilled)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 10, 12, 2),
              child: _BilledBand(),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search the menu',
                isDense: true,
              ),
              onChanged: (v) =>
                  setState(() => _search = v.trim().toLowerCase()),
            ),
          ),
          if (categories.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AppChoiceChip(
                      label: 'All',
                      selected: _categoryId == null,
                      onSelect: () => setState(() => _categoryId = null),
                    ),
                  ),
                  for (final c in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AppChoiceChip(
                        label: c.name,
                        selected: _categoryId == c.id,
                        onSelect: () => setState(() => _categoryId = c.id),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: menu.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorState(
                message: "Couldn't load the menu.",
                detail: '$e',
                onRetry: () => ref.invalidate(menuProvider),
              ),
              data: (items) {
                final filtered = items.where((i) {
                  final byCategory =
                      _categoryId == null || i.categoryId == _categoryId;
                  final bySearch =
                      _search.isEmpty || i.name.toLowerCase().contains(_search);
                  return byCategory && bySearch;
                }).toList();

                if (filtered.isEmpty) {
                  return _EmptyState(
                    icon: Icons.restaurant_menu,
                    title: _search.isEmpty
                        ? 'Nothing on this menu yet'
                        : 'No dish matches "$_search"',
                    body: _search.isEmpty
                        ? 'Add dishes on the web app under Menu, then pull to refresh here.'
                        : 'Try a shorter search, or pick a different category.',
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 210,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final item = filtered[i];
                    final range = item.priceRange;
                    return MenuTile(
                      name: item.name,
                      minPriceCents: range.min,
                      maxPriceCents: range.max,
                      currency: currency,
                      imageUrl: item.imageUrl,
                      isVeg: item.isVeg,
                      soldOut: item.is86,
                      optionCount: item.optionCount,
                      qtyInOrder: _qtyInCart(item),
                      onTap: () => _addDish(item, currency),
                      // Long-press is the manager's way in — discoverable to
                      // whoever needs it, invisible to everyone else.
                      onLongPress: can86
                          ? () => showItem86Sheet(
                              context: context,
                              ref: ref,
                              item: item,
                            )
                          : null,
                    );
                  },
                );
              },
            ),
          ),
          _CartPanel(
            cart: _cart,
            currency: currency,
            busy: _busy,
            isAmend: _isAmend,
            isBilled: _isBilled,
            onSetQty: _setQty,
            onRemove: _removeLine,
            onFire: _commitAndFire,
          ),
        ],
      ),
    );
  }

  int _qtyInCart(PosMenuItem item) {
    var total = 0;
    for (final line in _cart.lines) {
      if (line.title == item.name || line.title.startsWith('${item.name} (')) {
        total += line.qty;
      }
    }
    return total;
  }
}

/// This order already has a bill, and adding to it moves the total.
///
/// Same shape as the checkout screen's `_StatusBand` — tinted fill, matching
/// border, icon and words carrying the meaning so it survives a greyscale
/// screenshot. That widget is private to its own file, so the pattern travels
/// rather than the class. The concern is `Bill.printedTotalIsStale` seen a step
/// earlier: there it warns that the guest is holding an old total, here it
/// warns you are about to create one.
class _BilledBand extends StatelessWidget {
  const _BilledBand();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Orange is this system's bill-requested colour, and this is the same
    // moment in the service — the guest is waiting to pay.
    final color = context.semantic.attentionText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'This order is already billed',
                  style: theme.textTheme.labelLarge?.copyWith(color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  'Anything you add goes on the same bill and changes the '
                  'total. The bill will need reprinting.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The running order. Collapsed to a summary bar until tapped — on a phone the
/// dish grid is the thing a waiter needs to see.
class _CartPanel extends StatefulWidget {
  const _CartPanel({
    required this.cart,
    required this.currency,
    required this.busy,
    required this.isAmend,
    required this.isBilled,
    required this.onSetQty,
    required this.onRemove,
    required this.onFire,
  });

  final CartController cart;
  final String currency;
  final bool busy;
  final bool isAmend;

  /// Three states, not two: the kitchen half of the button is true either way,
  /// but on a billed order the money moves too, and the label is the last place
  /// to say so before the tap.
  final bool isBilled;
  final void Function(CartDisplayLine, int) onSetQty;
  final void Function(CartDisplayLine) onRemove;
  final VoidCallback onFire;

  @override
  State<_CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends State<_CartPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lines = widget.cart.lines;
    final empty = lines.isEmpty;

    return Material(
      color: scheme.surfaceContainerLow,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Divider(height: 1, color: scheme.outline),
            if (_expanded && !empty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: lines.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: scheme.outline),
                  itemBuilder: (context, i) => _CartRow(
                    // Keyed by a STABLE id, never by content — a signature key
                    // rebuilds the row on every edit and loses the caret.
                    key: ValueKey(lines[i].id),
                    line: lines[i],
                    currency: widget.currency,
                    onSetQty: (q) => widget.onSetQty(lines[i], q),
                    onRemove: () => widget.onRemove(lines[i]),
                  ),
                ),
              ),
            InkWell(
              onTap: empty
                  ? null
                  : () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Row(
                  children: [
                    Icon(
                      _expanded ? Icons.expand_more : Icons.expand_less,
                      color: empty ? scheme.onSurfaceVariant : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        empty
                            ? 'Nothing added yet'
                            : '${widget.cart.itemCount} item'
                                  '${widget.cart.itemCount == 1 ? '' : 's'}',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    Text(
                      money(widget.cart.totalCents, widget.currency),
                      style: (theme.textTheme.titleMedium ?? const TextStyle())
                          .tabular,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              // One button. Confirming an order is sending it — there is no
              // save-that-doesn't-cook.
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: empty || widget.busy ? null : widget.onFire,
                  icon: widget.busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.local_fire_department),
                  label: Text(
                    widget.isBilled
                        ? 'Send & update the bill'
                        : widget.isAmend
                        ? 'Send new items'
                        : 'Send to kitchen',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({
    super.key,
    required this.line,
    required this.currency,
    required this.onSetQty,
    required this.onRemove,
  });

  final CartDisplayLine line;
  final String currency;
  final ValueChanged<int> onSetQty;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.title, style: theme.textTheme.titleSmall),
                if (line.modifierNames.isNotEmpty)
                  Text(
                    line.modifierNames.join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                if (line.notes != null && line.notes!.isNotEmpty)
                  Text(line.notes!, style: theme.textTheme.bodySmall),
                if (line.isFired)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        size: 13,
                        color: semantic.warningText,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'With the kitchen',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: semantic.warningText,
                        ),
                      ),
                    ],
                  ),
                // Never colour alone: the cloud icon and the words carry it.
                if (line.isPending)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_upload_outlined,
                        size: 13,
                        color: semantic.infoText,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Waiting to send',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: semantic.infoText,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (line.canEditQty) ...[
            IconButton(
              onPressed: () => onSetQty(line.qty - 1),
              icon: const Icon(Icons.remove, size: 18),
              tooltip: 'One fewer',
              constraints: const BoxConstraints(
                minWidth: Tokens.tapTarget,
                minHeight: Tokens.tapTarget,
              ),
            ),
            Text(
              '${line.qty}',
              style: (theme.textTheme.titleSmall ?? const TextStyle()).tabular,
            ),
            IconButton(
              onPressed: () => onSetQty(line.qty + 1),
              icon: const Icon(Icons.add, size: 18),
              tooltip: 'One more',
              constraints: const BoxConstraints(
                minWidth: Tokens.tapTarget,
                minHeight: Tokens.tapTarget,
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '×${line.qty}',
                style:
                    (theme.textTheme.titleSmall ?? const TextStyle()).tabular,
              ),
            ),
          SizedBox(
            width: 84,
            child: Text(
              money(line.lineTotalCents, currency),
              textAlign: TextAlign.right,
              style: (theme.textTheme.bodyMedium ?? const TextStyle()).tabular,
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: Icon(
              line.isFired ? Icons.block : Icons.delete_outline,
              size: 18,
            ),
            tooltip: line.isFired ? 'Void line' : 'Remove',
            constraints: const BoxConstraints(
              minWidth: Tokens.tapTarget,
              minHeight: Tokens.tapTarget,
            ),
          ),
        ],
      ),
    );
  }
}

/// An empty state teaches the next step — never "No data."
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// An error state says the recovery, and offers it.
class _ErrorState extends StatelessWidget {
  const _ErrorState({
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
      ),
    );
  }
}

/// Shared by the tables board.
class PosEmptyState extends StatelessWidget {
  const PosEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) =>
      _EmptyState(icon: icon, title: title, body: body);
}

/// Colour for a table state. Always paired with the label — never alone.
Color tableStateColor(BuildContext context, String state) {
  final s = context.semantic;
  return switch (state) {
    'free' => s.goodText,
    'occupied' => s.warningText,
    'reserved' => s.infoText,
    'bill_requested' => s.attentionText,
    _ => s.neutral,
  };
}

/// A table card for the board.
class TableCard extends StatelessWidget {
  const TableCard({
    super.key,
    required this.table,
    required this.onTap,
    this.onLongPress,
  });

  final PosTable table;
  final VoidCallback onTap;

  /// Manager ops (set the table's state). Null when the user can't.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = tableStateColor(context, table.state);
    final filled = table.state == 'occupied' || table.state == 'bill_requested';

    return Semantics(
      button: true,
      label:
          'Table ${table.label}, ${tableStateLabel(table.state).toLowerCase()}, '
          'seats ${table.capacity}',
      child: ExcludeSemantics(
        child: Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Tokens.radiusLg),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(Tokens.radiusLg),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: color.withValues(alpha: 0.5),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(Tokens.radiusLg),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TableGlyph(
                    seats: table.capacity,
                    filled: filled,
                    size: 46,
                    color: color,
                  ),
                  const SizedBox(height: 6),
                  Text(table.label, style: theme.textTheme.titleMedium),
                  Text(
                    tableStateLabel(table.state),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
