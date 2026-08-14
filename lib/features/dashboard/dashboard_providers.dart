import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/supabase/dashboard_repository.dart';
import '../tenant/tenant_providers.dart';

/// Windows an owner actually asks for. Mirrors the web dashboard's chips, so
/// "last 30 days" means the same number on both screens.
const dashboardWindows = [7, 14, 30, 90];

/// The chosen window. Deliberately **not** persisted: this is a glance, and the
/// next glance starts from the default rather than from whatever was tapped
/// last week.
class DashboardWindow extends Notifier<int> {
  @override
  int build() => 14;

  void select(int days) {
    if (dashboardWindows.contains(days)) state = days;
  }
}

final dashboardWindowProvider = NotifierProvider<DashboardWindow, int>(
  DashboardWindow.new,
);

/// The dashboard, for the active restaurant and the chosen window.
///
/// **Network-only, by design.** Every other read in this app is cache-first
/// because a waiter must take orders on dead wifi; this one is an owner
/// glancing at today's money, and a stale number here is worse than an honest
/// "couldn't load". The POS remains the offline surface.
final dashboardSummaryProvider = FutureProvider.autoDispose<DashboardSummary>((
  ref,
) async {
  final tenant = ref.watch(activeTenantProvider);
  if (tenant == null) throw const DashboardForbidden();
  final days = ref.watch(dashboardWindowProvider);
  return ref
      .watch(dashboardRepositoryProvider(tenant.tenantId))
      .summary(days: days);
});
