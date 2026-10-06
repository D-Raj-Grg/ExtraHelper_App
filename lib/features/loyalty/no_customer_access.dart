import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/notice.dart';
import '../tenant/tenant_providers.dart';

/// The locked door both Customers screens show to someone without
/// `loyalty.view`. One widget, so the list and the detail cannot drift into
/// two different explanations of the same rule.
class NoCustomerAccess extends StatelessWidget {
  const NoCustomerAccess({super.key});

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

/// Gates the Customers screens on the plan's `loyalty` feature, the way the
/// web's `/loyalty` page does (`requireFeature`). Sits *inside* the permission
/// check: someone without `loyalty.view` still gets [NoCustomerAccess].
class LoyaltyFeatureGate extends ConsumerWidget {
  const LoyaltyFeatureGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feature = ref.watch(tenantFeatureProvider('loyalty'));
    return feature.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: RetryNotice(
          message: "Couldn't check your plan.",
          detail: '$e',
          icon: Icons.cloud_off_outlined,
          onRetry: () => ref.invalidate(tenantFeatureProvider('loyalty')),
        ),
      ),
      data: (on) => on ? child : const _PlanLocked(),
    );
  }
}

class _PlanLocked extends StatelessWidget {
  const _PlanLocked();

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
              Icons.workspace_premium_outlined,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Not included in your plan',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              "Customers and loyalty aren't part of this restaurant's current "
              'plan. The owner can upgrade under Billing on the web.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
