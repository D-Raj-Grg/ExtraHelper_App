import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/money.dart';
import '../tenant/tenant_providers.dart';
import 'coupons_providers.dart';

/// The web's stats row: how many campaigns are in each state, plus how often
/// they were used and what they have given away. Hidden while loading, on a
/// failure, and when there are no coupons — the list below owns those states.
class CouponStatsStrip extends ConsumerWidget {
  const CouponStatsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(couponStatsProvider).valueOrNull;
    if (stats == null || stats.total == 0) return const SizedBox.shrink();
    final currency = ref.watch(activeTenantProvider)?.currency ?? 'USD';
    final theme = Theme.of(context);
    const tabular = [FontFeature.tabularFigures()];

    final tiles = <(String, String)>[
      ('Active', '${stats.active}'),
      ('Scheduled', '${stats.scheduled}'),
      ('Expired', '${stats.expired}'),
      ('Used up', '${stats.usedUp}'),
      ('Paused', '${stats.paused}'),
      ('Redemptions', '${stats.redemptions}'),
      ('Given away', money(stats.discountGivenCents, currency)),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (label, value) in tiles)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 96),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        value,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: tabular,
                        ),
                      ),
                      Text(
                        label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
