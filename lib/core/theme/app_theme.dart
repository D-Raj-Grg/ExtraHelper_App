import 'package:flutter/material.dart';

import 'tokens.dart';

/// The app's Material 3 themes, carrying the ported design system.
///
/// One widget tree for both platforms — no Cupertino fork. For a staff tool
/// read at arm's length mid-service, legibility and consistency with the web
/// app beat platform idiom.
class AppTheme {
  const AppTheme._();

  static const fontFamily = 'Figtree';

  /// Figtree ships as a variable font, so weight is applied through the `wght`
  /// axis. `fontWeight` alone would leave every style at the default instance
  /// on platforms that don't map it automatically.
  static List<FontVariation> _wght(double w) => [FontVariation('wght', w)];

  static ThemeData light() => _build(
    brightness: Brightness.light,
    scheme: const ColorScheme.light(
      primary: Tokens.lightPrimary,
      onPrimary: Tokens.lightPrimaryForeground,
      secondary: Tokens.lightSecondary,
      onSecondary: Tokens.lightSecondaryForeground,
      surface: Tokens.lightBackground,
      onSurface: Tokens.lightForeground,
      surfaceContainerLow: Tokens.lightCard,
      surfaceContainerHighest: Tokens.lightMuted,
      onSurfaceVariant: Tokens.lightMutedForeground,
      error: Tokens.lightDestructive,
      onError: Colors.white,
      outline: Tokens.lightBorder,
      outlineVariant: Tokens.lightBorder,
    ),
    semantic: SemanticColors.light(),
    ring: Tokens.lightRing,
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    scheme: const ColorScheme.dark(
      primary: Tokens.darkPrimary,
      onPrimary: Tokens.darkPrimaryForeground,
      secondary: Tokens.darkSecondary,
      onSecondary: Tokens.darkSecondaryForeground,
      surface: Tokens.darkBackground,
      onSurface: Tokens.darkForeground,
      surfaceContainerLow: Tokens.darkCard,
      surfaceContainerHighest: Tokens.darkMuted,
      onSurfaceVariant: Tokens.darkMutedForeground,
      error: Tokens.darkDestructive,
      onError: Colors.black,
      outline: Tokens.darkBorder,
      outlineVariant: Tokens.darkBorder,
    ),
    semantic: SemanticColors.dark(),
    ring: Tokens.darkRing,
  );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required SemanticColors semantic,
    required Color ring,
  }) {
    final base = ThemeData(brightness: brightness, colorScheme: scheme);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      extensions: [semantic],
      textTheme: _textTheme(base.textTheme, scheme),

      // ≥44px everywhere a finger lands. Material's defaults are smaller, and
      // this gets hit one-handed in a hurry.
      materialTapTargetSize: MaterialTapTargetSize.padded,

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(Tokens.tapTarget, Tokens.tapTarget),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
            fontVariations: _wght(600),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(Tokens.tapTarget, Tokens.tapTarget),
          side: BorderSide(color: scheme.outline, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(Tokens.tapTarget, Tokens.tapTarget),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(Tokens.tapTarget, Tokens.tapTarget),
        ),
      ),

      cardTheme: CardThemeData(
        color: brightness == Brightness.light
            ? Tokens.lightCard
            : Tokens.darkCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outline),
          borderRadius: BorderRadius.circular(Tokens.radiusLg),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light
            ? Tokens.lightCard
            : Tokens.darkCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          borderSide: BorderSide(color: scheme.outline, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          borderSide: BorderSide(color: scheme.outline, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          borderSide: BorderSide(color: ring, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
        ),
      ),

      dividerTheme: DividerThemeData(color: scheme.outline, space: 1),
    );
  }

  static TextTheme _textTheme(TextTheme base, ColorScheme scheme) {
    TextStyle style(TextStyle? s, double size, double weight, {Color? color}) {
      return (s ?? const TextStyle()).copyWith(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: FontWeight.values.firstWhere(
          (w) => w.value >= weight,
          orElse: () => FontWeight.w900,
        ),
        fontVariations: _wght(weight),
        color: color ?? scheme.onSurface,
        height: 1.25,
      );
    }

    return base.copyWith(
      headlineLarge: style(base.headlineLarge, 30, 700),
      headlineMedium: style(base.headlineMedium, 26, 700),
      headlineSmall: style(base.headlineSmall, 22, 700),
      titleLarge: style(base.titleLarge, 20, 600),
      titleMedium: style(base.titleMedium, 17, 600),
      titleSmall: style(base.titleSmall, 15, 600),
      bodyLarge: style(base.bodyLarge, 16, 400),
      bodyMedium: style(base.bodyMedium, 15, 400),
      bodySmall: style(base.bodySmall, 13, 400, color: scheme.onSurfaceVariant),
      labelLarge: style(base.labelLarge, 15, 600),
      labelMedium: style(base.labelMedium, 13, 600),
      labelSmall: style(
        base.labelSmall,
        12,
        600,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// Tabular figures for anything that sits in a column — this is a money app,
/// and prices that shift width as digits change are unreadable in a list.
const tabularFigures = [FontFeature.tabularFigures()];

extension MoneyTextStyle on TextStyle {
  /// Apply tabular figures. Use on every figure in a column.
  TextStyle get tabular => copyWith(fontFeatures: tabularFigures);
}
