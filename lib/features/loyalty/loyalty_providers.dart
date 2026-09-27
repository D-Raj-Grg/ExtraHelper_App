import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/supabase/customers_repository.dart';
import '../tenant/tenant_providers.dart';

/// What is typed into the Customers search box. Empty means "the newest
/// guests plus every debtor" — see [CustomersRepository.overview].
class CrmSearch extends Notifier<String> {
  @override
  String build() {
    ref.watch(activeTenantProvider); // A search means nothing across tenants.
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
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) throw StateError('No restaurant selected.');
  final query = ref.watch(crmSearchProvider);
  return ref
      .watch(customersRepositoryProvider(tenant.tenantId))
      .overview(query: query);
});

/// One guest's bills, newest first (`customer_bill_history`).
final customerHistoryProvider = FutureProvider.autoDispose
    .family<List<CustomerBillRow>, String>((ref, customerId) async {
      final tenant = ref.watch(activeTenantProvider);
      if (tenant == null) throw StateError('No restaurant selected.');
      return ref
          .watch(customersRepositoryProvider(tenant.tenantId))
          .history(customerId);
    });
