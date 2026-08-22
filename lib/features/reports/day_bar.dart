import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'day_report_providers.dart';

/// Which day the sheet is showing, and how to reach the ones either side.
///
/// Prev / next / Today, and no calendar. Material's date picker hands back a
/// **device-local** `DateTime`, which would put the phone's clock in charge of
/// a boundary the server owns — the one thing this feature must never do. The
/// real journey is "close last night's till this morning", which is one tap
/// back; jumping to an arbitrary day is what the web sheet is for.
///
/// Next is disabled at today rather than hidden: a control that vanishes reads
/// as a bug, and a disabled one says "you are already at the end".
class DayBar extends ConsumerWidget {
  const DayBar({super.key, required this.dayLabel});

  /// The server's own words for this day — never formatted here.
  final String dayLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cursor = ref.watch(dayCursorProvider);
    final notifier = ref.read(dayCursorProvider.notifier);

    return Row(
      children: [
        _Step(
          icon: Icons.chevron_left,
          label: 'Previous day',
          onPressed: cursor.canGoBack ? notifier.previous : null,
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                dayLabel,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!cursor.isToday)
                TextButton(
                  onPressed: notifier.today,
                  child: const Text('Back to today'),
                ),
            ],
          ),
        ),
        _Step(
          icon: Icons.chevron_right,
          label: 'Next day',
          // Null when there is no later day — and also while the app has yet
          // to learn what today is, which it cannot work out for itself.
          onPressed: cursor.canGoForward ? notifier.next : null,
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.label, this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      tooltip: label,
      // Material's default is 40px; a manager taps this at a counter.
      iconSize: 28,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }
}
