import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scaffold.dart';
import '../../app/router.dart';
import '../../core/format/money.dart';
import '../../core/format/when.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/notice.dart';
import '../../data/supabase/customers_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../tenant/tenant_providers.dart';
import 'customer_dialogs.dart';
import 'loyalty_providers.dart';
import 'no_customer_access.dart';

/// One regular: what they owe, what they have earned, what they ordered.
///
/// "Collect" on an unpaid bill jumps straight to that bill's checkout — the
/// tab is settled where money is always taken, not from a second surface that
/// would have to reimplement payment.
class CustomerDetailScreen extends ConsumerStatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  final _points = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _points.dispose();
    super.dispose();
  }

  CustomersRepository? get _repo {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null) return null;
    return ref.read(customersRepositoryProvider(tenant.tenantId));
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// After a write: this guest, their bills, and the list behind us all
  /// changed.
  void _refresh() {
    ref.invalidate(customerProvider(widget.customerId));
    ref.invalidate(customerHistoryProvider(widget.customerId));
    ref.invalidate(crmOverviewProvider);
  }

  /// Pull-to-refresh holds its spinner until both loads land.
  Future<void> _reload() => Future.wait([
    ref.refresh(customerProvider(widget.customerId).future),
    ref.refresh(customerHistoryProvider(widget.customerId).future),
  ]);

  /// Runs one repo call; returns true when it went through.
  Future<bool> _run(
    Future<void> Function(CustomersRepository repo) work,
    String success,
  ) async {
    final repo = _repo;
    if (repo == null || _busy) return false;
    setState(() => _busy = true);
    var ok = false;
    String message;
    try {
      await work(repo);
      ok = true;
      message = success;
      _refresh();
    } on PosFailure catch (e) {
      message = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _say(message);
    return ok;
  }

  Future<void> _adjust(String type) async {
    final n = int.tryParse(_points.text.trim());
    if (n == null || n <= 0) {
      _say('Enter how many points.');
      return;
    }
    final ok = await _run(
      (repo) => repo.adjustPoints(
        customerId: widget.customerId,
        points: n,
        type: type,
      ),
      type == 'earn' ? 'Added $n pts.' : 'Redeemed $n pts.',
    );
    if (ok) _points.clear();
  }

  Future<void> _edit(CrmCustomer c) async {
    final draft = await showEditCustomerDialog(context, c);
    if (draft == null) return;
    await _run(
      (repo) => repo.update(
        customerId: c.id,
        name: draft.name,
        phone: draft.phone,
        email: draft.email,
      ),
      'Customer updated.',
    );
  }

  Future<void> _merge(CrmCustomer c) async {
    final repo = _repo;
    if (repo == null) return;
    final keepId = await showMergeCustomerDialog(
      context,
      c,
      search: (q) async => (await repo.overview(query: q)).customers,
    );
    if (keepId == null) return;
    final ok = await _run(
      (repo) => repo.merge(keepId: keepId, dropId: c.id),
      'Merged ${c.label}.',
    );
    if (ok && mounted) context.pop();
  }

  Future<void> _delete(CrmCustomer c) async {
    final sure = await confirmDeleteCustomer(context, c);
    if (!sure) return;
    final ok = await _run((repo) => repo.delete(c.id), 'Deleted ${c.label}.');
    if (ok && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(identityStatusProvider);
    final canView = ref.watch(hasPermissionProvider('loyalty.view'));
    final currency = ref.watch(activeTenantProvider)?.currency ?? 'USD';
    final canEdit = ref.watch(hasPermissionProvider('loyalty.edit'));
    final canCollect = ref.watch(hasPermissionProvider('payment.take'));
    final loaded = ref.watch(customerProvider(widget.customerId));
    // The name sits in the app bar, outside the gates below, so it needs the
    // same gates: it appears only once access and the plan are both confirmed.
    // While the plan check is still loading (or failed) the bar says
    // "Customer" rather than flash a name the body may then lock away.
    final planHasLoyalty =
        ref.watch(tenantFeatureProvider('loyalty')).valueOrNull ?? false;
    final mayShow =
        status == IdentityStatus.ready && canView && planHasLoyalty;
    final customer = mayShow ? loaded.valueOrNull : null;

    return AppScaffold(
      title: customer?.label ?? 'Customer',
      showDrawer: false,
      actions: [
        if (status == IdentityStatus.ready &&
            canView &&
            canEdit &&
            customer != null)
          PopupMenuButton<String>(
            tooltip: 'More',
            enabled: !_busy,
            onSelected: (v) => switch (v) {
              'edit' => _edit(customer),
              'merge' => _merge(customer),
              _ => _delete(customer),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                ),
              ),
              PopupMenuItem(
                value: 'merge',
                child: ListTile(
                  leading: Icon(Icons.merge_outlined),
                  title: Text('Merge into another customer'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Delete'),
                ),
              ),
            ],
          ),
      ],
      // The same door as the list: a deep link to a customer must not
      // show more than the list would.
      body: switch (status) {
        IdentityStatus.unavailable => Padding(
          padding: const EdgeInsets.all(16),
          child: RetryNotice(
            message: "Couldn't check your access.",
            detail: '${ref.watch(identityErrorProvider)}',
            onRetry: () => ref
              ..invalidate(membershipsProvider)
              ..invalidate(permissionsProvider),
          ),
        ),
        IdentityStatus.ready when !canView => const NoCustomerAccess(),
        IdentityStatus.ready => LoyaltyFeatureGate(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: loaded.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  RetryNotice(
                    message: "Couldn't load this customer.",
                    detail: '$e',
                    icon: Icons.cloud_off_outlined,
                    onRetry: _refresh,
                  ),
                ],
              ),
              data: (c) => c == null
                  ? const _NotFound()
                  : _Detail(
                      customer: c,
                      currency: currency,
                      canEdit: canEdit,
                      canCollect: canCollect,
                      busy: _busy,
                      points: _points,
                      onEarn: () => _adjust('earn'),
                      onRedeem: () => _adjust('burn'),
                      history: ref.watch(customerHistoryProvider(c.id)),
                      onRetryHistory: () =>
                          ref.invalidate(customerHistoryProvider(c.id)),
                    ),
            ),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.customer,
    required this.currency,
    required this.canEdit,
    required this.canCollect,
    required this.busy,
    required this.points,
    required this.onEarn,
    required this.onRedeem,
    required this.history,
    required this.onRetryHistory,
  });

  final CrmCustomer customer;
  final String currency;
  final bool canEdit;
  final bool canCollect;
  final bool busy;
  final TextEditingController points;
  final VoidCallback onEarn;
  final VoidCallback onRedeem;
  final AsyncValue<List<CustomerBillRow>> history;
  final VoidCallback onRetryHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        _Header(customer: customer),
        const SizedBox(height: 8),
        _CreditBox(customer: customer, currency: currency),
        if (canEdit) ...[
          const SizedBox(height: 8),
          _PointsRow(
            controller: points,
            busy: busy,
            onEarn: onEarn,
            onRedeem: onRedeem,
          ),
        ],
        const SizedBox(height: 20),
        _SectionLabel('Unpaid bills'),
        ...history.when(
          loading: () => const [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (e, _) => [
            RetryNotice(
              message: "Couldn't load bills.",
              detail: '$e',
              icon: Icons.cloud_off_outlined,
              onRetry: onRetryHistory,
            ),
          ],
          data: (rows) {
            // Buckets follow the bill's *status*, not the amount: an open
            // bill with nothing left to collect is still open, and belongs
            // here until someone closes it at the till. Void rows are gone.
            final unpaid = rows
                .where((r) => r.status == 'open' || r.status == 'partial')
                .toList();
            final paid = rows.where((r) => r.status == 'paid').toList();
            return [
              if (unpaid.isEmpty)
                _Muted('Nothing outstanding.')
              else
                for (final r in unpaid)
                  _BillCard(
                    key: ValueKey(r.billId),
                    row: r,
                    currency: currency,
                    onCollect: canCollect
                        ? () => context.push(Routes.billPath(r.billId))
                        : null,
                  ),
              const SizedBox(height: 20),
              _SectionLabel('Past orders'),
              if (paid.isEmpty)
                _Muted('No paid bills yet.')
              else
                for (final r in paid)
                  Card(
                    key: ValueKey(r.billId),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        '${billDate(r.createdAt)} · '
                        '${money(r.totalCents, currency)}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      subtitle: r.itemsSummary == null
                          ? null
                          : Text(
                              r.itemsSummary!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                  ),
            ];
          },
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.customer});

  final CrmCustomer customer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final c = customer;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (c.phone != null && c.phone!.isNotEmpty)
              _ContactLine(icon: Icons.phone_outlined, text: c.phone!),
            if (c.email != null && c.email!.isNotEmpty)
              _ContactLine(icon: Icons.mail_outline, text: c.email!),
            if ((c.phone == null || c.phone!.isEmpty) &&
                (c.email == null || c.email!.isEmpty))
              Text(
                'No phone or email on file.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Chip(
                  label: Text(_capitalise(c.tier)),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 12),
                Text(
                  '${c.points} pts',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _capitalise(String s) {
    final t = s.trim();
    if (t.isEmpty) return 'Member';
    return t[0].toUpperCase() + t.substring(1).toLowerCase();
  }
}

class _ContactLine extends StatelessWidget {
  const _ContactLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditBox extends StatelessWidget {
  const _CreditBox({required this.customer, required this.currency});

  final CrmCustomer customer;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owes = customer.owesCents > 0;
    final n = customer.unpaidBills;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Outstanding credit',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              money(customer.owesCents, currency),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: owes ? theme.colorScheme.error : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              owes
                  ? 'across $n unpaid ${n == 1 ? 'bill' : 'bills'}'
                  : 'Nothing owed.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PointsRow extends StatelessWidget {
  const _PointsRow({
    required this.controller,
    required this.busy,
    required this.onEarn,
    required this.onRedeem,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onEarn;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Points',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, Tokens.tapTarget),
              ),
              onPressed: busy ? null : onEarn,
              child: const Text('Earn'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, Tokens.tapTarget),
              ),
              onPressed: busy ? null : onRedeem,
              child: const Text('Redeem'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({
    super.key,
    required this.row,
    required this.currency,
    required this.onCollect,
  });

  final CustomerBillRow row;
  final String currency;
  final VoidCallback? onCollect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final r = row;
    final head = [
      billDate(r.createdAt),
      if (r.tableLabel != null && r.tableLabel!.isNotEmpty) r.tableLabel!,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    head,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (r.itemsSummary != null && r.itemsSummary!.isNotEmpty)
                    Text(
                      r.itemsSummary!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: money(r.totalCents, currency)),
                        const TextSpan(text: ' · '),
                        if (r.unpaid)
                          TextSpan(
                            text: 'owes ${money(r.outstandingCents, currency)}',
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        else
                          TextSpan(
                            text: 'nothing left to collect',
                            style: TextStyle(color: muted),
                          ),
                        if (r.paidCents > 0)
                          TextSpan(
                            text: ' (paid ${money(r.paidCents, currency)})',
                            style: TextStyle(color: muted),
                          ),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            if (onCollect != null) ...[
              const SizedBox(width: 8),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, Tokens.tapTarget),
                ),
                onPressed: onCollect,
                child: const Text('Collect'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const Icon(Icons.person_off_outlined, size: 36),
        const SizedBox(height: 12),
        Text(
          'Customer not found',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'They may have been merged or deleted.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton(
            onPressed: () => context.pop(),
            child: const Text('Back'),
          ),
        ),
      ],
    );
  }
}
