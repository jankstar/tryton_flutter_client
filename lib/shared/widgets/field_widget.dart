import 'dart:async';
import 'dart:convert';

import 'package:url_launcher/url_launcher.dart';

import 'package:intl/intl.dart';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/pyson/pyson_evaluator.dart';
import '../../core/serialization/tryton_serializer.dart';
import '../../features/model/field_definition.dart';
import '../../features/model/model_service.dart';
import '../../features/shell/app_shell.dart' show pushFormScreen;
import '../../features/views/navigation_context.dart';
import '../../core/l10n/locale_provider.dart';
import '../utils/number_format_utils.dart';
import '../utils/symbol_cache.dart' as sym_cache;

/// Renders a Tryton field as the appropriate Flutter widget.
class FieldWidget extends ConsumerWidget {
  final FieldDefinition field;
  final dynamic value;
  final bool readOnly;
  final bool isRequired;
  final void Function(dynamic newValue)? onChanged;
  final VoidCallback? onBlur;

  /// Current record values — used to evaluate PYSON in field domains.
  final Map<String, dynamic> recordValues;

  /// Name of the sibling field holding the currency/unit (from XML or fields_get).
  final String? symbolField;

  /// Relation model of the symbol field (e.g. 'res.currency').
  final String? symbolRelation;

  /// When set, a small × clear button appears inside the field decoration.
  /// Used in context forms so clearing a field removes its domain condition.
  final VoidCallback? onClear;

  /// widget= attribute from the view XML arch (overrides field.type rendering).
  /// Values: 'url', 'email', 'callto', 'sip', 'password', 'progressbar', ...
  final String? widgetOverride;

  /// Tryton model name — used to load dynamic selection options from the server.
  final String? model;

  const FieldWidget({
    super.key,
    required this.field,
    required this.value,
    this.readOnly = false,
    this.isRequired = false,
    this.onChanged,
    this.onBlur,
    this.recordValues = const {},
    this.symbolField,
    this.symbolRelation,
    this.onClear,
    this.widgetOverride,
    this.model,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (field.invisible) return const SizedBox.shrink();

    return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: _buildField(context, ref));
  }

  Widget _buildField(BuildContext context, WidgetRef ref) {
    final effective = readOnly || field.readonly;

    // widget= XML attribute overrides the default type-based rendering.
    switch (widgetOverride) {
      case 'url':
      case 'email':
      case 'callto':
      case 'sip':
        return _LinkField(
          field: field,
          value: _safeText(value),
          scheme: widgetOverride!,
          readOnly: effective,
          isRequired: isRequired,
          onChanged: onChanged,
          onBlur: onBlur,
        );
      case 'password':
        return _TextInputField(
          initialValue: _safeText(value),
          decoration: _decoration(context),
          readOnly: effective,
          obscureText: true,
          onChanged: onChanged,
          onBlur: onBlur,
        );
      case 'progressbar':
        return _ProgressBarField(field: field, value: value);
    }

    switch (field.type) {
      case 'boolean':
        return CheckboxListTile(
          title: isRequired
              ? RichText(
                  text: TextSpan(
                    text: field.label,
                    style: DefaultTextStyle.of(context).style,
                    children: const [
                      TextSpan(
                        text: ' *',
                        style: TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                )
              : Text(field.label),
          value: value as bool? ?? false,
          onChanged: effective ? null : (v) => onChanged?.call(v),
          contentPadding: EdgeInsets.zero,
        );

      case 'selection':
        return _SelectionField(
          field: field,
          value: value,
          readOnly: effective,
          onChanged: onChanged,
          decoration: _decoration(context),
        );

      case 'date':
        return _DateField(
          field: field,
          value: value is TrytonDate ? value as TrytonDate : null,
          readOnly: effective,
          onChanged: onChanged,
        );

      case 'datetime':
        return _DateTimeField(
          field: field,
          value: value is DateTime ? value as DateTime : null,
          readOnly: effective,
          onChanged: onChanged,
        );

      case 'integer':
        final intLocale = Localizations.localeOf(context).toLanguageTag();
        return _TextInputField(
          initialValue: formatNumericValue(value, locale: intLocale, isInteger: true),
          decoration: _decoration(context),
          readOnly: effective,
          keyboardType: TextInputType.number,
          onChanged: (v) {
            final plain = v.replaceAll(RegExp(r'[^\d\-]'), '');
            onChanged?.call(int.tryParse(plain));
          },
          onBlur: onBlur,
        );

      case 'float':
      case 'numeric':
        return _NumericField(
          field: field,
          value: value,
          readOnly: effective,
          onChanged: onChanged,
          onBlur: onBlur,
          symbolField: symbolField ?? field.symbol,
          symbolRelation: symbolRelation,
          recordValues: recordValues,
        );

      case 'text':
        return _TextInputField(
          initialValue: _safeText(value),
          decoration: _decoration(context),
          readOnly: effective,
          maxLines: 4,
          onChanged: onChanged,
          onBlur: onBlur,
        );

      case 'many2one':
        return _Many2OneField(
          field: field,
          value: value,
          readOnly: effective,
          onChanged: onChanged,
          recordValues: recordValues,
        );

      case 'one2many':
      case 'many2many':
        return _X2ManyField(field: field, value: value, readOnly: effective);

      default: // 'char' and any unknown types
        return _TextInputField(
          initialValue: _safeText(value),
          decoration: _decoration(context),
          readOnly: effective,
          onChanged: onChanged,
          onBlur: onBlur,
        );
    }
  }

  /// Converts a field value to display text, guarding against raw Map/List
  /// objects that would otherwise show as Dart's toString() representation.
  static String _safeText(dynamic value) {
    if (value == null || value == false) return '';
    if (value is String) return value;
    if (value is List || value is Map) return '';
    return value.toString();
  }

  /// Builds the input decoration.
  /// Required fields show a red asterisk (*) after the label –
  /// the Flutter/Material Design standard for mandatory fields.
  InputDecoration _decoration(BuildContext context) {
    final labelWidget = isRequired
        ? RichText(
            text: TextSpan(
              text: field.label,
              style:
                  Theme.of(context).inputDecorationTheme.labelStyle ??
                  TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16),
              children: const [
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: Colors.red),
                ),
              ],
            ),
          )
        : null;

    // Clear button inside the field — only when onClear is set and value exists
    final clearBtn = (!readOnly && onClear != null && _hasValue(value))
        ? IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Löschen',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onClear,
          )
        : null;

    return InputDecoration(
      label: labelWidget,
      labelText: labelWidget == null ? field.label : null,
      helperText: field.help,
      border: const OutlineInputBorder(),
      suffixIcon: clearBtn,
    );
  }

  static bool _hasValue(dynamic v) =>
      v != null && v != false && !(v is String && v.isEmpty) && !(v is List && v.isEmpty);
}

// ─── Text input field with blur-based on_change trigger ──────────────────────

/// Like SAO's text widget: fires [onChanged] on every keystroke (local state)
/// but fires [onBlur] only when the field loses focus (triggers on_change RPC).
/// This prevents a server request on every character typed.
class _TextInputField extends StatefulWidget {
  final String initialValue;
  final InputDecoration decoration;
  final bool readOnly;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLines;
  final bool obscureText;
  final void Function(dynamic)? onChanged;
  final VoidCallback? onBlur;

  const _TextInputField({
    required this.initialValue,
    required this.decoration,
    required this.readOnly,
    this.keyboardType,
    this.maxLines = 1,
    this.obscureText = false,
    this.onChanged,
    this.onBlur,
  }) : inputFormatters = null;

  @override
  State<_TextInputField> createState() => _TextInputFieldState();
}

class _TextInputFieldState extends State<_TextInputField> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_TextInputField old) {
    super.didUpdateWidget(old);
    // Keep controller in sync when the form reloads (e.g. after on_change)
    if (old.initialValue != widget.initialValue && !_focus.hasFocus) {
      _ctrl.text = widget.initialValue;
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) {
      widget.onBlur?.call();
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
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _ctrl,
      focusNode: _focus,
      decoration: widget.decoration,
      readOnly: widget.readOnly,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      obscureText: widget.obscureText,
      // Update local state on every keystroke (no RPC)
      onChanged: (v) => widget.onChanged?.call(v),
    );
  }
}

// ─── Date field ───────────────────────────────────────────────────────────────

class _DateField extends StatelessWidget {
  final FieldDefinition field;
  final TrytonDate? value;
  final bool readOnly;
  final void Function(dynamic)? onChanged;

  const _DateField({required this.field, this.value, required this.readOnly, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final formatted = value != null ? value.toString() : '';
    return TextFormField(
      readOnly: true,
      controller: TextEditingController(text: formatted),
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
        suffixIcon: readOnly
            ? null
            : IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: value?.toDateTime() ?? DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    onChanged?.call(TrytonDate.fromDateTime(picked));
                  }
                },
              ),
      ),
    );
  }
}

// ─── Selection field ──────────────────────────────────────────────────────────

class _SelectionField extends StatelessWidget {
  final FieldDefinition field;
  final dynamic value;
  final bool readOnly;
  final void Function(dynamic)? onChanged;
  final InputDecoration decoration;

  const _SelectionField({
    required this.field,
    required this.value,
    required this.readOnly,
    required this.decoration,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = field.selection ?? [];
    final rawKey = (value == null || value == false) ? null : value.toString();
    final selValue = (rawKey != null && items.any((e) => e[0].toString() == rawKey)) ? rawKey : null;

    // If options unavailable but value is set, show as read-only text.
    if (items.isEmpty && rawKey != null) {
      return TextFormField(
        key: ValueKey(rawKey),
        initialValue: rawKey,
        decoration: decoration,
        readOnly: true,
        enabled: false,
      );
    }

    return DropdownButtonFormField<String>(
      value: selValue,
      decoration: decoration,
      isExpanded: true,
      items: items
          .map(
            (e) => DropdownMenuItem<String>(
              value: e[0].toString(),
              child: Text(e[1].toString(), overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: readOnly ? null : (v) => onChanged?.call(v),
    );
  }
}

// ─── Date+time field ──────────────────────────────────────────────────────────

class _DateTimeField extends StatelessWidget {
  final FieldDefinition field;
  final DateTime? value;
  final bool readOnly;
  final void Function(dynamic)? onChanged;

  const _DateTimeField({required this.field, this.value, required this.readOnly, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    final formatted = value != null ? fmt.format(value!) : '';
    return TextFormField(
      readOnly: true,
      controller: TextEditingController(text: formatted),
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
        suffixIcon: readOnly
            ? null
            : IconButton(
                icon: const Icon(Icons.access_time),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: value ?? DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                  );
                  if (date == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: value != null ? TimeOfDay.fromDateTime(value!) : TimeOfDay.now(),
                  );
                  if (time == null) return;
                  onChanged?.call(DateTime(date.year, date.month, date.day, time.hour, time.minute));
                },
              ),
      ),
    );
  }
}

// ─── Numeric/Float field with optional currency symbol ───────────────────────

/// Renders a float/numeric field. When [symbolField] is set, loads the
/// currency/unit symbol from the server (like SAO's field.get_symbol) and
/// displays it as a prefix or suffix depending on the position returned.
class _NumericField extends ConsumerStatefulWidget {
  final FieldDefinition field;
  final dynamic value;
  final bool readOnly;
  final void Function(dynamic)? onChanged;
  final VoidCallback? onBlur;
  final String? symbolField;
  final String? symbolRelation;
  final Map<String, dynamic> recordValues;

  const _NumericField({
    required this.field,
    this.value,
    required this.readOnly,
    this.onChanged,
    this.onBlur,
    this.symbolField,
    this.symbolRelation,
    this.recordValues = const {},
  });

  @override
  ConsumerState<_NumericField> createState() => _NumericFieldState();
}

class _NumericFieldState extends ConsumerState<_NumericField> {
  String _symbol = '';
  double _position = 1.0; // <0.5 = prefix, ≥0.5 = suffix

  @override
  void initState() {
    super.initState();
    _loadSymbol();
  }

  @override
  void didUpdateWidget(_NumericField old) {
    super.didUpdateWidget(old);
    // Reload when the currency field value changes
    final oldId = _currencyId(old.recordValues);
    final newId = _currencyId(widget.recordValues);
    if (oldId != newId) _loadSymbol();
  }

  int? _currencyId(Map<String, dynamic> values) {
    if (widget.symbolField == null) return null;
    final v = values[widget.symbolField];
    if (v is List && v.isNotEmpty) return (v[0] as num?)?.toInt();
    if (v is int) return v;
    return null;
  }

  Future<void> _loadSymbol() async {
    if (widget.symbolField == null) return;
    final currencyId = _currencyId(widget.recordValues);
    if (currencyId == null || currencyId <= 0) return;
    final relation = widget.symbolRelation;
    if (relation == null || relation.isEmpty) return;

    final svc = ref.read(modelServiceProvider);
    final (sym, pos) = await sym_cache.resolveSymbol(svc, relation, currencyId);
    if (sym.isNotEmpty && mounted) {
      setState(() {
        _symbol = sym;
        _position = pos;
      });
    }
  }

  String _format(dynamic value, String locale) =>
      formatNumericValue(value, digits: widget.field.digits, locale: locale);

  dynamic _parse(String text, String locale) => parseNumericValue(text, locale);

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final displayValue = _format(widget.value, locale);
    final hasPrefix = _symbol.isNotEmpty && _position < 0.5;
    final hasSuffix = _symbol.isNotEmpty && _position >= 0.5;

    return _TextInputField(
      initialValue: displayValue,
      decoration: InputDecoration(
        labelText: widget.field.label,
        border: const OutlineInputBorder(),
        prefixText: hasPrefix ? '$_symbol ' : null,
        suffixText: hasSuffix ? ' $_symbol' : null,
      ),
      readOnly: widget.readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (v) => widget.onChanged?.call(_parse(v, locale)),
      onBlur: widget.onBlur,
    );
  }
}

// ─── Many2One field ───────────────────────────────────────────────────────────

/// Many2One field with:
/// - Link icon (indicates: foreign key to another model)
/// - When a value is set: "Open" button (navigates to the linked record)
/// - In edit mode: search with autocomplete dropdown + "Clear" button
/// - Like the original: primary = Open, secondary = Search/Clear
class _Many2OneField extends ConsumerStatefulWidget {
  final FieldDefinition field;
  final dynamic value;
  final bool readOnly;
  final void Function(dynamic)? onChanged;
  final Map<String, dynamic> recordValues;

  const _Many2OneField({
    required this.field,
    this.value,
    required this.readOnly,
    this.onChanged,
    this.recordValues = const {},
  });

  @override
  ConsumerState<_Many2OneField> createState() => _Many2OneFieldState();
}

class _Many2OneFieldState extends ConsumerState<_Many2OneField> {
  int? _id;
  String _name = '';
  bool _searching = false;

  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;
  bool _loadingSuggestions = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _updateFromValue(widget.value);
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        // Delay hiding the dropdown so onTap on a dropdown item fires first.
        // Without the delay, focus loss dismisses the dropdown before the tap
        // is registered (classic Flutter autocomplete race condition).
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted && !_focus.hasFocus) {
            if (_ctrl.text != _name) _ctrl.text = _name;
            setState(() {
              _showSuggestions = false;
              _searching = false;
            });
          }
        });
      }
    });
  }

  @override
  void didUpdateWidget(_Many2OneField old) {
    super.didUpdateWidget(old);
    // value can be a List ([id, rec_name]) – use listEquals to avoid
    // false positives when the content is the same but the object differs.
    final changed = old.value is List && widget.value is List
        ? !listEquals(old.value as List, widget.value as List)
        : old.value != widget.value;
    if (changed) _updateFromValue(widget.value);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _updateFromValue(dynamic v) {
    if (v is List && v.isNotEmpty && v[0] != null && v[0] != false) {
      _id = (v[0] as num?)?.toInt();
      final rawName = v.length > 1 ? v[1] : null;
      if (rawName != null && rawName != false && rawName.toString().isNotEmpty) {
        _name = rawName.toString();
      } else {
        // ID present, name missing → placeholder + load asynchronously
        _name = '';
        if (_id != null) _loadRecName();
      }
    } else if (v is int && v > 0) {
      _id = v;
      _name = '';
      _loadRecName(); // load asynchronously
    } else {
      _id = null;
      _name = '';
    }
    _ctrl.text = _name;
    _searching = false;
  }

  /// Loads the rec_name asynchronously if it is not included in the value.
  Future<void> _loadRecName() async {
    final id = _id;
    final relation = widget.field.relation;
    if (id == null || relation == null) return;
    try {
      final records = await ref.read(modelServiceProvider).read(relation, [id], ['rec_name']);
      if (!mounted) return;
      final name = records.isNotEmpty ? records.first['rec_name']?.toString() ?? '' : '';
      if (name.isNotEmpty && _id == id) {
        setState(() {
          _name = name;
          _ctrl.text = _name;
        });
      }
    } catch (_) {
      // Silently ignore error – ID remains as fallback
    }
  }

  void _startSearch() {
    setState(() {
      _searching = true;
      _suggestions = [];
      _showSuggestions = false;
    });
    _ctrl.clear();
    _focus.requestFocus();
    _doSearch('');
  }

  void _onTyped(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () => _doSearch(text));
  }

  Future<void> _doSearch(String query) async {
    if (widget.field.relation == null) return;
    setState(() => _loadingSuggestions = true);
    try {
      // Apply field domain to restrict results (e.g. [['translatable','=',True]]
      // on ir.lang so only installed languages are shown).
      final domain = _evalFieldDomain();
      final results = await ref
          .read(modelServiceProvider)
          .searchName(widget.field.relation!, query, domain: domain, limit: 12);
      if (mounted) {
        setState(() {
          _suggestions = results;
          _showSuggestions = results.isNotEmpty;
          _loadingSuggestions = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSuggestions = false);
    }
  }

  /// Evaluates the field's domain against the current record values.
  /// Mirrors SAO's `record.expr_eval(this.description.domain)`:
  /// PYSON expressions like Eval('party') are resolved using recordValues.
  List<dynamic> _evalFieldDomain() {
    final raw = widget.field.domainRaw;
    if (raw == null) return const [];

    try {
      // Build eval context from current record values (like SAO's EvalEnvironment)
      final ctx = <String, dynamic>{};
      for (final entry in widget.recordValues.entries) {
        final v = entry.value;
        // Many2One values are [id, name] – expose the id for Eval('field')
        ctx[entry.key] = (v is List && v.isNotEmpty) ? v[0] : v;
      }
      final ev = PYSONEvaluator(ctx);

      List<dynamic> decoded;
      if (raw is String && raw.isNotEmpty && raw != '[]') {
        final d = jsonDecode(raw);
        if (d is! List) return const [];
        decoded = d;
      } else if (raw is List) {
        decoded = raw.cast<dynamic>();
      } else {
        return const [];
      }

      // _normalizeDomain is in pyson_evaluator.dart but not exported.
      // Replicate the same logic: evaluate PYSON maps inside each condition.
      return _evalDomainList(decoded, ev);
    } catch (_) {
      return const [];
    }
  }

  /// Recursively evaluates PYSON expressions inside a domain list.
  List<dynamic> _evalDomainList(List<dynamic> domain, PYSONEvaluator ev) {
    return domain.map((item) {
      if (item is List && item.length == 3) {
        // [field, op, value] — evaluate value if it's a PYSON expression
        final val = item[2];
        final evaled = (val is Map<String, dynamic> && val.containsKey('__class__')) ? ev.eval(val) : val;
        return [item[0], item[1], evaled];
      }
      if (item is List) return _evalDomainList(item.cast<dynamic>(), ev);
      if (item is Map<String, dynamic> && item.containsKey('__class__')) {
        return ev.eval(item);
      }
      return item; // 'AND', 'OR', string operators
    }).toList();
  }

  void _select(Map<String, dynamic> record) {
    final id = (record['id'] as num?)?.toInt();
    final name = record['rec_name']?.toString() ?? '';
    setState(() {
      _id = id;
      _name = name;
      _ctrl.text = name;
      _searching = false;
      _showSuggestions = false;
    });
    widget.onChanged?.call([id, name]);
    _focus.unfocus();
  }

  void _clear() {
    setState(() {
      _id = null;
      _name = '';
      _ctrl.clear();
      _searching = false;
      _showSuggestions = false;
    });
    widget.onChanged?.call(null);
  }

  void _open(BuildContext ctx) {
    if (_id == null || widget.field.relation == null) return;
    // Clear nav context: single-record jump has no Prev/Next.
    ref.read(navContextProvider.notifier).state = null;
    pushFormScreen(
      ctx,
      model: widget.field.relation!,
      recordId: _id!,
      title: _name.isNotEmpty ? _name : widget.field.label,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = _id != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: _ctrl,
          focusNode: _focus,
          readOnly: widget.readOnly && !_searching,
          decoration: InputDecoration(
            labelText: widget.field.label,
            border: const OutlineInputBorder(),
            // Link icon: indicates foreign key character
            prefixIcon: Tooltip(
              message: widget.field.relation ?? 'Referenz',
              child: const Icon(Icons.account_tree_outlined, size: 16),
            ),
            suffixIcon: _buildSuffix(context, hasValue),
          ),
          onTap: widget.readOnly
              ? null
              : () {
                  if (!_searching) _startSearch();
                },
          onChanged: _searching ? _onTyped : null,
        ),
        // Autocomplete-Dropdown
        if (_searching && (_showSuggestions || _loadingSuggestions))
          _Dropdown(loading: _loadingSuggestions, items: _suggestions, onSelect: _select),
      ],
    );
  }

  Widget? _buildSuffix(BuildContext context, bool hasValue) {
    final btns = <Widget>[];

    // Primary button: open record (like SAO's "tryton-open")
    if (hasValue && widget.field.relation != null) {
      btns.add(_IconBtn(icon: Icons.open_in_new, tooltip: context.l10n.openRecord, onPressed: () => _open(context)));
    }

    if (!widget.readOnly) {
      if (hasValue) {
        // Secondary button: clear (like SAO's "tryton-clear")
        btns.add(_IconBtn(icon: Icons.clear, tooltip: context.l10n.clearField, onPressed: _clear));
      } else if (!_searching) {
        // Secondary button: search (like SAO's "tryton-search")
        btns.add(_IconBtn(icon: Icons.search, tooltip: context.l10n.searchRecord, onPressed: _startSearch));
      } else {
        // Cancel search
        btns.add(
          _IconBtn(
            icon: Icons.cancel_outlined,
            tooltip: context.l10n.cancel,
            onPressed: () {
              setState(() {
                _searching = false;
                _showSuggestions = false;
                _ctrl.text = _name;
              });
              _focus.unfocus();
            },
          ),
        );
      }
    }

    if (btns.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: btns);
  }
}

// ─── Helper methods ───────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _IconBtn({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon, size: 16),
    tooltip: tooltip,
    onPressed: onPressed,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
  );
}

class _Dropdown extends StatelessWidget {
  final bool loading;
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic>) onSelect;
  const _Dropdown({required this.loading, required this.items, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: loading && items.isEmpty
            ? const LinearProgressIndicator(minHeight: 3)
            : ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final rec = items[i];
                  final name = rec['rec_name']?.toString() ?? '#${rec['id']}';
                  return InkWell(
                    onTap: () => onSelect(rec),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Text(name, style: const TextStyle(fontSize: 13)),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ─── X2Many field (display only in MVP) ──────────────────────────────────────

class _X2ManyField extends StatelessWidget {
  final FieldDefinition field;
  final dynamic value;
  final bool readOnly;

  const _X2ManyField({required this.field, this.value, required this.readOnly});

  @override
  Widget build(BuildContext context) {
    final count = value is List ? (value as List).length : 0;
    return InputDecorator(
      decoration: InputDecoration(labelText: field.label, border: const OutlineInputBorder()),
      child: Text('$count entries', style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

// ─── Link field (widget="url" / "email" / "callto" / "sip") ──────────────────

class _LinkField extends StatelessWidget {
  final FieldDefinition field;
  final String value;
  final String scheme; // 'url', 'email', 'callto', 'sip'
  final bool readOnly;
  final bool isRequired;
  final void Function(dynamic)? onChanged;
  final VoidCallback? onBlur;

  const _LinkField({
    required this.field,
    required this.value,
    required this.scheme,
    required this.readOnly,
    this.isRequired = false,
    this.onChanged,
    this.onBlur,
  });

  Uri? _buildUri(String text) {
    if (text.isEmpty) return null;
    switch (scheme) {
      case 'email':
        return Uri.tryParse('mailto:$text');
      case 'callto':
        return Uri.tryParse('tel:$text');
      case 'sip':
        return Uri.tryParse('sip:$text');
      default:
        // 'url' — ensure scheme present
        if (!text.startsWith('http://') && !text.startsWith('https://')) {
          return Uri.tryParse('https://$text');
        }
        return Uri.tryParse(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uri = readOnly ? _buildUri(value) : null;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
        suffixIcon: uri != null
            ? IconButton(
                icon: Icon(Icons.open_in_new, size: 16, color: cs.primary),
                tooltip: value,
                onPressed: () async {
                  if (await canLaunchUrl(uri)) launchUrl(uri);
                },
              )
            : null,
      ),
      child: readOnly
          ? GestureDetector(
              onTap: uri != null
                  ? () async {
                      if (await canLaunchUrl(uri)) launchUrl(uri);
                    }
                  : null,
              child: Text(
                value,
                style: uri != null ? TextStyle(color: cs.primary, decoration: TextDecoration.underline) : null,
              ),
            )
          : TextFormField(
              initialValue: value,
              decoration: const InputDecoration.collapsed(hintText: ''),
              onChanged: onChanged,
            ),
    );
  }
}

// ─── Progress bar field (widget="progressbar") ───────────────────────────────

class _ProgressBarField extends StatelessWidget {
  final FieldDefinition field;
  final dynamic value;
  const _ProgressBarField({required this.field, required this.value});

  @override
  Widget build(BuildContext context) {
    double? progress;
    if (value is num) progress = (value as num).toDouble().clamp(0.0, 1.0);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(4)),
          if (progress != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('${(progress * 100).toStringAsFixed(0)} %', style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
