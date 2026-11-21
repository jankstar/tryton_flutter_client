import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/views/tree_view.dart';

import 'form_harness.dart';

/// T3: the search dialog (spec 11.2, Python `WinSearch`) is a screen with
/// the same TreeView as every list: widths by type, stored and dragged
/// widths, horizontal scrolling; single/multiple choice, double click /
/// Enter = choice + OK, no links, New only with the create right.
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);
  const full = {'read': 1, 'write': 1, 'create': 1, 'delete': 1};
  setUp(clearListCaches);

  const formArch = '<form><label name="partner"/><field name="partner"/>'
      '<field name="tags" colspan="4"/></form>';

  FakeFormRpc server({
    String tree = '<tree><field name="code"/><field name="name" width="210"/>'
        '<field name="country"/></tree>',
    Map<String, Map<String, int>> access = const {},
  }) =>
      FakeFormRpc({
        'model.ir.model.list_models': (_) =>
            ['test.form', 'test.party', 'test.country'],
        'model.ir.model.access.get_access': (p) => {
              for (final m in p[0] as List) m: access[m] ?? full,
            },
        'model.test.form.fields_view_get': (_) => formView(formArch, {
              'partner': {
                'type': 'many2one',
                'string': 'Partner',
                'relation': 'test.party',
              },
              'tags': {
                'type': 'many2many',
                'string': 'Tags',
                'relation': 'test.party',
              },
            }),
        'model.test.form.read': (p) => [
              {
                'id': 1,
                'partner': null,
                'partner.': null,
                'tags': <int>[],
                '_timestamp': '1',
              }
            ],
        'model.test.party.fields_view_get': (p) => p[1] == 'tree'
            ? {
                'type': 'tree',
                'view_id': 20,
                'arch': tree,
                'fields': {
                  'code': {'type': 'integer', 'string': 'Code'},
                  'name': {'type': 'char', 'string': 'Name'},
                  'country': {
                    'type': 'many2one',
                    'string': 'Country',
                    'relation': 'test.country',
                  },
                  'long1': {'type': 'char', 'string': 'Long 1'},
                  'long2': {'type': 'char', 'string': 'Long 2'},
                },
              }
            : formView('<form><label name="name"/><field name="name"/></form>',
                {
                  'name': {'type': 'char', 'string': 'Name'}
                }),
        'model.test.party.autocomplete': (_) => <dynamic>[],
        'model.test.party.search': (_) => [1, 2],
        'model.test.party.search_count': (_) => 2,
        'model.test.party.read': (p) => [
              for (final id in p[0] as List)
                {
                  'id': id,
                  'code': id,
                  'name': 'P$id',
                  'rec_name': 'P$id',
                  'country': 5,
                  'country.': {'rec_name': 'Germany'},
                  'long1': 'L',
                  'long2': 'L',
                  '_timestamp': '1',
                  '_write': true,
                  '_delete': true,
                }
            ],
        'model.ir.ui.view_tree_width.set_width': (_) => null,
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
      });

  Finder m2o() => find.byKey(const ValueKey('m2o-partner'));
  String m2oText(WidgetTester tester) =>
      tester.widget<TextField>(m2o()).controller!.text;
  Finder inDialog(Finder f) =>
      find.descendant(of: find.byType(Dialog), matching: f);
  Finder header(String key) =>
      find.byKey(ValueKey('search-dialog-header-$key'));
  double width(WidgetTester tester, String key) =>
      tester.getSize(header(key)).width;

  /// Types „P“ into the many2one and leaves it: several hits → dialog.
  Future<void> openSearch(WidgetTester tester, FakeFormRpc rpc,
      {Size size = const Size(1400, 1000)}) async {
    await pumpForm(tester, rpc,
        model: 'test.form', recordId: 1, settle: false, metadata: true,
        size: size);
    await tester.enterText(m2o(), 'P');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFrames(tester, 20);
    expect(find.text('Search Partner'), findsOneWidget);
  }

  testWidgets('column widths like the lists: by type, stored width wins; '
      'dragging changes and stores it', (tester) async {
    final rpc = server();
    await openSearch(tester, rpc);
    expect(width(tester, 'code#0'), 80 * treeWidthFactor,
        reason: 'integer width of the lists');
    expect(width(tester, 'name#0'), 210,
        reason: 'the stored width (view width) wins');

    final edge = tester.getTopRight(header('name#0')) + const Offset(-3, 17);
    await tester.dragFrom(edge, const Offset(80, 0));
    await pumpFrames(tester);
    expect(width(tester, 'name#0'), greaterThan(260));
    final call = rpc.named('model.ir.ui.view_tree_width.set_width').single;
    expect(call.params[0], 'test.party',
        reason: 'the same widths as the list of the model');
    expect((call.params[1] as Map)['name'], [width(tester, 'name#0').round()]);
  }, variant: desktop);

  testWidgets('wider columns than the dialog scroll horizontally',
      (tester) async {
    await openSearch(
        tester,
        server(
            tree: '<tree><field name="name" width="500"/>'
                '<field name="long1" width="500"/>'
                '<field name="long2" width="500"/></tree>'),
        size: const Size(900, 800));
    // the table's own horizontal scroll view (not the search entry's)
    final states = tester
        .stateList<ScrollableState>(find.descendant(
            of: find.byType(TreeView), matching: find.byType(Scrollable)))
        .where((s) => s.position.axis == Axis.horizontal);
    expect(states, isNotEmpty);
    expect(states.first.position.maxScrollExtent, greaterThan(0));
  }, variant: desktop);

  testWidgets('the search text of the field is prefilled; no links in the '
      'rows; the dialog is 90 % wide', (tester) async {
    await openSearch(tester, server());
    final text = tester.widget<TextField>(inDialog(find.descendant(
        of: find.byKey(const ValueKey('search-dialog-text')),
        matching: find.byType(TextField))));
    expect(text.controller!.text, contains('P'));
    expect(inDialog(find.text('Germany')), findsNWidgets(2));
    expect(find.byKey(const ValueKey('search-dialog-link-1-country#0')),
        findsNothing, reason: 'no relation links in the dialog');
    expect(tester.getSize(find.byKey(const ValueKey('search-dialog-frame'))).width,
        1400 * 0.9);
    expect(inDialog(find.text('2')), findsWidgets, reason: 'counter');
  }, variant: desktop);

  testWidgets('double click chooses and closes (no form)', (tester) async {
    await openSearch(tester, server());
    await tester.tap(inDialog(find.text('P2')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(inDialog(find.text('P2')));
    await pumpFrames(tester);
    expect(find.text('Search Partner'), findsNothing);
    expect(m2oText(tester), 'P2');
    expect(find.byType(Dialog), findsNothing, reason: 'no form popup');
  }, variant: desktop);

  testWidgets('Enter takes the selected row', (tester) async {
    await openSearch(tester, server());
    await tester.tap(inDialog(find.text('P1')));
    await tester.pump(kDoubleTapTimeout);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFrames(tester);
    expect(find.text('Search Partner'), findsNothing);
    expect(m2oText(tester), 'P1');
  }, variant: desktop);

  testWidgets('single choice: a click moves the selection, no „select all“; '
      'OK only with a selection', (tester) async {
    await openSearch(tester, server());
    FilledButton ok() =>
        tester.widget<FilledButton>(inDialog(find.widgetWithText(FilledButton, 'OK')));
    expect(ok().onPressed, isNull);
    Checkbox box(int id) => tester.widget<Checkbox>(
        find.byKey(ValueKey('search-dialog-check-$id')));
    await tester.tap(inDialog(find.text('P1')));
    await tester.pump(kDoubleTapTimeout);
    await tester.tap(inDialog(find.text('P2')));
    await tester.pump(kDoubleTapTimeout);
    await tester.pump();
    expect(box(1).value, isFalse);
    expect(box(2).value, isTrue);
    expect(ok().onPressed, isNotNull);
    expect(inDialog(find.byWidgetPredicate((w) => w is Checkbox && w.tristate)),
        findsNothing);
  }, variant: desktop);

  testWidgets('multiple choice (many2many Add): clicks toggle, OK takes all',
      (tester) async {
    final rpc = server();
    await pumpForm(tester, rpc,
        model: 'test.form', recordId: 1, settle: false, metadata: true);
    await tester.tap(find.byKey(const ValueKey('x2m-add')));
    await pumpFrames(tester, 20);
    await tester.tap(inDialog(find.text('P1')));
    await tester.pump(kDoubleTapTimeout);
    await tester.tap(inDialog(find.text('P2')));
    await tester.pump(kDoubleTapTimeout);
    await tester.pump();
    Checkbox box(int id) => tester.widget<Checkbox>(
        find.byKey(ValueKey('search-dialog-check-$id')));
    expect(box(1).value, isTrue);
    expect(box(2).value, isTrue);
    await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Add')));
    await pumpFrames(tester);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('P1'), findsOneWidget);
    expect(find.text('P2'), findsOneWidget);
  }, variant: desktop);

  testWidgets('New with the create right', (tester) async {
    await openSearch(tester, server());
    expect(find.byKey(const ValueKey('search-dialog-new')), findsOneWidget);
  }, variant: desktop);

  testWidgets('no New without the create right', (tester) async {
    final rpc = server(access: {
      'test.party': {'read': 1, 'write': 1, 'create': 0, 'delete': 1}
    });
    await openSearch(tester, rpc);
    expect(find.byKey(const ValueKey('search-dialog-new')), findsNothing);
  }, variant: desktop);

  testWidgets('narrow window (< 600 px): full screen', (tester) async {
    await openSearch(tester, server(), size: const Size(500, 900));
    expect(find.byKey(const ValueKey('search-dialog-frame')), findsNothing);
    expect(tester.getSize(find.byType(Dialog)), const Size(500, 900));
  }, variant: desktop);
}
