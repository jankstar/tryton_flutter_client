import 'package:xml/xml.dart';

import '../model/model.dart';
import '../serialization/tryton_serializer.dart';

// Calendar view (spec 9.6; Python gui/window/view_form/view/calendar_.py
// and calendar_gtk/calendar_.py, SAO view/calendar.js): the definition
// of `<calendar>`, the shown period with its search domain and the
// events of the loaded records – no widgets.

/// Default text and background colour of the events (Python
/// `CONFIG['calendar.colors']`).
const calendarDefaultColors = ('#fff', '#3465a4');

/// One event of the calendar: [start]/[end] local, [allDay] for date
/// fields; [end] null without `dtend`.
class CalendarEvent {
  final Record record;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final bool editable;
  final String label;
  final String textColor;
  final String backgroundColor;

  const CalendarEvent({
    required this.record,
    required this.start,
    required this.end,
    required this.allDay,
    required this.editable,
    required this.label,
    required this.textColor,
    required this.backgroundColor,
  });

  /// Last moment of the event (the start without end).
  DateTime get last => end ?? start;

  /// The event touches the day [day] (local midnight).
  bool onDay(DateTime day) {
    final next = DateTime(day.year, day.month, day.day + 1);
    if (!start.isBefore(next)) return false;
    if (!start.isBefore(day)) return true;
    return allDay ? !last.isBefore(day) : last.isAfter(day);
  }
}

/// `<calendar dtstart dtend mode color background_color editable>` with
/// its title fields and the shown period (Python `Calendar_`).
class CalendarState {
  final Map<String, String> attributes;

  /// Names of the `<field>` nodes: the lines of an event's text.
  final List<String> fields;

  /// `month`, `week` or `day`.
  String mode;

  /// The selected day (local midnight).
  DateTime selectedDate;

  /// First day of a week ([DateTime.monday] … [DateTime.sunday]).
  final int firstWeekday;

  /// Period of the last search (Python `current_domain_period`).
  late (DateTime, DateTime) domainPeriod = displayedPeriod;

  CalendarState(this.attributes, this.fields,
      {DateTime? today, this.firstWeekday = DateTime.monday})
      : mode = switch (attributes['mode']) {
          'week' => 'week',
          'day' => 'day',
          _ => 'month',
        },
        selectedDate = _day(today ?? DateTime.now());

  factory CalendarState.parse(String arch,
      {DateTime? today, int firstWeekday = DateTime.monday}) {
    final root = XmlDocument.parse(arch).rootElement;
    return CalendarState(
      {for (final a in root.attributes) a.localName: a.value},
      [
        for (final e in root.childElements)
          if (e.localName == 'field' && e.getAttribute('name') != null)
            e.getAttribute('name')!,
      ],
      today: today,
      firstWeekday: firstWeekday,
    );
  }

  String get dtstart => attributes['dtstart'] ?? '';
  String? get dtend =>
      (attributes['dtend'] ?? '').isEmpty ? null : attributes['dtend'];

  /// `editable` (default 1): events can be moved, days create records.
  bool get editable =>
      (int.tryParse(attributes['editable'] ?? '1') ?? 1) != 0;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// First day of the week of [day].
  DateTime weekStart(DateTime day) {
    final back = (day.weekday - firstWeekday) % 7;
    return DateTime(day.year, day.month, day.day - back);
  }

  /// Shown period [start, end) (Python `get_displayed_period`): the day;
  /// the week; six weeks from the week of the first of the month.
  (DateTime, DateTime) get displayedPeriod {
    final d = selectedDate;
    switch (mode) {
      case 'day':
        return (d, DateTime(d.year, d.month, d.day + 1));
      case 'week':
        final start = weekStart(d);
        return (start, DateTime(start.year, start.month, start.day + 7));
      default:
        final start = weekStart(DateTime(d.year, d.month, 1));
        return (start, DateTime(start.year, start.month, start.day + 42));
    }
  }

  /// The days of the shown period.
  List<DateTime> get days {
    final (start, end) = displayedPeriod;
    return [
      for (var d = start; d.isBefore(end); d = DateTime(d.year, d.month, d.day + 1))
        d,
    ];
  }

  /// Takes the shown period for the search when it is not inside the
  /// last one (Python `update_domain`); true = search again.
  bool updateDomain() {
    final (start, end) = displayedPeriod;
    final (cs, ce) = domainPeriod;
    if (!start.isBefore(cs) && !end.isAfter(ce)) return false;
    domainPeriod = (start, end);
    return true;
  }

  /// Search domain of the period (Python `current_domain`): events with
  /// start and end overlapping it; date fields compare dates.
  List<dynamic> currentDomain(Map<String, Field> modelFields) {
    var (Object start, Object end) = domainPeriod;
    final dtstart = this.dtstart;
    final dtend = this.dtend ?? dtstart;
    if (modelFields[dtstart] is DateField) {
      start = TrytonDate.fromDateTime(start as DateTime);
    }
    if (modelFields[dtend] is DateField) {
      end = TrytonDate.fromDateTime(end as DateTime);
    }
    return [
      [dtstart, '!=', null],
      [dtend, '!=', null],
      [
        'OR',
        [
          'AND',
          [dtstart, '>=', start],
          [dtstart, '<', end],
        ],
        [
          'AND',
          [dtend, '>=', start],
          [dtend, '<', end],
        ],
        [
          'AND',
          [dtstart, '<', start],
          [dtend, '>', end],
        ],
      ],
    ];
  }

  /// Moves through the periods (Python `previous_page`/`next_page`).
  void page(int step) {
    _selectedTime = null;
    final d = selectedDate;
    selectedDate = switch (mode) {
      'day' => DateTime(d.year, d.month, d.day + step),
      'week' => DateTime(d.year, d.month, d.day + 7 * step),
      _ => DateTime(d.year, d.month + step, 1),
    };
  }

  /// Selects the day of [moment]; a time of the week/day view is kept
  /// as [selectedMoment] (start of a new record).
  void select(DateTime moment, {bool withTime = false}) {
    selectedDate = _day(moment);
    _selectedTime = withTime ? moment : null;
  }

  DateTime? _selectedTime;

  /// Start of a new record: the chosen time, else the selected day at
  /// midnight (Python `set_default_date`).
  DateTime get selectedMoment => _selectedTime ?? selectedDate;

  /// The events of [records] (Python `display`): records without start
  /// and with the end before the start are skipped; an event is editable
  /// with `editable`, the write right [canWrite] and start/end not
  /// readonly.
  List<CalendarEvent> events(Iterable<Record> records,
      {bool canWrite = true}) {
    final result = <CalendarEvent>[];
    for (final record in records) {
      final fields = record.model.fields;
      final startField = fields[dtstart];
      if (startField == null) continue;
      final startValue = startField.get(record);
      if (startValue == null) continue;
      final endField = dtend == null ? null : fields[dtend];
      final endValue = endField?.get(record);
      final start = _toDateTime(startValue);
      final end = endValue == null ? null : _toDateTime(endValue);
      if (start == null) continue;
      if (end != null && start.isAfter(end)) continue;
      final allDay =
          startValue is TrytonDate && (endValue == null || endValue is TrytonDate);
      bool readonly(Field? f) {
        if (f == null) return false;
        f.setState(record);
        return f.stateAttrs(record)['readonly'] == true;
      }
      final label = [
        for (final name in this.fields)
          if (fields[name] case final f?) _text(f.getClient(record)),
      ].join('\n').trimRight();
      String color(String? attr, String fallback) {
        if (attr == null || attr.isEmpty) return fallback;
        final v = fields[attr]?.get(record);
        return v is String && v.isNotEmpty ? v : fallback;
      }

      result.add(CalendarEvent(
        record: record,
        start: start,
        end: end,
        allDay: allDay,
        editable: editable &&
            canWrite &&
            !readonly(startField) &&
            !readonly(endField),
        label: label,
        textColor: color(attributes['color'], calendarDefaultColors.$1),
        backgroundColor: color(
            attributes['background_color'], calendarDefaultColors.$2),
      ));
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  /// Sets the new start/end of a moved event (Python `on_event_released`,
  /// SAO `event_drop`): date fields take the dates; moved later the end
  /// is set first (keeps start ≤ end for on_change). Not saved here.
  Future<void> move(Record record, DateTime start, DateTime? end) async {
    final fields = record.model.fields;
    final startField = fields[dtstart]!;
    final endField = dtend == null ? null : fields[dtend];
    final previous = _toDateTime(startField.get(record));
    final Object newStart =
        startField is DateField ? TrytonDate.fromDateTime(start) : start;
    final Object? newEnd = end == null
        ? null
        : endField is DateField
            ? TrytonDate.fromDateTime(end)
            : end;
    if (previous == null || !previous.isAfter(start)) {
      if (endField != null) await endField.setClient(record, newEnd);
      await startField.setClient(record, newStart);
    } else {
      await startField.setClient(record, newStart);
      if (endField != null) await endField.setClient(record, newEnd);
    }
  }

  /// Start of a new record (Python/SAO `set_default_date`): [moment]
  /// (the day at midnight or the chosen time), a date for date fields;
  /// then on_change/on_change_with of the start.
  Future<void> setDefaultDate(Record record, DateTime moment) async {
    final field = record.model.fields[dtstart];
    if (field == null) return;
    await field.setClient(
        record, field is DateField ? TrytonDate.fromDateTime(moment) : moment);
  }

  static DateTime? _toDateTime(dynamic v) => switch (v) {
        DateTime() => v,
        TrytonDate() => v.toDateTime(),
        _ => null,
      };

  static String _text(dynamic v) => v == null || v == false ? '' : '$v';
}
