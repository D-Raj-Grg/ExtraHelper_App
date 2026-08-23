import '../../data/supabase/settings_repository.dart';

/// Parsing and validation for the charges screen. Pure — no Flutter, no
/// network — so the rules can be tested without a widget or a server.
///
/// The sentences are the web's, word for word (`app/(app)/settings/actions.ts`
/// and `charges-tab.tsx`): the same mistake made on a phone and on a laptop
/// should be corrected the same way.

/// A percentage of the bill, added to dine-in orders.
String? validateServiceCharge(String raw) {
  final value = double.tryParse(raw.trim());
  if (value == null) return 'Service charge must be a number.';
  if (value.isNaN || value < 0 || value > 100) {
    return 'Service charge must be between 0 and 100.';
  }
  return null;
}

/// A flat fee on takeaway and delivery, in currency units — not cents.
String? validatePackagingFee(String raw) {
  final value = double.tryParse(raw.trim());
  if (value == null) return 'Packaging fee must be a number.';
  if (value.isNaN || value < 0) return "Packaging fee can't be negative.";
  return null;
}

String? validateTaxRuleName(String raw) =>
    raw.trim().isEmpty ? 'Give the rule a name.' : null;

String? validateTaxRuleRate(String raw) {
  final value = double.tryParse(raw.trim());
  if (value == null) return 'Rate must be a number.';
  if (value.isNaN || value < 0 || value > 100) {
    return 'Rate must be between 0 and 100.';
  }
  return null;
}

/// `12.50` rather than `12.5` reads as money; `13` rather than `13.0` reads as
/// a rate. Percentages keep their trailing zeros only when they have a
/// fraction to show.
String formatRate(double rate) {
  if (rate == rate.roundToDouble()) return rate.toStringAsFixed(0);
  return rate.toString();
}

String formatFee(double fee) => fee.toStringAsFixed(2);

/// A tax rule plus an identity that survives editing it.
///
/// The list is keyed on [id], never on the rule's contents: two rules can
/// legitimately be called the same thing mid-edit, and a key derived from the
/// name moves the caret to another row the moment someone types.
class TaxRuleDraft {
  const TaxRuleDraft(this.id, this.rule);

  final int id;
  final TaxRule rule;

  TaxRuleDraft withRule(TaxRule next) => TaxRuleDraft(id, next);
}

/// Describes a rule in one line, the way the list row does.
String describeTaxRule(TaxRule rule) =>
    '${formatRate(rule.rate)}% · ${rule.inclusive ? 'Inclusive' : 'Exclusive'}';
