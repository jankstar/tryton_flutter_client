import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/core/theme/app_theme.dart';
import 'package:tryton_flutter_client/core/theme/tryton_colors.dart';

import 'form_harness.dart';

/// Issue #7: the search entry in the header of x2many lists and the search
/// bar of the list have the background of the other inputs (the form's),
/// not the grey of their bar – in the light and the dark theme.
void main() {
  FakeFormRpc server() => FakeFormRpc({
    'model.test.form.fields_view_get': (p) => p[1] == 'tree'
        ? {
            'type': 'tree',
            'view_id': 3,
            'arch': '<tree><field name="name"/></tree>',
            'fields': {
              'name': {'type': 'char', 'string': 'Name'},
            },
          }
        : formView(
            '<form><label name="name"/><field name="name"/>'
            '<field name="tags" colspan="4"/></form>',
            {
              'name': {'type': 'char', 'string': 'Name'},
              'tags': {
                'type': 'many2many',
                'string': 'Tags',
                'relation': 'test.tag',
              },
            },
          ),
    'model.test.form.read': (_) => [
      {'id': 1, 'name': 'A', 'tags': <int>[], '_timestamp': '1'},
    ],
    'model.test.tag.fields_view_get': (_) => {
      'type': 'tree',
      'view_id': 4,
      'arch': '<tree><field name="name"/></tree>',
      'fields': {
        'name': {'type': 'char', 'string': 'Name'},
      },
    },
    'model.test.form.search': (_) => [1],
    'model.test.form.search_count': (_) => 1,
    'model.ir.model.search_read': (_) => <dynamic>[],
    'model.ir.model.get_notification': (_) => <String, dynamic>{},
    'model.test.form.resources': (_) => <String, dynamic>{},
  });

  /// The fill the [InputDecorator] of the field [key] paints.
  Color? fillOf(WidgetTester tester, String key) {
    final decorator = tester.widget<InputDecorator>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(InputDecorator),
      ),
    );
    return decorator.decoration.filled == true
        ? decorator.decoration.fillColor
        : null;
  }

  for (final appTheme in [AppTheme.blueGlacier, AppTheme.blackMamba]) {
    final theme = appTheme.buildThemeData();
    final cs = theme.colorScheme;
    final mode = theme.brightness.name;

    testWidgets('$mode: x2many search entry like the form, not the bar', (
      tester,
    ) async {
      await pumpForm(
        tester,
        server(),
        model: 'test.form',
        recordId: 1,
        theme: theme,
      );
      final bar = tester.widget<Container>(
        find.byKey(const ValueKey('x2m-toolbar')),
      );
      // the bar in the band colour of the theme (same form everywhere)
      final band = theme.extension<TrytonColors>()!.x2manyHeaderBackground;
      expect((bar.decoration as BoxDecoration).color, band);
      expect(fillOf(tester, 'x2m-add-entry'), cs.surface);
      expect(
        theme.scaffoldBackgroundColor,
        cs.surface,
        reason: 'form background',
      );
      expect(cs.surface, isNot(band));
      if (theme.brightness == Brightness.light) {
        // nearly white
        expect(cs.surface.computeLuminance(), greaterThan(0.9));
      }
      // the border is the box of the other inputs (theme)
      final decorator = tester.widget<InputDecorator>(
        find.descendant(
          of: find.byKey(const ValueKey('x2m-add-entry')),
          matching: find.byType(InputDecorator),
        ),
      );
      expect(decorator.decoration.border, isA<OutlineInputBorder>());
    });

    testWidgets('$mode: search bar of the list like the other inputs', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        server(),
        const ScreenAttributes('test.form', mode: ['tree']),
        settle: false,
        theme: theme,
      );
      await pumpFrames(tester, 10);
      expect(fillOf(tester, 'search-text'), cs.surface);
    });
  }
}
