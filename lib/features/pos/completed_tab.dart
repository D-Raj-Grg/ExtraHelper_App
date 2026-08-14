import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/labels.dart';
import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/choice_chip.dart';
import '../../data/print/reprint_actions.dart';
import '../tenant/tenant_providers.dart';
import 'models.dart';
import 'order_composer.dart' show PosEmptyState;
import 'pos_providers.dart';

/// Today's finished orders — billed, closed and cancelled.
///
/// **Today only.** A busy till closes a few hundred orders a day; anything
/// older is a question for the reports on the web app, not a longer list on a
/// phone. That is the same boundary the web's Completed tab draws, computed by
/// `tenant_day_start` so both clients agree on when the day turned over.
///
/// Nothing here is editable. It exists so a waiter can answer "did table six
/// pay?", get a receipt out again, and find a bill that has already left the
/// Orders board.
class CompletedTab extends ConsumerWidget {
  const CompletedTab({super.key, required this.onOpenBill});

  /// Null without `checkout.view` — the list stays readable, the route into
  /// money doesn't exist.
  final void Function(String billId)? onOpenBill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(completedOrdersProvider);
    final currency = ref.watch(activeTenantProvider)?.currency ?? 'USD';
    final canPrintTicket = ref.watch(hasPermissionProvider('order.view'));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(completedOrdersProvider),
      child: orders.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          children: [
            const SizedBox(height: 80),
            _CompletedError(
              detail: '$e',
              onRetry: () => ref.invalidate(completedOrdersProvider),
            ),
          ],
        ),
        data: (list) {
          if (list.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 60),
                PosEmptyState(
                  icon: Icons.done_all,
                  title: 'Nothing finished yet today',
                  body:
                      'Orders land here the moment they are billed, paid or '
                      'cancelled. Yesterday and further back live in the '
                      'reports on the web app.',
                ),
              ],
            );
          }

          final counts = <String, int>{};
          for (final o in list) {
            counts[o.status] = (counts[o.status] ?? 0) + 1;
          }
          // A chip whose status has emptied would be a filter onto nothing, so
          // the selection falls back to All rather than showing a blank list.
          final chosen = ref.watch(completedFilterProvider);
          final active = counts.containsKey(chosen) ? chosen : null;
          final shown = active == null
              ? list
              : list.where((o) => o.status == active).toList();

          // Summed from each order's own lines, not from `bills.total_cents`:
          // two orders merged onto one bill both carry the whole bill total,
          // and adding those would count the money twice. Cancelled orders took
          // nothing, so they are left out entirely.
          final takings = list
              .where((o) => !o.isCancelled)
              .fold(0, (sum, o) => sum + o.lineTotalCents);

          return Column(
            children: [
              _Summary(
                count: list.length,
                takings: takings,
                currency: currency,
              ),
              _StatusChips(
                counts: counts,
                total: list.length,
                selected: active,
                onSelect: (s) =>
                    ref.read(completedFilterProvider.notifier).select(s),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final order = shown[i];
                    // Two orders on one bill is a merge, and the figure beside
                    // the bill badge is the whole bill — say so, or it reads
                    // like this one order cost that much.
                    final mergedCount = order.billId == null
                        ? 1
                        : list.where((o) => o.billId == order.billId).length;

                    return _CompletedCard(
                      order: order,
                      currency: currency,
                      mergedCount: mergedCount,
                      onOpenBill: onOpenBill,
                      canPrintTicket: canPrintTicket,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.count,
    required this.takings,
    required this.currency,
  });

  final int count;
  final int takings;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Row(
        children: [
          Text(
            '$count order${count == 1 ? '' : 's'} today',
            style: theme.textTheme.titleSmall,
          ),
          const Spacer(),
          Text(
            money(takings, currency),
            style: (theme.textTheme.titleSmall ?? const TextStyle()).tabular,
            semanticsLabel: 'Takings ${money(takings, currency)}',
          ),
        ],
      ),
    );
  }
}

class _StatusChips extends StatelessWidget {
  const _StatusChips({
    required this.counts,
    required this.total,
    required this.selected,
    required this.onSelect,
  });

  final Map<String, int> counts;
  final int total;
  final String? selected;
  final ValueChanged<String?> onSelect;

  /// Fixed order, so the chips don't reshuffle themselves as the day goes on.
  static const _order = ['billed', 'closed', 'cancelled'];

  @override
  Widget build(BuildContext context) {
    final present = _order.where(counts.containsKey);
    if (present.length < 2) return const SizedBox(height: 12);

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
          for (final status in present) ...[
            const SizedBox(width: 8),
            AppChoiceChip(
              label: orderStatusLabel(status),
              detail: '${counts[status]}',
              selected: selected == status,
              showCheck: true,
              onSelect: () => onSelect(status),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompletedCard extends ConsumerWidget {
  const _CompletedCard({
    required this.order,
    required this.currency,
    required this.mergedCount,
    required this.onOpenBill,
    required this.canPrintTicket,
  });

  final PosCompletedOrder order;
  final String currency;
  final int mergedCount;
  final void Function(String billId)? onOpenBill;
  final bool canPrintTicket;

  Future<void> _say(BuildContext context, Future<String> work) async {
    final message = await work;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semantic;
    final billId = order.billId;
    final canOpenBill = onOpenBill != null && billId != null;

    // Cancelled is the one a manager scanning the list must not read as a sale.
    final statusColor = switch (order.status) {
      'closed' => semantic.goodText,
      'billed' => semantic.attentionText,
      'cancelled' => scheme.error,
      _ => semantic.neutral,
    };

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Tokens.radiusLg),
      child: InkWell(
        onTap: canOpenBill ? () => onOpenBill!(billId) : null,
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
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
                    // A cancelled order took no money. A zero would read as a
                    // sale rung up for nothing.
                    order.isCancelled
                        ? '—'
                        : money(order.lineTotalCents, currency),
                    style: (theme.textTheme.titleMedium ?? const TextStyle())
                        .tabular,
                  ),
                  _CardMenu(
                    onOpenBill: canOpenBill ? () => onOpenBill!(billId) : null,
                    onReprintBill: canOpenBill
                        ? () => _say(context, reprintBill(ref, billId))
                        : null,
                    onReprintSlip: canPrintTicket
                        ? () => _say(context, reprintOrderSlip(ref, order.id))
                        : null,
                    onReprintKots: canPrintTicket
                        ? () => _say(context, reprintOrderKots(ref, order.id))
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 9, color: statusColor),
                      const SizedBox(width: 6),
                      Text(
                        orderStatusLabel(order.status),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    order.isCancelled
                        ? '—'
                        : '${order.lineCount} '
                              'item${order.lineCount == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    _timeOfDay(order.createdAt),
                    style: (theme.textTheme.bodySmall ?? const TextStyle())
                        .tabular,
                  ),
                  if (order.billStatus != null)
                    Text(
                      mergedCount > 1
                          ? '${billStatusLabel(order.billStatus!)} · '
                                'merged ×$mergedCount · '
                                '${money(order.billTotalCents ?? 0, currency)}'
                          : '${billStatusLabel(order.billStatus!)} · '
                                '${money(order.billTotalCents ?? 0, currency)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 24-hour clock: a service that runs past midnight reads wrong in am/pm at a
/// glance, and this sits beside money already set in tabular figures.
String _timeOfDay(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';

class _CardMenu extends StatelessWidget {
  const _CardMenu({
    required this.onOpenBill,
    required this.onReprintBill,
    required this.onReprintSlip,
    required this.onReprintKots,
  });

  final VoidCallback? onOpenBill;
  final VoidCallback? onReprintBill;
  final VoidCallback? onReprintSlip;
  final VoidCallback? onReprintKots;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, IconData, VoidCallback)>[
      if (onOpenBill != null) ('View bill', Icons.receipt_long, onOpenBill!),
      if (onReprintBill != null)
        ('Reprint receipt', Icons.print_outlined, onReprintBill!),
      if (onReprintSlip != null)
        ('Reprint order slip', Icons.description_outlined, onReprintSlip!),
      if (onReprintKots != null)
        (
          'Reprint kitchen tickets',
          Icons.soup_kitchen_outlined,
          onReprintKots!,
        ),
    ];
    // No permission means no control, never a disabled one.
    if (entries.isEmpty) return const SizedBox(width: 8);

    return PopupMenuButton<VoidCallback>(
      tooltip: 'Order actions',
      icon: const Icon(Icons.more_vert),
      iconSize: 20,
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        for (final (label, icon, action) in entries)
          PopupMenuItem(
            value: action,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon),
              title: Text(label),
            ),
          ),
      ],
    );
  }
}

class _CompletedError extends StatelessWidget {
  const _CompletedError({required this.detail, required this.onRetry});

  final String detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off,
            size: 36,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            "Couldn't load today's orders.",
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
