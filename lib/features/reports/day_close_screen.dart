import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/format/labels.dart';
import '../../core/format/money.dart';
import '../../core/format/variance.dart';
import '../../core/format/when.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/day_report_repository.dart';
import '../../data/supabase/expenses_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../tenant/tenant_providers.dart';
import 'day_bar.dart';
import 'day_count_sheet.dart';
import 'day_cutoff_card.dart';
import 'day_orders.dart';
import 'day_report_providers.dart';
import 'print_day_report_button.dart';

/// The day close — the Z-report, on the phone.
///
/// One trading day, reconciled so it can be signed off: what was sold, what was
/// tendered, what went in the drawer, and every order behind the figures. It
/// renders `daily_report`, the same RPC the web sheet and the thermal slip
/// read, so the three cannot disagree about a day.
///
/// The manager who closes the till is standing at it, not at a laptop. That is
/// the whole reason this screen exists.
class DayCloseScreen extends ConsumerWidget {
  const DayCloseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(activeTenantProvider);
    final report = ref.watch(dayReportProvider);

    // Fires outside build, so recording the server's answer is not a
    // state-write-during-build. This is the only way the app learns what
    // "today" is — it cannot work it out.
    ref.listen(dayReportProvider, (_, next) {
      // Settled data only. While a new day loads, the AsyncValue still carries
      // the *previous* day's report — after stepping forward or back to today
      // that would record the day just left as "today".
      if (next.isLoading) return;
      final day = next.valueOrNull?.day;
      if (day != null) ref.read(dayCursorProvider.notifier).rememberToday(day);
    });

    return AppScaffold(
      title: 'Day close',
      subtitle: tenant?.name ?? 'The trading day, ready to sign off',
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(dayReportProvider.future),
        child: report.when(
          loading: () => const _Centered(child: CircularProgressIndicator()),
          error: (e, _) => e is DayReportForbidden
              ? const _NoReportsAccess()
              : _LoadFailed(
                  detail: '$e',
                  onRetry: () => ref.invalidate(dayReportProvider),
                ),
          data: (r) => _Sheet(r: r),
        ),
      ),
    );
  }
}

class _Sheet extends ConsumerWidget {
  const _Sheet({required this.r});

  final DayReport r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cur = r.currency;
    final s = r.sales;
    final cut = cutoffLabel(r.cutoffMinutes);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        DayBar(dayLabel: r.dayLabel),
        const SizedBox(height: 8),

        // The window and the zone are the caveat on every figure below. A
        // manager comparing this against a printout needs to know which hours
        // it covers, and whose clock decided them.
        Text(
          cut == null
              ? 'Trading day runs midnight to midnight. Times in ${r.timezone}.'
              : 'Trading day runs $cut to $cut the next morning. '
                    'Times in ${r.timezone}.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),

        if (r.cash.openCount > 0) ...[
          _OpenDrawerBanner(count: r.cash.openCount),
          const SizedBox(height: 16),
        ],

        _KpiGrid(
          children: [
            _Kpi(
              icon: Icons.payments_outlined,
              label: 'Revenue',
              value: money(s.revenueCents, cur),
            ),
            _Kpi(
              icon: Icons.receipt_long_outlined,
              label: 'Bills',
              value: '${s.bills}',
            ),
            _Kpi(
              icon: Icons.confirmation_number_outlined,
              label: 'Avg ticket',
              value: money(s.avgCents, cur),
            ),
            _Kpi(
              icon: Icons.percent_outlined,
              label: 'Tax',
              value: money(s.taxCents, cur),
            ),
            _Kpi(
              icon: Icons.room_service_outlined,
              label: 'Service',
              value: money(s.serviceCents, cur),
            ),
            _Kpi(
              icon: Icons.discount_outlined,
              label: 'Discounts',
              value: money(s.discountCents, cur),
            ),
            _Kpi(
              icon: Icons.block_outlined,
              label: 'Voids',
              value: '${r.voids.count} · ${money(r.voids.valueCents, cur)}',
              warn: r.voids.count > 0,
            ),
            _Kpi(
              icon: Icons.cancel_outlined,
              label: 'Cancellations',
              value:
                  '${r.cancellations.count} · '
                  '${money(r.cancellations.valueCents, cur)}',
              warn: r.cancellations.count > 0,
            ),
            _Kpi(
              icon: Icons.undo_outlined,
              label: 'Refunds',
              value: money(r.refunds.totalCents, cur),
              warn: r.refunds.totalCents > 0,
            ),
            // Only with `profit.view`: the server leaves the keys out
            // otherwise, and an absent figure must not read as zero profit.
            if (s.grossProfitCents != null) ...[
              _Kpi(
                icon: Icons.trending_up_outlined,
                label: 'Gross profit',
                value: money(s.grossProfitCents!, cur),
              ),
              _Kpi(
                icon: Icons.pie_chart_outline,
                label: 'Margin',
                // Profit without a margin (no net sales to divide by) is a
                // dash, not a 0.0% that reads as "sold at cost".
                value: s.marginPct == null
                    ? '—'
                    : '${s.marginPct!.toStringAsFixed(1)}%',
              ),
            ],
          ],
        ),
        if ((s.uncostedLines ?? 0) > 0) ...[
          const SizedBox(height: 8),
          Text(
            '${s.uncostedLines} ${s.uncostedLines == 1 ? 'line' : 'lines'} '
            'had no cost — enter costs on the web Inventory → Costing tab.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),

        PrintDayReportButton(day: r.day),
        const SizedBox(height: 16),

        _Section(
          title: 'Sales breakdown',
          empty: r.isQuiet ? 'No paid bills on this day.' : null,
          children: [
            _Line(
              label: 'Gross (subtotal)',
              value: money(s.subtotalCents, cur),
            ),
            // Negated: a discount came *off* the bill, and showing it as a
            // positive makes the column refuse to add up.
            _Line(label: 'Discounts', value: money(-s.discountCents, cur)),
            _Line(label: 'Service charge', value: money(s.serviceCents, cur)),
            _Line(label: 'Tax', value: money(s.taxCents, cur)),
            _Line(label: 'Tips', value: money(s.tipCents, cur)),
            _Line(label: 'Rounding', value: money(s.roundingCents, cur)),
            _Line(
              label: 'Revenue',
              value: money(s.revenueCents, cur),
              strong: true,
            ),
          ],
        ),
        const SizedBox(height: 16),

        _Section(
          title: 'Payments taken',
          empty: r.payments.isEmpty
              ? 'Nothing was tendered on this day.'
              : null,
          children: [
            for (final p in r.payments)
              _Line(
                label: paymentMethodLabel(p.method),
                note: '${p.count}',
                value: money(p.amountCents, cur),
              ),
            _Line(
              label: 'Payments total',
              value: money(r.paymentsTotalCents, cur),
              strong: true,
            ),
          ],
        ),

        // The line that stops the sheet reading as a contradiction. Revenue
        // buckets on the bill's date and payments on the payment's date, so
        // the two legitimately differ; saying which way, in words, is cheaper
        // than the support call.
        if (r.carriedCents != 0) ...[
          const SizedBox(height: 8),
          Text(
            r.carriedCents > 0
                ? '${money(r.carriedCents, cur)} of what was taken today '
                      'settles bills raised on an earlier day, which is why '
                      'payments exceed revenue.'
                : '${money(-r.carriedCents, cur)} of today\'s bills has not '
                      'been tendered yet, which is why revenue exceeds '
                      'payments.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),

        _CashBookSection(r: r),
        const SizedBox(height: 16),

        _Section(
          title: 'Expenses · ${money(r.expenses.totalCents, cur)}',
          empty: r.expenses.items.isEmpty
              ? 'No expenses logged on this day. Staff add them under '
                    'Expenses as they spend.'
              : null,
          children: [
            for (final x in r.expenses.items)
              _Line(
                label: x.note,
                note:
                    '${x.time} · ${x.category} · '
                    '${PaidFrom.from(x.paidFrom).label}',
                value: money(x.amountCents, cur),
              ),
            const Divider(height: 16),
            for (final c in r.expenses.byCategory)
              _Line(
                label: c.name,
                note: '×${c.count}',
                value: money(c.amountCents, cur),
              ),
            _Line(
              label: 'Total expenses',
              value: money(r.expenses.totalCents, cur),
              strong: true,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // The shift drawer only for restaurants that run one, or on a day a
        // session happened to close anyway.
        if (r.cashDrawerEnabled || r.cash.sessions.isNotEmpty) ...[
          _Section(
            title: 'Cash drawer',
            empty: r.cash.sessions.isEmpty
                ? 'No drawer was closed on this day.'
                : null,
            children: [
              for (final x in r.cash.sessions)
                _CashSession(x: x, currency: cur),
              if (r.cash.sessions.length > 1)
                _Line(
                  label: 'Total variance',
                  value: _signed(r.cash.totals.varianceCents, cur),
                  strong: true,
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        _Section(
          title: 'Top items',
          empty: r.topItems.isEmpty ? 'Nothing was sold on this day.' : null,
          children: [
            for (final t in r.topItems)
              _Line(
                label: t.description,
                note: t.profitCents == null
                    ? '×${t.qty}'
                    : '×${t.qty} · profit ${money(t.profitCents!, cur)}',
                value: money(t.revenueCents, cur),
              ),
          ],
        ),
        const SizedBox(height: 16),

        _Section(
          title: 'Counts',
          children: [
            _Line(label: 'Bills', value: '${s.bills}'),
            _Line(label: 'Tables served', value: '${s.tablesServed}'),
            _Line(
              label: 'Voided lines',
              note: '${r.voids.count}',
              value: money(r.voids.valueCents, cur),
            ),
            _Line(
              label: 'Cancelled orders',
              note: '${r.cancellations.count}',
              value: money(r.cancellations.valueCents, cur),
            ),
            _Line(
              label: 'Refunds',
              note: '${r.refunds.count}',
              value: money(r.refunds.totalCents, cur),
            ),
            _Line(label: 'Voided bills', value: '${r.voidBills}'),
          ],
        ),

        if (r.isQuiet) ...[const SizedBox(height: 16), _QuietDay()],

        const SizedBox(height: 16),
        DayOrders(report: r),

        const SizedBox(height: 16),
        DayCutoffCard(report: r),
      ],
    );
  }
}

/// Expected against counted, for cash and for online. The count itself is a
/// sheet, saved through `close_day`; re-closing overwrites the earlier count.
class _CashBookSection extends ConsumerStatefulWidget {
  const _CashBookSection({required this.r});

  final DayReport r;

  @override
  ConsumerState<_CashBookSection> createState() => _CashBookSectionState();
}

class _CashBookSectionState extends ConsumerState<_CashBookSection> {
  bool _busy = false;

  Future<void> _count() async {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null || _busy) return;
    final r = widget.r;
    final draft = await showDayCountSheet(
      context,
      book: r.cashBook,
      currency: r.currency,
    );
    if (draft == null) return;
    setState(() => _busy = true);
    String message;
    try {
      await ref
          .read(expensesRepositoryProvider(tenant.tenantId))
          .closeDay(
            day: r.day,
            cashCents: draft.cashCents,
            onlineCents: draft.onlineCents,
            note: draft.note,
          );
      message = 'Day closed.';
      ref.invalidate(dayReportProvider);
    } on PosFailure catch (e) {
      message = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.r.cashBook;
    final cur = widget.r.currency;
    final theme = Theme.of(context);

    List<Widget> ledger({
      required String title,
      required int sales,
      required int refunds,
      required int expenses,
      required int expected,
      required int? counted,
      required int? diff,
    }) {
      final v = diff == null ? null : variance(diff);
      return [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _Line(label: 'Taken in sales', value: money(sales, cur)),
        if (refunds > 0)
          _Line(label: 'Refunded', value: '−${money(refunds, cur)}'),
        _Line(
          label: 'Expenses paid',
          value: expenses > 0 ? '−${money(expenses, cur)}' : '—',
        ),
        _Line(label: 'Should have', value: money(expected, cur), strong: true),
        _Line(
          label: 'Counted',
          value: counted == null ? 'Not counted' : money(counted, cur),
        ),
        // Sign, word and colour together — never colour alone.
        if (v != null && diff != null)
          _Line(
            label: v.label,
            value: _signed(diff, cur),
            color: v.color(context),
            strong: true,
          ),
      ];
    }

    return _Section(
      title: 'Cash book',
      children: [
        Text(
          b.closed && b.closedAt != null
              ? 'Counted by ${b.closedBy ?? 'someone'} · '
                    '${billDateTime(b.closedAt!)}'
              : 'At night, count the cash in hand and check online received.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        ...ledger(
          title: 'Cash',
          sales: b.cashSalesCents,
          refunds: b.cashRefundsCents,
          expenses: b.cashExpensesCents,
          expected: b.expectedCashCents,
          counted: b.countedCashCents,
          diff: b.cashVarianceCents,
        ),
        const Divider(height: 16),
        ...ledger(
          title: 'Online',
          sales: b.onlineSalesCents,
          refunds: b.onlineRefundsCents,
          expenses: b.onlineExpensesCents,
          expected: b.expectedOnlineCents,
          counted: b.countedOnlineCents,
          diff: b.onlineVarianceCents,
        ),
        if (b.note != null && b.note!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Note: ${b.note}', style: theme.textTheme.bodySmall),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: b.closed
              ? OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _busy ? null : _count,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Recount'),
                )
              : FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _busy ? null : _count,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Count cash & close the day'),
                ),
        ),
      ],
    );
  }
}

String _signed(int cents, String currency) =>
    cents > 0 ? '+${money(cents, currency)}' : money(cents, currency);

/// A drawer left open while the day was closed.
///
/// Icon and words both, never colour alone: this is the difference between
/// "the day balanced" and "the day balanced apart from the till still in use".
class _OpenDrawerBanner extends StatelessWidget {
  const _OpenDrawerBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: semantic.warningText),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_outlined,
            size: 20,
            color: semantic.warningText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 1
                  ? '1 cash drawer is still open. The cash reconciliation '
                        'below covers closed sessions only.'
                  : '$count cash drawers are still open. The cash '
                        'reconciliation below covers closed sessions only.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: semantic.warningText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CashSession extends StatelessWidget {
  const _CashSession({required this.x, required this.currency});

  final DayCashSession x;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final v = variance(x.varianceCents);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  x.cashier ?? 'Unknown cashier',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (x.closedAt != null)
                Text(
                  clockTime(x.closedAt!),
                  style: theme.textTheme.bodySmall?.tabular.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          _Line(label: 'Float', value: money(x.openingFloatCents, currency)),
          if (x.payoutsCents > 0)
            _Line(
              label: 'Cash out',
              value: '−${money(x.payoutsCents, currency)}',
            ),
          if (x.paidInCents > 0)
            _Line(
              label: 'Paid in',
              value: '+${money(x.paidInCents, currency)}',
            ),
          _Line(label: 'Expected', value: money(x.expectedCents, currency)),
          _Line(label: 'Counted', value: money(x.countedCents, currency)),
          // Sign, word and colour together. Short and over are not the same
          // problem, and red-vs-green alone cannot say which is which.
          _Line(
            label: 'Variance',
            note: v.label,
            value: _signed(x.varianceCents, currency),
            color: v.color(context),
            strong: true,
          ),
          if (x.autoApprovedCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.bolt_outlined,
                    size: 14,
                    color: semantic.warningText,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${x.autoApprovedCount} approved by the close, '
                      'not by a manager',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: semantic.warningText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _QuietDay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Nothing was billed on this day. Take an order on the POS and settle '
        'it, and its figures land here.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chrome. Same vocabulary as the dashboard — cards, a titled section, and a
// label/value row — because these two screens are read by the same person for
// the same reason and should not look like different products.
// ---------------------------------------------------------------------------

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 3 : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    this.warn = false,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Draws the eye to a figure that wants a second look — never the only
  /// signal, since the label says what it is.
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.titleLarge?.tabular.copyWith(
                  fontWeight: FontWeight.w700,
                  color: warn ? semantic.warningText : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.children = const [], this.empty});

  final String title;
  final List<Widget> children;

  /// The sentence to show instead of the rows. Teaches what would fill it —
  /// never "No data".
  final String? empty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (empty != null)
              Text(
                empty!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...children,
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.note,
    this.color,
    this.strong = false,
  });

  final String label;
  final String value;

  /// A count or a word beside the label — "3", "Short".
  final String? note;

  final Color? color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weight = strong ? FontWeight.w700 : FontWeight.w400;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                text: label,
                children: note == null
                    ? null
                    : [
                        TextSpan(
                          text: '  $note',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: color ?? theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: weight,
                color: strong ? null : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.tabular.copyWith(
              fontWeight: weight,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrollable, so pull-to-refresh still works over a spinner or an error.
class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _NoReportsAccess extends StatelessWidget {
  const _NoReportsAccess();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Centered(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Reports are not yours to see',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'The day close needs the Reports permission. Ask an owner or '
              'manager to grant it.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.detail, required this.onRetry});

  final String detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Centered(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text("Couldn't load the day", style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'This report is read live, so it needs a connection. Check '
              'coverage and try again.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
