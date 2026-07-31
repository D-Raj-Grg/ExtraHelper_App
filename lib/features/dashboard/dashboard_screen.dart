import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/labels.dart';
import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/choice_chip.dart';
import '../../data/supabase/dashboard_repository.dart';
import '../tenant/tenant_providers.dart';
import 'dashboard_providers.dart';
import 'revenue_chart.dart';

/// The owner's glance: what today made, what is still open, what is running out.
///
/// Read-only on purpose. Every figure comes from `dashboard_summary`, the same
/// RPC the web dashboard renders, so the phone and the counter screen can never
/// disagree about today's revenue.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(activeTenantProvider);
    final summary = ref.watch(dashboardSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tenant == null
                    ? 'Today at a glance'
                    : 'Today at a glance · ${tenant.timezone}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(dashboardSummaryProvider.future),
        child: summary.when(
          loading: () => const _Centered(child: CircularProgressIndicator()),
          error: (e, _) => e is DashboardForbidden
              ? const _NoReportsAccess()
              : _LoadFailed(
                  detail: '$e',
                  onRetry: () => ref.invalidate(dashboardSummaryProvider),
                ),
          data: (data) => _Dashboard(data: data),
        ),
      ),
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.data});

  final DashboardSummary data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final days = ref.watch(dashboardWindowProvider);
    final cur = data.currency;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (data.isEmpty) ...[const _NothingYet(), const SizedBox(height: 16)],

        // --- KPIs ----------------------------------------------------------
        _KpiGrid(
          children: [
            _Kpi(
              icon: Icons.receipt_long_outlined,
              label: 'Revenue today',
              value: money(data.todayRevenueCents, cur),
              delta: data.deltaPct,
              foot: data.deltaPct == null
                  ? 'Nothing sold yesterday to compare'
                  : 'vs yesterday',
            ),
            _Kpi(
              icon: Icons.restaurant_outlined,
              label: 'Paid orders today',
              value: '${data.todayBills}',
              foot: 'Avg ${money(data.todayAvgCents, cur)} per order',
            ),
            _Kpi(
              icon: Icons.soup_kitchen_outlined,
              label: 'Orders open now',
              value: '${data.activeOrders}',
              foot: '${data.openKots} kitchen tickets open',
            ),
            _Kpi(
              icon: Icons.inventory_2_outlined,
              label: 'Low stock',
              value: '${data.lowStockCount}',
              foot: data.lowStockCount == 0 ? 'All stocked' : 'Needs reorder',
              warn: data.lowStockCount > 0,
            ),
          ],
        ),

        const SizedBox(height: 20),

        // --- Revenue ------------------------------------------------------
        Row(
          children: [
            Text('Revenue', style: theme.textTheme.titleMedium),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final w in dashboardWindows) ...[
                AppChoiceChip(
                  label: '$w days',
                  selected: w == days,
                  showCheck: true,
                  onSelect: () =>
                      ref.read(dashboardWindowProvider.notifier).select(w),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        RevenueChart(series: data.series, currency: cur),

        const SizedBox(height: 24),

        // --- Lists ---------------------------------------------------------
        _Section(
          title: 'Running low',
          subtitle: 'Below reorder level',
          empty: 'Nothing is below its reorder level.',
          children: [
            for (final i in data.lowStock)
              _LineRow(
                leading: Icon(
                  i.isOversold ? Icons.error_outline : Icons.warning_amber,
                  size: 18,
                  color: i.isOversold
                      ? context.semantic.dangerText
                      : context.semantic.warningText,
                ),
                title: i.name,
                // Colour is reinforcement only: the word and the two figures
                // carry the state on their own.
                trailing: Text(
                  '${_qty(i.currentQty)} / ${_qty(i.reorderLevel)} ${i.uom}',
                  style: theme.textTheme.bodySmall?.tabular.copyWith(
                    color: i.isOversold
                        ? context.semantic.dangerText
                        : context.semantic.warningText,
                  ),
                ),
                subtitle: i.isOversold ? 'Oversold' : 'Low',
              ),
          ],
        ),

        _Section(
          title: 'Next on the book',
          subtitle: 'Reservations from now on',
          empty: 'No reservations booked.',
          children: [
            for (final r in data.reservations)
              _LineRow(
                leading: const Icon(Icons.event_outlined, size: 18),
                title: r.name,
                subtitle:
                    '${r.partySize} guests · ${reservationStatusLabel(r.status)}'
                    '${r.tableLabel == null ? '' : ' · Table ${r.tableLabel}'}',
                trailing: Text(
                  r.atText,
                  style: theme.textTheme.bodySmall?.tabular,
                ),
              ),
          ],
        ),

        _Section(
          title: 'Recent payments',
          subtitle: 'Latest paid bills',
          empty: 'No bills paid yet.',
          children: [
            for (final p in data.recentPayments)
              _LineRow(
                leading: const Icon(Icons.payments_outlined, size: 18),
                title: p.tableLabel == null
                    ? 'Takeaway'
                    : 'Table ${p.tableLabel}',
                subtitle: p.atText,
                trailing: Text(
                  money(p.totalCents, cur),
                  style: theme.textTheme.titleSmall?.tabular,
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// 8.000 → 8, 3.750 → 3.75. Stock is entered by people, not machines.
  static String _qty(double v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toString().replaceFirst(RegExp(r'0+$'), '');
}

/// Two per row on a phone, four on a tablet held wide.
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 4 : 2;
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
    required this.foot,
    this.delta,
    this.warn = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String foot;
  final double? delta;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final up = (delta ?? 0) >= 0;

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
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.tabular.copyWith(
                fontWeight: FontWeight.w700,
                color: warn ? semantic.warningText : null,
              ),
            ),
            if (delta != null) ...[
              const SizedBox(height: 4),
              // Arrow *and* sign, so the direction survives greyscale.
              Row(
                children: [
                  Icon(
                    up ? Icons.trending_up : Icons.trending_down,
                    size: 14,
                    color: up ? semantic.goodText : semantic.dangerText,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${up ? '+' : ''}${delta!.toStringAsFixed(1)}%',
                    style: theme.textTheme.labelMedium?.tabular.copyWith(
                      color: up ? semantic.goodText : semantic.dangerText,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Text(
              foot,
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.empty,
    required this.children,
  });

  final String title;
  final String subtitle;

  /// What to say when there is nothing — never "No data".
  final String empty;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          Text(subtitle, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          if (children.isEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(empty, style: theme.textTheme.bodyMedium),
              ),
            )
          else
            Card(
              margin: EdgeInsets.zero,
              child: Column(children: children),
            ),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.leading,
    required this.title,
    required this.trailing,
    this.subtitle,
  });

  final Widget leading;
  final String title;
  final Widget trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }
}

/// Signed in, in a restaurant, without `reports.view`. A real state for a
/// kitchen or inventory role — say which, and who can change it.
class _NoReportsAccess extends StatelessWidget {
  const _NoReportsAccess();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Centered(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('No access to reports', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            "Your role in this restaurant doesn't include seeing revenue. An "
            'owner or manager can change that on the web app under Team.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// No sales, no orders, no history — a restaurant that hasn't opened yet, not a
/// broken screen. Teach the next step.
class _NothingYet extends StatelessWidget {
  const _NothingYet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.insights_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Nothing has been sold yet. Take an order and settle a bill, '
                'and today’s figures appear here.',
                style: theme.textTheme.bodyMedium,
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
    final scheme = theme.colorScheme;
    return _Centered(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 36, color: scheme.error),
          const SizedBox(height: 12),
          Text(
            "Couldn't load the dashboard",
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'It needs a connection — unlike taking orders, which works offline. '
            'Check coverage and try again.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Inside a RefreshIndicator: a non-scrollable child cannot be pulled, so
    // these states would trap a user with no way to retry by gesture.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(padding: const EdgeInsets.all(32), child: child),
          ),
        ),
      ),
    );
  }
}
