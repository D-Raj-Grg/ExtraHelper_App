import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scaffold.dart';
import '../../app/router.dart';
import '../../core/format/money.dart';
import '../../core/format/when.dart';
import '../../core/widgets/notice.dart';
import '../../data/supabase/customers_repository.dart';
import '../tenant/tenant_providers.dart';
import 'loyalty_providers.dart';

/// Who comes back, who owes, and what they said on the way out.
///
/// Debtors sort to the top on purpose: the person opening this screen at the
/// counter is usually asking "does this guest have a tab?", and the list has
/// to answer before they finish typing the name.
class LoyaltyScreen extends ConsumerStatefulWidget {
  const LoyaltyScreen({super.key});

  @override
  ConsumerState<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends ConsumerState<LoyaltyScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(crmSearchProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.read(crmSearchProvider.notifier).set(value.trim());
    });
  }

  void _refresh() => ref.invalidate(crmOverviewProvider);

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(identityStatusProvider);
    final canView = ref.watch(hasPermissionProvider('loyalty.view'));

    return AppScaffold(
      title: 'Customers',
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
        IdentityStatus.ready when !canView => const _NoAccess(),
        IdentityStatus.ready => _Body(
          search: _search,
          onSearch: _onSearch,
          onRefresh: _refresh,
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.search,
    required this.onSearch,
    required this.onRefresh,
  });

  final TextEditingController search;
  final ValueChanged<String> onSearch;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(activeTenantProvider)?.currency ?? 'USD';
    final query = ref.watch(crmSearchProvider);
    final searching = query.isNotEmpty;
    final overview = ref.watch(crmOverviewProvider);

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          TextField(
            controller: search,
            onChanged: onSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search name, phone or email',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: searching || search.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        search.clear();
                        onSearch('');
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          ...overview.when(
            loading: () => const [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
            error: (e, _) => [_Problem(message: '$e', onRetry: onRefresh)],
            data: (o) => [
              if (!searching) ...[
                _CreditBanner(overview: o, currency: currency),
                const SizedBox(height: 12),
              ],
              if (o.customers.isEmpty)
                _Empty(searching: searching)
              else
                for (final c in o.customers)
                  _CustomerTile(
                    key: ValueKey(c.id),
                    customer: c,
                    currency: currency,
                  ),
              if (!searching) ...[
                const SizedBox(height: 20),
                _FeedbackSection(rows: o.feedback.take(20).toList()),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CreditBanner extends StatelessWidget {
  const _CreditBanner({required this.overview, required this.currency});

  final CrmOverview overview;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owed = overview.totalOwedCents > 0;
    final tone = owed
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    final n = overview.debtors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: owed
            ? theme.colorScheme.error.withValues(alpha: 0.08)
            : theme.colorScheme.surfaceContainerLow,
        border: Border.all(
          color: owed ? theme.colorScheme.error : theme.colorScheme.outline,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            owed ? Icons.account_balance_wallet_outlined : Icons.check_circle,
            color: tone,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              owed
                  ? 'Outstanding credit · ${money(overview.totalOwedCents, currency)} '
                        'across $n ${n == 1 ? 'customer' : 'customers'}'
                  : 'No credit outstanding',
              style: theme.textTheme.titleSmall?.copyWith(
                color: tone,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({
    super.key,
    required this.customer,
    required this.currency,
  });

  final CrmCustomer customer;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = customer;
    final muted = theme.colorScheme.onSurfaceVariant;
    final contact = [
      if (c.phone != null && c.phone!.isNotEmpty) c.phone!,
      if (c.email != null && c.email!.isNotEmpty) c.email!,
    ].join(' · ');
    const tabular = [FontFeature.tabularFigures()];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => context.push(Routes.customerPath(c.id)),
        title: Text(
          c.label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: contact.isEmpty
            ? null
            : Text(
                contact,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${c.points} pts',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: tabular,
              ),
            ),
            if (c.owes) ...[
              Text(
                'Owes ${money(c.owesCents, currency)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabular,
                ),
              ),
              Text(
                '${c.unpaidBills} unpaid '
                '${c.unpaidBills == 1 ? 'bill' : 'bills'}',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeedbackSection extends StatelessWidget {
  const _FeedbackSection({required this.rows});

  final List<CustomerFeedback> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text('Feedback', style: theme.textTheme.labelLarge),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              'No feedback yet.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          )
        else
          for (final f in rows)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (f.rating != null)
                          Text(
                            _stars(f.rating!),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              letterSpacing: 1,
                            ),
                          ),
                        if (f.rating != null) const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            f.customerName ?? 'Guest',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          billDate(f.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                    if (f.comment != null && f.comment!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(f.comment!, style: theme.textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
            ),
      ],
    );
  }

  static String _stars(int rating) {
    final r = rating.clamp(0, 5);
    return '${'★' * r}${'☆' * (5 - r)}';
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          const Icon(Icons.people_outline, size: 36),
          const SizedBox(height: 12),
          Text(
            searching ? 'Nobody matches' : 'No customers yet',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            searching
                ? 'Try a shorter name, or part of the phone number.'
                : 'Attach a guest to a bill at checkout and they show up '
                      'here with their points and any tab they run.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('No customer access', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              "Your role in this restaurant doesn't include seeing "
              'customers. An owner or manager can change that under Team.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: RetryNotice(
        message: "Couldn't load customers.",
        detail: message,
        icon: Icons.cloud_off_outlined,
        onRetry: onRetry,
      ),
    );
  }
}
