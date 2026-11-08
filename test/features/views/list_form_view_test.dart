import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/features/views/dynamic_form_screen.dart';
import 'package:tryton_flutter_client/features/views/list_form_view.dart';

import 'form_harness.dart';

/// View type list-form (spec 9.4, E30): the records as cards with the
/// form layout of the arch, selection, activation, editing, paging.
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  FakeFormRpc server({int count = 2}) => FakeFormRpc({
        'model.test.form.fields_view_get': (p) => p[1] == 'list-form'
            ? {
                'type': 'list-form',
                'view_id': 5,
                'arch': '<list-form col="4"><field name="name"/>'
                    '<field name="amount"/></list-form>',
                'fields': {
                  'name': {'type': 'char', 'string': 'Name'},
                  'amount': {'type': 'integer', 'string': 'Amount'},
                },
              }
            : formView('<form><field name="name"/></form>', {
                'name': {'type': 'char', 'string': 'Name'},
              }),
        'model.test.form.search': (p) =>
            [for (var i = 1; i <= count; i++) i],
        'model.test.form.search_count': (_) => count,
        'model.test.form.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'name': 'Card $id', 'amount': id * 10, '_timestamp': '1'}
            ],
        'model.test.form.write': (_) => null,
        'model.test.form.view_toolbar_get': (_) => <String, dynamic>{},
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        'model.test.form.resources': (_) => <String, dynamic>{},
      });

  const attributes =
      ScreenAttributes('test.form', mode: ['list-form', 'form']);

  Finder card(int id) => find.byKey(ValueKey('list-form-card-$id'));

  bool selected(WidgetTester tester, int id) =>
      tester.widget<Card>(find.descendant(of: card(id), matching: find.byType(Card)))
          .elevation ==
      2;

  testWidgets('cards with the form layout of the arch, no search bar',
      (tester) async {
    final rpc = server();
    await pumpScreen(tester, rpc, attributes, settle: false);
    await pumpFrames(tester);
    expect(find.byType(ListFormView), findsOneWidget);
    expect(card(1), findsOneWidget);
    expect(card(2), findsOneWidget);
    // the same widgets as the form: text fields with floating labels
    expect(
        find.descendant(of: card(1), matching: find.widgetWithText(TextField, 'Card 1')),
        findsOneWidget);
    expect(
        find.descendant(of: card(2), matching: find.widgetWithText(TextField, '20')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('search-text')), findsNothing,
        reason: 'not searchable (Python search_active)');
  }, variant: desktop);

  testWidgets('a click selects the card, a double click opens the form',
      (tester) async {
    final rpc = server();
    await pumpScreen(tester, rpc, attributes, settle: false);
    await pumpFrames(tester);
    await tester.tapAt(tester.getTopRight(card(2)) + const Offset(-6, 6));
    await pumpFrames(tester, 5);
    expect(selected(tester, 2), isTrue);
    expect(selected(tester, 1), isFalse);

    await tester.tapAt(tester.getTopRight(card(1)) + const Offset(-6, 6));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(tester.getTopRight(card(1)) + const Offset(-6, 6));
    await pumpFrames(tester);
    expect(find.byType(DynamicFormScreen), findsOneWidget, reason: 'activated');
    expect(find.widgetWithText(TextField, 'Card 1'), findsOneWidget);
  }, variant: desktop);

  testWidgets('editing in a card: leaving the card saves the record',
      (tester) async {
    final rpc = server();
    await pumpScreen(tester, rpc, attributes, settle: false);
    await pumpFrames(tester);
    final name = find.descendant(
        of: card(1), matching: find.widgetWithText(TextField, 'Card 1'));
    await tester.tap(name);
    await tester.enterText(name, 'Changed');
    await pumpFrames(tester, 5);
    await tester.tapAt(tester.getTopRight(card(2)) + const Offset(-6, 6));
    await pumpFrames(tester);
    final write = rpc.named('model.test.form.write').single;
    expect(write.params[0], [1]);
    expect(write.params[1], {'name': 'Changed'});
    expect(selected(tester, 2), isTrue);
  }, variant: desktop);

  testWidgets('paging: the cards are built in steps of display_size',
      (tester) async {
    final rpc = server(count: 150);
    await pumpScreen(tester, rpc, attributes, settle: false);
    await pumpFrames(tester);
    int built() => (tester
                .widget<ListView>(find.byKey(const ValueKey('list-form')))
                .childrenDelegate as SliverChildBuilderDelegate)
            .childCount!;
    expect(built(), 100);
    await tester.drag(find.byKey(const ValueKey('list-form')), const Offset(0, -200000));
    await pumpFrames(tester);
    expect(built(), 150);
  }, variant: desktop);
}
