import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/features/views/calendar_view.dart';
import 'package:tryton_flutter_client/features/views/dynamic_form_screen.dart';
import 'package:tryton_flutter_client/features/views/graph_view.dart';

import 'form_harness.dart';

/// Graph (spec 9.5, E31) and calendar (spec 9.6, E32) as views of a
/// screen.
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  final fields = {
    'name': {'type': 'char', 'string': 'Name'},
    'party': {'type': 'many2one', 'string': 'Party', 'relation': 'party.party'},
    'amount': {'type': 'integer', 'string': 'Amount'},
    'start': {'type': 'datetime', 'string': 'Start'},
    'end': {'type': 'datetime', 'string': 'End'},
  };

  FakeFormRpc server(String type, String arch,
          List<Map<String, dynamic>> rows) =>
      FakeFormRpc({
        'model.test.event.fields_view_get': (p) => p[1] == type
            ? {'type': type, 'view_id': 7, 'arch': arch, 'fields': fields}
            : formView('<form><field name="name"/><field name="start"/></form>',
                fields),
        'model.test.event.search': (_) => [for (final r in rows) r['id']],
        'model.test.event.search_count': (_) => rows.length,
        'model.test.event.read': (p) => [
              for (final id in p[0] as List)
                {...rows.firstWhere((r) => r['id'] == id), '_timestamp': '1'}
            ],
        'model.test.event.write': (_) => null,
        'model.test.event.default_get': (_) => <String, dynamic>{},
        'model.test.event.view_toolbar_get': (_) => <String, dynamic>{},
        'model.test.event.resources': (_) => <String, dynamic>{},
        'model.ir.action.keyword.get_keyword': (_) => <dynamic>[],
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
      });

  testWidgets('graph: bars of the sums with legend; a tap opens graph_open '
      'with the ids of the bar', (tester) async {
    final rpc = server(
        'graph',
        '<graph type="vbar"><x><field name="party"/></x>'
            '<y><field name="amount"/><field name="#" string="Count"/></y></graph>',
        [
          for (final id in [1, 2, 3])
            {'id': id, 'party': 4, 'party.': {'rec_name': 'Acme'}, 'amount': id * 10},
        ]);
    await pumpScreen(
        tester, rpc, const ScreenAttributes('test.event', mode: ['graph', 'form']),
        settle: false);
    await pumpFrames(tester);
    expect(find.byType(GraphView), findsOneWidget);
    expect(find.byKey(const ValueKey('graph-bar')), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget, reason: 'legend');
    expect(find.text('Count'), findsOneWidget);
    final bars = tester.widget<BarChart>(find.byType(BarChart)).data.barGroups;
    expect(bars, hasLength(1));
    expect([for (final r in bars.single.barRods) r.toY], [60, 3]);
    expect(find.byKey(const ValueKey('search-text')), findsOneWidget,
        reason: 'graph is searchable');

    // the left rod of the only group (plot area right of the 56 px of
    // the y labels), low enough to be inside it
    final chart = tester.getRect(find.byType(BarChart));
    final plotCenter = chart.left + 56 + (chart.width - 56) / 2;
    await tester.tapAt(Offset(plotCenter - 12, chart.bottom - 60));
    await pumpFrames(tester, 5);
    final calls = rpc.named('model.ir.action.keyword.get_keyword');
    expect(calls, hasLength(1));
    expect(calls.single.params, [
      'graph_open',
      ['test.event', 1],
    ]);
  }, variant: desktop);

  group('calendar', () {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    // a day of the same week: tomorrow, or yesterday on the last weekday
    final other = day.weekday == DateTime.sunday
        ? day.subtract(const Duration(days: 1))
        : day.add(const Duration(days: 1));
    String key(DateTime d) =>
        'calendar-day-${DateFormat('yyyy-MM-dd').format(d)}';

    FakeFormRpc calendarServer() => server(
            'calendar',
            '<calendar dtstart="start" dtend="end" mode="month">'
                '<field name="name"/></calendar>',
            [
              {
                'id': 1,
                'name': 'Meeting',
                'start': day.add(const Duration(hours: 9)),
                'end': day.add(const Duration(hours: 10)),
              },
            ]);
    const attributes =
        ScreenAttributes('test.event', mode: ['calendar', 'form']);

    testWidgets('search limited to the shown period; paging beyond it '
        'searches again; the event is shown on its day', (tester) async {
      final rpc = calendarServer();
      await pumpScreen(tester, rpc, attributes, settle: false);
      await pumpFrames(tester);
      expect(find.byType(CalendarView), findsOneWidget);
      final searches = rpc.named('model.test.event.search');
      expect(searches, hasLength(1));
      final domain = '${searches.single.params[0]}';
      expect(domain, contains('[start, !=, null]'));
      expect(domain, contains('[end, >=, '));
      expect(
          find.descendant(
              of: find.byKey(ValueKey(key(day))),
              matching: find.byKey(const ValueKey('calendar-event-1'))),
          findsOneWidget);

      // week inside the searched month: no new search
      await tester.tap(find.text('Week'));
      await pumpFrames(tester, 5);
      expect(rpc.named('model.test.event.search'), hasLength(1));
      await tester.tap(find.text('Month'));
      await pumpFrames(tester, 5);
      await tester.tap(find.byKey(const ValueKey('calendar-next')));
      await pumpFrames(tester, 5);
      expect(rpc.named('model.test.event.search'), hasLength(2));
    }, variant: desktop);

    testWidgets('dragging an event to another day writes start and end; a '
        'tap opens the form', (tester) async {
      final rpc = calendarServer();
      await pumpScreen(tester, rpc, attributes, settle: false);
      await pumpFrames(tester);
      final event = find.byKey(const ValueKey('calendar-event-1'));
      final target = tester.getCenter(find.byKey(ValueKey(key(other))));
      final gesture = await tester.startGesture(tester.getCenter(event));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(4, 4));
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await pumpFrames(tester, 5);
      final writes = rpc.named('model.test.event.write');
      expect(writes, hasLength(1));
      final values = writes.single.params[1] as Map;
      expect(values['start'], other.add(const Duration(hours: 9)));
      expect(values['end'], other.add(const Duration(hours: 10)));

      await tester.tap(find.byKey(const ValueKey('calendar-event-1')));
      await pumpFrames(tester);
      expect(find.byType(DynamicFormScreen), findsOneWidget);
    }, variant: desktop);

    testWidgets('a double tap on a day creates a record starting that day',
        (tester) async {
      final rpc = calendarServer();
      await pumpScreen(tester, rpc, attributes, settle: false);
      await pumpFrames(tester);
      final cell = find.byKey(ValueKey(key(other)));
      await tester.tapAt(tester.getBottomRight(cell) - const Offset(6, 6));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(tester.getBottomRight(cell) - const Offset(6, 6));
      await pumpFrames(tester);
      expect(rpc.named('model.test.event.default_get'), hasLength(1));
      expect(find.byType(DynamicFormScreen), findsOneWidget);
    }, variant: desktop);
  });
}
