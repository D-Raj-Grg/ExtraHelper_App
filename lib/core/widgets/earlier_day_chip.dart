import 'package:flutter/material.dart';

import '../format/when.dart';
import '../theme/tokens.dart';

/// "From Aug 19" — a bill or order carried over from an earlier day.
///
/// An unpaid bill deliberately survives midnight (a debt from last night is
/// still a debt this morning), and until now nothing on the card said which
/// night it was from. That is what made staff read a stale bill as one that
/// "didn't clear".
class EarlierDayChip extends StatelessWidget {
  const EarlierDayChip({super.key, required this.at});

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final color = semantic.attentionText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(Tokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon as well as colour: this has to survive greyscale.
          Icon(Icons.history, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'From ${billDate(at)}',
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
