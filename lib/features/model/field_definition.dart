import 'dart:convert';

/// Describes a Tryton model field as returned by `fields_get`/`fields_view_get`.
class FieldDefinition {
  final String name;
  final String type;
  final String label;
  final bool readonly;
  final bool required;
  final bool invisible;
  final String? relation;
  final String? relationField;
  final List<List<dynamic>>? selection;
  final List<int>? digits;
  final String? help;
  final List<String>? onChange;
  final List<String>? onChangeWith;
  /// Raw PYSON states from the server: e.g. `{'invisible': {'__class__': 'Equal', ...}}`
  /// Evaluated in `DynamicFormScreen` against the current field values.
  final Map<String, dynamic>? statesRaw;
  /// Field-level domain from fields_get (may contain PYSON).
  /// Used for domain_readonly detection (like SAO's attr_domain).
  final dynamic domainRaw;
  /// Name of the sibling field carrying currency/unit (from fields_get 'symbol').
  /// SAO: field.description.symbol – e.g. 'currency' for a Numeric amount field.
  final String? symbol;
  /// If the selection options are provided by a classmethod (not a static list),
  /// this holds the method name (e.g. 'get_states'). The client calls
  /// model.model_name.method_name(ctx) to obtain the [[key, label], ...] list.
  final String? selectionFunction;
  /// Fields whose current values are passed to [selectionFunction]
  /// (`model.X.<method>(values, ctx)`); the selection is reloaded when one
  /// of them changes (spec 5.6, SAO `selection_mixin`).
  final List<String>? selectionChangeWith;
  /// `sort` from fields_get (default true): selection options are sorted by
  /// label, like the Python client and SAO.
  final bool selectionSort;

  const FieldDefinition({
    required this.name,
    required this.type,
    required this.label,
    this.readonly = false,
    this.required = false,
    this.invisible = false,
    this.relation,
    this.relationField,
    this.selection,
    this.digits,
    this.help,
    this.onChange,
    this.onChangeWith,
    this.statesRaw,
    this.domainRaw,
    this.symbol,
    this.selectionFunction,
    this.selectionChangeWith,
    this.selectionSort = true,
  });

  /// Selection options sorted by label (stable, like Python's
  /// `sort(key=itemgetter(1))`).
  static List<List<dynamic>> sortSelection(List<List<dynamic>> options) {
    String label(List<dynamic> o) => o.length > 1 ? '${o[1] ?? ''}' : '';
    final indexed = options.indexed.toList()
      ..sort((a, b) {
        final c = label(a.$2).compareTo(label(b.$2));
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return [for (final (_, o) in indexed) o];
  }

  factory FieldDefinition.fromJson(String name, Map<String, dynamic> json) {
    List<List<dynamic>>? sel;
    String? selFn;
    if (json['selection'] is List) {
      sel = (json['selection'] as List)
          .map((e) => e is List ? e : [e, e.toString()])
          .toList()
          .cast<List<dynamic>>();
    } else if (json['selection'] is String) {
      // Dynamic selection: Tryton returns the classmethod name.
      selFn = json['selection'] as String;
    }
    final selSort = json['sort'] is bool ? json['sort'] as bool : true;
    if (sel != null && selSort) sel = sortSelection(sel);

    // states arrives from the server as a JSON string (not a Map!):
    //   '{"invisible": {"__class__": "Equal", "s1": {...}, "s2": "property"}}'
    // SAO decodes it with JSON.parse + PYSON reviver.
    // We decode the string to a Map and evaluate it with PYSONEvaluator.
    Map<String, dynamic>? statesRaw;
    final rawStates = json['states'];
    if (rawStates is Map<String, dynamic> && rawStates.isNotEmpty) {
      statesRaw = rawStates;
    } else if (rawStates is String &&
        rawStates.isNotEmpty &&
        rawStates != '{}' &&
        rawStates != '[]') {
      try {
        final decoded = _jsonDecode(rawStates);
        if (decoded is Map<String, dynamic>) statesRaw = decoded;
      } catch (_) {}
    }

    return FieldDefinition(
      name: name,
      type: json['type'] as String? ?? 'char',
      label: json['string'] as String? ?? name,
      // readonly/required/invisible can be bool OR a PYSON expression
      readonly: json['readonly'] is bool ? json['readonly'] as bool : false,
      required: json['required'] is bool ? json['required'] as bool : false,
      invisible: json['invisible'] is bool ? json['invisible'] as bool : false,
      relation: json['relation'] as String?,
      relationField: json['relation_field'] as String?,
      selection: sel,
      digits: json['digits'] is List
          ? (json['digits'] as List).map((e) => (e as num).toInt()).toList()
          : null,
      help: json['help'] as String?,
      onChange: json['on_change'] is List
          ? (json['on_change'] as List).map((e) => e.toString()).toList()
          : null,
      onChangeWith: json['on_change_with'] is List
          ? (json['on_change_with'] as List).map((e) => e.toString()).toList()
          : null,
      statesRaw: statesRaw,
      domainRaw: json['domain'],
      symbol: json['symbol'] as String?,
      selectionFunction: selFn,
      selectionChangeWith: json['selection_change_with'] is List
          ? (json['selection_change_with'] as List)
              .map((e) => e.toString())
              .toList()
          : null,
      selectionSort: selSort,
    );
  }

  FieldDefinition copyWithSelection(List<List<dynamic>> newSelection) =>
      FieldDefinition(
        name: name, type: type, label: label,
        readonly: readonly, required: required, invisible: invisible,
        relation: relation, relationField: relationField,
        selection:
            selectionSort ? sortSelection(newSelection) : newSelection,
        digits: digits, help: help,
        onChange: onChange, onChangeWith: onChangeWith,
        statesRaw: statesRaw, domainRaw: domainRaw,
        symbol: symbol, selectionFunction: selectionFunction,
        selectionChangeWith: selectionChangeWith,
        selectionSort: selectionSort,
      );

  bool get isRelation =>
      type == 'many2one' || type == 'one2many' || type == 'many2many';
  bool get isNumeric => type == 'integer' || type == 'float' || type == 'numeric';
  bool get isDate => type == 'date';
  bool get isDateTime => type == 'datetime';
}

/// Decodes a JSON string; throws an exception for invalid JSON.
dynamic _jsonDecode(String s) => jsonDecode(s);
