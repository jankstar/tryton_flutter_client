import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/model/model.dart';
import '../../core/pyson/pyson_evaluator.dart';
import '../../core/domain/date_text.dart';
import '../../core/serialization/tryton_serializer.dart';
import '../../shared/utils/date_format_utils.dart';
import '../../shared/utils/number_format_utils.dart';
import '../auth/user_preferences_provider.dart';
import '../model/field_definition.dart';

/// Cell text of [name] in a list row (many2one/reference: rec_name,
/// selection/multiselection: labels, boolean: ✓, x2many: count, date and
/// time in [dateFormat] / the field's time format, timedelta with the
/// context converter).
String recordCellText(Record record, String name, FieldDefinition? fd,
    {String dateFormat = '%x', String? localeTag, String? widget}) {
  final field = record.model.fields[name];
  if (field == null) return '';
  if (field is Many2OneField) return '${field.getClient(record)}';
  if (field is ReferenceField) {
    final client = field.getClient(record);
    return client is List && client.length > 1 ? '${client[1]}' : '';
  }
  if (field is One2ManyField) return '( ${field.getEval(record).length} )';
  final val = field.get(record);
  if (val == null || val == false) return '';
  if (field is BooleanField) return PYSONEvaluator.truthy(val) ? '✓' : '';
  if (fd?.type == 'multiselection' && val is List) {
    final labels = {for (final s in fd!.selection ?? const []) '${s[0]}': '${s[1]}'};
    return [for (final v in val) labels['$v'] ?? '$v'].join(', ');
  }
  if (fd?.type == 'selection' && fd!.selection != null) {
    final label = record.values['$name:string'];
    if (label is String && label.isNotEmpty) return label;
    final match = fd.selection!
        .where((e) => e[0].toString() == val.toString())
        .firstOrNull;
    return match?[1]?.toString() ?? val.toString();
  }
  String timeFormat() {
    final f = record.exprEval(field.description['format']);
    return f is String && f.isNotEmpty ? f : defaultTimeFormat;
  }

  if (val is TrytonDate) {
    return formatDate(val.toDateTime(), dateFormat, localeTag);
  }
  // datetime: local time in the field's `format` (e.g. `%H:%M:%S.%f` of
  // timestamps); `widget="date"`/`"time"` show only that part.
  if (val is DateTime) {
    final format = switch (widget) {
      'date' => dateFormat,
      'time' => timeFormat(),
      _ => '$dateFormat ${timeFormat()}',
    };
    return formatDate(val.toLocal(), format, localeTag);
  }
  if (val is TrytonTime) {
    return formatDate(
        DateTime(2000, 1, 1, val.hour, val.minute, val.second, 0,
            val.microsecond),
        timeFormat());
  }
  if (val is Duration) {
    final converter = field is TimeDeltaField ? field.converter(record.group) : null;
    return formatTimedelta(val, converter is Map
        ? {
            for (final e in converter.entries)
              if (e.value is num) '${e.key}': e.value as num
          }
        : null);
  }
  // Prevent raw List/Map from leaking as toString()
  if (val is List || val is Map) return '';
  return val.toString();
}

/// [recordCellText] with the date format of the preferences.
class RecordTextCell extends ConsumerWidget {
  final Record record;
  final String name;
  final FieldDefinition? fd;
  final TextStyle? style;

  /// `widget` of the column (`date`/`time` on datetime fields).
  final String? widget;
  const RecordTextCell(this.record, this.name, this.fd,
      {super.key, this.style, this.widget});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Text(
      recordCellText(record, name, fd,
          dateFormat: ref.watch(dateFormatProvider),
          localeTag: Localizations.localeOf(context).toLanguageTag(),
          widget: widget),
      overflow: TextOverflow.ellipsis,
      style: style);
}

/// Text of a `sum="1"` column (Python/SAO `update_with_selection`):
/// „selected\nall“ of the records of [group] (selected = all when
/// [selected] is empty), `-` while a record is not loaded; decimals = the
/// largest `digits` of the records, timedelta with the context converter.
String recordSumText(RecordGroup group, String name, Iterable<Record> selected,
    {required String locale, NumberLocale? numberLocale}) {
  final field = group.model.fields[name];
  if (field == null) return '';
  final chosen = selected.toSet();
  // Numeric values are summed exactly like Python's Decimal, floats as
  // double.
  _Decimal? sum;
  _Decimal? selectedSum;
  double? fsum;
  double? fselected;
  Duration? dsum;
  Duration? dselected;
  int? digit = 0;
  for (final r in group) {
    if (!r.isLoaded(name) && r.id >= 0) return '-';
    final v = field.get(r);
    if (v == null) continue;
    final inSelection = chosen.isEmpty || chosen.contains(r);
    if (v is Duration) {
      dsum = (dsum ?? Duration.zero) + v;
      if (inSelection) dselected = (dselected ?? Duration.zero) + v;
      continue;
    }
    if (v is TrytonDecimal) {
      final d = _Decimal.parse(v.value);
      if (d == null) continue;
      sum = sum == null ? d : sum + d;
      if (inSelection) selectedSum = selectedSum == null ? d : selectedSum + d;
    } else if (v is num) {
      fsum = (fsum ?? 0) + v.toDouble();
      if (inSelection) fselected = (fselected ?? 0) + v.toDouble();
    } else {
      continue;
    }
    if (field is FloatField && field is! IntegerField) {
      final digits = field.digits(r);
      final dec = digits != null && digits.length > 1 ? digits[1] : null;
      digit = dec != null && digit != null ? (dec > digit ? dec : digit) : null;
    }
  }
  if (field is TimeDeltaField) {
    final raw = field.converter(group);
    final conv = raw is Map
        ? {for (final e in raw.entries) if (e.value is num) '${e.key}': e.value as num}
        : null;
    return '${formatTimedelta(dselected ?? Duration.zero, conv)}\n'
        '${formatTimedelta(dsum ?? Duration.zero, conv)}';
  }
  String f(_Decimal? d, double? v) => formatNumericValue(
      d != null ? TrytonDecimal(d.toString()) : (v ?? 0),
      digits: [null, digit],
      locale: locale,
      numberLocale: numberLocale,
      isInteger: field is IntegerField);
  final decimal = sum != null || selectedSum != null;
  return decimal
      ? '${f(selectedSum ?? _Decimal.zero, null)}\n${f(sum ?? _Decimal.zero, null)}'
      : '${f(null, fselected)}\n${f(null, fsum)}';
}

/// An exact decimal (unscaled integer and scale) for the sums of numeric
/// fields (Python `Decimal`): `0.1 + 0.2` stays `0.3`.
class _Decimal {
  final BigInt unscaled;
  final int scale;
  const _Decimal(this.unscaled, this.scale);

  static final zero = _Decimal(BigInt.zero, 0);

  static _Decimal? parse(String text) {
    var t = text.trim();
    if (t.contains('e') || t.contains('E')) {
      final d = double.tryParse(t);
      if (d == null) return null;
      t = d.toString();
      if (t.contains('e')) return null;
    }
    final negative = t.startsWith('-');
    if (negative || t.startsWith('+')) t = t.substring(1);
    final parts = t.split('.');
    if (parts.length > 2) return null;
    final fraction = parts.length == 2 ? parts[1] : '';
    final digits = '${parts[0].isEmpty ? '0' : parts[0]}$fraction';
    final value = BigInt.tryParse(digits);
    if (value == null) return null;
    return _Decimal(negative ? -value : value, fraction.length);
  }

  _Decimal operator +(_Decimal other) {
    final scale = this.scale > other.scale ? this.scale : other.scale;
    BigInt at(_Decimal d) => d.unscaled * BigInt.from(10).pow(scale - d.scale);
    return _Decimal(at(this) + at(other), scale);
  }

  @override
  String toString() {
    final negative = unscaled.isNegative;
    var digits = unscaled.abs().toString();
    if (scale == 0) return '${negative ? '-' : ''}$digits';
    digits = digits.padLeft(scale + 1, '0');
    final point = digits.length - scale;
    return '${negative ? '-' : ''}${digits.substring(0, point)}.${digits.substring(point)}';
  }
}

/// Touch devices (Android, iOS): tapping a row opens it, a long press
/// selects; otherwise a click selects and a double click (or Enter)
/// opens, like SAO.
bool isTouchPlatform(BuildContext context) => switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia =>
        true,
      _ => false,
    };

/// Whether [fd] is shown as a right-aligned number.
bool isNumericField(FieldDefinition? fd) =>
    fd?.type == 'float' || fd?.type == 'numeric' || fd?.type == 'integer';

/// `<tree visual="…">` evaluated for [record]: `success`, `warning`,
/// `danger` or ''.
String recordVisual(Record record, String? visual) {
  if (visual == null || visual.isEmpty) return '';
  try {
    return record.exprEval(visual)?.toString() ?? '';
  } catch (_) {
    return '';
  }
}

/// Number cell of [name] with the number format of the preferences, the
/// digits of the field (also `get_digits` of a referenced record) and the
/// currency/unit of the field's `symbol` field (`get_symbol`).
class RecordNumericCell extends ConsumerStatefulWidget {
  final Record record;
  final String name;
  final FieldDefinition field;
  final TextStyle? style;

  /// Column attributes: `factor`, `grouping`, `symbol` (else of the field).
  final num factor;
  final bool grouping;
  final String? symbol;

  const RecordNumericCell(
      {super.key,
      required this.record,
      required this.name,
      required this.field,
      this.style,
      this.factor = 1,
      this.grouping = true,
      this.symbol});

  /// Cell of [name] of [record].
  factory RecordNumericCell.of(Record record, String name, FieldDefinition fd,
          {TextStyle? style,
          num factor = 1,
          bool grouping = true,
          String? symbol}) =>
      RecordNumericCell(
          record: record,
          name: name,
          field: fd,
          style: style,
          factor: factor,
          grouping: grouping,
          symbol: symbol);

  @override
  ConsumerState<RecordNumericCell> createState() => _RecordNumericCellState();
}

class _RecordNumericCellState extends ConsumerState<RecordNumericCell> {
  FloatField? get _field {
    final f = widget.record.model.fields[widget.name];
    return f is FloatField ? f : null;
  }

  String? get _symbol => widget.symbol ?? widget.field.symbol;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RecordNumericCell old) {
    super.didUpdateWidget(old);
    _load();
  }

  void _load() {
    final field = _field;
    if (field == null) return;
    final record = widget.record;
    final symbol = _symbol;
    final futures = [
      if (field.digitsPending(record)) field.loadDigits(record),
      if (symbol != null && field.symbol(record, symbol) == null)
        field.loadSymbol(record, symbol),
    ];
    if (futures.isEmpty) return;
    Future.wait(futures).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final field = _field;
    final record = widget.record;
    final formatted = formatNumericValue(
      field?.get(record),
      digits: field?.digits(record, factor: widget.factor) ??
          widget.field.digits,
      locale: Localizations.localeOf(context).toLanguageTag(),
      numberLocale: ref.watch(numberLocaleProvider),
      isInteger: widget.field.type == 'integer',
      factor: widget.factor,
      grouping: widget.grouping,
    );
    final symbolName = _symbol;
    final symbol = symbolName == null || field == null
        ? null
        : field.symbol(record, symbolName);
    final text = symbol == null || symbol.$1.isEmpty
        ? formatted
        : symbol.$2 < 0.5
            ? '${symbol.$1} $formatted'
            : '$formatted ${symbol.$1}';
    return Text(text,
        style: widget.style,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end);
  }
}
