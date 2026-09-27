import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/supabase/customers_repository.dart';
import '../tenant/tenant_providers.dart';

// Every provider here keys off the tenant *id*, not the Membership object:
// `Membership` has no `==`, so a refetched-but-identical membership would
// otherwise read as a change and reset the search or refire every load.

/// What is typed into the Customers search box. Empty means "the newest
/// guests plus every debtor" — see [CustomersRepository.overview].
class CrmSearch extends Notifier<String> {
  @override
  String build() {
    // A search means nothing across tenants.
    ref.watch(activeTenantProvider.select((m) => m?.tenantId));
    return '';
  }

  void set(String q) => state = q;
}

final crmSearchProvider = NotifierProvider<CrmSearch, String>(CrmSearch.new);

/// Network-only: debts and points are money, and a stale figure here is a
/// wrong figure.
final crmOverviewProvider = FutureProvider.autoDispose<CrmOverview>((
  ref,
) async {
  final tenantId = ref.watch(activeTenantProvider.select((m) => m?.tenantId));
  if (tenantId == null) throw StateError('No restaurant selected.');
  final query = ref.watch(crmSearchProvider);
  return ref
      .watch(customersRepositoryProvider(tenantId))
      .overview(query: query);
});

/// One guest with their credit — null when no such row is in this tenant
/// (merged away, deleted, or a stale link).
final customerProvider = FutureProvider.autoDispose
    .family<CrmCustomer?, String>((ref, customerId) async {
      final tenantId = ref.watch(
        activeTenantProvider.select((m) => m?.tenantId),
      );
      if (tenantId == null) throw StateError('No restaurant selected.');
      return ref
          .watch(customersRepositoryProvider(tenantId))
          .customer(customerId);
    });

/// One guest's bills, newest first (`customer_bill_history`).
final customerHistoryProvider = FutureProvider.autoDispose
    .family<List<CustomerBillRow>, String>((ref, customerId) async {
      final tenantId = ref.watch(
        activeTenantProvider.select((m) => m?.tenantId),
      );
      if (tenantId == null) throw StateError('No restaurant selected.');
      return ref
          .watch(customersRepositoryProvider(tenantId))
          .history(customerId);
    });
