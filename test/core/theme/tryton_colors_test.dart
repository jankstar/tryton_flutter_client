import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/theme/app_theme.dart';
import 'package:tryton_flutter_client/core/theme/tryton_colors.dart';
import 'package:tryton_flutter_client/features/tabs/menu_sidebar.dart';
import 'package:tryton_flutter_client/features/views/record_menu.dart';
import 'package:tryton_flutter_client/features/views/embedded_tree_widget.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';

import '../../features/views/form_harness.dart';

/// T5 and the toolbar redesign (2026-11-22): the Tryton areas take their
/// colours from [TrytonColors]; every theme has the form of Blue Ocean
/// (SAO) – coloured band, button groups, position pill, grey menu and
/// notebook bar, italic labels and list headers –, only the colours of
/// its scheme differ.
void main() {
  group('every theme: the form of Blue Ocean in its own colours', () {
    for (final theme in AppTheme.values.where((t) => t != AppTheme.blueOcean)) {
      test(theme.label, () {
        final data = theme.buildThemeData();
        final cs = data.colorScheme;
        final tc = data.extension<TrytonColors>();
        expect(tc, isNotNull, reason: 'every theme has TrytonColors');
        tc!;
        final dark = cs.brightness == Brightness.dark;
        // a coloured band (dark themes: primaryContainer, not the pastel
        // primary) – header, x2many header and menu header alike
        final band = dark ? cs.primaryContainer : cs.primary;
        final onBand = dark ? cs.onPrimaryContainer : cs.onPrimary;
        expect(tc.headerBackground, band);
        expect(tc.x2manyHeaderBackground, band);
        expect(tc.menuHeaderBackground, band);
        expect(tc.headerForeground, onBand);
        expect(tc.x2manyTitle, onBand);
        // button groups and position pill on the band
        expect(tc.toolbarButtonBackground,
            dark ? cs.surfaceContainerHighest : cs.surface);
        expect(tc.positionBackground, tc.toolbarButtonBackground);
        expect(tc.positionForeground, cs.primary);
        expect(tc.toolbarButtonActive, isNotNull);
        // the tab bar a little darker than the band
        expect(tc.tabBarBackground.computeLuminance(),
            lessThan(band.computeLuminance()));
        expect(tc.tabBarForeground, onBand);
        // grey menu and notebook bar
        expect(tc.menuBackground, cs.surfaceContainer);
        expect(tc.notebookBackground, cs.surfaceContainer);
        expect(tc.notebookActive, cs.primary);
        // list header and labels: italic, the text colour
        expect(tc.listHeaderBackground, cs.surface);
        expect(tc.listHeaderFontStyle, FontStyle.italic);
        expect(tc.labelFontStyle, FontStyle.italic);
        expect(tc.labelColor, cs.onSurface);
        expect(tc.listLine, cs.outlineVariant);
      });
    }
  });

  testWidgets('without the extension (tests, plain MaterialApp): the form '
      'in the colours of the scheme', (tester) async {
    late TrytonColors tc;
    late ColorScheme cs;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      tc = TrytonColors.of(context);
      cs = Theme.of(context).colorScheme;
      return const SizedBox();
    })));
    expect(tc.headerBackground, cs.primary);
    expect(tc.labelFontStyle, FontStyle.italic);
  });

  testWidgets('the widgets read their colours from TrytonColors',
      (tester) async {
    const header = Color(0xFF112233), x2m = Color(0xFF223344),
        list = Color(0xFF334455), label = Color(0xFF445566),
        active = Color(0xFF556677);
    final base = ThemeData(useMaterial3: true);
    final theme = base.copyWith(extensions: [
      TrytonColors(
        headerBackground: header,
        headerSubtitle: Colors.black,
        toolbarIcon: Colors.black,
        tabBarBackground: Colors.black,
        tabSelected: Colors.black,
        tabSelectedForeground: Colors.white,
        menuHeaderBackground: Colors.black,
        menuIcon: Colors.black,
        menuDivider: Colors.black,
        notebookActive: active,
        x2manyHeaderBackground: x2m,
        x2manyTitle: Colors.black,
        listHeaderBackground: list,
        listHeaderFontStyle: FontStyle.italic,
        listLine: Colors.black,
        labelColor: label,
        labelReadonlyColor: label,
        labelFontStyle: FontStyle.italic,
      ),
    ]);
    final rpc = FakeFormRpc({
      'model.test.form.fields_view_get': (_) => formView(
          '<form><label name="name"/><field name="name"/>'
              '<notebook><page string="Lines" id="l">'
              '<field name="lines"/></page></notebook></form>',
          {
            'name': {'type': 'char', 'string': 'Name'},
            'lines': {
              'type': 'one2many',
              'string': 'Lines',
              'relation': 'test.line',
              'relation_field': 'form',
            },
          }),
      'model.test.form.read': (_) => [
            {'id': 1, 'name': 'A', 'lines': [11], '_timestamp': '1'}
          ],
      'model.test.line.fields_view_get': (_) => {
            'type': 'tree',
            'arch': '<tree><field name="name"/></tree>',
            'fields': {
              'name': {'type': 'char', 'string': 'Line'},
            },
          },
      'model.test.line.read': (p) => [
            {'id': 11, 'name': 'L11', '_timestamp': '1'}
          ],
      'model.ir.model.search_read': (_) => <dynamic>[],
      'model.ir.model.get_notification': (_) => <String, dynamic>{},
      'model.test.form.resources': (_) => <String, dynamic>{},
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1, theme: theme);
    expect(tester.widget<AppBar>(find.byType(AppBar)).backgroundColor, header);
    final x2mBar = tester.widget<Container>(find.byKey(const ValueKey('x2m-toolbar')));
    expect((x2mBar.decoration as BoxDecoration).color, x2m);
    expect(
        find.descendant(
            of: find.byType(EmbeddedTreeWidget),
            matching: find.byWidgetPredicate(
                (w) => w is Container && w.color == list)),
        findsOneWidget,
        reason: 'list header');
    final labelText = tester.widget<Text>(find.text('Name:'));
    expect(labelText.style?.color, label);
    expect(labelText.style?.fontStyle, FontStyle.italic);
    expect(tester.widget<TabBar>(find.byType(TabBar)).labelColor, active);
    final column = tester.widget<Text>(find.descendant(
        of: find.byType(EmbeddedTreeWidget), matching: find.text('Line')));
    expect(column.style?.fontStyle, FontStyle.italic);
  });

  test('Blue Ocean: explicit SAO scheme and colours', () {
    final data = AppTheme.blueOcean.buildThemeData();
    final cs = data.colorScheme;
    expect(cs.brightness, Brightness.light);
    expect(cs.primary, const Color(0xFF2774FA));
    expect(cs.onPrimary, Colors.white);
    expect(cs.surface, Colors.white);
    expect(cs.surfaceContainerHighest, const Color(0xFFF8F8F8));
    expect(cs.outline, const Color(0xFF777777), reason: 'readable hints');
    expect(cs.outlineVariant, const Color(0xFFDDDDDD));
    final tc = data.extension<TrytonColors>()!;
    expect(tc.headerBackground, const Color(0xFF2774FA));
    expect(tc.headerTitle, const Color(0xFFA0C7FC));
    expect(tc.tabBarBackground, const Color(0xFF1E5DC8));
    expect(tc.menuBackground, const Color(0xFFF8F8F8));
    expect(tc.menuText, const Color(0xFF333333));
    expect(tc.menuIcon, const Color(0xFF274C77));
    expect(tc.notebookBackground, const Color(0xFFF8F8F8));
    expect(tc.notebookInactive, const Color(0xFF777777));
    expect(tc.listHeaderFontStyle, FontStyle.italic);
    expect(tc.labelFontStyle, FontStyle.italic);
    expect(tc.valueColor, const Color(0xFF555555));
  });

  testWidgets('Blue Ocean on the widgets: header band, x2many header, '
      'notebook tabs, labels', (tester) async {
    final rpc = FakeFormRpc({
      'model.test.form.fields_view_get': (_) => formView(
          '<form><label name="name"/><field name="name"/>'
              '<notebook><page string="Lines" id="l">'
              '<field name="lines"/></page>'
              '<page string="Other" id="o"/></notebook></form>',
          {
            'name': {'type': 'char', 'string': 'Name'},
            'lines': {
              'type': 'one2many',
              'string': 'Lines',
              'relation': 'test.line',
              'relation_field': 'form',
            },
          }),
      'model.test.form.read': (_) => [
            {'id': 1, 'name': 'A', 'lines': [11], '_timestamp': '1'}
          ],
      'model.test.line.fields_view_get': (_) => {
            'type': 'tree',
            'arch': '<tree><field name="name"/></tree>',
            'fields': {
              'name': {'type': 'char', 'string': 'Line'},
            },
          },
      'model.test.line.read': (p) => [
            {'id': 11, 'name': 'L11', '_timestamp': '1'}
          ],
      'model.ir.model.search_read': (_) => <dynamic>[],
      'model.ir.model.get_notification': (_) => <String, dynamic>{},
      'model.test.form.resources': (_) => <String, dynamic>{},
    });
    await pumpForm(tester, rpc,
        model: 'test.form',
        recordId: 1,
        theme: AppTheme.blueOcean.buildThemeData());
    const blue = Color(0xFF2774FA);
    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(bar.backgroundColor, blue);
    expect(bar.foregroundColor, Colors.white);
    final x2mBar =
        tester.widget<Container>(find.byKey(const ValueKey('x2m-toolbar')));
    expect((x2mBar.decoration as BoxDecoration).color, blue);
    expect(tester.widget<Text>(find.byKey(const ValueKey('x2m-title'))).style?.color,
        Colors.white);
    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabs.labelColor, blue);
    expect(tabs.indicatorColor, blue);
    expect(tabs.unselectedLabelColor, const Color(0xFF777777));
    expect(
        find.ancestor(
            of: find.byType(TabBar),
            matching: find.byWidgetPredicate(
                (w) => w is ColoredBox && w.color == const Color(0xFFF8F8F8))),
        findsOneWidget,
        reason: 'notebook bar background');
    final label = tester.widget<Text>(find.text('Name:'));
    expect(label.style?.color, const Color(0xFF333333));
    expect(label.style?.fontStyle, FontStyle.italic);

    // toolbar buttons in groups: each button paints its background –
    // enabled white, disabled translucent white (SAO opacity .65: light
    // blue on the band) –, icons #274C77, pressed #ACCFFD
    ButtonStyle? groupStyle(String key) => tester
        .widget<IconButtonTheme>(find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(IconButtonTheme)))
        .data
        .style;
    for (final key in [
      'toolbar-group-navigation',
      'toolbar-group-records',
      'toolbar-group-close',
      // the x2many header has the same button groups as the top bar
      'x2m-group-switch',
      'x2m-group-new',
    ]) {
      final style = groupStyle(key)!;
      expect(style.backgroundColor?.resolve({}), Colors.white, reason: key);
      expect(style.backgroundColor?.resolve({WidgetState.disabled}),
          Colors.white.withAlpha(ToolbarButtonGroup.disabledAlpha),
          reason: '$key: disabled light blue on the band');
      expect(style.foregroundColor?.resolve({}), const Color(0xFF274C77));
      expect(style.overlayColor?.resolve({WidgetState.pressed}),
          const Color(0xFFACCFFD));
    }
    // „Open“ like SAO with the icon of the many2one field's Open
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('x2m-open')),
            matching: find.byIcon(Icons.open_in_new)),
        findsOneWidget);
    expect(
        tester.widget<IconButton>(find.descendant(
            of: find.byKey(const ValueKey('x2m-open')),
            matching: find.byType(IconButton))).tooltip,
        'Open');
    final pill = tester.widget<Container>(find.ancestor(
        of: find.byKey(const ValueKey('x2m-position')),
        matching: find.byType(Container)).first);
    expect((pill.decoration as BoxDecoration).color, Colors.white);
    expect(tester.widget<Text>(find.byKey(const ValueKey('x2m-position'))).style?.color,
        blue);
  });

  testWidgets('the other themes: the same button groups in their colours',
      (tester) async {
    final rpc = FakeFormRpc({
      'model.test.form.fields_view_get': (_) => formView(
          '<form><label name="name"/><field name="name"/></form>',
          {'name': {'type': 'char', 'string': 'Name'}}),
      'model.test.form.read': (_) => [
            {'id': 1, 'name': 'A', '_timestamp': '1'}
          ],
      'model.ir.model.search_read': (_) => <dynamic>[],
      'model.ir.model.get_notification': (_) => <String, dynamic>{},
      'model.test.form.resources': (_) => <String, dynamic>{},
    });
    final theme = AppTheme.polarFox.buildThemeData();
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1, theme: theme);
    // compact buttons in groups like Blue Ocean, in the theme's colours
    final style = tester
        .widget<IconButtonTheme>(find.descendant(
            of: find.byKey(const ValueKey('toolbar-group-records')),
            matching: find.byType(IconButtonTheme)))
        .data
        .style!;
    expect(style.backgroundColor?.resolve({}), theme.colorScheme.surface);
    expect(style.backgroundColor?.resolve({WidgetState.disabled}),
        theme.colorScheme.surface.withAlpha(ToolbarButtonGroup.disabledAlpha));
    expect(style.minimumSize?.resolve({}), const Size(40, 40));
  });

  testWidgets('Blue Ocean: menu background, header and divider',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.blueOcean.buildThemeData(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: MenuSidebar()),
      ),
    ));
    await tester.pump();
    expect(
        find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color == const Color(0xFFF8F8F8)),
        findsWidgets,
        reason: 'menu background');
    expect(
        find.byWidgetPredicate(
            (w) => w is Container && w.color == const Color(0xFF2774FA)),
        findsOneWidget,
        reason: 'menu header');
    expect(
        tester
            .widgetList<Divider>(find.byType(Divider))
            .every((d) => d.color == const Color(0xFFDDDDDD)),
        isTrue);
  });
}
