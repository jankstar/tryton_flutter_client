import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain/date_text.dart';
import '../../core/screen/graph.dart';
import '../../core/screen/screen.dart';
import '../../shared/utils/date_format_utils.dart';
import '../../shared/utils/number_format_utils.dart';
import '../auth/user_preferences_provider.dart';

/// Graph view of a screen (spec 9.5, Python graph_gtk): the loaded
/// records of the search summed per x ([aggregateGraph]) as vertical or
/// horizontal bars, lines or pie (fl_chart). A tap on a bar, point or
/// slice calls [onOpen] with the ids of its records (keyword
/// `graph_open`).
class GraphView extends ConsumerStatefulWidget {
  final TrytonScreen screen;
  final GraphDefinition definition;
  final void Function(List<int> ids) onOpen;

  const GraphView({
    super.key,
    required this.screen,
    required this.definition,
    required this.onOpen,
  });

  @override
  ConsumerState<GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends ConsumerState<GraphView> {
  bool _loading = false;

  /// Width of the chart (number of x labels that fit).
  double _width = 800;

  GraphDefinition get _def => widget.definition;

  /// Loads the x/y fields of all records of the group (in batches of the
  /// group, Python reads them on access).
  Future<void> _load() async {
    final x = _def.x?.name;
    if (x == null || _loading) return;
    _loading = true;
    try {
      for (final record in widget.screen.group.toList()) {
        if (!mounted) return;
        if (!record.isLoaded(x)) await record.load(x, processException: false);
      }
    } catch (_) {
      // shown as far as loaded
    } finally {
      _loading = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final x = _def.x?.name;
    final group = widget.screen.group;
    if (x != null && group.any((r) => !r.isLoaded(x)) && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final dateFormat = ref.watch(dateFormatProvider);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final data = aggregateGraph(
      _def,
      group.where((r) => x == null || r.isLoaded(x)),
      formatDate: (d) => formatDate(d.toDateTime(), dateFormat, locale),
      formatDateTime: (d) =>
          '${formatDate(d, dateFormat, locale)} ${strftime(d, '%H:%M:%S')}',
    );
    final numbers = ref.watch(numberLocaleProvider) ?? const NumberLocale();
    final colors = {
      for (final MapEntry(:key, :value) in _def.colors().entries)
        key: Color(value),
    };
    final cs = Theme.of(context).colorScheme;
    final background = _def.background == null
        ? null
        : parseGraphColor(_def.background!);
    final chart = data.xs.isEmpty
        ? Center(
            child: Text(_loading ? '…' : '—',
                style: TextStyle(color: cs.outline)))
        : switch (_def.type) {
            'pie' => _pie(data, numbers),
            'line' => _line(data, colors, numbers),
            'hbar' => _bar(data, colors, numbers, horizontal: true),
            _ => _bar(data, colors, numbers, horizontal: false),
          };
    return Container(
      key: const ValueKey('graph-view'),
      decoration: BoxDecoration(
        gradient: background == null
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [cs.surface, Color(background)],
              ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 16, 20, 12),
      child: Column(children: [
        if (_def.legend) _legend(data, colors),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            _width = box.maxWidth;
            return chart;
          }),
        ),
      ]),
    );
  }

  // ─── Labels ────────────────────────────────────────────────────────────

  /// All y values are timedeltas (Python: the labels as timedelta).
  bool get _timedelta =>
      _def.y.isNotEmpty && _def.y.every((y) => y.isTimedelta);

  String _value(double v, NumberLocale numbers) {
    if (_timedelta) {
      return formatTimedelta(
          Duration(microseconds: (v * 1e6).round()));
    }
    final whole = v == v.roundToDouble();
    return numbers.localize(whole ? v.toInt().toString() : v.toStringAsFixed(2));
  }

  Widget _legend(GraphData data, Map<String, Color> colors) {
    final entries = _def.type == 'pie'
        ? [
            for (final (i, x) in data.xs.indexed)
              (data.labels[x] ?? '$x', _pieColor(i, data.xs.length)),
          ]
        : [for (final y in _def.y) (y.string, colors[y.key] ?? Colors.grey)];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(spacing: 16, runSpacing: 4, children: [
        for (final (label, color) in entries)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, color: color),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ]),
      ]),
    );
  }

  Color _pieColor(int index, int count) {
    final master = parseGraphColor(_def.color) ?? 0xff3465a4;
    final scheme =
        generateColorScheme(master, [for (var i = 0; i < count; i++) '$i']);
    return Color(scheme['$index'] ?? master);
  }

  AxisTitles _xTitles(GraphData data, {required bool rotate}) => AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: rotate ? 40 : 28,
          interval: 1,
          getTitlesWidget: (value, meta) {
            final i = value.round();
            if (i < 0 || i >= data.xs.length || value != i.toDouble()) {
              return const SizedBox.shrink();
            }
            // as many labels as fit (the longest one wide)
            final longest = data.labels.values
                .fold(4, (m, l) => math.max(m, l.length));
            final fit = math.max(1, (_width - 56) ~/ (longest * 6.5 + 12));
            final step = math.max(1, (data.xs.length / fit).ceil());
            if (i % step != 0) return const SizedBox.shrink();
            return SideTitleWidget(
              meta: meta,
              child: Text(data.labels[data.xs[i]] ?? '',
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            );
          },
        ),
      );

  AxisTitles _yTitles(GraphData data, NumberLocale numbers) => AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 56,
          interval: _yInterval(data),
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            child: Text(_value(value, numbers),
                style: const TextStyle(fontSize: 11)),
          ),
        ),
      );

  /// About five steps of 1, 2 or 5 × 10ⁿ on the value axis.
  static double _yInterval(GraphData data) {
    final (min, max) = data.range;
    final raw = (max - min) / 5;
    if (raw <= 0) return 1;
    final exp = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final f = raw / exp;
    return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * exp;
  }

  void _open(GraphData data, int index) {
    if (index < 0 || index >= data.xs.length) return;
    final ids = data.ids[data.xs[index]] ?? const <int>[];
    if (ids.isNotEmpty) widget.onOpen(ids);
  }

  // ─── Charts ────────────────────────────────────────────────────────────

  Widget _bar(GraphData data, Map<String, Color> colors, NumberLocale numbers,
      {required bool horizontal}) {
    final (min, max) = data.range;
    return BarChart(
      key: const ValueKey('graph-bar'),
      BarChartData(
        rotationQuarterTurns: horizontal ? 1 : 0,
        minY: min,
        maxY: max == min ? min + 1 : max,
        alignment: BarChartAlignment.spaceAround,
        titlesData: FlTitlesData(
          bottomTitles: _xTitles(data, rotate: horizontal),
          leftTitles: _yTitles(data, numbers),
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(horizontalInterval: _yInterval(data)),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                BarTooltipItem(
              '${data.labels[data.xs[groupIndex]]}\n'
              '${_def.y[rodIndex].string}: ${_value(rod.toY, numbers)}',
              const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          touchCallback: (event, response) {
            if (event is FlTapUpEvent) {
              _open(data, response?.spot?.touchedBarGroupIndex ?? -1);
            }
          },
        ),
        barGroups: [
          for (final (i, x) in data.xs.indexed)
            BarChartGroupData(x: i, barsSpace: 2, barRods: [
              for (final y in _def.y)
                BarChartRodData(
                  toY: data.value(x, y.key),
                  color: colors[y.key],
                  width: math.max(
                      4, math.min(24, 240 / (data.xs.length * _def.y.length))),
                  borderRadius: BorderRadius.zero,
                ),
            ]),
        ],
      ),
    );
  }

  Widget _line(GraphData data, Map<String, Color> colors, NumberLocale numbers) {
    final (min, max) = data.range;
    return LineChart(
      key: const ValueKey('graph-line'),
      LineChartData(
        minY: min,
        maxY: max == min ? min + 1 : max,
        minX: 0,
        maxX: math.max(1, data.xs.length - 1).toDouble(),
        titlesData: FlTitlesData(
          bottomTitles: _xTitles(data, rotate: false),
          leftTitles: _yTitles(data, numbers),
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
            horizontalInterval: _yInterval(data), drawVerticalLine: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${_def.y[s.barIndex].string}: ${_value(s.y, numbers)}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                ),
            ],
          ),
          touchCallback: (event, response) {
            final spots = response?.lineBarSpots;
            if (event is FlTapUpEvent && spots != null && spots.isNotEmpty) {
              _open(data, spots.first.spotIndex);
            }
          },
        ),
        lineBarsData: [
          for (final y in _def.y)
            LineChartBarData(
              spots: [
                for (final (i, x) in data.xs.indexed)
                  FlSpot(i.toDouble(), data.value(x, y.key)),
              ],
              color: colors[y.key],
              barWidth: 2,
              isStepLineChart: y.interpolation != 'linear',
              lineChartStepData: LineChartStepData(
                stepDirection: switch (y.interpolation) {
                  'constant-left' => LineChartStepData.stepDirectionForward,
                  'constant-right' => LineChartStepData.stepDirectionBackward,
                  _ => LineChartStepData.stepDirectionMiddle,
                },
              ),
              dotData: FlDotData(show: data.xs.length <= 40),
              belowBarData: BarAreaData(
                show: y.fill(),
                color: (colors[y.key] ?? Colors.grey)
                    .withValues(alpha: 0.8 / _def.y.length),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pie(GraphData data, NumberLocale numbers) {
    final key = _def.y.isEmpty ? null : _def.y.first.key;
    if (key == null) return const SizedBox.shrink();
    final xs = [
      for (final (i, x) in data.xs.indexed)
        if (data.value(x, key) > 0) (i, x),
    ];
    final sum = xs.fold(0.0, (s, e) => s + data.value(e.$2, key));
    final fill = _def.y.first.fill(byDefault: true);
    return LayoutBuilder(builder: (context, box) {
      final radius = math.max(40.0, math.min(box.maxWidth, box.maxHeight) / 2 - 24);
      return PieChart(
        key: const ValueKey('graph-pie'),
        PieChartData(
          centerSpaceRadius: 0,
          sectionsSpace: fill ? 1 : 0,
          pieTouchData: PieTouchData(
            touchCallback: (event, response) {
              final index = response?.touchedSection?.touchedSectionIndex;
              if (event is FlTapUpEvent && index != null && index >= 0 &&
                  index < xs.length) {
                _open(data, xs[index].$1);
              }
            },
          ),
          sections: [
            for (final (i, x) in xs)
              PieChartSectionData(
                value: data.value(x, key),
                radius: radius,
                color: _pieColor(i, data.xs.length),
                title: '${data.labels[x]}\n${_value(data.value(x, key), numbers)}'
                    ' (${(100 * data.value(x, key) / sum).toStringAsFixed(0)} %)',
                titleStyle: const TextStyle(fontSize: 11, color: Colors.white),
                titlePositionPercentageOffset: 0.6,
              ),
          ],
        ),
      );
    });
  }
}
