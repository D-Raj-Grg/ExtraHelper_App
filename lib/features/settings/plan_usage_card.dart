import 'package:flutter/material.dart';

import '../../data/supabase/danger_repository.dart';

/// What the restaurant is using, against what its plan allows.
///
/// Shared by the plan screen and the dangerous area so the two never disagree
/// about the numbers — they come from one query either way.
class PlanUsageCard extends StatelessWidget {
  const PlanUsageCard({super.key, required this.usage});

  final ResourceUsage usage;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Usage',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            _UsageRow(
              label: 'Customers',
              used: usage.customers,
              limit: usage.customersLimit,
            ),
            _UsageRow(
              label: 'Tables',
              used: usage.tables,
              limit: usage.tablesLimit,
            ),
            _UsageRow(
              label: 'Staff',
              used: usage.staff,
              limit: usage.staffLimit,
            ),
            _UsageRow(
              label: 'Menu items',
              used: usage.menuItems,
              limit: usage.menuItemsLimit,
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.label, required this.used, this.limit});

  final String label;
  final int used;

  /// Null means no ceiling — a trial, or a plan that does not name this one.
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            limit == null ? '$used' : '$used of $limit',
            // Tabular so four rows of numbers line up rather than shuffling
            // with the digit widths.
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
