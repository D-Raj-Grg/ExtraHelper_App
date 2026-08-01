import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/labels.dart';
import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/pos_repository.dart';
import '../../data/sync/sync_providers.dart';
import '../tenant/tenant_providers.dart';
import 'manager_ops.dart';
import 'models.dart';
import 'order_composer.dart';
import 'pos_providers.dart';

/// The POS: a **Tables** board and an **Orders** list.
///
/// Tapping a table opens its live order if one is open, or starts a new order
/// seeded to that table. One decision, made here, so the composer never has to
/// ask which it is.
///
/// The `TabBar` itself belongs to the shell's app bar — the tabs and the bar
/// are one band — so the controller is passed in rather than owned here.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key, required this.tabs});

  final TabController tabs;

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
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

  Future<void> _openTable(PosTable table) async {
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

    final open = (orders ?? const <PosOrder>[])
        .where((o) => o.tableId == table.id && !o.isClosed)
        .firstOrNull;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => open != null
            ? OrderComposer(existingOrder: open)
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

    return TabBarView(
      controller: widget.tabs,
      children: [
        _TablesTab(onOpen: canOrder ? _openTable : null),
        _OrdersTab(
          onOpen: _openOrder,
          onNewTakeaway: canOrder ? _newTakeaway : null,
        ),
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
                          ? () => showTableStateSheet(
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
  const _OrdersTab({required this.onOpen, required this.onNewTakeaway});

  final void Function(PosOrder) onOpen;
  final VoidCallback? onNewTakeaway;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(activeOrdersProvider);
    final tenant = ref.watch(activeTenantProvider);
    final currency = tenant?.currency ?? 'USD';

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
                        'walk-in.',
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _OrderCard(
                order: list[i],
                currency: currency,
                onTap: () => onOpen(list[i]),
                onDelivered: () => _markDelivered(context, ref, list[i]),
              ),
            );
          },
        ),
      ),
    );
  }
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
  });

  final PosOrder order;
  final String currency;
  final VoidCallback onTap;
  final VoidCallback onDelivered;

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
                  Text(
                    money(order.totalCents, currency),
                    style: (theme.textTheme.titleMedium ?? const TextStyle())
                        .tabular,
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
