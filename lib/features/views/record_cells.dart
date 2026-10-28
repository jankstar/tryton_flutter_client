import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/model/model.dart';
import '../../core/pyson/pyson_evaluator.dart';
import '../../shared/utils/date_format_utils.dart';
import '../../shared/utils/number_format_utils.dart';
import '../../shared/utils/symbol_cache.dart' as sym_cache;
import '../model/field_definition.dart';
import '../model/model_service.dart';

/// Cell text of [name] in a list row (many2one/reference: rec_name,
/// selection: label, boolean: ✓, x2many: count).
String recordCellText(Record record, String name, FieldDefinition? fd) {
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
  if (fd?.type == 'selection' && fd!.selection != null) {
    final label = record.values['$name:string'];
    if (label is String && label.isNotEmpty) return label;
    final match = fd.selection!
        .where((e) => e[0].toString() == val.toString())
        .firstOrNull;
    return match?[1]?.toString() ?? val.toString();
  }
  // datetime: local time without milliseconds (DateTime.toString() would
  // show "2026-10-26 14:30:00.000").
  if (val is DateTime) return formatDateTimeValue(val);
  // Prevent raw List/Map from leaking as toString()
  if (val is List || val is Map) return '';
  return val.toString();
}

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

/// Number cell of [name] with locale formatting and the currency/unit of
/// the field's `symbol` field.
class RecordNumericCell extends ConsumerStatefulWidget {
  final dynamic value;
  final FieldDefinition field;

  /// Id of the currency/unit (value of the `symbol` field).
  final int? currencyId;
  final TextStyle? style;

  const RecordNumericCell(
      {super.key,
      required this.value,
      required this.field,
      this.currencyId,
      this.style});

  /// Cell of [name] of [record].
  factory RecordNumericCell.of(Record record, String name, FieldDefinition fd,
      {TextStyle? style}) {
    final symbol = fd.symbol;
    final symbolValue =
        symbol == null ? null : record.model.fields[symbol]?.get(record);
    return RecordNumericCell(
      value: record.model.fields[name]?.get(record),
      field: fd,
      currencyId: symbolValue is int ? symbolValue : null,
      style: style,
    );
  }

  @override
  ConsumerState<RecordNumericCell> createState() => _RecordNumericCellState();
}

class _RecordNumericCellState extends ConsumerState<RecordNumericCell> {
  String _symbol = '';
  double _position = 1.0;

  @override
  void initState() {
    super.initState();
    _loadSymbol();
  }

  @override
  void didUpdateWidget(RecordNumericCell old) {
    super.didUpdateWidget(old);
    if (old.currencyId != widget.currencyId) _loadSymbol();
  }

  Future<void> _loadSymbol() async {
    if (widget.field.symbol == null) return;
    final id = widget.currencyId;
    if (id == null || id <= 0) return;
    const relation = 'res.currency';
    final svc = ref.read(modelServiceProvider);
    final (sym, pos) = await sym_cache.resolveSymbol(svc, relation, id);
    if (sym.isNotEmpty && mounted) {
      setState(() {
        _symbol = sym;
        _position = pos;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final formatted = formatNumericValue(
      widget.value,
      digits: widget.field.digits,
      locale: locale,
      isInteger: widget.field.type == 'integer',
    );
    final hasPrefix = _symbol.isNotEmpty && _position < 0.5;
    final hasSuffix = _symbol.isNotEmpty && _position >= 0.5;
    final text = hasPrefix
        ? '$_symbol $formatted'
        : hasSuffix
            ? '$formatted $_symbol'
            : formatted;
    return Text(text,
        style: widget.style,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end);
  }
}
