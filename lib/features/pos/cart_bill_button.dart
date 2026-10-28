import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// "Generate bill" / "Finish the bill" label for an order, from whether
/// checkout has already opened a bill for it. `create_bill_for_order` is
/// idempotent, so the tap is the same either way; the word should tell the
/// truth about which it is.
String billButtonLabel({required bool hasBill}) =>
    hasBill ? 'Finish the bill' : 'Generate bill';

/// The cart's route to checkout, beside the send button.
///
/// Billing snapshots every line on the order, drafts included, so it waits
/// until the new items are sent ([unsent]) — the same rule as the web's
/// "Generate bill".
class CartBillButton extends StatelessWidget {
  const CartBillButton({
    super.key,
    required this.label,
    required this.unsent,
    required this.busy,
    required this.onPressed,
    this.showHint = true,
    this.padding = const EdgeInsets.fromLTRB(12, 0, 12, 8),
  });

  final String label;
  final bool unsent;
  final bool busy;
  final VoidCallback onPressed;

  /// Show "Send the new items first." above the button. The composer turns
  /// this off and renders the hint in its summary row instead.
  final bool showHint;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (unsent && showHint)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Send the new items first.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, Tokens.tapTarget),
            ),
            onPressed: unsent || busy ? null : onPressed,
            icon: const Icon(Icons.point_of_sale),
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
