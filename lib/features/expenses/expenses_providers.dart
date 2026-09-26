import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/supabase/expenses_repository.dart';
import '../../data/sync/outbox.dart';
import '../../data/sync/sync_providers.dart';
import '../tenant/tenant_providers.dart';

/// The day the expenses screen shows: `YYYY-MM-DD`, or null for **today** —
/// the only way to ask for today, since the phone cannot name it (see
/// `day_report_providers.dart`). The server's answer carries `today` back.
class ExpenseDayCursor extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(activeTenantProvider); // A day means nothing across tenants.
    return null;
  }

  void show(String? day) => state = day;
}

final expenseDayCursorProvider = NotifierProvider<ExpenseDayCursor, String?>(
  ExpenseDayCursor.new,
);

/// Network-only: this is what someone signs the night count against.
final expenseDayProvider = FutureProvider.autoDispose<ExpenseDay>((ref) async {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) throw StateError('No restaurant selected.');
  final day = ref.watch(expenseDayCursorProvider);
  return ref.watch(expensesRepositoryProvider(tenant.tenantId)).day(day: day);
});

/// Kept alive for the session so the add sheet still has categories to offer
/// after coverage drops — the write itself queues offline.
final expenseCategoriesProvider = FutureProvider<List<ExpenseCategory>>((
  ref,
) async {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) return const [];
  return ref.watch(expensesRepositoryProvider(tenant.tenantId)).categories();
});

/// Expenses logged on this phone that the server doesn't have yet.
final pendingExpensesProvider = FutureProvider.autoDispose<List<OutboxEntry>>((
  ref,
) async {
  final queue = ref.watch(orderQueueProvider);
  if (queue == null) return const [];
  return queue.pendingExpenses();
});

/// Rolling totals for the last [days] days (`report_expenses`). Null when the
/// caller holds no `reports.view`.
final expenseRangeProvider = FutureProvider.autoDispose
    .family<ExpenseRange?, int>((ref, days) async {
      final tenant = ref.watch(activeTenantProvider);
      if (tenant == null) return null;
      return ref
          .watch(expensesRepositoryProvider(tenant.tenantId))
          .range(span: Duration(days: days));
    });
