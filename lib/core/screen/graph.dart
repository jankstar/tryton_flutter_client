import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../model/model.dart';
import '../serialization/tryton_serializer.dart';

// Graph view (spec 9.5; Python gui/window/view_form/view/graph.py and
// graph_gtk/graph.py `updateDatas`, `setColorScheme`): the definition of
// `<graph>` and the aggregation of the loaded records – no widgets.

/// Named colours of `color` (Python `common.COLOR_SCHEMES`).
const graphColorSchemes = {
  'red': '#cf1d1d',
  'green': '#3fb41b',
  'blue': '#224565',
  'grey': '#444444',
  'black': '#000000',
  'darkcyan': '#305755',
};

/// Default colour of a graph (Python `CONFIG['graph.color']`).
const graphDefaultColor = '#3465a4';

/// A `<field>` of `<x>` or `<y>` with its attributes (`string` from the
/// field description when missing, not for `#`).
class GraphField {
  final Map<String, String> attributes;
  const GraphField(this.attributes);

  String get name => attributes['name'] ?? '';

  /// Key of a y value (several y of the same field differ by `key`).
  String get key => attributes['key'] ?? name;
  String get string => attributes['string'] ?? name;
  String? get color => attributes['color'];

  /// The count of the records (`name="#"`).
  bool get isCount => name == '#';

  /// Line filled (`fill`, line default 0, pie default 1).
  bool fill({bool byDefault = false}) {
    final v = attributes['fill'];
    return v == null ? byDefault : (int.tryParse(v) ?? 0) != 0;
  }

  /// `linear` (default), `constant-center`, `constant-left`,
  /// `constant-right`.
  String get interpolation => attributes['interpolation'] ?? 'linear';

  /// The y value is a timedelta shown with this converter (`timedelta`).
  bool get isTimedelta => attributes.containsKey('timedelta');
  String? get timedelta => attributes['timedelta'];

  /// PYSON domain a record must satisfy to count (`domain`).
  String? get domain => attributes['domain'];
}

/// `<graph type color legend background>` with its `<x>`/`<y>` fields.
class GraphDefinition {
  final Map<String, String> attributes;
  final GraphField? x;
  final List<GraphField> y;

  const GraphDefinition(this.attributes, this.x, this.y);

  /// `vbar` (default), `hbar`, `line`, `pie`.
  String get type => attributes['type'] ?? 'vbar';

  /// Master colour (named or `#rrggbb`).
  String get color => attributes['color'] ?? graphDefaultColor;

  bool get legend => (int.tryParse(attributes['legend'] ?? '1') ?? 1) != 0;

  String? get background => attributes['background'];

  /// Parses the `arch` of a graph view; [fields] are the field
  /// descriptions of `fields_view_get`.
  factory GraphDefinition.parse(String arch, Map<String, dynamic> fields) {
    final root = XmlDocument.parse(arch).rootElement;
    GraphField field(XmlElement e) {
      final attrs = {for (final a in e.attributes) a.localName: a.value};
      final name = attrs['name'];
      if ((attrs['string'] ?? '').isEmpty && name != null && name != '#') {
        final desc = fields[name];
        if (desc is Map && desc['string'] != null) {
          attrs['string'] = '${desc['string']}';
        }
      }
      return GraphField(attrs);
    }

    GraphField? x;
    final y = <GraphField>[];
    for (final child in root.childElements) {
      final fieldNodes = child.childElements
          .where((e) => e.localName == 'field')
          .map(field);
      if (child.localName == 'x') {
        if (fieldNodes.isNotEmpty) x = fieldNodes.last;
      } else if (child.localName == 'y') {
        y.addAll(fieldNodes);
      }
    }
    return GraphDefinition(
        {for (final a in root.attributes) a.localName: a.value}, x, y);
  }

  /// Colour of every y key (Python `setColorScheme`): derived from
  /// [color] by the golden angle, a y `color` wins.
  Map<String, int> colors() {
    final keys = [for (final f in y) f.key];
    final master = parseGraphColor(color) ?? parseGraphColor(graphDefaultColor)!;
    final r = ((master >> 16) & 0xff) / 255;
    final g = ((master >> 8) & 0xff) / 255;
    final b = (master & 0xff) / 255;
    final maxColor = math.max(math.max(r, g), b);
    final result = generateColorScheme(master, keys,
        maxColor / (keys.isEmpty ? 1 : keys.length));
    for (final f in y) {
      final c = f.color == null ? null : parseGraphColor(f.color!);
      if (c != null) result[f.key] = c;
    }
    return result;
  }
}

/// `#rgb`/`#rrggbb` or a name of [graphColorSchemes] → 0xAARRGGBB.
int? parseGraphColor(String color) {
  var hex = graphColorSchemes[color] ?? color;
  if (!hex.startsWith('#')) return null;
  hex = hex.substring(1);
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length != 6) return null;
  final v = int.tryParse(hex, radix: 16);
  return v == null ? null : 0xff000000 | v;
}

/// Colours for [keys] derived from [master] (Python
/// `generateColorscheme`): each one hue further by the golden angle and
/// lighter by [light].
Map<String, int> generateColorScheme(int master, List<String> keys,
    [double light = 0.1]) {
  final (h, s, v) = _rgbToHsv(((master >> 16) & 0xff) / 255,
      ((master >> 8) & 0xff) / 255, (master & 0xff) / 255);
  if (keys.isNotEmpty) light = math.min(light, (1 - v) / keys.length);
  const goldenAngle = 0.618033988749895;
  return {
    for (final (i, key) in keys.indexed)
      key: _hsvToRgb((h + goldenAngle * i) % 1, s, (v + light * i) % 1),
  };
}

(double, double, double) _rgbToHsv(double r, double g, double b) {
  final maxc = math.max(r, math.max(g, b));
  final minc = math.min(r, math.min(g, b));
  final v = maxc;
  if (minc == maxc) return (0, 0, v);
  final s = (maxc - minc) / maxc;
  final rc = (maxc - r) / (maxc - minc);
  final gc = (maxc - g) / (maxc - minc);
  final bc = (maxc - b) / (maxc - minc);
  double h;
  if (r == maxc) {
    h = bc - gc;
  } else if (g == maxc) {
    h = 2.0 + rc - bc;
  } else {
    h = 4.0 + gc - rc;
  }
  return ((h / 6.0) % 1.0, s, v);
}

int _hsvToRgb(double h, double s, double v) {
  double r, g, b;
  if (s == 0) {
    r = g = b = v;
  } else {
    final i = (h * 6).floor();
    final f = h * 6 - i;
    final p = v * (1 - s);
    final q = v * (1 - s * f);
    final t = v * (1 - s * (1 - f));
    (r, g, b) = switch (i % 6) {
      0 => (v, t, p),
      1 => (q, v, p),
      2 => (p, v, t),
      3 => (p, q, v),
      4 => (t, p, v),
      _ => (v, p, q),
    };
  }
  int c(double x) => (x * 255).round().clamp(0, 255);
  return 0xff000000 | c(r) << 16 | c(g) << 8 | c(b);
}

/// The aggregated values of a graph (Python `updateDatas`).
class GraphData {
  /// The x values in order (date/datetime axes with every day).
  final List<Object> xs;

  /// Sum per x and y key.
  final Map<Object, Map<String, double>> values;

  /// Text of every x.
  final Map<Object, String> labels;

  /// Ids of the records of every x (days filled in have none).
  final Map<Object, List<int>> ids;

  const GraphData(this.xs, this.values, this.labels, this.ids);

  double value(Object x, String key) => values[x]?[key] ?? 0;

  /// Smallest and largest value (the minimum at most 0).
  (double, double) get range {
    var min = 0.0, max = 0.0;
    for (final row in values.values) {
      for (final v in row.values) {
        if (v < min) min = v;
        if (v > max) max = v;
      }
    }
    return (min, max);
  }
}

/// Sums the y fields of [definition] per x value of [records] (Python
/// `updateDatas`): records without x are skipped, `#` counts, timedelta
/// values count in seconds, a y `domain` (PYSON) filters the records;
/// date and datetime axes get every day between the first and the last
/// x. [formatDate]/[formatDateTime] give the labels of those days.
GraphData aggregateGraph(
  GraphDefinition definition,
  Iterable<Record> records, {
  required String Function(TrytonDate date) formatDate,
  required String Function(DateTime dateTime) formatDateTime,
}) {
  final xField = definition.x;
  final values = <Object, Map<String, double>>{};
  final labels = <Object, String>{};
  final ids = <Object, List<int>>{};
  if (xField == null) return GraphData(const [], values, labels, ids);
  Object? minX, maxX;
  for (final record in records) {
    final field = record.model.fields[xField.name];
    if (field == null) continue;
    final x = _key(field.get(record));
    if (x == null) continue;
    if (minX == null || compareGraphKeys(x, minX) < 0) minX = x;
    if (maxX == null || compareGraphKeys(x, maxX) > 0) maxX = x;
    labels[x] = _label(field, record, x, formatDate, formatDateTime);
    (ids[x] ??= []).add(record.id);
    final row = values[x] ??= {};
    for (final y in definition.y) {
      if (y.domain case final domain? when domain.isNotEmpty) {
        if (!_truthy(record.exprEval(domain))) continue;
      }
      final sum = row[y.key] ?? 0;
      if (y.isCount) {
        row[y.key] = sum + 1;
      } else {
        row[y.key] = sum + _number(record.model.fields[y.name]?.get(record));
      }
    }
  }
  // date and datetime: every day of the range (Python adds a day each)
  if (minX is TrytonDate && maxX is TrytonDate) {
    var day = minX.toDateTime();
    final last = maxX.toDateTime();
    while (!day.isAfter(last)) {
      final x = TrytonDate.fromDateTime(day);
      labels[x] = formatDate(x);
      final row = values[x] ??= {};
      for (final y in definition.y) {
        row.putIfAbsent(y.key, () => 0);
      }
      day = DateTime(day.year, day.month, day.day + 1);
    }
  } else if (minX is DateTime && maxX is DateTime) {
    var moment = minX;
    while (!moment.isAfter(maxX)) {
      final at = moment;
      labels.putIfAbsent(at, () => formatDateTime(at));
      final row = values[moment] ??= {};
      for (final y in definition.y) {
        row.putIfAbsent(y.key, () => 0);
      }
      moment = DateTime(moment.year, moment.month, moment.day + 1,
          moment.hour, moment.minute, moment.second);
    }
  }
  final xs = values.keys.toList()..sort(compareGraphKeys);
  return GraphData(xs, values, labels, ids);
}

/// Hashable key of an x value (lists of a reference/many2one become
/// their text).
Object? _key(dynamic value) => switch (value) {
      null || false => null,
      List() => value.join(','),
      _ => value as Object,
    };

String _label(Field field, Record record, Object x,
    String Function(TrytonDate) formatDate,
    String Function(DateTime) formatDateTime) {
  if (x is TrytonDate) return formatDate(x);
  if (x is DateTime) return formatDateTime(x);
  if (field is SelectionField) {
    final selection = field.description['selection'];
    if (selection is List) {
      for (final s in selection) {
        if (s is List && s.length > 1 && s[0] == x) return '${s[1]}';
      }
    }
  }
  final client = field.getClient(record);
  return client == null || client == false ? '$x' : '$client';
}

double _number(dynamic value) => switch (value) {
      null || false => 0,
      num() => value.toDouble(),
      TrytonDecimal() => value.toDouble(),
      Duration() => value.inMicroseconds / 1e6,
      String() => double.tryParse(value) ?? 0,
      _ => 0,
    };

bool _truthy(dynamic v) =>
    v != null && v != false && v != 0 && !(v is List && v.isEmpty) && v != '';

/// Order of x values: dates and numbers by value, the rest as text.
int compareGraphKeys(Object a, Object b) {
  if (a is TrytonDate && b is TrytonDate) {
    return a.toDateTime().compareTo(b.toDateTime());
  }
  if (a is DateTime && b is DateTime) return a.compareTo(b);
  if (a is Duration && b is Duration) return a.compareTo(b);
  if (a is num && b is num) return a.compareTo(b);
  if (a is TrytonDecimal && b is TrytonDecimal) {
    return a.toDouble().compareTo(b.toDouble());
  }
  if (a is bool && b is bool) return (a ? 1 : 0) - (b ? 1 : 0);
  return '$a'.compareTo('$b');
}
