import 'package:flutter/material.dart';

/// Colours of the Tryton specific areas (spec T5): header band and
/// toolbar of forms and lists, the tab bar of the shell, the menu, the
/// notebook tabs, the x2many header, the list header and the field
/// labels.
///
/// Every theme has the same form (Blue Ocean / SAO: coloured band, button
/// groups, position pill, grey menu and notebook bar, italic labels and
/// list headers); [TrytonColors.fromScheme] gives it in the colours of a
/// seed theme, [TrytonColors.blueOcean] the measured SAO colours. A
/// `null` value means „the widget's own default“ (nothing is set).
@immutable
class TrytonColors extends ThemeExtension<TrytonColors> {
  // ─── header band (AppBar of form and list) ─────────────────────────────
  final Color headerBackground;

  /// Text and icons of the band; null: the AppBar's default.
  final Color? headerForeground;

  /// The title (record menu „Parties ▾“); null: [headerForeground].
  final Color? headerTitle;

  /// Second title line of the form (model · position).
  final Color headerSubtitle;

  /// The enabled „Switch“ icon of the toolbar.
  final Color toolbarIcon;

  /// Toolbar buttons as white button groups (SAO); null: plain icons.
  final Color? toolbarButtonBackground;
  final Color? toolbarButtonForeground;

  /// Background of a pressed / active toolbar button.
  final Color? toolbarButtonActive;

  /// Position indicator as a pill („1/53“); null: plain text.
  final Color? positionBackground;
  final Color? positionForeground;

  // ─── tab bar of the shell ──────────────────────────────────────────────
  final Color tabBarBackground;

  /// Icons and texts on the bar; null: the default.
  final Color? tabBarForeground;
  final Color tabSelected;
  final Color tabSelectedForeground;

  // ─── menu (sidebar) ────────────────────────────────────────────────────
  /// Background of the menu; null: the scaffold's.
  final Color? menuBackground;
  final Color menuHeaderBackground;

  /// Text and icons of the menu header; null: the default.
  final Color? menuHeaderForeground;

  /// Text of the entries; null: the default.
  final Color? menuText;
  final Color menuIcon;
  final Color menuDivider;

  // ─── notebook tabs ─────────────────────────────────────────────────────
  /// Null: the TabBar's defaults.
  final Color? notebookBackground;
  final Color? notebookInactive;
  final Color? notebookActive;

  // ─── x2many header ─────────────────────────────────────────────────────
  final Color x2manyHeaderBackground;
  final Color x2manyTitle;

  /// Icons and texts on the x2many header; null: the default.
  final Color? x2manyHeaderForeground;

  /// Buttons of the header as filled buttons; null: plain icons.
  final Color? x2manyButtonBackground;

  /// Icons of the header buttons; null: the default.
  final Color? x2manyButtonForeground;

  // ─── list header ───────────────────────────────────────────────────────
  final Color listHeaderBackground;

  /// Text of the column labels; null: the default.
  final Color? listHeaderText;

  /// Style of the column labels (italic in SAO); null: upright.
  final FontStyle? listHeaderFontStyle;

  /// Lines between rows and header cells.
  final Color listLine;

  // ─── form labels and values ────────────────────────────────────────────
  final Color labelColor;
  final Color labelReadonlyColor;

  /// Italic labels (SAO); null: upright.
  final FontStyle? labelFontStyle;

  /// Text of the field values; null: the default.
  final Color? valueColor;

  const TrytonColors({
    required this.headerBackground,
    this.headerForeground,
    this.headerTitle,
    required this.headerSubtitle,
    required this.toolbarIcon,
    this.toolbarButtonBackground,
    this.toolbarButtonForeground,
    this.toolbarButtonActive,
    this.positionBackground,
    this.positionForeground,
    required this.tabBarBackground,
    this.tabBarForeground,
    required this.tabSelected,
    required this.tabSelectedForeground,
    this.menuBackground,
    required this.menuHeaderBackground,
    this.menuHeaderForeground,
    this.menuText,
    required this.menuIcon,
    required this.menuDivider,
    this.notebookBackground,
    this.notebookInactive,
    this.notebookActive,
    required this.x2manyHeaderBackground,
    required this.x2manyTitle,
    this.x2manyHeaderForeground,
    this.x2manyButtonBackground,
    this.x2manyButtonForeground,
    required this.listHeaderBackground,
    this.listHeaderText,
    this.listHeaderFontStyle,
    required this.listLine,
    required this.labelColor,
    required this.labelReadonlyColor,
    this.labelFontStyle,
    this.valueColor,
  });

  /// The style of Blue Ocean (SAO) in the colours of [cs] – every theme
  /// has the same form, only the colours differ (decision 2026-11-22):
  /// a coloured band (light: `primary`; dark: `primaryContainer`, a pastel
  /// `primary` would glare), button groups and position pill on it, grey
  /// menu and notebook bar, italic labels and list headers.
  factory TrytonColors.fromScheme(ColorScheme cs) {
    final dark = cs.brightness == Brightness.dark;
    final band = dark ? cs.primaryContainer : cs.primary;
    final onBand = dark ? cs.onPrimaryContainer : cs.onPrimary;
    final button = dark ? cs.surfaceContainerHighest : cs.surface;
    final onButton = dark ? cs.primary : cs.onPrimaryContainer;
    return TrytonColors(
      headerBackground: band,
      headerForeground: onBand,
      headerTitle: onBand.withAlpha(190),
      headerSubtitle: onBand.withAlpha(190),
      toolbarIcon: onButton,
      toolbarButtonBackground: button,
      toolbarButtonForeground: onButton,
      toolbarButtonActive: dark ? cs.secondaryContainer : cs.primaryContainer,
      positionBackground: button,
      positionForeground: cs.primary,
      tabBarBackground: Color.lerp(band, Colors.black, 0.2)!,
      tabBarForeground: onBand,
      tabSelected: button,
      tabSelectedForeground: cs.primary,
      menuBackground: cs.surfaceContainer,
      menuHeaderBackground: band,
      menuHeaderForeground: onBand,
      menuText: cs.onSurface,
      menuIcon: onButton,
      menuDivider: cs.outlineVariant,
      notebookBackground: cs.surfaceContainer,
      notebookInactive: cs.onSurfaceVariant,
      notebookActive: cs.primary,
      x2manyHeaderBackground: band,
      x2manyTitle: onBand,
      x2manyHeaderForeground: onBand,
      listHeaderBackground: cs.surface,
      listHeaderText: cs.onSurface,
      listHeaderFontStyle: FontStyle.italic,
      listLine: cs.outlineVariant,
      labelColor: cs.onSurface,
      labelReadonlyColor: cs.onSurface,
      labelFontStyle: FontStyle.italic,
      valueColor: cs.onSurfaceVariant,
    );
  }

  /// Blue Ocean: the colours of the SAO web client (spec T5, measured
  /// from a SAO 8 screenshot).
  static const blueOcean = TrytonColors(
    headerBackground: Color(0xFF2774FA),
    headerForeground: Colors.white,
    headerTitle: Color(0xFFA0C7FC),
    headerSubtitle: Color(0xFFA0C7FC),
    toolbarIcon: Color(0xFF274C77),
    toolbarButtonBackground: Colors.white,
    toolbarButtonForeground: Color(0xFF274C77),
    toolbarButtonActive: Color(0xFFACCFFD),
    positionBackground: Colors.white,
    positionForeground: Color(0xFF2774FA),
    tabBarBackground: Color(0xFF1E5DC8),
    tabBarForeground: Colors.white,
    tabSelected: Colors.white,
    tabSelectedForeground: Color(0xFF2774FA),
    menuBackground: Color(0xFFF8F8F8),
    menuHeaderBackground: Color(0xFF2774FA),
    menuHeaderForeground: Colors.white,
    menuText: Color(0xFF333333),
    menuIcon: Color(0xFF274C77),
    menuDivider: Color(0xFFDDDDDD),
    notebookBackground: Color(0xFFF8F8F8),
    notebookInactive: Color(0xFF777777),
    notebookActive: Color(0xFF2774FA),
    x2manyHeaderBackground: Color(0xFF2774FA),
    x2manyTitle: Colors.white,
    x2manyHeaderForeground: Colors.white,
    // (the x2many buttons are toolbar button groups like the top bar)
    listHeaderBackground: Colors.white,
    listHeaderText: Color(0xFF333333),
    listHeaderFontStyle: FontStyle.italic,
    listLine: Color(0xFFDDDDDD),
    labelColor: Color(0xFF333333),
    labelReadonlyColor: Color(0xFF333333),
    labelFontStyle: FontStyle.italic,
    valueColor: Color(0xFF555555),
  );

  /// The colours of the current theme ([fromScheme] when the theme has no
  /// extension, e.g. in tests).
  static TrytonColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<TrytonColors>() ??
        TrytonColors.fromScheme(theme.colorScheme);
  }

  @override
  TrytonColors copyWith() => this;

  @override
  TrytonColors lerp(TrytonColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    Color? n(Color? a, Color? b) =>
        a == null || b == null ? (t < 0.5 ? a : b) : Color.lerp(a, b, t);
    return TrytonColors(
      headerBackground: c(headerBackground, other.headerBackground),
      headerForeground: n(headerForeground, other.headerForeground),
      headerTitle: n(headerTitle, other.headerTitle),
      headerSubtitle: c(headerSubtitle, other.headerSubtitle),
      toolbarIcon: c(toolbarIcon, other.toolbarIcon),
      toolbarButtonBackground:
          n(toolbarButtonBackground, other.toolbarButtonBackground),
      toolbarButtonForeground:
          n(toolbarButtonForeground, other.toolbarButtonForeground),
      toolbarButtonActive: n(toolbarButtonActive, other.toolbarButtonActive),
      positionBackground: n(positionBackground, other.positionBackground),
      positionForeground: n(positionForeground, other.positionForeground),
      tabBarBackground: c(tabBarBackground, other.tabBarBackground),
      tabBarForeground: n(tabBarForeground, other.tabBarForeground),
      tabSelected: c(tabSelected, other.tabSelected),
      tabSelectedForeground:
          c(tabSelectedForeground, other.tabSelectedForeground),
      menuBackground: n(menuBackground, other.menuBackground),
      menuHeaderBackground: c(menuHeaderBackground, other.menuHeaderBackground),
      menuHeaderForeground: n(menuHeaderForeground, other.menuHeaderForeground),
      menuText: n(menuText, other.menuText),
      menuIcon: c(menuIcon, other.menuIcon),
      menuDivider: c(menuDivider, other.menuDivider),
      notebookBackground: n(notebookBackground, other.notebookBackground),
      notebookInactive: n(notebookInactive, other.notebookInactive),
      notebookActive: n(notebookActive, other.notebookActive),
      x2manyHeaderBackground:
          c(x2manyHeaderBackground, other.x2manyHeaderBackground),
      x2manyTitle: c(x2manyTitle, other.x2manyTitle),
      x2manyHeaderForeground:
          n(x2manyHeaderForeground, other.x2manyHeaderForeground),
      x2manyButtonBackground:
          n(x2manyButtonBackground, other.x2manyButtonBackground),
      x2manyButtonForeground:
          n(x2manyButtonForeground, other.x2manyButtonForeground),
      listHeaderBackground: c(listHeaderBackground, other.listHeaderBackground),
      listHeaderText: n(listHeaderText, other.listHeaderText),
      listHeaderFontStyle:
          t < 0.5 ? listHeaderFontStyle : other.listHeaderFontStyle,
      listLine: c(listLine, other.listLine),
      labelColor: c(labelColor, other.labelColor),
      labelReadonlyColor: c(labelReadonlyColor, other.labelReadonlyColor),
      labelFontStyle: t < 0.5 ? labelFontStyle : other.labelFontStyle,
      valueColor: n(valueColor, other.valueColor),
    );
  }
}
