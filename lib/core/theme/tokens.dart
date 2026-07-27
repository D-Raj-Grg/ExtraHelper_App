import 'package:flutter/material.dart';

/// Design tokens, ported from the web app's `app/globals.css`.
///
/// The web defines these in oklch; the values below are the same colours
/// converted to sRGB, so the two clients are recognisably one product rather
/// than two eyeballed approximations. **Do not hand-tune these** — if the web
/// palette changes, re-convert.
///
/// Tinted neutrals throughout, never pure black (see `../../CLAUDE.md`).
class Tokens {
  const Tokens._();

  // --- Light ---------------------------------------------------------------
  static const lightBackground = Color(0xFFFFFFFF);
  static const lightForeground = Color(0xFF0C090C);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightCardForeground = Color(0xFF0C090C);
  static const lightPrimary = Color(0xFF8200DB);
  static const lightPrimaryForeground = Color(0xFFFAF5FF);
  static const lightSecondary = Color(0xFFF4F4F5);
  static const lightSecondaryForeground = Color(0xFF18181B);
  static const lightMuted = Color(0xFFF3F1F3);
  static const lightMutedForeground = Color(0xFF79697B);
  static const lightDestructive = Color(0xFFE7000B);
  static const lightBorder = Color(0xFFE7E4E7);
  static const lightRing = Color(0xFFA89EA9);

  // --- Dark ----------------------------------------------------------------
  static const darkBackground = Color(0xFF0C090C);
  static const darkForeground = Color(0xFFFAFAFA);
  static const darkCard = Color(0xFF1D161E);
  static const darkCardForeground = Color(0xFFFAFAFA);
  static const darkPrimary = Color(0xFF6E11B0);
  static const darkPrimaryForeground = Color(0xFFFAF5FF);
  static const darkSecondary = Color(0xFF27272A);
  static const darkSecondaryForeground = Color(0xFFFAFAFA);
  static const darkMuted = Color(0xFF2A212C);
  static const darkMutedForeground = Color(0xFFA89EA9);
  static const darkDestructive = Color(0xFFFF6467);
  static const darkBorder = Color(0x1AFFFFFF); // white @ 10%
  static const darkRing = Color(0xFF79697B);

  // --- Semantic hues -------------------------------------------------------
  // One meaning, one hue, app-wide — matching the web's Tailwind usage:
  //   emerald = good/free · amber = warning/occupied · destructive = error
  //   blue = reserved/info · orange = bill requested
  // Never used alone: every state pairs these with an icon, label, or shape.
  static const emerald400 = Color(0xFF34D399);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);

  static const amber400 = Color(0xFFFBBF24);
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);

  static const blue400 = Color(0xFF60A5FA);
  static const blue500 = Color(0xFF3B82F6);
  static const blue600 = Color(0xFF2563EB);
  static const blue700 = Color(0xFF1D4ED8);

  static const orange400 = Color(0xFFFB923C);
  static const orange500 = Color(0xFFF97316);
  static const orange600 = Color(0xFFEA580C);
  static const orange700 = Color(0xFFC2410C);

  /// Minimum interactive size. Staff hit these one-handed, mid-service, in a
  /// hurry — Material's defaults are smaller, so this is set explicitly
  /// everywhere it matters.
  static const double tapTarget = 44;

  static const double radiusSm = 6;
  static const double radiusMd = 10;
  static const double radiusLg = 14;
}

/// Semantic colours resolved for the current brightness.
///
/// A `ThemeExtension` rather than loose constants so call sites read
/// `context.semantic.good` and can never reach for a raw `Colors.green` —
/// which is the rule the web enforces with tokens-only Tailwind classes.
@immutable
class SemanticColors extends ThemeExtension<SemanticColors> {
  const SemanticColors({
    required this.good,
    required this.goodText,
    required this.warning,
    required this.warningText,
    required this.danger,
    required this.dangerText,
    required this.info,
    required this.infoText,
    required this.attention,
    required this.attentionText,
    required this.neutral,
  });

  /// Good / balanced / free.
  final Color good;
  final Color goodText;

  /// Warning / low stock / occupied / over.
  final Color warning;
  final Color warningText;

  /// Error / short / loss.
  final Color danger;
  final Color dangerText;

  /// Informational / reserved.
  final Color info;
  final Color infoText;

  /// Attention / bill requested.
  final Color attention;
  final Color attentionText;

  /// Inert states (cleaning, closed, cancelled).
  final Color neutral;

  factory SemanticColors.light() => const SemanticColors(
    good: Tokens.emerald500,
    goodText: Tokens.emerald700,
    warning: Tokens.amber500,
    warningText: Tokens.amber700,
    danger: Tokens.lightDestructive,
    dangerText: Tokens.lightDestructive,
    info: Tokens.blue500,
    infoText: Tokens.blue700,
    attention: Tokens.orange500,
    attentionText: Tokens.orange700,
    neutral: Tokens.lightMutedForeground,
  );

  factory SemanticColors.dark() => const SemanticColors(
    good: Tokens.emerald500,
    goodText: Tokens.emerald400,
    warning: Tokens.amber500,
    warningText: Tokens.amber400,
    danger: Tokens.darkDestructive,
    dangerText: Tokens.darkDestructive,
    info: Tokens.blue500,
    infoText: Tokens.blue400,
    attention: Tokens.orange500,
    attentionText: Tokens.orange400,
    neutral: Tokens.darkMutedForeground,
  );

  @override
  SemanticColors copyWith({
    Color? good,
    Color? goodText,
    Color? warning,
    Color? warningText,
    Color? danger,
    Color? dangerText,
    Color? info,
    Color? infoText,
    Color? attention,
    Color? attentionText,
    Color? neutral,
  }) {
    return SemanticColors(
      good: good ?? this.good,
      goodText: goodText ?? this.goodText,
      warning: warning ?? this.warning,
      warningText: warningText ?? this.warningText,
      danger: danger ?? this.danger,
      dangerText: dangerText ?? this.dangerText,
      info: info ?? this.info,
      infoText: infoText ?? this.infoText,
      attention: attention ?? this.attention,
      attentionText: attentionText ?? this.attentionText,
      neutral: neutral ?? this.neutral,
    );
  }

  @override
  SemanticColors lerp(ThemeExtension<SemanticColors>? other, double t) {
    if (other is! SemanticColors) return this;
    return SemanticColors(
      good: Color.lerp(good, other.good, t)!,
      goodText: Color.lerp(goodText, other.goodText, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningText: Color.lerp(warningText, other.warningText, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerText: Color.lerp(dangerText, other.dangerText, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoText: Color.lerp(infoText, other.infoText, t)!,
      attention: Color.lerp(attention, other.attention, t)!,
      attentionText: Color.lerp(attentionText, other.attentionText, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
    );
  }
}

extension SemanticColorsX on BuildContext {
  /// Semantic palette for the current theme. Falls back to the light set so a
  /// widget tested without the app theme still renders.
  SemanticColors get semantic =>
      Theme.of(this).extension<SemanticColors>() ?? SemanticColors.light();
}
