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
    {String dateFormat = '%x', String? localeTag}) {
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
  // datetime: local time without milliseconds.
  if (val is DateTime) {
    return formatDate(val.toLocal(), '$dateFormat ${timeFormat()}', localeTag);
  }
  if (val is TrytonTime) {
    return formatDate(
        DateTime(2000, 1, 1, val.hour, val.minute, val.second), timeFormat());
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
  const RecordTextCell(this.record, this.name, this.fd, {super.key, this.style});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Text(
      recordCellText(record, name, fd,
          dateFormat: ref.watch(dateFormatProvider),
          localeTag: Localizations.localeOf(context).toLanguageTag()),
      overflow: TextOverflow.ellipsis,
      style: style);
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

  const RecordNumericCell(
      {super.key,
      required this.record,
      required this.name,
      required this.field,
      this.style});

  /// Cell of [name] of [record].
  factory RecordNumericCell.of(Record record, String name, FieldDefinition fd,
          {TextStyle? style}) =>
      RecordNumericCell(record: record, name: name, field: fd, style: style);

  @override
  ConsumerState<RecordNumericCell> createState() => _RecordNumericCellState();
}

class _RecordNumericCellState extends ConsumerState<RecordNumericCell> {
  FloatField? get _field {
    final f = widget.record.model.fields[widget.name];
    return f is FloatField ? f : null;
  }

  String? get _symbol => widget.field.symbol;

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
      digits: field?.digits(record) ?? widget.field.digits,
      locale: Localizations.localeOf(context).toLanguageTag(),
      numberLocale: ref.watch(numberLocaleProvider),
      isInteger: widget.field.type == 'integer',
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
