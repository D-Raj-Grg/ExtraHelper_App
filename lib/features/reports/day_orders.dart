import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/format/labels.dart';
import '../../core/format/money.dart';
import '../../core/format/when.dart';
import '../../core/theme/app_theme.dart';
import '../../data/supabase/day_report_repository.dart';
import '../pos/models.dart';
import 'day_report_providers.dart';

/// Every order of the trading day, under the totals it adds up to.
///
/// The sheet above reconciles the day; this is the ledger behind it — the
/// answer to "which order was that?" without leaving for the POS. Rows are
/// bounded by the same window the RPC used, so the list and the figures above
/// cannot describe different days.
class DayOrders extends ConsumerWidget {
  const DayOrders({super.key, required this.report});

  final DayReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final orders = ref.watch(dayOrdersProvider);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Orders',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            orders.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(
                "Couldn't load the day's orders. $e",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              data: (page) => page.orders.isEmpty
                  ? Text(
                      'No orders were taken on this day.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : _List(page: page, report: report),
            ),
          ],
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.page, required this.report});

  final DayOrdersPage page;
  final DayReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cur = report.currency;
    final ordered = page.orderedCents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final o in page.orders)
          _OrderRow(order: o, currency: cur, report: report),
        const SizedBox(height: 8),
        Text(
          '${page.orders.length} '
          '${page.orders.length == 1 ? "order" : "orders"} · '
          '${money(ordered, cur)} ordered, excluding cancellations and voided '
          'lines. Tap a row for its items.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        // This column will not add up to Revenue, and a reader will try. Saying
        // why is cheaper than the support ticket.
        if (ordered != report.sales.revenueCents) ...[
          const SizedBox(height: 4),
          Text(
            'That is not the same figure as Revenue '
            '(${money(report.sales.revenueCents, cur)}): this column is what '
            'was ordered, at menu prices, whether or not it was paid for. '
            'Revenue is what was settled — paid bills only, at bill totals, '
            'after tax, service and discounts.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (page.truncated) ...[
          const SizedBox(height: 4),
          Text(
            'Showing the first ${page.orders.length} orders of this day. The '
            'web report has the rest.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// One order. The whole row is the target — on a phone, asking someone to hit
/// a six-character id is the wrong size of thing to aim at.
class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.currency,
    required this.report,
  });

  final PosCompletedOrder order;
  final String currency;
  final DayReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = order;
    final dest = _destination(o);
    final amount = money(o.lineTotalCents, currency);

    return Semantics(
      button: true,
      label: 'Order ${o.shortId}, $dest, $amount. Open details',
      child: InkWell(
        onTap: () => _showDetail(context, o, currency),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${o.shortId} · $dest',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${clockTime(o.createdAt)} · ${o.lineCount} items · '
                      '${orderStatusLabel(o.status)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                amount,
                style: theme.textTheme.bodyMedium?.tabular.copyWith(
                  // A cancelled order took no money. Struck through as well as
                  // muted, so it does not read as a figure that counts.
                  decoration: o.isCancelled ? TextDecoration.lineThrough : null,
                  color: o.isCancelled
                      ? theme.colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _destination(PosCompletedOrder o) => o.tableLabel != null
    ? 'Table ${o.tableLabel}'
    : orderTypeLabel(o.orderType);

void _showDetail(
  BuildContext context,
  PosCompletedOrder order,
  String currency,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _OrderDetail(order: order, currency: currency),
  );
}

class _OrderDetail extends StatelessWidget {
  const _OrderDetail({required this.order, required this.currency});

  final PosCompletedOrder order;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = order;
    final live = o.lines.where((l) => !l.isVoid).toList();
    final voided = o.lines.where((l) => l.isVoid).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            '#${o.shortId}',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_destination(o)}'
            '${o.guests != null ? " · ${o.guests} guests" : ""} · '
            '${orderStatusLabel(o.status)} · started '
            '${billDateTime(o.createdAt)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Divider(height: 24),

          if (live.isEmpty && voided.isEmpty)
            Text(
              'This order has no lines. It was opened and left empty.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

          for (final l in live)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${l.qty} × ${l.nameSnapshot}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${money(l.unitPriceCents, currency)} each',
                          style: theme.textTheme.bodySmall?.tabular.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (l.notes != null && l.notes!.isNotEmpty)
                          Text(
                            l.notes!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    money(l.lineTotalCents, currency),
                    style: theme.textTheme.bodyMedium?.tabular,
                  ),
                ],
              ),
            ),

          // Voids are shown, not hidden: "why is this order 300 short?" is
          // exactly the question this sheet exists to answer.
          if (voided.isNotEmpty) ...[
            const Divider(height: 24),
            Text(
              'Voided',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            for (final l in voided)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${l.qty} × ${l.nameSnapshot}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          decoration: TextDecoration.lineThrough,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      money(l.lineTotalCents, currency),
                      style: theme.textTheme.bodyMedium?.tabular.copyWith(
                        decoration: TextDecoration.lineThrough,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],

          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ordered',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                money(o.lineTotalCents, currency),
                style: theme.textTheme.titleMedium?.tabular.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // The bill is a different number from this one — it carries tax,
          // service and any discount, and on a merged table it covers other
          // orders too. Naming both stops the sheet reading as a contradiction.
          Text(
            o.billTotalCents != null
                ? 'Its bill totals ${money(o.billTotalCents!, currency)} — that '
                      'includes tax, service and discounts, and covers every '
                      'order sharing the bill.'
                : 'No bill was raised for this order.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          if (o.billId != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.push(Routes.billViewPath(o.billId!));
              },
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Open bill'),
            ),
          ],
        ],
      ),
    );
  }
}
