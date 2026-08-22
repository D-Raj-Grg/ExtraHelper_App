import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/supabase/day_report_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../../data/supabase/settings_repository.dart';
import '../pos/bill_providers.dart';
import '../pos/pos_providers.dart';
import '../tenant/tenant_providers.dart';
import 'day_report_providers.dart';

/// When this restaurant's trading day starts.
///
/// Lives on the day-close sheet rather than in a settings screen because this
/// is where the setting is legible: the line above says "trading day runs 4:00
/// am to 4:00 am", and this is how that line changes.
///
/// Owner and manager only — the same set `tenant_settings_owner_write` allows,
/// so the UI asks exactly what RLS will.
class DayCutoffCard extends ConsumerStatefulWidget {
  const DayCutoffCard({super.key, required this.report});

  final DayReport report;

  @override
  ConsumerState<DayCutoffCard> createState() => _DayCutoffCardState();
}

class _DayCutoffCardState extends ConsumerState<DayCutoffCard> {
  bool _busy = false;

  Future<void> _change(int minutes) async {
    if (_busy || minutes == widget.report.cutoffMinutes) return;

    final label = dayCutoffOptions[minutes] ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Start the day at $label?'),
        // Names the real consequence: this is not destructive, but it is
        // retroactive, which surprises people more.
        content: const Text(
          'Every past day re-buckets. Reports, this sheet and the POS '
          'Completed tab all turn over at the new time, and a sale rung up '
          'before it will count towards the day before.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Change it'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final tenant = ref.read(activeTenantProvider);
    String message;
    try {
      if (tenant == null) {
        message = 'No restaurant selected.';
      } else {
        await ref
            .read(settingsRepositoryProvider(tenant.tenantId))
            .setDayCutoff(minutes);
        message = 'The trading day now starts at $label.';

        // Everything downstream of `tenant_day_start` just changed its answer.
        ref.invalidate(dayReportProvider);
        ref.invalidate(completedOrdersProvider);
        ref.invalidate(filteredBillsProvider);
      }
    } on PosFailure catch (e) {
      message = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(isManagerProvider)) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final current = widget.report.cutoffMinutes;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Day starts at',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'A sale at 1:30 am counts towards the night before when the day '
              'starts later than midnight.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in dayCutoffOptions.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: entry.key == current,
                    onSelected: _busy ? null : (_) => _change(entry.key),
                    // Mid-service thumbs, not a desk.
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
