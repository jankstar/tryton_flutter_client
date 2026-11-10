import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/model/model.dart';
import 'package:tryton_flutter_client/core/screen/calendar.dart';
import 'package:tryton_flutter_client/core/screen/graph.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';

import '../model/model_fixtures.dart';

/// Graph aggregation (spec 9.5, Python graph_gtk/graph.py `updateDatas`)
/// and calendar period/domain (spec 9.6, Python calendar_gtk).
void main() {
  RecordGroup records(Map<String, dynamic> fields, List<Map<String, dynamic>> rows) {
    final model = TrytonModel('test.model');
    model.addFields(fields);
    final g = RecordGroup(model);
    g.load([for (final r in rows) r['id'] as int]);
    for (final r in rows) {
      g.get(r['id'] as int)!.set(r, modified: false);
    }
    return g;
  }

  String date(TrytonDate d) => '${d.day}.${d.month}.';
  String dateTime(DateTime d) => '${d.day}.${d.month}. ${d.hour}h';

  group('graph', () {
    const arch = '<graph type="vbar">'
        '<x><field name="party"/></x>'
        '<y><field name="total"/><field name="#" string="Count"/>'
        '<field name="total" key="big" string="Big" color="red"'
        ' domain=\'{"__class__": "Greater", "s1": {"__class__": "Eval", "v": "total", "d": 0}, "s2": 50, "e": false}\'/>'
        '</y></graph>';
    final fields = {
      'party': fieldDesc('many2one', {'relation': 'party.party', 'string': 'Party'}),
      'total': fieldDesc('numeric', {'string': 'Total'}),
      'when': fieldDesc('date', {'string': 'Date'}),
      'state': fieldDesc('selection', {
        'string': 'State',
        'selection': [
          ['draft', 'Draft'],
          ['done', 'Done'],
        ],
      }),
    };

    test('sums per x, # counts, key and domain of a y; strings from the '
        'fields', () {
      final def = GraphDefinition.parse(arch, fields);
      expect(def.x!.string, 'Party');
      expect([for (final y in def.y) y.string], ['Total', 'Count', 'Big']);
      final g = records(fields, [
        {'id': 1, 'party': 7, 'party.': {'rec_name': 'B'}, 'total': TrytonDecimal('10.5')},
        {'id': 2, 'party': 3, 'party.': {'rec_name': 'A'}, 'total': TrytonDecimal('100')},
        {'id': 3, 'party': 7, 'party.': {'rec_name': 'B'}, 'total': TrytonDecimal('60')},
        {'id': 4, 'party': null, 'total': TrytonDecimal('1')},
      ]);
      final data = aggregateGraph(def, g,
          formatDate: date, formatDateTime: dateTime);
      expect(data.xs, [3, 7], reason: 'sorted by the value; no x skipped');
      expect(data.labels, {3: 'A', 7: 'B'});
      expect(data.value(7, 'total'), 70.5);
      expect(data.value(7, '#'), 2);
      expect(data.value(7, 'big'), 60, reason: 'domain total > 50');
      expect(data.value(3, 'big'), 100);
      expect(data.ids[7], [1, 3]);
      expect(data.range, (0.0, 100.0));
      final colors = def.colors();
      expect(colors['big'], 0xffcf1d1d, reason: 'colour of the y');
      expect(colors['total'], 0xff3465a4, reason: 'first key: the master colour');
      expect(colors['#'], isNot(colors['total']));
    });

    test('date axis: every day between the first and the last', () {
      final def = GraphDefinition.parse(
          '<graph type="line"><x><field name="when"/></x>'
          '<y><field name="#"/></y></graph>',
          fields);
      final g = records(fields, [
        {'id': 1, 'when': const TrytonDate(2026, 2, 27)},
        {'id': 2, 'when': const TrytonDate(2026, 3, 2)},
        {'id': 3, 'when': const TrytonDate(2026, 2, 27)},
      ]);
      final data = aggregateGraph(def, g,
          formatDate: date, formatDateTime: dateTime);
      expect([for (final x in data.xs) data.labels[x]],
          ['27.2.', '28.2.', '1.3.', '2.3.']);
      expect([for (final x in data.xs) data.value(x, '#')], [2, 0, 0, 1]);
      expect(data.ids[const TrytonDate(2026, 2, 28)], isNull);
    });

    test('selection x shows the label; colour scheme from a name', () {
      final def = GraphDefinition.parse(
          '<graph type="pie" color="green"><x><field name="state"/></x>'
          '<y><field name="total"/></y></graph>',
          fields);
      final g = records(fields, [
        {'id': 1, 'state': 'done', 'total': TrytonDecimal('2')},
        {'id': 2, 'state': 'draft', 'total': TrytonDecimal('3')},
      ]);
      final data = aggregateGraph(def, g,
          formatDate: date, formatDateTime: dateTime);
      expect(data.labels, {'done': 'Done', 'draft': 'Draft'});
      expect(def.colors()['total'], 0xff3fb41b);
    });
  });

  group('calendar', () {
    final fields = {
      'start': fieldDesc('datetime'),
      'end': fieldDesc('datetime'),
      'day': fieldDesc('date'),
      'name': fieldDesc('char'),
      'color': fieldDesc('char'),
    };
    CalendarState calendar(String attrs, {DateTime? today}) =>
        CalendarState.parse('<calendar $attrs><field name="name"/></calendar>',
            today: today ?? DateTime(2026, 11, 10));

    test('periods: month = six weeks from the week of the 1st, week, day',
        () {
      final c = calendar('dtstart="start" dtend="end"');
      expect(c.mode, 'month');
      // November 2026: the 1st is a Sunday → week from Monday 26 Oct
      expect(c.displayedPeriod, (DateTime(2026, 10, 26), DateTime(2026, 12, 7)));
      expect(c.days, hasLength(42));
      c.mode = 'week';
      expect(c.displayedPeriod, (DateTime(2026, 11, 9), DateTime(2026, 11, 16)));
      c.mode = 'day';
      expect(c.displayedPeriod, (DateTime(2026, 11, 10), DateTime(2026, 11, 11)));
      c.page(1);
      expect(c.selectedDate, DateTime(2026, 11, 11));
    });

    test('domain of the period; a period inside the last one does not '
        'search again', () {
      final model = TrytonModel('test.event')..addFields(fields);
      final c = calendar('dtstart="start" dtend="end" mode="month"');
      final start = DateTime(2026, 10, 26), end = DateTime(2026, 12, 7);
      expect(c.currentDomain(model.fields), [
        ['start', '!=', null],
        ['end', '!=', null],
        [
          'OR',
          ['AND', ['start', '>=', start], ['start', '<', end]],
          ['AND', ['end', '>=', start], ['end', '<', end]],
          ['AND', ['start', '<', start], ['end', '>', end]],
        ],
      ]);
      c.mode = 'week';
      expect(c.updateDomain(), isFalse, reason: 'week inside the month');
      c.page(5);
      expect(c.updateDomain(), isTrue);
      expect(c.domainPeriod, (DateTime(2026, 12, 14), DateTime(2026, 12, 21)));

      final d = calendar('dtstart="day"');
      final domain = d.currentDomain(model.fields);
      expect(domain[0], ['day', '!=', null]);
      expect(domain[1], ['day', '!=', null], reason: 'no dtend: dtstart');
      expect((domain[2] as List)[1], [
        'AND',
        ['day', '>=', const TrytonDate(2026, 10, 26)],
        ['day', '<', const TrytonDate(2026, 12, 7)],
      ]);
    });

    test('events: all day for dates, invalid ones skipped, colours, '
        'moving sets end first when later', () async {
      final g = records(fields, [
        {'id': 1, 'start': DateTime(2026, 11, 10, 9), 'end': DateTime(2026, 11, 10, 10), 'name': 'Meeting', 'color': '#f00'},
        {'id': 2, 'start': DateTime(2026, 11, 12), 'end': DateTime(2026, 11, 11), 'name': 'Invalid'},
        {'id': 3, 'start': null, 'name': 'No start'},
      ]);
      final c = calendar('dtstart="start" dtend="end" background_color="color"');
      final events = c.events(g);
      expect([for (final e in events) e.label], ['Meeting']);
      expect(events.single.allDay, isFalse);
      expect(events.single.backgroundColor, '#f00');
      expect(events.single.textColor, calendarDefaultColors.$1);
      expect(events.single.onDay(DateTime(2026, 11, 10)), isTrue);
      expect(events.single.onDay(DateTime(2026, 11, 11)), isFalse);
      expect(c.events(g, canWrite: false).single.editable, isFalse);

      final record = g.get(1)!;
      await c.move(record, DateTime(2026, 11, 12, 14), DateTime(2026, 11, 12, 15));
      expect(record.model.fields['start']!.get(record), DateTime(2026, 11, 12, 14));
      expect(record.model.fields['end']!.get(record), DateTime(2026, 11, 12, 15));
      expect(record.modified, isTrue);

      final days = records(fields, [
        {'id': 5, 'day': const TrytonDate(2026, 11, 3), 'name': 'Holiday'},
      ]);
      final allDay = calendar('dtstart="day"').events(days).single;
      expect(allDay.allDay, isTrue);
      await calendar('dtstart="day"').move(days.get(5)!, DateTime(2026, 11, 4), null);
      expect(days.get(5)!.model.fields['day']!.get(days.get(5)!),
          const TrytonDate(2026, 11, 4));
    });
  });
}
