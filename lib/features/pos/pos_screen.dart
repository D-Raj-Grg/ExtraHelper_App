import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/labels.dart';
import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/pos_repository.dart';
import '../tenant/tenant_providers.dart';
import 'models.dart';
import 'order_composer.dart';
import 'pos_providers.dart';

/// The POS: a **Tables** board and an **Orders** list.
///
/// Tapping a table opens its live order if one is open, or starts a new order
/// seeded to that table. One decision, made here, so the composer never has to
/// ask which it is.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _openTable(PosTable table) async {
    // AWAIT the orders, don't read them.
    //
    // The Tables tab never watches this provider, so on a fresh launch it is
    // unbuilt and `.valueOrNull` is null — which read as "no open order" and
    // started a SECOND order on an occupied table. Awaiting the future builds
    // it if needed, so the answer is real rather than merely available.
    final orders = await ref.read(activeOrdersProvider.future);
    final open = orders
        .where((o) => o.tableId == table.id && !o.isClosed)
        .firstOrNull;
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => open != null
            ? OrderComposer(existingOrder: open)
            : OrderComposer(seedTable: table),
      ),
    );
    await ref.read(tablesProvider.notifier).refresh();
    ref.invalidate(activeOrdersProvider);
  }

  Future<void> _openOrder(PosOrder order) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderComposer(existingOrder: order),
      ),
    );
    ref.invalidate(activeOrdersProvider);
    await ref.read(tablesProvider.notifier).refresh();
  }

  Future<void> _newTakeaway() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const OrderComposer()));
    ref.invalidate(activeOrdersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final canOrder = ref.watch(hasPermissionProvider('order.create'));

    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Tables', icon: Icon(Icons.table_restaurant)),
            Tab(text: 'Orders', icon: Icon(Icons.receipt_long)),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _TablesTab(onOpen: canOrder ? _openTable : null),
              _OrdersTab(
                onOpen: _openOrder,
                onNewTakeaway: canOrder ? _newTakeaway : null,
              ),
            ],
          ),
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
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.currency,
    required this.onTap,
  });

  final PosOrder order;
  final String currency;
  final VoidCallback onTap;

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
