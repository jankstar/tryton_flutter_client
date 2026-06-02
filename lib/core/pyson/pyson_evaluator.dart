import 'dart:convert';

/// Evaluates Tryton PYSON expressions against a context (record field values).
///
/// PYSON objects arrive from the server as a Map with a `__class__` key:
///   `{"__class__": "Eval", "v": "state", "d": "draft"}` → returns field value
///   `{"__class__": "Not", "v": ...}` → logical NOT
///   `{"__class__": "Equal", "s1": ..., "s2": ...}` → equality comparison
///   etc.
class PYSONEvaluator {
  final Map<String, dynamic> context;

  const PYSONEvaluator(this.context);

  /// Evaluates any PYSON expression or literal.
  dynamic eval(dynamic expr) {
    if (expr == null) return null;
    if (expr is bool) return expr;
    if (expr is num) return expr;
    if (expr is String) return expr;
    if (expr is List) return expr.map(eval).toList();
    if (expr is Map<String, dynamic>) {
      final cls = expr['__class__'] as String?;
      return cls != null ? _evalClass(cls, expr) : expr;
    }
    return expr;
  }

  /// Evaluates an expression and returns a bool (for states).
  bool evalBool(dynamic expr) => _truthy(eval(expr));

  dynamic _evalClass(String cls, Map<String, dynamic> e) {
    switch (cls) {
      // ── Get field value ────────────────────────────────────────────────────
      case 'Eval':
        final fieldName = e['v'] as String?;
        if (fieldName == null) return e['d'];
        // Distinguish: key absent → return default; key present but null → return null.
        // This lets context-form clear buttons set values to null so that
        // _stripEmptyConditions can remove the resulting domain clause.
        if (!context.containsKey(fieldName)) return e['d'];
        final value = context[fieldName];
        // Many2One comes as [id, name] – use only the ID for comparisons
        if (value is List && value.isNotEmpty) return value[0];
        return value;

      // ── Boolean operations ────────────────────────────────────────────────
      case 'Not':
        return !_truthy(eval(e['v']));

      case 'Bool':
        return _truthy(eval(e['v']));

      case 'And':
        final clauses = e['s'] as List? ?? [];
        return clauses.every((c) => _truthy(eval(c)));

      case 'Or':
        final clauses = e['s'] as List? ?? [];
        return clauses.any((c) => _truthy(eval(c)));

      case 'If':
        return _truthy(eval(e['c'])) ? eval(e['t']) : eval(e['e']);

      // ── Comparisons ───────────────────────────────────────────────────────
      case 'Equal':
        return _equals(eval(e['s1']), eval(e['s2']));

      case 'Greater':
        final withEqual = e['e'] as bool? ?? false;
        return _compare(eval(e['s1']), eval(e['s2']), withEqual ? '>=' : '>');

      case 'Less':
        final withEqual = e['e'] as bool? ?? false;
        return _compare(eval(e['s1']), eval(e['s2']), withEqual ? '<=' : '<');

      case 'In':
        return _contains(eval(e['v']), eval(e['k']));

      case 'Not_in': // Some Tryton versions
        return !_truthy(_contains(eval(e['v']), eval(e['k'])));

      // ── Dictionary / collection ───────────────────────────────────────────
      case 'Get':
        final dict = eval(e['v']);
        final key = e['k']?.toString();
        final def = e['d'];
        if (dict is Map && key != null && dict.containsKey(key)) {
          return dict[key];
        }
        return def;

      case 'Len':
        final v = eval(e['v']);
        if (v is List) return v.length;
        if (v is Map) return v.length;
        if (v is String) return v.length;
        return 0;

      // ── Unknown – return as truthy/falsy-safe value ───────────────────────
      default:
        return null;
    }
  }

  bool _truthy(dynamic v) {
    if (v == null || v == false) return false;
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is double) return v != 0.0;
    if (v is String) return v.isNotEmpty;
    if (v is List) return v.isNotEmpty;
    if (v is Map) return v.isNotEmpty;
    return true;
  }

  bool _equals(dynamic a, dynamic b) {
    if (a == b) return true;
    // Numeric tolerance: 1 == 1.0
    if (a is num && b is num) return a.toDouble() == b.toDouble();
    return false;
  }

  bool _compare(dynamic a, dynamic b, String op) {
    if (a is num && b is num) {
      switch (op) {
        case '>': return a > b;
        case '>=': return a >= b;
        case '<': return a < b;
        case '<=': return a <= b;
      }
    }
    return false;
  }

  bool _contains(dynamic container, dynamic item) {
    if (container is List) return container.contains(item);
    if (container is Map) return container.containsKey(item?.toString());
    if (container is String && item != null) {
      return container.contains(item.toString());
    }
    return false;
  }
}

/// Evaluates the `states` dict of a field and returns a normalised result.
class FieldStateResult {
  final bool invisible;
  final bool readonly;
  final bool required;

  const FieldStateResult({
    this.invisible = false,
    this.readonly = false,
    this.required = false,
  });
}

/// Evaluates a `pyson_domain` string from an `ir.action.act_window`.
///
/// [pysonDomain] is a JSON string such as `'[["type","=","property"]]'`
/// or a string containing a PYSON expression.
/// [ctx] is the evaluation context (session context + active_*).
List<dynamic> evaluateActionDomain(String? pysonDomain, Map<String, dynamic> ctx) {
  if (pysonDomain == null || pysonDomain.isEmpty) return [];

  try {
    // pyson_domain is a JSON string → decode first
    dynamic decoded;
    if (pysonDomain.startsWith('[') || pysonDomain.startsWith('{')) {
      decoded = _jsonDecodeStr(pysonDomain);
    } else {
      decoded = pysonDomain;
    }

    if (decoded == null) return [];

    // Evaluate PYSON expressions in the result
    final ev = PYSONEvaluator(ctx);
    final result = ev.eval(decoded);

    if (result is List) return _normalizeDomain(result, ev);
    return [];
  } catch (_) {
    return [];
  }
}

/// Normalises a domain list and evaluates any contained PYSON expressions.
List<dynamic> _normalizeDomain(List<dynamic> domain, PYSONEvaluator ev) {
  return domain.map((item) {
    if (item is List) {
      if (item.length == 3) {
        // Domain condition [field, operator, value]
        final value = item[2];
        final evaledValue = (value is Map<String, dynamic> &&
                value.containsKey('__class__'))
            ? ev.eval(value)
            : value;
        return [item[0], item[1], evaledValue];
      }
      // Nested domain (AND/OR)
      return _normalizeDomain(item.cast<dynamic>(), ev);
    }
    if (item is Map<String, dynamic> && item.containsKey('__class__')) {
      return ev.eval(item);
    }
    return item; // 'AND', 'OR', etc.
  }).toList();
}

dynamic _jsonDecodeStr(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}

/// Result of domain_readonly evaluation for a single field.
/// Mirrors SAO's `state_attrs.domain_readonly` + `set_client` logic.
class DomainReadonlyResult {
  final bool readonly;
  final dynamic forcedValue; // null means no forced value
  const DomainReadonlyResult({this.readonly = false, this.forcedValue});
}

/// Evaluates the combined domain (screen domain + field domain) for a field
/// and returns whether the field is domain-readonly and what value to force.
///
/// Implements SAO's `unique_value` + `domain_readonly` algorithm:
/// if the merged domain is `[field, '=', value]` (single AND equality),
/// the field is locked to that value and made readonly.
DomainReadonlyResult evaluateDomainReadonly({
  required String fieldName,
  required dynamic fieldDomainRaw,   // from fields_get 'domain'
  required List<dynamic> screenDomain, // domain from the action / URL
  required Map<String, dynamic> values,
  required Map<String, dynamic> ctx,
}) {
  try {
    final ev = PYSONEvaluator({...ctx, ...values});

    // Evaluate field-level domain (may be PYSON string or list)
    List<dynamic> fieldDomain = [];
    if (fieldDomainRaw is String && fieldDomainRaw.isNotEmpty) {
      final decoded = _jsonDecodeStr(fieldDomainRaw);
      if (decoded is List) fieldDomain = _normalizeDomain(decoded, ev);
    } else if (fieldDomainRaw is List) {
      fieldDomain = _normalizeDomain(fieldDomainRaw.cast<dynamic>(), ev);
    }

    // Merge screen domain + field domain (AND logic like SAO's concat)
    final merged = _mergeDomains(screenDomain, fieldDomain);
    if (merged.isEmpty) return const DomainReadonlyResult();

    // unique_value: domain is [[field, '=', value]] → single AND equality
    final unique = _uniqueValue(merged, fieldName);
    if (unique == null) return const DomainReadonlyResult();

    // domain_readonly = true when the original domain uses AND (not OR)
    final isAnd = merged.isEmpty ||
        merged[0] == 'AND' ||
        (merged[0] is List); // implicit AND
    return DomainReadonlyResult(
      readonly: isAnd,
      forcedValue: unique,
    );
  } catch (_) {
    return const DomainReadonlyResult();
  }
}

/// Merges two domains with AND logic (like SAO's DomainInversion.concat).
List<dynamic> _mergeDomains(List<dynamic> a, List<dynamic> b) {
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  return ['AND', ...a, ...b];
}

/// Returns the forced value if [domain] uniquely constrains [fieldName]
/// to exactly one value via `=` or `in [value]`. Returns null otherwise.
/// Mirrors SAO's `DomainInversion.unique_value()`.
dynamic _uniqueValue(List<dynamic> domain, String fieldName) {
  // Unwrap 'AND' wrapper
  List<dynamic> conditions = domain;
  if (conditions.isNotEmpty && conditions[0] == 'AND') {
    conditions = conditions.sublist(1);
  }

  // Collect all equality constraints for fieldName
  dynamic found;
  int count = 0;
  for (final c in conditions) {
    if (c is! List || c.length < 3) continue;
    final name = c[0].toString();
    final op   = c[1].toString();
    final val  = c[2];
    if (name != fieldName) continue;
    if (op == '=') {
      found = val == false ? null : val;
      count++;
    } else if (op == 'in' && val is List && val.length == 1) {
      found = val[0] == false ? null : val[0];
      count++;
    }
  }
  if (count == 1) return found;
  return null;
}

FieldStateResult evaluateFieldStates({
  required Map<String, dynamic>? statesRaw,
  required bool staticInvisible,
  required bool staticReadonly,
  required bool staticRequired,
  required Map<String, dynamic> values,
}) {
  if (staticInvisible) {
    return const FieldStateResult(invisible: true);
  }

  if (statesRaw == null || statesRaw.isEmpty) {
    return FieldStateResult(
      invisible: staticInvisible,
      readonly: staticReadonly,
      required: staticRequired,
    );
  }

  final ev = PYSONEvaluator(values);

  bool invisible = staticInvisible;
  bool readonly = staticReadonly;
  bool required = staticRequired;

  final rawInvisible = statesRaw['invisible'];
  if (rawInvisible != null) {
    invisible = ev.evalBool(rawInvisible);
  }

  final rawReadonly = statesRaw['readonly'];
  if (rawReadonly != null) {
    readonly = ev.evalBool(rawReadonly);
  }

  final rawRequired = statesRaw['required'];
  if (rawRequired != null) {
    required = ev.evalBool(rawRequired);
  }

  return FieldStateResult(
    invisible: invisible,
    readonly: readonly,
    required: required,
  );
}
