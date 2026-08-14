import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scaffold.dart';
import '../../app/router.dart';
import '../../core/format/labels.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../../data/sync/order_queue.dart';
import '../../data/sync/sync_providers.dart';
import '../tenant/tenant_providers.dart';
import 'bill_providers.dart';
import 'models.dart';
import 'order_composer.dart';
import 'pos_providers.dart';
import 'table_ops_sheets.dart';

/// Manager ops: 86 a dish, set a table's state, and move an order between
/// tables.
///
/// Both are queued through the outbox, because both are things *other* staff
/// need to see — a sold-out dish, a table freed — and both are safe to replay,
/// being last-write-wins on a single row. Both are also enforced again inside
/// their RPC, so what follows is an affordance, not a gate.

/// Sold out, or back on. Reached by long-pressing a dish in the composer.
Future<void> showItem86Sheet({
  required BuildContext context,
  required WidgetRef ref,
  required PosMenuItem item,
}) async {
  final queue = ref.read(orderQueueProvider);
  if (queue == null) return;

  final turnOff = !item.is86;
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => _ConfirmSheet(
      icon: turnOff ? Icons.remove_shopping_cart : Icons.restart_alt,
      title: turnOff ? 'Mark ${item.name} sold out?' : 'Put ${item.name} back?',
      body: turnOff
          ? 'It disappears from every waiter’s phone and the web POS, and '
                'nobody can order it until someone puts it back.'
          : 'It becomes orderable again on every phone and on the web POS.',
      confirmLabel: turnOff ? 'Mark sold out' : 'Put it back',
      destructive: turnOff,
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final outcome = await queue.setItem86(itemId: item.id, is86: turnOff);
  if (!context.mounted) return;
  _report(
    context,
    outcome,
    done: turnOff ? '${item.name} is sold out.' : '${item.name} is back on.',
    queued: turnOff
        ? 'Saved. Other phones see it sold out once you’re back on coverage.'
        : 'Saved. It goes back on once you’re back on coverage.',
  );
  ref.invalidate(outboxStatusProvider);
}

/// What a long-press on a table offers: set its state, or move the order that
/// is sitting on it.
///
/// The move actions only appear when there **is** an order — an empty table has
/// nothing to transfer, merge or split, and offering it would be three taps to
/// reach a refusal.
Future<void> showTableActionsSheet({
  required BuildContext context,
  required WidgetRef ref,
  required PosTable table,
}) async {
  final canMove = ref.read(hasPermissionProvider('order.create'));
  final canMerge = ref.read(hasPermissionProvider('checkout.view'));

  final action = await showModalBottomSheet<_TableAction>(
    context: context,
    useSafeArea: true,
    builder: (_) => _TableActionsSheet(
      table: table,
      canMove: canMove && !table.isFree,
      canMerge: canMerge && !table.isFree,
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _TableAction.state:
      await showTableStateSheet(context: context, ref: ref, table: table);
    case _TableAction.transfer:
      await _transferOrder(context, ref, table);
    case _TableAction.merge:
      await _mergeTables(context, ref, table);
    case _TableAction.split:
      await _splitOrder(context, ref, table);
  }
}

enum _TableAction { state, transfer, merge, split }

class _TableActionsSheet extends StatelessWidget {
  const _TableActionsSheet({
    required this.table,
    required this.canMove,
    required this.canMerge,
  });

  final PosTable table;
  final bool canMove;
  final bool canMerge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Text(
              'Table ${table.label}',
              style: theme.textTheme.titleLarge,
            ),
          ),
          ListTile(
            minTileHeight: Tokens.tapTarget,
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Set table state'),
            subtitle: Text('Now ${tableStateLabel(table.state).toLowerCase()}'),
            onTap: () => Navigator.of(context).pop(_TableAction.state),
          ),
          if (canMove)
            ListTile(
              minTileHeight: Tokens.tapTarget,
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Move to another table'),
              subtitle: const Text('The whole order goes with it'),
              onTap: () => Navigator.of(context).pop(_TableAction.transfer),
            ),
          if (canMerge)
            ListTile(
              minTileHeight: Tokens.tapTarget,
              leading: const Icon(Icons.merge),
              title: const Text('Merge with another table'),
              subtitle: const Text('One bill for both'),
              onTap: () => Navigator.of(context).pop(_TableAction.merge),
            ),
          if (canMove)
            ListTile(
              minTileHeight: Tokens.tapTarget,
              leading: const Icon(Icons.call_split),
              title: const Text('Split dishes to another table'),
              subtitle: const Text('Some dishes move, the rest stay'),
              onTap: () => Navigator.of(context).pop(_TableAction.split),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Move the whole order to another table.
Future<void> _transferOrder(
  BuildContext context,
  WidgetRef ref,
  PosTable table,
) async {
  final repo = ref.read(posRepoProvider);
  if (repo == null) return;
  if (!_requireOnline(context, ref, 'moved')) return;

  final orderId = await _orderOn(context, ref, table);
  if (orderId == null || !context.mounted) return;

  final destination = await showTablePicker(
    context: context,
    ref: ref,
    exclude: table,
    title: 'Move table ${table.label} to…',
    body:
        'The whole order moves. Table ${table.label} is freed unless it has '
        'another order on it.',
    freeOnly: true,
  );
  if (destination == null || !context.mounted) return;

  await _run(
    context,
    ref,
    () => repo.transferOrder(orderId: orderId, toTableId: destination.id),
    done: 'Moved to table ${destination.label}.',
  );
}

/// Two parties, one bill.
Future<void> _mergeTables(
  BuildContext context,
  WidgetRef ref,
  PosTable table,
) async {
  final billRepo = ref.read(billRepoProvider);
  if (billRepo == null) return;
  if (!_requireOnline(context, ref, 'merged')) return;

  final primaryOrderId = await _orderOn(context, ref, table);
  if (primaryOrderId == null || !context.mounted) return;

  final other = await showTablePicker(
    context: context,
    ref: ref,
    exclude: table,
    title: 'Merge table ${table.label} with…',
    body:
        'Both orders end up on one bill. Pick the table whose order joins this '
        'one.',
  );
  if (other == null || !context.mounted) return;

  final otherOrderId = await _orderOn(context, ref, other);
  if (otherOrderId == null || !context.mounted) return;

  String message;
  String? billId;
  try {
    billId = await billRepo.mergeOrders(
      primaryOrderId: primaryOrderId,
      otherOrderId: otherOrderId,
    );
    message = 'Merged onto one bill.';
  } on PosFailure catch (e) {
    message = e.message;
  } finally {
    // **Refreshed even when it failed.** A merge is two RPCs, and the first —
    // `create_bill_for_order` — has already moved the primary order to `billed`
    // by the time the second can refuse. Invalidating only on success would
    // leave that order on the board, and tapping it would open the composer for
    // an order the server considers billed.
    if (context.mounted) {
      ref
        ..invalidate(activeOrdersProvider)
        ..invalidate(openBillsProvider)
        ..invalidate(filteredBillsProvider)
        ..invalidate(completedOrdersProvider);
      unawaited(ref.read(tablesProvider.notifier).refresh());
    }
  }

  if (!context.mounted) return;
  if (billId != null) {
    await context.push(Routes.billPath(billId));
    return;
  }
  _say(context, message);
}

/// Some dishes go to a table of their own.
Future<void> _splitOrder(
  BuildContext context,
  WidgetRef ref,
  PosTable table,
) async {
  final repo = ref.read(posRepoProvider);
  if (repo == null) return;
  if (!_requireOnline(context, ref, 'split')) return;

  final orderId = await _orderOn(context, ref, table);
  if (orderId == null || !context.mounted) return;

  // **Refresh, don't read.** `orderProvider` is a plain family with nothing
  // invalidating it, so a second split on the same table would be offered the
  // snapshot from the first — including the lines it already moved. Picking one
  // sends a dead `order_items.id` to `split_order_items`, which moves fewer
  // rows than the waiter chose, or none at all.
  final order = await ref.refresh(orderProvider(orderId).future);
  if (order == null || !context.mounted) {
    if (context.mounted) _say(context, "Couldn't read that order.");
    return;
  }

  final currency = ref.read(activeTenantProvider)?.currency ?? 'USD';
  final itemIds = await showSplitLinePicker(
    context: context,
    order: order,
    currency: currency,
  );
  if (itemIds == null || itemIds.isEmpty || !context.mounted) return;

  final destination = await showTablePicker(
    context: context,
    ref: ref,
    exclude: table,
    title: 'Move those dishes to…',
    body: 'They become a new order on the table you pick.',
    freeOnly: true,
  );
  if (destination == null || !context.mounted) return;

  await _run(
    context,
    ref,
    () => repo.splitOrderItems(
      orderId: orderId,
      toTableId: destination.id,
      itemIds: itemIds,
    ),
    // Deliberately not "3 dishes moved": `split_order_items` returns the new
    // order's id, not a count, and it succeeds when **at least one** line
    // matched. Naming a number here would let the app claim more than the
    // server did.
    done: 'Moved to table ${destination.label}.',
  );
}

/// Which order is on this table, with the answer a waiter needs when there
/// isn't one.
Future<String?> _orderOn(
  BuildContext context,
  WidgetRef ref,
  PosTable table,
) async {
  final repo = ref.read(posRepoProvider);
  if (repo == null) return null;
  try {
    final id = await repo.activeOrderIdForTable(table.id);
    if (id == null && context.mounted) {
      _say(context, 'Table ${table.label} has no open order to move.');
    }
    return id;
  } on PosFailure catch (e) {
    if (context.mounted) _say(context, e.message);
    return null;
  }
}

/// None of these can be queued: each writes a destination table's state, and a
/// split mints an order id the screen has to have.
bool _requireOnline(BuildContext context, WidgetRef ref, String verb) {
  if (ref.read(isOnlineProvider).valueOrNull ?? true) return true;
  _say(
    context,
    "No coverage — tables can't be $verb yet. The order is safe; try again "
    "when you're back.",
  );
  return false;
}

Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() write, {
  required String done,
}) async {
  String message;
  try {
    await write();
    message = done;
  } on PosFailure catch (e) {
    message = e.message;
  }
  // `ref` after disposal throws, and it would throw from a future nobody
  // awaits — an unhandled error rather than a visible one. A tenant switch or
  // a sign-out mid-write is exactly when this lands.
  if (!context.mounted) return;
  ref.invalidate(activeOrdersProvider);
  unawaited(ref.read(tablesProvider.notifier).refresh());
  _say(context, message);
}

void _say(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Free / occupied / reserved / bill requested / cleaning, from the board.
Future<void> showTableStateSheet({
  required BuildContext context,
  required WidgetRef ref,
  required PosTable table,
}) async {
  final queue = ref.read(orderQueueProvider);
  if (queue == null) return;

  final chosen = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => _TableStateSheet(table: table),
  );
  if (chosen == null || chosen == table.state || !context.mounted) return;

  final outcome = await queue.setTableState(tableId: table.id, state: chosen);
  if (!context.mounted) return;
  _report(
    context,
    outcome,
    done:
        'Table ${table.label} is now ${tableStateLabel(chosen).toLowerCase()}.',
    queued:
        'Saved. The board updates for everyone once you’re back on '
        'coverage.',
  );
  ref.invalidate(outboxStatusProvider);
  await ref.read(tablesProvider.notifier).refresh();
}

/// Queued-but-not-sent is a success, and says so. A refusal is the server's
/// sentence, shown as-is.
void _report(
  BuildContext context,
  QueueOutcome outcome, {
  required String done,
  required String queued,
}) {
  final scheme = Theme.of(context).colorScheme;
  final failed = outcome.isRejected;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              failed
                  ? Icons.error_outline
                  : outcome.synced
                  ? Icons.check_circle_outline
                  : Icons.cloud_upload_outlined,
              size: 20,
              color: failed ? scheme.onError : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                failed ? outcome.error! : (outcome.synced ? done : queued),
              ),
            ),
          ],
        ),
        backgroundColor: failed ? scheme.error : null,
      ),
    );
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
    required this.icon,
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.destructive,
  });

  final IconData icon;
  final String title;
  final String body;
  final String confirmLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: destructive ? semantic.attentionText : semantic.goodText,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 10),
          // Name the real consequence, never "are you sure?".
          Text(body, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(confirmLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TableStateSheet extends StatelessWidget {
  const _TableStateSheet({required this.table});

  final PosTable table;

  static const _states = [
    'free',
    'occupied',
    'reserved',
    'bill_requested',
    'cleaning',
  ];

  static IconData _icon(String state) => switch (state) {
    'free' => Icons.event_available,
    'occupied' => Icons.people,
    'reserved' => Icons.bookmark_outline,
    'bill_requested' => Icons.receipt_long,
    'cleaning' => Icons.cleaning_services,
    _ => Icons.help_outline,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Text(
                'Table ${table.label}',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'Freeing a table with a live order is refused by the server — '
                'close or cancel the order first.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            for (final state in _states)
              ListTile(
                minTileHeight: Tokens.tapTarget,
                leading: Icon(
                  _icon(state),
                  color: tableStateColor(context, state),
                ),
                title: Text(tableStateLabel(state)),
                // The tick, not the colour, is what says "this one".
                trailing: state == table.state ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(state),
              ),
          ],
        ),
      ),
    );
  }
}

/// What managers did today, and why.
final auditLogProvider = FutureProvider.autoDispose<List<PosAuditEntry>>((
  ref,
) async {
  final repo = ref.watch(posRepoProvider);
  if (repo == null) return const [];
  return repo.auditLog();
});

/// The manager's log — voids, discounts, stock and table changes.
///
/// `audit_logs` RLS restricts SELECT to owners and managers, so a waiter who
/// reached this screen would see an empty list rather than someone else's data.
class ManagerLogScreen extends ConsumerWidget {
  const ManagerLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(auditLogProvider);

    return AppScaffold(
      title: 'Manager log',
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(auditLogProvider),
        child: log.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 80),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 36,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Couldn't load the log.",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$e',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: () => ref.invalidate(auditLogProvider),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          data: (entries) {
            if (entries.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 60),
                  PosEmptyState(
                    icon: Icons.fact_check_outlined,
                    title: 'Nothing to review',
                    body:
                        'Voids, discounts, stock changes and table changes show '
                        'up here with who did them and why.',
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _LogRow(entry: entries[i]),
            );
          },
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final PosAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semantic;

    final (icon, color, label) = switch (entry.action) {
      'void' => (Icons.block, semantic.dangerText, 'Void'),
      'discount' => (Icons.percent, semantic.warningText, 'Discount'),
      'item_86' => (
        Icons.remove_shopping_cart,
        semantic.attentionText,
        'Sold out',
      ),
      'item_unset_86' => (Icons.restart_alt, semantic.goodText, 'Back on'),
      'table_state' => (Icons.table_restaurant, semantic.infoText, 'Table'),
      _ => (Icons.article_outlined, semantic.neutral, entry.action),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              // Colour never carries it alone — the word is right there.
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.subject,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _clock(entry.createdAt),
                style: (theme.textTheme.bodySmall ?? const TextStyle()).tabular,
              ),
            ],
          ),
          if (entry.reason != null) ...[
            const SizedBox(height: 6),
            Text(entry.reason!, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 4),
          Text(
            entry.actorName ?? 'Account since removed',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'am' : 'pm'}';
  }
}
