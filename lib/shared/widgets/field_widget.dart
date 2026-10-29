import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/serialization/tryton_serializer.dart';
import '../../features/model/field_definition.dart';
import '../../features/model/field_support.dart';
import '../../features/model/model_service.dart';
import '../../core/l10n/locale_provider.dart';
import '../utils/date_format_utils.dart';
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

  /// Field is invalid (required/domain, spec 9.2.3 `has-error`): red border.
  final bool invalid;

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
    this.invalid = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (field.invisible) return const SizedBox.shrink();

    return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: _buildField(context, ref));
  }

  Widget _buildField(BuildContext context, WidgetRef ref) {
    final effective = readOnly || field.readonly;

    // No own widget yet (E13) → read-only placeholder, never a text input
    // (the value would be shown/edited as garbage and written back).
    if (isUnsupportedField(field.type, widgetOverride)) {
      return _UnsupportedField(
          field: field, kind: widgetOverride ?? field.type);
    }

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

      // Many2One/One2One/Reference are edited with RecordMany2One (on the
      // record); here only the name is shown.
      case 'many2one':
      case 'one2one':
        return _TextInputField(
          initialValue: value is List && value.length > 1 && value[1] is String
              ? value[1] as String
              : '',
          decoration: _decoration(context),
          readOnly: true,
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
      // has-error: red border without text (the message comes on save)
      errorText: invalid ? '' : null,
      errorStyle: invalid ? const TextStyle(height: 0, fontSize: 0) : null,
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

// ─── Placeholder for unsupported field types / widgets ──────────────────────

class _UnsupportedField extends StatelessWidget {
  final FieldDefinition field;
  /// Field type or widget name, e.g. "binary" or "image".
  final String kind;

  const _UnsupportedField({required this.field, required this.kind});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
        enabled: false,
        prefixIcon: const Icon(Icons.block, size: 18),
      ),
      child: Text(
        '${context.l10n.fieldNotSupported} (${field.name}: $kind)',
        style: TextStyle(color: cs.onSurfaceVariant, fontStyle: FontStyle.italic),
      ),
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
    // Value is local time (decoded from UTC by TrytonSerializer); the
    // picked value is local too and is sent back as UTC on encode.
    final local = value?.toLocal();
    final formatted = local != null ? formatDateTimeValue(local) : '';
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
                    initialDate: local ?? DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                  );
                  if (date == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: local != null ? TimeOfDay.fromDateTime(local) : TimeOfDay.now(),
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
