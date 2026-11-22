import 'package:flutter/material.dart';

import 'tryton_colors.dart';

enum AppTheme {
  blackMamba,
  polarFox,
  greenViper,
  blueGlacier,
  redLove,
  yellowCitrine,
  blueOcean,
}

extension AppThemeX on AppTheme {
  String get label => switch (this) {
        AppTheme.blackMamba => 'Black Mamba',
        AppTheme.polarFox => 'Polar Fox',
        AppTheme.greenViper => 'Green Viper',
        AppTheme.blueGlacier => 'Blue Glacier',
        AppTheme.redLove => 'Red Love',
        AppTheme.yellowCitrine => 'Yellow Citrine',
        AppTheme.blueOcean => 'Blue Ocean',
      };

  Color get seedColor => switch (this) {
        AppTheme.blackMamba => const Color(0xFF0055A5),
        AppTheme.polarFox => const Color(0xFF78909C),
        AppTheme.greenViper => const Color(0xFF1B5E20),
        AppTheme.blueGlacier => const Color(0xFF0277BD),
        AppTheme.redLove => const Color(0xFFC62828),
        AppTheme.yellowCitrine => const Color(0xFFF57F17),
        AppTheme.blueOcean => const Color(0xFF2774FA),
      };

  Brightness get brightness => switch (this) {
        AppTheme.blackMamba => Brightness.dark,
        AppTheme.polarFox => Brightness.light,
        AppTheme.greenViper => Brightness.dark,
        AppTheme.blueGlacier => Brightness.light,
        AppTheme.redLove => Brightness.dark,
        AppTheme.yellowCitrine => Brightness.light,
        AppTheme.blueOcean => Brightness.light,
      };

  /// The colour scheme: Blue Ocean has explicit SAO colours (spec T5),
  /// the others derive it from their seed.
  ColorScheme get colorScheme => switch (this) {
        AppTheme.blueOcean => const ColorScheme.light(
            primary: Color(0xFF2774FA),
            onPrimary: Colors.white,
            primaryContainer: Color(0xFFACCFFD),
            onPrimaryContainer: Color(0xFF274C77),
            secondary: Color(0xFF274C77),
            onSecondary: Colors.white,
            secondaryContainer: Color(0xFFB4CEFD),
            onSecondaryContainer: Color(0xFF274C77),
            surface: Colors.white,
            onSurface: Color(0xFF333333),
            onSurfaceVariant: Color(0xFF555555),
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: Color(0xFFFCFCFC),
            surfaceContainer: Color(0xFFF8F8F8),
            surfaceContainerHigh: Color(0xFFF8F8F8),
            surfaceContainerHighest: Color(0xFFF8F8F8),
            // hint texts and counters stay readable (#DDD: only lines)
            outline: Color(0xFF777777),
            outlineVariant: Color(0xFFDDDDDD),
          ),
        _ => ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness),
      };

  /// The colours of the Tryton areas: Blue Ocean the SAO ones, the others
  /// those of their scheme (unchanged look).
  TrytonColors trytonColors(ColorScheme cs) => switch (this) {
        AppTheme.blueOcean => TrytonColors.blueOcean,
        _ => TrytonColors.fromScheme(cs),
      };

  ThemeData buildThemeData() {
    final cs = colorScheme;
    const kRadius = BorderRadius.all(Radius.circular(4));
    const kShape = RoundedRectangleBorder(borderRadius: kRadius);
    return ThemeData(
      colorScheme: cs,
      // the Tryton areas keep the colours of the scheme (spec T5)
      extensions: [trytonColors(cs)],
      useMaterial3: true,
      fontFamily: 'Lato',
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        // the field underline light like SAO (#DDD: outlineVariant),
        // focused in the primary colour – every theme (same form)
        activeIndicatorBorder: WidgetStateBorderSide.resolveWith((states) =>
            states.contains(WidgetState.error)
                ? BorderSide(color: cs.error)
                : states.contains(WidgetState.focused)
                    ? BorderSide(color: cs.primary, width: 2)
                    : BorderSide(color: cs.outlineVariant)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: kShape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: kShape),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: kShape),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(shape: kShape),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(shape: kShape),
      ),
    );
  }
}
