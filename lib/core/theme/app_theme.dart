import 'package:flutter/material.dart';

enum AppTheme {
  blackMamba,
  polarFox,
  greenViper,
  blueGlacier,
  redLove,
  yellowCitrine,
}

extension AppThemeX on AppTheme {
  String get label => switch (this) {
        AppTheme.blackMamba => 'Black Mamba',
        AppTheme.polarFox => 'Polar Fox',
        AppTheme.greenViper => 'Green Viper',
        AppTheme.blueGlacier => 'Blue Glacier',
        AppTheme.redLove => 'Red Love',
        AppTheme.yellowCitrine => 'Yellow Citrine',
      };

  Color get seedColor => switch (this) {
        AppTheme.blackMamba => const Color(0xFF0055A5),
        AppTheme.polarFox => const Color(0xFF78909C),
        AppTheme.greenViper => const Color(0xFF1B5E20),
        AppTheme.blueGlacier => const Color(0xFF0277BD),
        AppTheme.redLove => const Color(0xFFC62828),
        AppTheme.yellowCitrine => const Color(0xFFF57F17),
      };

  Brightness get brightness => switch (this) {
        AppTheme.blackMamba => Brightness.dark,
        AppTheme.polarFox => Brightness.light,
        AppTheme.greenViper => Brightness.dark,
        AppTheme.blueGlacier => Brightness.light,
        AppTheme.redLove => Brightness.dark,
        AppTheme.yellowCitrine => Brightness.light,
      };

  ThemeData buildThemeData() {
    final cs = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    const kRadius = BorderRadius.all(Radius.circular(4));
    const kShape = RoundedRectangleBorder(borderRadius: kRadius);
    return ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
