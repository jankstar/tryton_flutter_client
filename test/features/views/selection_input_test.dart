import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/domain/domain_parser.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/features/views/search_box.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';
import 'package:tryton_flutter_client/shared/widgets/selection_input.dart';

import 'form_harness.dart';

/// T2: selection entries with a filtered list (Python `Gtk.ComboBox` with
/// entry and completion): filter, keyboard, Escape, leaving, on_change
/// once, the whole list scrolled to the value, bottom sheet on touch,
/// editable list cell, search entry of the filter's check lists.
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  // ~600 time zones like „Configure Company“ → Timezone
  final zones = <List<dynamic>>[
    [null, ''],
    for (var i = 0; i < 300; i++) ['Africa/Zone$i', 'Africa/Zone$i'],
    ['Europe/Berlin', 'Europe/Berlin'],
    ['Europe/Paris', 'Europe/Paris'],
    ['Europe/Zürich', 'Europe/Zürich'],
    ['America/Oberlin', 'America/Oberlin'],
    for (var i = 0; i < 300; i++) ['Pacific/Zone$i', 'Pacific/Zone$i'],
  ];

  group('filterSelection', () {
    final labels = [for (final z in zones) '${z[1]}'];
    String first(String q) => labels[filterSelection(labels, q).first];

    test('substring, case ignored, word starts first', () {
      expect(first('berl'), 'Europe/Berlin',
          reason: 'word start before „Oberlin“');
      final hits = [for (final i in filterSelection(labels, 'BERL')) labels[i]];
      expect(hits, ['Europe/Berlin', 'America/Oberlin']);
    });

    test('accents and umlauts tolerant', () {
      expect(first('zurich'), 'Europe/Zürich');
      expect(first('Zür'), 'Europe/Zürich');
      expect(foldSelectionText('Ångström Straße'), 'angstrom strasse');
    });

    test('empty query: everything in order', () {
      expect(filterSelection(labels, '  '), hasLength(labels.length));
    });
  });

  /// A [SelectionInput] of [zones] with [value]; [selected] logs the
  /// chosen keys (on_change), a second entry takes the focus away.
  Future<List<dynamic>> pumpInput(WidgetTester tester,
      {dynamic value = 'Europe/Paris', bool required = false}) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final selected = <dynamic>[];
    var current = value;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: StatefulBuilder(
          // the other entry above: the list opens below the field
          builder: (context, setState) => Column(children: [
            const SizedBox(
                width: 300,
                child: TextField(key: ValueKey('other'))),
            SizedBox(
              width: 300,
              child: SelectionInput(
                fieldKey: const ValueKey('selection-tz'),
                items: zones,
                value: current,
                required: required,
                onSelected: (key) {
                  selected.add(key);
                  setState(() => current = key);
                },
              ),
            ),
          ]),
        ),
      ),
    ));
    return selected;
  }

  Finder entry() => find.byKey(const ValueKey('selection-tz'));
  String text(WidgetTester tester) =>
      tester.widget<TextField>(entry()).controller!.text;
  Finder option(String label) => find.descendant(
      of: find.byKey(const ValueKey('selection-options')),
      matching: find.text(label));

  testWidgets('typing filters („berl“ → Europe/Berlin first), Enter '
      'chooses; on_change exactly once', (tester) async {
    final selected = await pumpInput(tester);
    await tester.tap(entry());
    await tester.pump();
    await tester.enterText(entry(), 'b');
    await tester.pump();
    await tester.enterText(entry(), 'be');
    await tester.pump();
    await tester.enterText(entry(), 'berl');
    await tester.pump();
    expect(selected, isEmpty, reason: 'no on_change while typing');
    expect(option('Europe/Berlin'), findsOneWidget);
    expect(option('America/Oberlin'), findsOneWidget);
    expect(tester.getTopLeft(option('Europe/Berlin')).dy,
        lessThan(tester.getTopLeft(option('America/Oberlin')).dy));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, ['Europe/Berlin']);
    expect(text(tester), 'Europe/Berlin');
    expect(find.byKey(const ValueKey('selection-options')), findsNothing);
  }, variant: desktop);

  testWidgets('arrow keys move through the list', (tester) async {
    final selected = await pumpInput(tester);
    await tester.tap(entry());
    await tester.pump();
    await tester.enterText(entry(), 'berl');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, ['America/Oberlin']);
  }, variant: desktop);

  testWidgets('Escape restores the value', (tester) async {
    final selected = await pumpInput(tester);
    await tester.tap(entry());
    await tester.pump();
    await tester.enterText(entry(), 'berl');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(text(tester), 'Europe/Paris');
    expect(find.byKey(const ValueKey('selection-options')), findsNothing);
    expect(selected, isEmpty);
  }, variant: desktop);

  testWidgets('leaving with a text of no entry keeps the value; an exact '
      'label chooses its entry', (tester) async {
    final selected = await pumpInput(tester);
    await tester.tap(entry());
    await tester.pump();
    await tester.enterText(entry(), 'xyz');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('other')));
    await tester.pump();
    expect(text(tester), 'Europe/Paris');
    expect(selected, isEmpty);

    await tester.tap(entry());
    await tester.pump();
    await tester.enterText(entry(), 'europe/berlin');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('other')));
    await tester.pump();
    expect(selected, ['Europe/Berlin']);
    expect(text(tester), 'Europe/Berlin');
  }, variant: desktop);

  testWidgets('a press beside entry and list closes the list, the value '
      'stays', (tester) async {
    final selected = await pumpInput(tester);
    await tester.tap(entry());
    await tester.pump();
    await tester.enterText(entry(), 'berl');
    await tester.pump();
    expect(find.byKey(const ValueKey('selection-options')), findsOneWidget);
    await tester.tapAt(const Offset(900, 700));
    await tester.pump();
    expect(find.byKey(const ValueKey('selection-options')), findsNothing);
    expect(text(tester), 'Europe/Paris');
    expect(selected, isEmpty);
  }, variant: desktop);

  testWidgets('empty text: cleared unless required', (tester) async {
    var selected = await pumpInput(tester);
    await tester.tap(entry());
    await tester.pump();
    await tester.enterText(entry(), '');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('other')));
    await tester.pump();
    expect(selected, [null]);

    await tester.pumpWidget(const SizedBox());
    selected = await pumpInput(tester, value: 'Europe/Berlin', required: true);
    await tester.tap(entry());
    await tester.pump();
    await tester.enterText(entry(), '');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('other')));
    await tester.pump();
    expect(selected, isEmpty);
    expect(text(tester), 'Europe/Berlin');
  }, variant: desktop);

  testWidgets('the arrow shows the whole list scrolled to the value; '
      'virtualised, at most 60 % of the window', (tester) async {
    final selected =
        await pumpInput(tester, value: 'Pacific/Zone250');
    await tester.tap(find.byKey(const ValueKey('selection-tz-arrow')));
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('selection-options'));
    expect(list, findsOneWidget);
    expect(tester.getSize(list).height, lessThanOrEqualTo(800 * 0.6));
    expect(option('Pacific/Zone250'), findsOneWidget,
        reason: 'the current entry is scrolled into view');
    expect(option('Africa/Zone0'), findsNothing);
    final built = tester
        .widgetList(find.descendant(of: list, matching: find.byType(InkWell)))
        .length;
    expect(built, lessThan(zones.length ~/ 10), reason: 'virtualised');
    await tester.tap(option('Pacific/Zone251'));
    await tester.pump();
    expect(selected, ['Pacific/Zone251']);
  }, variant: desktop);

  testWidgets('touch: a tap opens a bottom sheet with a search entry',
      (tester) async {
    final selected = await pumpInput(tester);
    await tester.tap(entry());
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('selection-sheet-search'));
    expect(search, findsOneWidget);
    await tester.enterText(search, 'berl');
    await tester.pumpAndSettle();
    expect(find.text('Europe/Berlin'), findsOneWidget);
    expect(find.text('Africa/Zone1'), findsNothing);
    await tester.tap(find.text('Europe/Berlin'));
    await tester.pumpAndSettle();
    expect(selected, ['Europe/Berlin']);
    expect(text(tester), 'Europe/Berlin');
  });

  testWidgets('filter dialog: a search entry above a long check list',
      (tester) async {
    final parser = DomainParser({
      'tz': {
        'string': 'Timezone',
        'type': 'selection',
        'selection': [
          for (var i = 0; i < 20; i++) ['z$i', 'Zone $i'],
          ['b', 'Europe/Berlin'],
        ],
      },
      'state': {
        'string': 'State',
        'type': 'selection',
        'selection': [
          ['a', 'A'],
          ['b', 'B'],
        ],
      },
    });
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: FilterDialog(parser: parser)),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('filter-search-tz-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('filter-search-state-0')), findsNothing,
        reason: 'short lists stay without search');
    await tester.enterText(find.byKey(const ValueKey('filter-search-tz-0')), 'berl');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('filter-tz-Europe/Berlin')), findsOneWidget);
    expect(find.byKey(const ValueKey('filter-tz-Zone 1')), findsNothing);
  });

  testWidgets('editable list: the selection cell is the same entry',
      (tester) async {
    final rpc = FakeFormRpc({
      'model.test.line.fields_view_get': (p) => {
            'type': 'tree',
            'view_id': 7,
            'arch': '<tree editable="1"><field name="name"/>'
                '<field name="tz"/></tree>',
            'fields': {
              'name': {'type': 'char', 'string': 'Name'},
              'tz': {'type': 'selection', 'string': 'Timezone', 'selection': zones},
            },
          },
      'model.test.line.search': (_) => [1],
      'model.test.line.search_count': (_) => 1,
      'model.test.line.read': (p) => [
            {
              'id': 1,
              'name': 'A',
              'tz': 'Europe/Paris',
              'rec_name': 'A',
              '_timestamp': '1',
              '_write': true,
              '_delete': true,
            }
          ],
      'model.test.line.write': (_) => null,
      'model.ir.model.search_read': (_) => <dynamic>[],
      'model.ir.model.get_notification': (_) => <String, dynamic>{},
    });
    await pumpScreen(tester, rpc, const ScreenAttributes('test.line', mode: ['tree']));
    await tester.tap(find.text('Europe/Paris'));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    final cell = find.byKey(const ValueKey('selection-tz'));
    expect(cell, findsOneWidget);
    await tester.enterText(cell, 'berl');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(cell).controller!.text, 'Europe/Berlin');
    // leaving the row saves it (root list)
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();
    expect(rpc.named('model.test.line.write').single.params[1], {'tz': 'Europe/Berlin'});
  }, variant: desktop);

  testWidgets('in the form: as high as a text input', (tester) async {
    final rpc = FakeFormRpc({
      'model.test.form.fields_view_get': (_) => formView(
          '<form><label name="name"/><field name="name"/>'
              '<label name="tz"/><field name="tz"/></form>',
          {
            'name': {'type': 'char', 'string': 'Name'},
            'tz': {'type': 'selection', 'string': 'Timezone', 'selection': zones},
          }),
      'model.test.form.read': (_) => [
            {'id': 1, 'name': 'Acme', 'tz': 'Europe/Berlin', '_timestamp': '1'}
          ],
      'model.ir.model.search_read': (_) => <dynamic>[],
      'model.ir.model.get_notification': (_) => <String, dynamic>{},
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    final tz = find.byKey(const ValueKey('selection-tz'));
    expect(tester.widget<TextField>(tz).controller!.text, 'Europe/Berlin');
    expect(tester.getSize(tz).height, tester.getSize(textFieldOf('Name')).height);
  }, variant: desktop);
}
