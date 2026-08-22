import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/format/labels.dart';
import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../tenant/tenant_providers.dart';
import 'models.dart';

/// The trading day so far, above the orders that make it up.
///
/// Computed from the rows already on screen rather than fetched: a second query
/// would be a second source of truth for "today's takings", and the two would
/// eventually disagree. The Realtime refetch replaces the same list, so this
/// recomputes for free and is never stale relative to what is below it.
///
/// **The totals describe the day, not the filter.** They are summed from every
/// order, not the filtered subset — a figure that moved when you tapped
/// "Cancelled" would be answering a different question from the one the label
/// asks.
class DaySummaryBar extends ConsumerWidget {
  const DaySummaryBar({
    super.key,
    required this.orders,
    required this.currency,
  });

  /// Every order of the day, unfiltered.
  final List<PosCompletedOrder> orders;

  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canSeeReports = ref.watch(hasPermissionProvider('reports.view'));

    // Summed from each order's own lines, not from `bills.total_cents`: two
    // orders merged onto one bill both carry the whole bill total, and adding
    // those counts the money twice. Cancelled orders took nothing.
    final takings = orders
        .where((o) => !o.isCancelled)
        .fold(0, (sum, o) => sum + o.lineTotalCents);

    final split = paymentSplit(orders);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${orders.length} order${orders.length == 1 ? '' : 's'} today',
                style: theme.textTheme.titleSmall,
              ),
              const Spacer(),
              Text(
                money(takings, currency),
                style:
                    (theme.textTheme.titleSmall ?? const TextStyle()).tabular,
                semanticsLabel: 'Takings ${money(takings, currency)}',
              ),
            ],
          ),
          if (split.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in split)
                  Chip(
                    label: Text(
                      '${paymentMethodLabel(e.key)} '
                      '${money(e.value, currency)}',
                      style: theme.textTheme.labelSmall?.tabular,
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
          if (canSeeReports)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.push(Routes.dayClose),
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: const Text('Day close sheet'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  minimumSize: const Size(0, 44),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What was tendered today, by method, biggest first.
///
/// **Deduped by bill.** `add_order_to_bill` merges tables, so one bill's
/// payments hang off every order sharing it; summing them straight off the
/// orders would count a merged table's cash once per order on it.
List<MapEntry<String, int>> paymentSplit(List<PosCompletedOrder> orders) {
  final seen = <String>{};
  final totals = <String, int>{};

  for (final o in orders) {
    final billId = o.billId;
    if (billId == null || !seen.add(billId)) continue;
    for (final p in o.billPayments) {
      if (!p.isCompleted) continue;
      totals[p.method] = (totals[p.method] ?? 0) + p.amountCents;
    }
  }

  final entries = totals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries;
}
