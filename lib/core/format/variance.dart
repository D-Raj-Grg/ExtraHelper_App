import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// How a cash drawer's variance should be described.
///
/// Variance is `counted − expected` (see `close_cash_session`): negative means
/// the drawer came up short, positive means it was over. Both are worth a
/// second look, but only short is a loss — so they do not share a colour.
///
/// The word is not decoration. Colour alone cannot carry short-vs-over: red
/// against green is the most common colourblindness, and this is the one figure
/// on the sheet where getting the direction wrong costs someone money. Render
/// [label] beside the signed amount, always.
///
/// Ported from the web's `components/cash/variance.ts`, which the day-close
/// sheet and the Cash page share for the same reason: the same number must not
/// be described two different ways on two screens.
enum VarianceTone { balanced, short, over }

class VarianceStyle {
  const VarianceStyle(this.label, this.tone);

  final String label;
  final VarianceTone tone;

  Color color(BuildContext context) {
    final semantic = context.semantic;
    return switch (tone) {
      VarianceTone.balanced => semantic.goodText,
      VarianceTone.short => semantic.dangerText,
      VarianceTone.over => semantic.warningText,
    };
  }
}

VarianceStyle variance(int cents) {
  if (cents == 0) return const VarianceStyle('Balanced', VarianceTone.balanced);
  if (cents < 0) return const VarianceStyle('Short', VarianceTone.short);
  return const VarianceStyle('Over', VarianceTone.over);
}
