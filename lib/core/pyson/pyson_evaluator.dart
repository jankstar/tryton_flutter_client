import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../serialization/tryton_serializer.dart';

/// Evaluates Tryton PYSON expressions against an evaluation environment
/// (spec 03-pyson-domains.md 6). Reference is the Tryton desktop client
/// (`tryton/pyson.py`, same semantics as trytond); SAO only where it agrees.
///
/// PYSON objects arrive from the server as a Map with a `__class__` key:
///   `{"__class__": "Eval", "v": "state", "d": "draft"}` → returns field value
///   `{"__class__": "Not", "v": ...}` → logical NOT
///   `{"__class__": "Equal", "s1": ..., "s2": ...}` → equality comparison
///   etc.
///
/// The [context] is built by the caller (see `pyson_environment.dart`):
/// record values in `get_eval` format (Many2One = id), `context`,
/// `active_model`, `active_id`, `_parent_<field>` …
///
/// Value types: `Date` → [TrytonDate], `DateTime` → UTC [DateTime],
/// `TimeDelta` → [Duration]. Like in the Python client all date arithmetic
/// works on UTC fields (record datetimes are naive UTC there).
class PYSONEvaluator {
  final Map<String, dynamic> context;

  const PYSONEvaluator(this.context);

  /// Classes already reported as unknown (logged once each).
  static final Set<String> _unknownLogged = {};

  /// Evaluates any PYSON expression or literal.
  dynamic eval(dynamic expr) {
    if (expr is List) return expr.map(eval).toList();
    if (expr is Map) {
      final cls = expr['__class__'];
      if (cls is String) return _evalClass(cls, expr);
      // Plain dicts: their values may contain PYSON (decoded inside out).
      return expr.map((k, v) => MapEntry(k, eval(v)));
    }
    return expr;
  }

  /// Evaluates an expression and returns a bool (for states).
  bool evalBool(dynamic expr) => truthy(eval(expr));

  dynamic _evalClass(String cls, Map e) {
    switch (cls) {
      // ── Get value from the environment ────────────────────────────────────
      case 'Eval':
        // Key absent → default; key present but null → null. This lets
        // context-form clear buttons set values to null so that
        // _stripEmptyConditions can remove the resulting domain clause.
        final def = eval(e['d']);
        final name = e['v'];
        if (name is! String) return def;
        return _lookup(context, name, def);

      // ── Boolean operations ────────────────────────────────────────────────
      case 'Not':
        return !truthy(eval(e['v']));

      case 'Bool':
        return truthy(eval(e['v']));

      case 'And':
        final clauses = e['s'] as List? ?? const [];
        return clauses.every((c) => truthy(eval(c)));

      case 'Or':
        final clauses = e['s'] as List? ?? const [];
        return clauses.any((c) => truthy(eval(c)));

      case 'If':
        return truthy(eval(e['c'])) ? eval(e['t']) : eval(e['e']);

      // ── Comparisons ───────────────────────────────────────────────────────
      case 'Equal':
        return _equals(eval(e['s1']), eval(e['s2']));

      case 'Greater':
        return _compare(eval(e['s1']), eval(e['s2']),
            greater: true, orEqual: truthy(eval(e['e'])));

      case 'Less':
        return _compare(eval(e['s1']), eval(e['s2']),
            greater: false, orEqual: truthy(eval(e['e'])));

      case 'In':
        return _contains(eval(e['v']), eval(e['k']));

      // ── Dictionary / collection ───────────────────────────────────────────
      case 'Get':
        final dict = eval(e['v']);
        final key = eval(e['k'])?.toString();
        final def = eval(e['d']);
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

      // ── Dates and durations ───────────────────────────────────────────────
      case 'Date':
        return _date(e);

      case 'DateTime':
        return _dateTime(e);

      case 'TimeDelta':
        // timedelta(days, seconds, microseconds); floats are allowed.
        num part(String key) {
          final v = eval(e[key]);
          return v is num ? v : 0;
        }
        return Duration(
            microseconds: ((part('d') * 86400 + part('s')) * 1000000 +
                    part('m'))
                .round());

      default:
        // Like the Python client and SAO: an unknown class stays a dict
        // (with evaluated values).
        if (_unknownLogged.add(cls)) {
          debugPrint('PYSON: unknown class "$cls" – kept as dict');
        }
        return e.map((k, v) => MapEntry(k, k == '__class__' ? v : eval(v)));
    }
  }

  /// `Eval` lookup with dot paths: an exact key wins, otherwise `a.b.c`
  /// descends into `a` (missing level → default), like SAO.
  static dynamic _lookup(Map ctx, String name, dynamic def) {
    final idx = name.indexOf('.');
    if (idx >= 0 && !ctx.containsKey(name)) {
      final sub = ctx[name.substring(0, idx)];
      return _lookup(sub is Map ? sub : const {}, name.substring(idx + 1), def);
    }
    return ctx.containsKey(name) ? ctx[name] : def;
  }

  /// PYSON truthiness = Python `bool()`: null, false, 0, '', empty
  /// list/dict, Decimal 0 and a zero duration are false. A time (also
  /// 00:00) is true, as in Python ≥ 3.5 and trytond (SAO differs here).
  static bool truthy(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.isNotEmpty;
    if (v is List) return v.isNotEmpty;
    if (v is Map) return v.isNotEmpty;
    if (v is Duration) return v != Duration.zero;
    if (v is TrytonDecimal) return (double.tryParse(v.value) ?? 0) != 0;
    return true;
  }

  static bool _equals(dynamic a, dynamic b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_equals(a[i], b[i])) return false;
      }
      return true;
    }
    // A Date never equals a DateTime (different types, like SAO).
    if (a is DateTime && b is DateTime) return a.isAtSameMomentAs(b);
    if (a is TrytonDecimal && (b is num || b is TrytonDecimal) ||
        b is TrytonDecimal && a is num) {
      return _toNumber(a) == _toNumber(b);
    }
    if (a is TrytonTime && b is TrytonTime) {
      return a.hour == b.hour &&
          a.minute == b.minute &&
          a.second == b.second &&
          a.microsecond == b.microsecond;
    }
    // int == double compares numerically in Dart (1 == 1.0).
    return a == b;
  }

  /// `Greater`/`Less`: null on either side → false (Python client and SAO);
  /// otherwise both sides are compared as numbers (see [_toNumber]).
  static bool _compare(dynamic a, dynamic b,
      {required bool greater, required bool orEqual}) {
    if (a == null || b == null) return false;
    final x = _toNumber(a);
    final y = _toNumber(b);
    if (x == null || y == null) return false;
    if (greater) return orEqual ? x >= y : x > y;
    return orEqual ? x <= y : x < y;
  }

  /// Numeric value for comparisons (Python `Greater._convert`): DateTime →
  /// epoch seconds, Date → its midnight (UTC) in epoch seconds, Duration →
  /// total seconds. Anything else that is no number (Python raises) → null.
  static double? _toNumber(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is bool) return v ? 1 : 0;
    if (v is TrytonDecimal) return double.tryParse(v.value);
    if (v is DateTime) return v.microsecondsSinceEpoch / 1e6;
    if (v is TrytonDate) {
      return DateTime.utc(v.year, v.month, v.day).microsecondsSinceEpoch /
          1e6;
    }
    if (v is Duration) return v.inMicroseconds / 1e6;
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  static bool _contains(dynamic container, dynamic item) {
    if (container is List) return container.any((c) => _equals(c, item));
    if (container is Map) {
      return container.containsKey(item) ||
          container.containsKey(item?.toString());
    }
    if (container is String && item != null) {
      return container.contains(item.toString());
    }
    return false;
  }

  static int? _int(dynamic v) => v is num ? v.toInt() : null;

  /// Integer parameter; 0 and null mean "not set" for absolute values
  /// (relativedelta: `self.year or other.year`) and "no change" for deltas.
  int _param(Map e, String key) => _int(eval(e[key])) ?? 0;

  /// `Date(y, M, d, dy, dM, dd, start)`: base is `start` (a Date, or the
  /// UTC date of a DateTime), otherwise today (local date).
  TrytonDate _date(Map e) {
    final start = eval(e['start']);
    final (int, int, int) base;
    if (start is TrytonDate) {
      base = (start.year, start.month, start.day);
    } else if (start is DateTime) {
      final u = start.toUtc();
      base = (u.year, u.month, u.day);
    } else {
      final now = clock();
      base = (now.year, now.month, now.day);
    }
    final (y, m, d) = _relativeDate(base, e);
    final result = DateTime.utc(y, m, d + _param(e, 'dd'));
    return TrytonDate(result.year, result.month, result.day);
  }

  /// `DateTime(…, h, m, s, ms, …, dh, dm, ds, dms, start)` on UTC fields:
  /// base is `start` (a DateTime, or a Date at 00:00), otherwise now.
  /// `ms` and `dms` are microseconds.
  DateTime _dateTime(Map e) {
    final start = eval(e['start']);
    final DateTime base = switch (start) {
      DateTime s => s.toUtc(),
      TrytonDate s => DateTime.utc(s.year, s.month, s.day),
      _ => clock().toUtc(),
    };
    final (y, m, d) = _relativeDate((base.year, base.month, base.day), e);
    // Absolute time parts are applied when not null (0 is a valid value).
    final result = DateTime.utc(
      y,
      m,
      d,
      _int(eval(e['h'])) ?? base.hour,
      _int(eval(e['m'])) ?? base.minute,
      _int(eval(e['s'])) ?? base.second,
      0,
      _int(eval(e['ms'])) ?? base.millisecond * 1000 + base.microsecond,
    );
    return result.add(Duration(
      days: _param(e, 'dd'),
      hours: _param(e, 'dh'),
      minutes: _param(e, 'dm'),
      seconds: _param(e, 'ds'),
      microseconds: _param(e, 'dms'),
    ));
  }

  /// Year, month and day like dateutil's `relativedelta(year=y, month=M,
  /// day=d, years=dy, months=dM)`: absolute values replace (0/null keep the
  /// base), the deltas are added, and the day is clamped to the end of the
  /// resulting month at the very end.
  (int, int, int) _relativeDate((int, int, int) base, Map e) {
    final y = _param(e, 'y');
    final m = _param(e, 'M');
    final d = _param(e, 'd');
    final total = ((y != 0 ? y : base.$1) + _param(e, 'dy')) * 12 +
        (m != 0 ? m : base.$2) -
        1 +
        _param(e, 'dM');
    final year = (total / 12).floor();
    final month = total - year * 12 + 1;
    final last = DateTime.utc(year, month + 1, 0).day;
    return (year, month, math.min(d != 0 ? d : base.$3, last));
  }

  /// Current time; replaceable in tests.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;
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
///
/// [environment] is the record's evaluation environment
/// (`recordEnvironment`, values in `get_eval` format).
DomainReadonlyResult evaluateDomainReadonly({
  required String fieldName,
  required dynamic fieldDomainRaw,   // from fields_get 'domain'
  required List<dynamic> screenDomain, // domain from the action / URL
  required Map<String, dynamic> environment,
}) {
  try {
    final ev = PYSONEvaluator(environment);

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

/// Evaluates `states` (invisible/readonly/required) of a field, button or
/// page. [environment] is the record's evaluation environment
/// (`recordEnvironment`, values in `get_eval` format).
FieldStateResult evaluateFieldStates({
  required Map<String, dynamic>? statesRaw,
  required bool staticInvisible,
  required bool staticReadonly,
  required bool staticRequired,
  required Map<String, dynamic> environment,
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

  final ev = PYSONEvaluator(environment);

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
