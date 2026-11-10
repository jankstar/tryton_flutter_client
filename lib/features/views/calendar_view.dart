import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart';
import '../../core/screen/calendar.dart';
import '../../core/screen/graph.dart' show parseGraphColor;

/// Calendar view of a screen (spec 9.6, Python calendar_gtk, SAO
/// view/calendar.js): month (six weeks), week and day with a time grid.
/// Today/previous/next and the mode change the shown period
/// ([onPeriodChanged]: search again when it left the searched one); a
/// tap on an event opens it ([onOpen]); a double tap on a day or time
/// creates a record starting there ([onNew]); editable events are moved
/// by dragging and (with `dtend`) resized at their lower edge
/// ([onMove]: start/end set, the caller saves).
class CalendarView extends StatefulWidget {
  final CalendarState calendar;
  final List<CalendarEvent> events;
  final VoidCallback onPeriodChanged;
  final void Function(Record record) onOpen;

  /// Null: no records can be created (not editable or no create right).
  final VoidCallback? onNew;
  final Future<void> Function(CalendarEvent event, DateTime start,
      DateTime? end) onMove;

  const CalendarView({
    super.key,
    required this.calendar,
    required this.events,
    required this.onPeriodChanged,
    required this.onOpen,
    required this.onNew,
    required this.onMove,
  });

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

/// Height of one hour of the time grid.
const _hourHeight = 48.0;

/// Minutes a moved or resized event snaps to.
const _snapMinutes = 15;

class _CalendarViewState extends State<CalendarView> {
  final _grid = GlobalKey();
  final _scroll = ScrollController(
      initialScrollOffset: 7 * _hourHeight); // like SAO scrollTime 6–7h

  /// Live end change of the event being resized.
  CalendarEvent? _resizing;
  double _resizeDy = 0;

  CalendarState get _cal => widget.calendar;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _change(void Function() change) {
    setState(change);
    widget.onPeriodChanged();
  }

  String get _locale => Localizations.localeOf(context).toLanguageTag();

  bool get _touch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  // ─── Header ────────────────────────────────────────────────────────────

  String _title() {
    final d = _cal.selectedDate;
    switch (_cal.mode) {
      case 'day':
        return DateFormat.yMMMMEEEEd(_locale).format(d);
      case 'week':
        final (start, end) = _cal.displayedPeriod;
        final last = end.subtract(const Duration(days: 1));
        return '${DateFormat.yMMMd(_locale).format(start)} – '
            '${DateFormat.yMMMd(_locale).format(last)}';
      default:
        return DateFormat.yMMMM(_locale).format(d);
    }
  }

  Widget _header() {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          OutlinedButton(
            key: const ValueKey('calendar-today'),
            onPressed: () => _change(() => _cal.select(DateTime.now())),
            child: Text(l.calendarToday),
          ),
          IconButton(
            key: const ValueKey('calendar-previous'),
            tooltip: l.previousRecord,
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _change(() => _cal.page(-1)),
          ),
          IconButton(
            key: const ValueKey('calendar-next'),
            tooltip: l.nextRecord,
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _change(() => _cal.page(1)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(_title(),
                key: const ValueKey('calendar-title'),
                style: Theme.of(context).textTheme.titleMedium),
          ),
          SegmentedButton<String>(
            key: const ValueKey('calendar-mode'),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(value: 'month', label: Text(l.calendarMonth)),
              ButtonSegment(value: 'week', label: Text(l.calendarWeek)),
              ButtonSegment(value: 'day', label: Text(l.calendarDay)),
            ],
            selected: {_cal.mode},
            onSelectionChanged: (s) => _change(() => _cal.mode = s.first),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('calendar-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        const Divider(height: 1),
        Expanded(child: _cal.mode == 'month' ? _month() : _timeGrid()),
      ],
    );
  }

  // ─── Events ────────────────────────────────────────────────────────────

  Color _color(String value, Color fallback) {
    final c = parseGraphColor(value);
    return c == null ? fallback : Color(c);
  }

  Widget _chip(CalendarEvent e, {bool compact = true, double? height}) {
    final cs = Theme.of(context).colorScheme;
    final bg = _color(e.backgroundColor, cs.primary);
    final fg = _color(e.textColor, cs.onPrimary);
    final time = e.allDay ? '' : '${DateFormat.Hm(_locale).format(e.start)} ';
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(3)),
      child: Text(
        compact ? '$time${e.label.split('\n').first}' : '$time${e.label}',
        maxLines: compact ? 1 : null,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: fg, fontSize: 11),
      ),
    );
  }

  /// An event: tap opens; editable ones can be dragged (desktop at once,
  /// touch after a long press).
  Widget _event(CalendarEvent e, Widget child, {double width = 160}) {
    final tappable = GestureDetector(
      key: ValueKey('calendar-event-${e.record.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onOpen(e.record),
      child: Tooltip(message: e.label, waitDuration: const Duration(seconds: 1), child: child),
    );
    if (!e.editable) return tappable;
    final feedback = Material(
      color: Colors.transparent,
      child: SizedBox(width: width, child: Opacity(opacity: 0.8, child: child)),
    );
    return _touch
        ? LongPressDraggable<CalendarEvent>(
            data: e, feedback: feedback, child: tappable)
        : Draggable<CalendarEvent>(
            data: e, feedback: feedback, child: tappable);
  }

  /// Moves [e] by whole days to [day] (time and duration kept).
  void _moveToDay(CalendarEvent e, DateTime day) {
    final from = DateTime(e.start.year, e.start.month, e.start.day);
    final days = DateTime.utc(day.year, day.month, day.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;
    if (days == 0) return;
    DateTime shift(DateTime d) =>
        DateTime(d.year, d.month, d.day + days, d.hour, d.minute, d.second);
    widget.onMove(e, shift(e.start), e.end == null ? null : shift(e.end!));
  }

  // ─── Month ─────────────────────────────────────────────────────────────

  Widget _weekdayHeader(List<DateTime> days) => Row(children: [
        for (final d in days)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(DateFormat.E(_locale).format(d),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
      ]);

  Widget _month() {
    final days = _cal.days;
    final today = DateUtils.dateOnly(DateTime.now());
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final rowHeight = math.max(84.0, (box.maxHeight - 24) / 6);
      final perCell = math.max(1, ((rowHeight - 22) / 18).floor());
      return SingleChildScrollView(
        child: Column(children: [
          _weekdayHeader(days.sublist(0, 7)),
          for (var w = 0; w < 6; w++)
            SizedBox(
              height: rowHeight,
              child: Row(children: [
                for (final day in days.sublist(w * 7, w * 7 + 7))
                  Expanded(child: _monthCell(day, today, cs, perCell)),
              ]),
            ),
        ]),
      );
    });
  }

  Widget _monthCell(DateTime day, DateTime today, ColorScheme cs, int perCell) {
    final events = [for (final e in widget.events) if (e.onDay(day)) e];
    final selected = DateUtils.isSameDay(day, _cal.selectedDate);
    final other = day.month != _cal.selectedDate.month;
    final shown = events.length > perCell ? perCell - 1 : events.length;
    return DragTarget<CalendarEvent>(
      onAcceptWithDetails: (d) => _moveToDay(d.data, day),
      builder: (context, candidates, _) => GestureDetector(
        key: ValueKey('calendar-day-${DateFormat('yyyy-MM-dd').format(day)}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _cal.select(day)),
        onDoubleTap: widget.onNew == null
            ? null
            : () {
                setState(() => _cal.select(day));
                widget.onNew!();
              },
        child: Container(
          decoration: BoxDecoration(
            color: candidates.isNotEmpty
                ? cs.primaryContainer
                : selected
                    ? cs.secondaryContainer.withValues(alpha: 0.5)
                    : null,
            border: Border.all(color: cs.outlineVariant, width: 0.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
              child: Text('${day.day}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: DateUtils.isSameDay(day, today)
                        ? FontWeight.bold
                        : null,
                    color: DateUtils.isSameDay(day, today)
                        ? cs.primary
                        : other
                            ? cs.outline
                            : null,
                  )),
            ),
            for (final e in events.take(shown)) _event(e, _chip(e)),
            if (shown < events.length)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text('+${events.length - shown}',
                    style: TextStyle(fontSize: 11, color: cs.outline)),
              ),
          ]),
        ),
      ),
    );
  }

  // ─── Week and day ──────────────────────────────────────────────────────

  Widget _timeGrid() {
    final days = _cal.days;
    final cs = Theme.of(context).colorScheme;
    final allDay = [for (final e in widget.events) if (e.allDay) e];
    const gutter = 48.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const SizedBox(width: gutter),
        Expanded(child: Row(children: [
          for (final d in days)
            Expanded(
              child: Text(
                  _cal.mode == 'day'
                      ? DateFormat.EEEE(_locale).format(d)
                      : DateFormat.MEd(_locale).format(d),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall),
            ),
        ])),
      ]),
      // all-day events
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(width: gutter),
        Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final d in days)
            Expanded(
              child: DragTarget<CalendarEvent>(
                onWillAcceptWithDetails: (det) => det.data.allDay,
                onAcceptWithDetails: (det) => _moveToDay(det.data, d),
                builder: (context, candidates, _) => Container(
                  constraints: const BoxConstraints(minHeight: 24),
                  decoration: BoxDecoration(
                    color: candidates.isNotEmpty ? cs.primaryContainer : null,
                    border: Border.all(color: cs.outlineVariant, width: 0.5),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final e in allDay)
                      if (e.onDay(d)) _event(e, _chip(e)),
                  ]),
                ),
              ),
            ),
        ])),
      ]),
      Expanded(
        child: SingleChildScrollView(
          controller: _scroll,
          child: SizedBox(
            height: 24 * _hourHeight,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: gutter,
                child: Stack(children: [
                  for (var h = 1; h < 24; h++)
                    Positioned(
                      top: h * _hourHeight - 7,
                      right: 6,
                      child: Text(
                          DateFormat.Hm(_locale).format(DateTime(2000, 1, 1, h)),
                          style: TextStyle(fontSize: 10, color: cs.outline)),
                    ),
                ]),
              ),
              Expanded(child: _gridBody(days, cs)),
            ]),
          ),
        ),
      ),
    ]);
  }

  /// The time grid of [days]: one drop target (the time from the drop
  /// position), double tap on a time creates a record there.
  Widget _gridBody(List<DateTime> days, ColorScheme cs) {
    return LayoutBuilder(builder: (context, box) {
      final column = box.maxWidth / days.length;
      DateTime at(Offset local, {bool snap = true}) {
        final i = (local.dx / column).floor().clamp(0, days.length - 1);
        var minutes = (local.dy / _hourHeight * 60).round();
        if (snap) minutes = (minutes / _snapMinutes).round() * _snapMinutes;
        minutes = minutes.clamp(0, 24 * 60 - _snapMinutes);
        final d = days[i];
        return DateTime(d.year, d.month, d.day, minutes ~/ 60, minutes % 60);
      }

      Offset? tapped;
      return DragTarget<CalendarEvent>(
        key: _grid,
        onWillAcceptWithDetails: (det) => !det.data.allDay,
        onAcceptWithDetails: (det) {
          final box = _grid.currentContext?.findRenderObject() as RenderBox?;
          if (box == null) return;
          final e = det.data;
          final start = at(box.globalToLocal(det.offset));
          final end = e.end == null ? null : start.add(e.end!.difference(e.start));
          if (start != e.start) widget.onMove(e, start, end);
        },
        builder: (context, candidates, _) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => tapped = d.localPosition,
          onTap: () {
            final p = tapped;
            if (p != null) setState(() => _cal.select(at(p), withTime: true));
          },
          onDoubleTap: widget.onNew == null
              ? null
              : () {
                  final p = tapped;
                  if (p != null) _cal.select(at(p), withTime: true);
                  widget.onNew!();
                },
          child: Stack(children: [
            // hour lines and day columns
            for (var h = 0; h < 24; h++)
              Positioned(
                top: h * _hourHeight,
                left: 0,
                right: 0,
                child: Divider(height: 1, color: cs.outlineVariant),
              ),
            for (var i = 0; i < days.length; i++)
              Positioned(
                top: 0,
                bottom: 0,
                left: i * column,
                width: column,
                child: Container(
                  decoration: BoxDecoration(
                    color: DateUtils.isSameDay(days[i], DateTime.now())
                        ? cs.primaryContainer.withValues(alpha: 0.25)
                        : null,
                    border: Border(
                        left: BorderSide(color: cs.outlineVariant, width: 0.5)),
                  ),
                ),
              ),
            for (var i = 0; i < days.length; i++)
              ..._timedEvents(days[i], i * column, column),
          ]),
        ),
      );
    });
  }

  /// Timed events of [day] in its column: overlapping ones side by side.
  List<Widget> _timedEvents(DateTime day, double left, double width) {
    final next = DateTime(day.year, day.month, day.day + 1);
    final events = [
      for (final e in widget.events)
        if (!e.allDay && e.onDay(day)) e,
    ];
    // lanes: each event in the first lane free at its start
    final lanes = <DateTime>[];
    final laneOf = <CalendarEvent, int>{};
    for (final e in events) {
      final start = e.start.isBefore(day) ? day : e.start;
      var lane = lanes.indexWhere((end) => !end.isAfter(start));
      final end = _endOf(e);
      if (lane < 0) {
        lanes.add(end);
        lane = lanes.length - 1;
      } else {
        lanes[lane] = end;
      }
      laneOf[e] = lane;
    }
    final laneWidth = width / math.max(1, lanes.length);
    return [
      for (final e in events)
        () {
          final start = e.start.isBefore(day) ? day : e.start;
          var end = _endOf(e);
          if (identical(e, _resizing)) {
            end = end.add(Duration(
                minutes: ((_resizeDy / _hourHeight * 60) / _snapMinutes).round() *
                    _snapMinutes));
          }
          if (end.isAfter(next)) end = next;
          final top = start.difference(day).inMinutes / 60 * _hourHeight;
          final height = math.max(18.0,
              end.difference(start).inMinutes / 60 * _hourHeight - 2);
          return Positioned(
            top: top,
            left: left + laneOf[e]! * laneWidth,
            width: laneWidth - 2,
            height: height,
            child: Stack(children: [
              Positioned.fill(
                child: _event(e, _chip(e, compact: height < 36, height: height),
                    width: laneWidth - 2),
              ),
              if (e.editable && e.end != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 6,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeRow,
                    child: GestureDetector(
                      key: ValueKey('calendar-resize-${e.record.id}'),
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: (_) => setState(() {
                        _resizing = e;
                        _resizeDy = 0;
                      }),
                      onVerticalDragUpdate: (d) =>
                          setState(() => _resizeDy += d.delta.dy),
                      onVerticalDragEnd: (_) => _endResize(e),
                      onVerticalDragCancel: () =>
                          setState(() => _resizing = null),
                    ),
                  ),
                ),
            ]),
          );
        }(),
    ];
  }

  /// End shown for an event: without end one snap long.
  DateTime _endOf(CalendarEvent e) {
    final end = e.end ?? e.start.add(const Duration(minutes: 60));
    return end.isAfter(e.start)
        ? end
        : e.start.add(const Duration(minutes: _snapMinutes));
  }

  void _endResize(CalendarEvent e) {
    final minutes =
        ((_resizeDy / _hourHeight * 60) / _snapMinutes).round() * _snapMinutes;
    setState(() => _resizing = null);
    if (minutes == 0 || e.end == null) return;
    var end = e.end!.add(Duration(minutes: minutes));
    final min = e.start.add(const Duration(minutes: _snapMinutes));
    if (end.isBefore(min)) end = min;
    widget.onMove(e, e.start, end);
  }
}
