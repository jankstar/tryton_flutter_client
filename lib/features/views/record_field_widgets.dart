import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/domain/date_text.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart' hide TextField;
import '../../core/serialization/tryton_serializer.dart';
import '../../core/xml/view_definition.dart';
import '../../shared/utils/date_format_utils.dart';
import '../../shared/utils/number_format_utils.dart';
import '../auth/auth_provider.dart';
import '../auth/user_preferences_provider.dart';
import '../model/field_definition.dart';
import '../model/model_rpc.dart';
import '../model/model_service.dart';
import 'record_link.dart' show parseHexColor;
import 'search_dialog.dart';
import '../../shared/dialogs/tryton_dialogs.dart';
import 'form_label_style.dart';

// Form widgets that work on the record and its field (spec 9.2.4): they
// format with `field.get`/digits/converter and hand the converted value
// to the form (`onText` while typing, written on blur; `onValue` at once).

/// Input decoration of a form field (label with `*` when required, red
/// border when invalid).
InputDecoration recordDecoration(BuildContext context, FieldDefinition fd,
    {bool required = false,
    bool invalid = false,
    bool readOnly = false,
    String? prefixText,
    String? suffixText,
    Widget? prefixIcon,
    Widget? suffixIcon}) {
  final label = required
      ? RichText(
          text: TextSpan(
            text: fd.label,
            style: Theme.of(context).inputDecorationTheme.labelStyle ??
                Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
            children: const [
              TextSpan(text: ' *', style: TextStyle(color: Colors.red)),
            ],
          ),
        )
      : null;
  return InputDecoration(
    label: formLabel(context, label),
    labelText: formLabel(context, label == null ? fd.label : null),
    border: formBorder(context, readOnly: readOnly && !invalid),
    prefixText: prefixText,
    suffixText: suffixText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    errorText: invalid ? '' : null,
    errorStyle: invalid ? const TextStyle(height: 0, fontSize: 0) : null,
  );
}

/// Result of parsing the text of an input: [ok] false keeps the old value.
typedef ParsedValue = ({bool ok, dynamic value});

/// A text input on the record: shows [format] (again after focus loss),
/// parses each change with [parse] and hands valid values to [onText]
/// (kept by the form, written with `setClient` on [onBlur]). [onKey] may
/// replace the text for a typed character (date operators); it returns
/// the new text or null to let the character through.
class RecordTextInput extends StatefulWidget {
  final String Function() format;
  final ParsedValue Function(String text) parse;
  final InputDecoration decoration;
  final bool readOnly;
  final bool autofocus;
  final void Function(dynamic value)? onText;
  final VoidCallback? onBlur;
  final String? Function(String character, String text)? onKey;
  final TextInputType? keyboardType;
  final TextAlign textAlign;
  final int maxLines;

  const RecordTextInput({
    super.key,
    required this.format,
    required this.parse,
    required this.decoration,
    this.readOnly = false,
    this.autofocus = false,
    this.onText,
    this.onBlur,
    this.onKey,
    this.keyboardType,
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
  });

  @override
  State<RecordTextInput> createState() => _RecordTextInputState();
}

class _RecordTextInputState extends State<RecordTextInput> {
  /// The value text shown last (the record's value, [RecordTextInput.format]).
  late String _shown = widget.format();
  late final TextEditingController _ctrl = TextEditingController(text: _shown);
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKeyEvent)
    ..addListener(_onFocusChange);
  bool _valid = true;

  /// A new value of the record (date picker, on_change) is shown – also
  /// with the focus (it returns to the field when the picker closes), as
  /// long as nothing was typed since the last value; typing is kept.
  @override
  void didUpdateWidget(RecordTextInput old) {
    super.didUpdateWidget(old);
    final text = widget.format();
    if (text == _shown) return;
    if (!_focus.hasFocus || _ctrl.text == _shown) {
      _ctrl.value = TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: text.length));
      _valid = true;
    }
    _shown = text;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final onKey = widget.onKey;
    final character = event.character;
    if (onKey == null ||
        widget.readOnly ||
        event is KeyUpEvent ||
        character == null ||
        character.length != 1 ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final text = onKey(character, _ctrl.text);
    if (text == null) return KeyEventResult.ignored;
    _ctrl.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
    _changed(text);
    return KeyEventResult.handled;
  }

  void _changed(String text) {
    final parsed = widget.parse(text);
    _valid = parsed.ok;
    if (parsed.ok) widget.onText?.call(parsed.value);
  }

  void _onFocusChange() {
    if (_focus.hasFocus) return;
    widget.onBlur?.call();
    // Invalid text is dropped (Python: the widget shows the value again).
    if (!_valid) {
      _valid = true;
      _ctrl.text = _shown = widget.format();
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: _ctrl,
        focusNode: _focus,
        autofocus: widget.autofocus,
        decoration: widget.decoration,
        readOnly: widget.readOnly,
        keyboardType: widget.keyboardType,
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        onChanged: _changed,
        onFieldSubmitted: (_) => _focus.unfocus(),
      );
}

/// Common parameters of the record field widgets.
class RecordFieldArgs {
  final Record record;
  final FieldNode node;
  final FieldDefinition fd;
  final bool readOnly;
  final bool required;
  final bool invalid;
  final bool autofocus;

  /// Typed value, written on blur.
  final void Function(dynamic value) onText;
  final VoidCallback onBlur;

  /// Value written at once.
  final void Function(dynamic value) onValue;

  const RecordFieldArgs({
    required this.record,
    required this.node,
    required this.fd,
    required this.readOnly,
    this.required = false,
    this.invalid = false,
    this.autofocus = false,
    required this.onText,
    required this.onBlur,
    required this.onValue,
  });

  Field get field => record.model.fields[node.name]!;

  InputDecoration decoration(BuildContext context,
          {String? prefixText,
          String? suffixText,
          Widget? prefixIcon,
          Widget? suffixIcon}) =>
      recordDecoration(context, fd,
          required: required,
          invalid: invalid,
          readOnly: readOnly,
          prefixText: prefixText,
          suffixText: suffixText,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon);
}

// ─── Numbers (spec 5.6, 9.2.4, 15.4) ─────────────────────────────────────────

/// integer/float/numeric: `digits` (list, PYSON or field → `get_digits`),
/// `factor`, `grouping`, `symbol` (`get_symbol`: prefix < 0.5 ≤ suffix)
/// and the number format of the preferences.
class RecordNumberInput extends ConsumerStatefulWidget {
  final RecordFieldArgs args;
  const RecordNumberInput({super.key, required this.args});

  @override
  ConsumerState<RecordNumberInput> createState() => _RecordNumberInputState();
}

class _RecordNumberInputState extends ConsumerState<RecordNumberInput> {
  RecordFieldArgs get a => widget.args;
  FloatField get _field => a.field as FloatField;
  bool get _isInteger => _field is IntegerField;
  String? get _symbolName {
    final s = a.node.attrs['symbol'] ?? a.fd.symbol;
    return s is String && s.isNotEmpty ? s : null;
  }

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  @override
  void didUpdateWidget(RecordNumberInput old) {
    super.didUpdateWidget(old);
    _loadPending();
  }

  /// digits/symbol of a referenced record are loaded once, then shown.
  void _loadPending() {
    final record = a.record;
    final field = _field;
    final symbol = _symbolName;
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

  NumberLocale _locale() =>
      ref.read(numberLocaleProvider) ??
      NumberLocale.intl(Localizations.localeOf(context).toLanguageTag());

  String _format() => formatNumericValue(
        _field.get(a.record),
        digits: _field.digits(a.record, factor: a.node.factor),
        locale: '',
        numberLocale: _locale(),
        isInteger: _isInteger,
        factor: a.node.factor,
        grouping: a.node.grouping,
      );

  /// Input → internal value (÷ factor, rounded to the digits).
  ParsedValue _parse(String text) {
    if (text.trim().isEmpty) return (ok: true, value: null);
    final plain = _locale().delocalize(text);
    if (plain == null) return (ok: false, value: null);
    return (ok: true, value: numberValue(_field, a.record, plain, a.node.factor));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(numberLocaleProvider);
    final symbolName = _symbolName;
    final symbol =
        symbolName == null ? null : _field.symbol(a.record, symbolName);
    final hasSymbol = symbol != null && symbol.$1.isNotEmpty;
    return RecordTextInput(
      key: ValueKey('number-${a.node.name}'),
      format: _format,
      parse: _parse,
      readOnly: a.readOnly,
      autofocus: a.autofocus,
      keyboardType: TextInputType.numberWithOptions(
          decimal: !_isInteger, signed: true),
      textAlign: TextAlign.end,
      decoration: a.decoration(context,
          prefixText: hasSymbol && symbol.$2 < 0.5 ? '${symbol.$1} ' : null,
          suffixText: hasSymbol && symbol.$2 >= 0.5 ? ' ${symbol.$1}' : null),
      onText: a.onText,
      onBlur: a.onBlur,
    );
  }
}

/// The internal value of the plain number text [plain] for [field]
/// (Python `apply_factor`): ÷ [factor], rounded to the digits (else to the
/// precision of the input plus the factor's).
dynamic numberValue(FloatField field, Record record, String plain, num factor) {
  if (field is IntegerField) {
    final v = num.tryParse(plain);
    if (v == null) return null;
    return factor == 1 ? v.round() : (v / factor).round();
  }
  final digits = field.digits(record);
  final dec = digits != null && digits.length > 1 ? digits[1] : null;
  if (field is NumericField) {
    if (factor == 1) {
      return TrytonDecimal(dec == null ? plain : plainNumber(TrytonDecimal(plain), dec));
    }
    final scaled = double.parse(plain) / factor;
    final precision = dec ?? _precision(plain, factor);
    return TrytonDecimal(plainNumber(scaled, precision));
  }
  final v = double.tryParse(plain);
  if (v == null) return null;
  if (factor == 1) {
    return dec == null ? v : double.parse(v.toStringAsFixed(dec));
  }
  final precision = dec ?? _precision(plain, factor);
  return double.parse((v / factor).toStringAsFixed(precision));
}

/// Decimals of [plain] plus those added by dividing by [factor].
int _precision(String plain, num factor) {
  final dot = plain.indexOf('.');
  final own = dot < 0 ? 0 : plain.length - dot - 1;
  var extra = 0;
  var f = factor.abs().toDouble();
  while (f > 1.0000001) {
    f /= 10;
    extra++;
  }
  return own + extra;
}

// ─── Date, datetime, time (spec 9.2.4, 15.2, 15.3) ───────────────────────────

/// date/datetime/time with the date format of the preferences, the
/// field's time `format`, a picker and the keyboard operators.
class RecordDateInput extends ConsumerWidget {
  final RecordFieldArgs args;
  const RecordDateInput({super.key, required this.args});

  String get _type {
    final w = args.node.widget;
    if (w == 'date' || w == 'datetime' || w == 'time') return w!;
    final t = args.fd.type;
    return t == 'timestamp' ? 'datetime' : t;
  }

  /// strftime format of the field (date part and/or time part).
  String _formatOf(String dateFormat) {
    final field = args.field;
    dynamic time = args.node.format ?? field.description['format'];
    // PYSON-encoded (the server sends `'"%H:%M:%S"'`, Python
    // `time_format` = `expr_eval`); a plain strftime string is taken as is
    if (time is! String || time.startsWith('"') || time.startsWith('{')) {
      time = args.record.exprEval(time);
    }
    final timeFormat = time is String && time.isNotEmpty ? time : defaultTimeFormat;
    return switch (_type) {
      'date' => dateFormat,
      'time' => timeFormat,
      _ => '$dateFormat $timeFormat',
    };
  }

  DateTime? _current() {
    final value = args.field.get(args.record);
    return switch (value) {
      TrytonDate() => value.toDateTime(),
      DateTime() => value.toLocal(),
      TrytonTime() => DateTime(2000, 1, 1, value.hour, value.minute,
          value.second, 0, value.microsecond),
      _ => null,
    };
  }

  dynamic _value(DateTime? d) {
    if (d == null) return null;
    return switch (_type) {
      'date' => TrytonDate.fromDateTime(d),
      'time' => TrytonTime(d.hour, d.minute, d.second,
          d.millisecond * 1000 + d.microsecond),
      _ => d,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = _formatOf(ref.watch(dateFormatProvider));
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    String show(DateTime? d) => d == null ? '' : formatDate(d, format, localeTag);
    DateTime? parse(String text) => _type == 'time'
        ? (strptime(text, format) ?? dateParse('2000-01-01 $text', '%Y-%m-%d $format'))
        : dateParse(text, format);
    final readOnly = args.readOnly;
    return RecordTextInput(
      key: ValueKey('date-${args.node.name}'),
      format: () => show(_current()),
      parse: (text) {
        if (text.trim().isEmpty) return (ok: true, value: null);
        final d = parse(text);
        return d == null ? (ok: false, value: null) : (ok: true, value: _value(d));
      },
      // Operators (15.3): on the shown value, the result shown and typed.
      onKey: (character, text) {
        final base = text.trim().isEmpty ? null : parse(text) ?? _current();
        final next = applyDateOperator(base, character);
        return next == null ? null : show(next);
      },
      readOnly: readOnly,
      autofocus: args.autofocus,
      decoration: args.decoration(context,
          suffixIcon: readOnly
              ? null
              : IconButton(
                  icon: Icon(_type == 'time'
                      ? Icons.access_time
                      : Icons.calendar_today),
                  onPressed: () => _pick(context),
                )),
      onText: args.onText,
      onBlur: args.onBlur,
    );
  }

  Future<void> _pick(BuildContext context) async {
    final current = _current();
    DateTime? date;
    if (_type != 'time') {
      date = await showDatePicker(
        context: context,
        initialDate: current ?? DateTime.now(),
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
      );
      if (date == null || !context.mounted) return;
    }
    var time = current == null ? null : TimeOfDay.fromDateTime(current);
    if (_type != 'date') {
      time = await showTimePicker(
          context: context, initialTime: time ?? TimeOfDay.now());
      if (time == null) return;
    }
    final d = date ?? current ?? DateTime(2000);
    args.onValue(_value(DateTime(d.year, d.month, d.day, time?.hour ?? 0,
        time?.minute ?? 0, _type == 'date' ? 0 : (current?.second ?? 0))));
  }
}

// ─── timedelta (spec 9.2.4, 15.5) ────────────────────────────────────────────

/// timedelta as text (`1d 02:30`) with the `converter` of the context
/// (e.g. `company_work_time`: 1d = 8h).
class RecordTimeDeltaInput extends StatelessWidget {
  final RecordFieldArgs args;
  const RecordTimeDeltaInput({super.key, required this.args});

  Map<String, num>? get _converter {
    final field = args.field;
    final raw = field is TimeDeltaField ? field.converter(args.record.group) : null;
    if (raw is! Map) return null;
    return {
      for (final e in raw.entries)
        if (e.value is num) '${e.key}': e.value as num
    };
  }

  @override
  Widget build(BuildContext context) {
    final converter = _converter;
    return RecordTextInput(
      key: ValueKey('timedelta-${args.node.name}'),
      format: () {
        final v = args.field.get(args.record);
        return v is Duration ? formatTimedelta(v, converter) : '';
      },
      parse: (text) {
        if (text.trim().isEmpty) return (ok: true, value: null);
        final d = parseTimedelta(text, converter);
        return d == null ? (ok: false, value: null) : (ok: true, value: d);
      },
      readOnly: args.readOnly,
      autofocus: args.autofocus,
      decoration: args.decoration(context),
      onText: args.onText,
      onBlur: args.onBlur,
    );
  }
}

// ─── multiselection ──────────────────────────────────────────────────────────

/// multiselection: the values of `selection` as chips; the sorted list is
/// written at once.
class RecordMultiSelection extends StatelessWidget {
  final RecordFieldArgs args;
  const RecordMultiSelection({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    final value = args.field.get(args.record);
    final selected = {for (final v in (value is List ? value : const [])) '$v'};
    final known = args.fd.selection ?? const [];
    // a stored value without option (e.g. options not loaded yet) stays
    // visible with its key
    final items = [
      ...known,
      for (final v in (value is List ? value : const []))
        if (!known.any((i) => '${i[0]}' == '$v')) [v, '$v'],
    ];
    return InputDecorator(
      decoration: args.decoration(context),
      child: Wrap(spacing: 6, runSpacing: 4, children: [
        for (final item in items)
          FilterChip(
            key: ValueKey('multi-${args.node.name}-${item[0]}'),
            label: Text('${item[1]}'),
            selected: selected.contains('${item[0]}'),
            onSelected: args.readOnly
                ? null
                : (on) {
                    final next = [
                      for (final i in items)
                        if (('${i[0]}' == '${item[0]}')
                            ? on
                            : selected.contains('${i[0]}'))
                          i[0]
                    ];
                    args.onValue(next);
                  },
          ),
      ]),
    );
  }
}

// ─── many2one as selection (widget="selection") ──────────────────────────────

/// Entries of [RecordSelectionMany2One] per `relation|domain|context`
/// (Python `SelectionMixin._domain_cache`): `(id, rec_name, help)`.
final Map<String, List<(int, String, String?)>> _m2oSelectionCache = {};

/// Clears the cached many2one selections (logout).
void clearMany2OneSelectionCache() => _m2oSelectionCache.clear();

/// many2one/one2one with `widget="selection"` (spec 9.2.4, Python
/// `SelectionMixin.update_selection`): a dropdown of
/// `search_read(field.getDomain, 0, null, null, ['rec_name', help_field])`
/// with `field.getContext` in the model's default order, plus an empty
/// entry; cached per domain and context, reloaded when the domain
/// changes (a late answer of an older domain is dropped). A value not in
/// the list (e.g. inactive) is shown with its rec_name. Errors give only
/// the empty entry (no dialog). Read-only: the rec_name as text.
class RecordSelectionMany2One extends StatefulWidget {
  final RecordFieldArgs args;
  const RecordSelectionMany2One({super.key, required this.args});

  @override
  State<RecordSelectionMany2One> createState() =>
      _RecordSelectionMany2OneState();
}

class _RecordSelectionMany2OneState extends State<RecordSelectionMany2One> {
  RecordFieldArgs get a => widget.args;

  /// Key of the shown entries and of the running request.
  String? _key;
  String? _requested;
  List<(int, String, String?)> _entries = const [];

  String get _relation => '${a.field.description['relation'] ?? ''}';

  String? get _helpField {
    final h = a.node.attrs['help_field'];
    return h is String && h.isNotEmpty ? h : null;
  }

  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(RecordSelectionMany2One old) {
    super.didUpdateWidget(old);
    _update();
  }

  /// Loads the entries of the current domain/context (cached).
  void _update() {
    if (a.readOnly || _relation.isEmpty) return;
    final field = a.field;
    final domain = field.getDomain(a.record);
    final context = field.getContext(a.record);
    final key = '$_relation|${jsonEncode(TrytonSerializer.encode([domain, context]))}';
    if (key == _key || key == _requested) return;
    final cached = _m2oSelectionCache[key];
    if (cached != null) {
      _key = key;
      _requested = null;
      _entries = cached;
      return;
    }
    _requested = key;
    final help = _helpField;
    a.record.model.related(_relation).execute('search_read', [
      domain,
      0,
      null,
      null,
      ['rec_name', ?help],
    ], context: context, processException: false).then((result) {
      final entries = [
        for (final r in (result is List ? result : const []))
          if (r is Map && r['id'] is int)
            (
              r['id'] as int,
              '${r['rec_name'] ?? ''}',
              help == null || r[help] == null || r[help] == false
                  ? null
                  : '${r[help]}'
            )
      ];
      _m2oSelectionCache[key] = entries;
      _apply(key, entries);
    }).catchError((Object _) {
      // no dialog: only the empty entry (not cached)
      _apply(key, const <(int, String, String?)>[]);
    });
  }

  /// Takes the answer of [key] only if it is still the requested one.
  void _apply(String key, List<(int, String, String?)> entries) {
    if (!mounted || key != _requested) return;
    setState(() {
      _key = key;
      _requested = null;
      _entries = entries;
    });
  }

  @override
  Widget build(BuildContext context) {
    final field = a.field;
    final value = field.get(a.record);
    final id = value is int ? value : null;
    final name = '${field.getClient(a.record) ?? ''}';
    if (a.readOnly) {
      return InputDecorator(
        decoration: a.decoration(context),
        // (the text style of an input: as high as the other fields)
        child: Text(name,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge),
      );
    }
    final entries = [..._entries];
    // A value not in the list (inactive, other domain): with its rec_name.
    if (id != null && !entries.any((e) => e.$1 == id)) {
      entries.add((id, name, null));
    }
    Widget label((int, String, String?) e) {
      final text = Text(e.$2, overflow: TextOverflow.ellipsis);
      return e.$3 == null ? text : Tooltip(message: e.$3!, child: text);
    }

    return DropdownButtonFormField<int?>(
      // a new value (e.g. from on_change) rebuilds the field
      key: ValueKey('m2o-selection-${a.node.name}-$id'),
      initialValue: id,
      isExpanded: true,
      // (the dense dropdown line is 24 px, a text line 20: less padding
      // keeps the field as high as a text field)
      decoration: a.decoration(context).copyWith(
          contentPadding: const EdgeInsets.fromLTRB(10, 7, 10, 6)),
      items: [
        for (final e in entries)
          DropdownMenuItem<int?>(value: e.$1, child: label(e)),
        // the empty entry at the end, like the Python client
        const DropdownMenuItem<int?>(value: null, child: Text('')),
      ],
      onChanged: (v) {
        if (v == id) return;
        if (v == null) {
          a.onValue(null);
          return;
        }
        final entry = entries.firstWhere((e) => e.$1 == v);
        a.onValue([entry.$1, entry.$2]);
      },
    );
  }
}

// ─── color, pyson (char widgets) ─────────────────────────────────────────────

const _palette = [
  '#000000', '#7f7f7f', '#ffffff', '#e53935', '#fb8c00', '#fdd835',
  '#43a047', '#00acc1', '#1e88e5', '#3949ab', '#8e24aa', '#d81b60',
];

/// widget="color": text (`#rrggbb`) with a colour square and a picker.
class RecordColorInput extends StatelessWidget {
  final RecordFieldArgs args;
  const RecordColorInput({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    final value = args.field.get(args.record);
    final text = value is String ? value : '';
    final color = parseHexColor(text);
    return RecordTextInput(
      key: ValueKey('color-${args.node.name}'),
      format: () {
        final v = args.field.get(args.record);
        return v is String ? v : '';
      },
      parse: (text) => (ok: true, value: text),
      readOnly: args.readOnly,
      autofocus: args.autofocus,
      decoration: args.decoration(context,
          prefixIcon: Padding(
            padding: const EdgeInsets.all(10),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color ?? Colors.transparent,
                border: Border.all(color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          suffixIcon: args.readOnly
              ? null
              : IconButton(
                  icon: const Icon(Icons.palette_outlined),
                  tooltip: context.l10n.selectColor,
                  onPressed: () async {
                    final chosen = await showDialog<String>(
                      context: context,
                      builder: (context) => SimpleDialog(
                        title: Text(context.l10n.selectColor),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final c in _palette)
                                InkWell(
                                  key: ValueKey('color-$c'),
                                  onTap: () => Navigator.pop(context, c),
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: parseHexColor(c),
                                      border: Border.all(color: Colors.grey),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                            ]),
                          ),
                        ],
                      ),
                    );
                    if (chosen != null) args.onValue(chosen);
                  },
                )),
      onText: args.onText,
      onBlur: args.onBlur,
    );
  }
}

/// widget="pyson": the PYSON (JSON) text; valid when it decodes (spec
/// 9.2.4), shown by an icon; an invalid text is not written.
class RecordPysonInput extends StatefulWidget {
  final RecordFieldArgs args;
  const RecordPysonInput({super.key, required this.args});

  @override
  State<RecordPysonInput> createState() => _RecordPysonInputState();
}

class _RecordPysonInputState extends State<RecordPysonInput> {
  bool _valid = true;

  static bool isValid(String text) {
    if (text.trim().isEmpty) return true;
    try {
      jsonDecode(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.args;
    return RecordTextInput(
      key: ValueKey('pyson-${a.node.name}'),
      format: () {
        final v = a.field.get(a.record);
        return v is String ? v : '';
      },
      parse: (text) {
        final valid = isValid(text);
        if (valid != _valid) setState(() => _valid = valid);
        return (ok: valid, value: text.trim().isEmpty ? null : text);
      },
      readOnly: a.readOnly,
      autofocus: a.autofocus,
      decoration: a.decoration(context,
          suffixIcon: Icon(_valid ? Icons.check_circle_outline : Icons.error_outline,
              color: _valid ? Colors.green : Theme.of(context).colorScheme.error)),
      onText: a.onText,
      onBlur: a.onBlur,
    );
  }
}

// ─── dict (spec 9.2.4, 5.6) ──────────────────────────────────────────────────

/// dict: one row per key (sorted by `sequence`) with an editor of the key
/// type; keys added through a search on `schema_model` (`get_keys`),
/// removed with a button. Changes are written at once.
class RecordDictField extends ConsumerStatefulWidget {
  final RecordFieldArgs args;
  const RecordDictField({super.key, required this.args});

  @override
  ConsumerState<RecordDictField> createState() => _RecordDictFieldState();
}

class _RecordDictFieldState extends ConsumerState<RecordDictField> {
  final _search = TextEditingController();
  bool _loading = false;

  RecordFieldArgs get a => widget.args;
  DictField get _field => a.field as DictField;
  Map<String, dynamic> get _value => _field.get(a.record) as Map<String, dynamic>;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  @override
  void didUpdateWidget(RecordDictField old) {
    super.didUpdateWidget(old);
    _loadKeys();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Definitions of keys of the value that are not known yet.
  void _loadKeys() {
    final missing = [
      for (final k in _value.keys)
        if (!_field.keys.containsKey(k)) k
    ];
    if (missing.isEmpty || _loading) return;
    _loading = true;
    _field.addKeys(missing, a.record).catchError((Object _) {}).whenComplete(() {
      _loading = false;
      if (mounted) setState(() {});
    });
  }

  void _set(String key, dynamic value) =>
      a.onValue({..._value, key: value});

  void _remove(String key) => a.onValue({..._value}..remove(key));

  Future<void> _add() async {
    final schema = _field.description['schema_model'];
    if (schema is! String) return;
    final results = await showSearchDialog(
      context,
      model: schema,
      session: modelSessionFor(ref.read(modelServiceProvider)),
      domain: _field.getDomain(a.record),
      searchContext: _field.getContext(a.record),
      multi: true,
      searchText: _search.text.isEmpty ? null : _search.text,
    );
    _search.clear();
    if (results.isEmpty) return;
    final names = await _field.addNewKeys([for (final r in results) r.id], a.record);
    a.onValue({..._value, for (final n in names) n: _value[n]});
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    final keys = [
      for (final k in value.keys)
        if (_field.keys.containsKey(k)) k
    ]..sort((x, y) => ((_field.keys[x]!['sequence'] as num?) ?? 0)
        .compareTo((_field.keys[y]!['sequence'] as num?) ?? 0));
    final l = context.l10n;
    return InputDecorator(
      decoration: a.decoration(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final key in keys)
          Padding(
            key: ValueKey('dict-${a.node.name}-$key'),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              SizedBox(
                width: 140,
                child: Text('${_field.keys[key]!['string'] ?? key}:',
                    overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DictEntry(
                  definition: _field.keys[key]!,
                  value: value[key],
                  readOnly: a.readOnly,
                  onChanged: (v) => _set(key, v),
                ),
              ),
              if (!a.readOnly)
                IconButton(
                  key: ValueKey('dict-remove-$key'),
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                  tooltip: l.remove,
                  onPressed: () => _remove(key),
                ),
            ]),
          ),
        if (!a.readOnly)
          Row(children: [
            Expanded(
              child: TextField(
                key: ValueKey('dict-search-${a.node.name}'),
                controller: _search,
                decoration: InputDecoration(
                    isDense: true, hintText: l.search, border: InputBorder.none),
                onSubmitted: (_) => _add(),
              ),
            ),
            IconButton(
              key: ValueKey('dict-add-${a.node.name}'),
              icon: const Icon(Icons.add, size: 18),
              tooltip: l.addValue,
              onPressed: _add,
            ),
          ]),
      ]),
    );
  }
}

/// Editor of one dict key by its `type` (char, color, boolean, selection,
/// multiselection, integer, float, numeric, date, datetime).
class _DictEntry extends ConsumerStatefulWidget {
  final Map<String, dynamic> definition;
  final dynamic value;
  final bool readOnly;
  final void Function(dynamic value) onChanged;
  const _DictEntry(
      {required this.definition,
      required this.value,
      required this.readOnly,
      required this.onChanged});

  @override
  ConsumerState<_DictEntry> createState() => _DictEntryState();
}

class _DictEntryState extends ConsumerState<_DictEntry> {
  late final TextEditingController _ctrl = TextEditingController(text: _text());
  late final FocusNode _focus = FocusNode()..addListener(_blur);

  String get _type => '${widget.definition['type'] ?? 'char'}';

  NumberLocale _locale() =>
      ref.read(numberLocaleProvider) ??
      NumberLocale.intl(Localizations.localeOf(context).toLanguageTag());

  int? get _decimals {
    final digits = widget.definition['digits'];
    return digits is List && digits.length > 1 && digits[1] is int
        ? digits[1] as int
        : null;
  }

  String _text() {
    final v = widget.value;
    if (v == null || v == false) return '';
    switch (_type) {
      case 'integer' || 'float' || 'numeric':
        return formatNumericValue(v,
            locale: '',
            numberLocale: _locale(),
            isInteger: _type == 'integer',
            digits: [null, _decimals]);
      case 'date':
        return v is TrytonDate
            ? formatDate(v.toDateTime(), ref.read(dateFormatProvider))
            : '$v';
      case 'datetime':
        return v is DateTime
            ? formatDate(v.toLocal(), '${ref.read(dateFormatProvider)} $defaultTimeFormat')
            : '$v';
    }
    return '$v';
  }

  dynamic _parse(String text) {
    if (text.trim().isEmpty) return null;
    switch (_type) {
      case 'integer':
        final p = _locale().delocalize(text);
        return p == null ? widget.value : num.tryParse(p)?.round();
      case 'float':
        final p = _locale().delocalize(text);
        return p == null ? widget.value : double.tryParse(p);
      case 'numeric':
        final p = _locale().delocalize(text);
        return p == null ? widget.value : TrytonDecimal(p);
      case 'date':
        final d = dateParse(text, ref.read(dateFormatProvider));
        return d == null ? widget.value : TrytonDate.fromDateTime(d);
      case 'datetime':
        return dateParse(text, '${ref.read(dateFormatProvider)} $defaultTimeFormat') ??
            widget.value;
    }
    return text;
  }

  void _blur() {
    if (_focus.hasFocus) return;
    final value = _parse(_ctrl.text);
    if (value != widget.value) widget.onChanged(value);
  }

  @override
  void didUpdateWidget(_DictEntry old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus) {
      final text = _text();
      if (_ctrl.text != text) _ctrl.text = text;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_blur);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  List<List<dynamic>> get _selection => [
        for (final s in (widget.definition['selection'] as List? ?? const []))
          if (s is List && s.length >= 2) s
      ];

  @override
  Widget build(BuildContext context) {
    switch (_type) {
      case 'boolean':
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: Checkbox(
            value: widget.value == true,
            onChanged: widget.readOnly ? null : (v) => widget.onChanged(v ?? false),
          ),
        );
      case 'selection':
        final items = _selection;
        final current = items.any((s) => s[0] == widget.value) ? widget.value : null;
        return DropdownButton<dynamic>(
          isExpanded: true,
          value: current,
          items: [
            const DropdownMenuItem(value: null, child: Text('')),
            for (final s in items)
              DropdownMenuItem(value: s[0], child: Text('${s[1]}')),
          ],
          onChanged: widget.readOnly ? null : widget.onChanged,
        );
      case 'multiselection':
        final selected = {...(widget.value is List ? widget.value as List : const [])};
        return Wrap(spacing: 4, children: [
          for (final s in _selection)
            FilterChip(
              label: Text('${s[1]}'),
              selected: selected.contains(s[0]),
              onSelected: widget.readOnly
                  ? null
                  : (on) => widget.onChanged([
                        for (final i in _selection)
                          if (i[0] == s[0] ? on : selected.contains(i[0])) i[0]
                      ]),
            ),
        ]);
    }
    final color = _type == 'color' ? parseHexColor(_ctrl.text) : null;
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      readOnly: widget.readOnly,
      textAlign: const {'integer', 'float', 'numeric'}.contains(_type)
          ? TextAlign.end
          : TextAlign.start,
      decoration: InputDecoration(
        isDense: true,
        border: formBorder(context, readOnly: widget.readOnly),
        prefixIcon: _type == 'color'
            ? Padding(
                padding: const EdgeInsets.all(8),
                child: Container(width: 16, height: 16, color: color ?? Colors.transparent))
            : null,
      ),
      onSubmitted: (_) => _focus.unfocus(),
    );
  }
}

// ─── html (spec 9.2.4) ───────────────────────────────────────────────────────

/// widget="html": a link to the server's HTML editor
/// `<server>/<db>/ir/html/<model>/<id>/<field>?language=…&title=…` (trytond
/// `ir/routes.py`), opened in the browser; with `translate` one link per
/// language.
class RecordHtmlButton extends ConsumerWidget {
  final RecordFieldArgs args;
  const RecordHtmlButton({super.key, required this.args});

  static Uri? uri(String baseUrl, String database, Record record, String field,
      String language, String title) {
    if (record.id < 0) return null;
    final base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
    return base.resolve(
        '${Uri.encodeComponent(database)}/ir/html/${record.model.name}/'
        '${record.id}/$field').replace(queryParameters: {
      'language': language,
      'title': title,
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.read(sessionProvider);
    final language = '${session.context['language'] ?? 'en'}';
    final title = context.l10n.appTitle;
    Uri? link(String lang) => uri(ref.read(rpcClientProvider).baseUrl,
        session.database ?? '', args.record, args.node.name, lang, title);
    final translate = args.node.attrs['translate'] == true;
    return InputDecorator(
      decoration: args.decoration(context),
      child: Row(children: [
        TextButton.icon(
          key: ValueKey('html-${args.node.name}'),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: Text(args.fd.label),
          onPressed: link(language) == null
              ? null
              : () => launchUrl(link(language)!, mode: LaunchMode.externalApplication),
        ),
        if (translate && args.record.id >= 0)
          IconButton(
            icon: const Icon(Icons.translate, size: 18),
            tooltip: context.l10n.translate,
            onPressed: () async {
              final languages = await translatableLanguages(args.record);
              if (!context.mounted || languages.isEmpty) return;
              final code = await showDialog<String>(
                context: context,
                builder: (context) => SimpleDialog(
                  title: Text(context.l10n.translate),
                  children: [
                    for (final l in languages)
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, l.code),
                        child: Text(l.name),
                      ),
                  ],
                ),
              );
              final target = code == null ? null : link(code);
              if (target != null) {
                await launchUrl(target, mode: LaunchMode.externalApplication);
              }
            },
          ),
      ]),
    );
  }
}

// ─── Translation dialog (spec 9.2.5) ─────────────────────────────────────────

/// Translatable languages (`ir.lang` with `translatable`).
Future<List<({String code, String name})>> translatableLanguages(Record record) async {
  final lang = record.model.related('ir.lang');
  final ids = await lang.execute('search', [
    [
      ['translatable', '=', true]
    ]
  ]);
  if (ids is! List || ids.isEmpty) return const [];
  final rows = await lang.execute('read', [ids, ['code', 'name']]);
  return [
    for (final r in (rows as List? ?? const []))
      (code: '${(r as Map)['code']}', name: '${r['name']}')
  ];
}

/// Translation dialog of a `translate` field (spec 9.2.5, Python
/// `TranslateDialog`): only for saved, unmodified records; per language
/// the value (with `fuzzy_translation`) and a "Fuzzy" hint, edited after
/// "Edit"; OK writes the edited ones per language and reloads the record.
Future<void> showTranslateDialog(
    BuildContext context, Record record, String field,
    {bool multiline = false}) async {
  final l = context.l10n;
  if (record.id < 0 || record.modified) {
    await showMessage(context, l.saveBeforeTranslate);
    return;
  }
  final languages = await translatableLanguages(record);
  if (!context.mounted) return;
  if (languages.isEmpty) {
    await showMessage(context, l.noOtherLanguage);
    return;
  }
  final values = <String, (String, String)>{};
  for (final language in languages) {
    Future<String> read(bool fuzzy) async {
      final rows = await record.model.execute('read', [
        [record.id],
        [field]
      ], context: {
        ...record.getContext(),
        'language': language.code,
        'fuzzy_translation': fuzzy,
      });
      final v = ((rows as List).first as Map)[field];
      return v is String ? v : '';
    }

    values[language.code] = (await read(false), await read(true));
  }
  if (!context.mounted) return;
  final edited = await showDialog<Map<String, String>>(
    context: context,
    builder: (_) => _TranslateDialog(
        languages: languages, values: values, multiline: multiline),
  );
  if (edited == null || edited.isEmpty) return;
  for (final MapEntry(key: code, value: text) in edited.entries) {
    await record.model.execute('write', [
      [record.id],
      {field: text}
    ], context: {
      ...record.getContext(),
      'language': code,
      'fuzzy_translation': false,
    });
  }
  record.cancel();
  await record.reload();
}

class _TranslateDialog extends StatefulWidget {
  final List<({String code, String name})> languages;

  /// code → (value, fuzzy value)
  final Map<String, (String, String)> values;
  final bool multiline;
  const _TranslateDialog(
      {required this.languages, required this.values, required this.multiline});

  @override
  State<_TranslateDialog> createState() => _TranslateDialogState();
}

class _TranslateDialogState extends State<_TranslateDialog> {
  late final Map<String, TextEditingController> _ctrls = {
    for (final l in widget.languages)
      l.code: TextEditingController(text: widget.values[l.code]?.$2 ?? '')
  };
  final Set<String> _editing = {};

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.translate),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final language in widget.languages)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 110,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('${language.name}:', textAlign: TextAlign.end),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: ValueKey('translate-${language.code}'),
                      controller: _ctrls[language.code],
                      readOnly: !_editing.contains(language.code),
                      maxLines: widget.multiline ? 4 : 1,
                      decoration: const InputDecoration(
                          isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 4),
                  FilterChip(
                    key: ValueKey('translate-edit-${language.code}'),
                    label: Text(l.edit),
                    selected: _editing.contains(language.code),
                    onSelected: (on) => setState(() => on
                        ? _editing.add(language.code)
                        : _editing.remove(language.code)),
                  ),
                  if (widget.values[language.code]?.$1 !=
                      widget.values[language.code]?.$2)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 10),
                      child: Text(l.fuzzy,
                          style: TextStyle(color: Colors.orange.shade800)),
                    ),
                ]),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            for (final code in _editing) code: _ctrls[code]!.text,
          }),
          child: Text(l.ok),
        ),
      ],
    );
  }
}
