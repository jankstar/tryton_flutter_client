import '../pyson/pyson_evaluator.dart';
import '../serialization/tryton_serializer.dart';

/// Domain inversion (spec 03-pyson-domains.md 7.2): port of SAO's
/// `Sao.common.DomainInversion` (common.js), checked against the Python
/// client `tryton/common/domain_inversion.py` 8.0.
///
/// A domain is a `List`: a leaf `[field, operator, value, (model)]`, a list
/// of domains (implicit AND) or `['AND'|'OR', ...]`. Inversion results are
/// a domain, `true` (no constraint) or `false` (not satisfiable).
///
/// Where SAO and Python differ, Python wins, except `constrainedLeaf`
/// (SAO 8.2 also treats `in` with one value as constrained).

/// True for `[field, operator, value, …]`.
bool isLeaf(dynamic expression) =>
    expression is List && expression.length > 2 && expression[1] is String;

bool _isBoolOp(dynamic d) => d == 'AND' || d == 'OR';

bool _isEmpty(dynamic d) =>
    d == null || (d is List && d.isEmpty) || (d is Map && d.isEmpty);

// ── Operators ───────────────────────────────────────────────────────────────

/// Python `==` for domain values: lists deep, numbers and Decimals
/// numerically, DateTime by instant; a date never equals a datetime.
bool domainEquals(dynamic a, dynamic b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!domainEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is DateTime && b is DateTime) return a.isAtSameMomentAs(b);
  final x = _number(a), y = _number(b);
  if (x != null && y != null) return x == y;
  if (a is TrytonTime && b is TrytonTime) return _timeKey(a) == _timeKey(b);
  return a == b;
}

double? _number(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is TrytonDecimal) return double.tryParse(v.value);
  return null;
}

int _timeKey(TrytonTime t) =>
    ((t.hour * 60 + t.minute) * 60 + t.second) * 1000000 + t.microsecond;

/// Ordering like Python (`<`, `>`); null when the types are not comparable
/// (Python raises TypeError → the leaf is false).
int? _compare(dynamic a, dynamic b) {
  final x = _number(a), y = _number(b);
  if (x != null && y != null) return x.compareTo(y);
  if (a is String && b is String) return a.compareTo(b);
  if (a is TrytonDate && b is TrytonDate) {
    return DateTime.utc(a.year, a.month, a.day)
        .compareTo(DateTime.utc(b.year, b.month, b.day));
  }
  if (a is DateTime && b is DateTime) return a.compareTo(b);
  if (a is Duration && b is Duration) return a.compareTo(b);
  if (a is TrytonTime && b is TrytonTime) {
    return _timeKey(a).compareTo(_timeKey(b));
  }
  if (a is bool && b is bool) return (a ? 1 : 0).compareTo(b ? 1 : 0);
  return null;
}

bool _contains(dynamic container, dynamic item) {
  if (container is List) return container.any((c) => domainEquals(c, item));
  if (container is String && item is String) return container.contains(item);
  if (container is Map) return container.containsKey(item);
  return false;
}

/// `in` (Python `in_`): a list on the left matches if any element is in
/// the right side.
bool domainIn(dynamic a, dynamic b) {
  if (a is List) {
    if (b is List) return a.any((x) => _contains(b, x));
    return _contains(a, b);
  }
  return _contains(b, a);
}

/// SQL `LIKE` on [value]: `%` = any sequence, `_` = one character, `\`
/// escapes `%`/`_`. The whole value must match (Python `fullmatch`).
bool sqlLike(dynamic value, dynamic pattern, {bool ignoreCase = true}) {
  if (value is! String || pattern is! String) return false;
  final buffer = StringBuffer();
  var escape = false;
  for (final char in pattern.split('')) {
    if (escape) {
      buffer.write(RegExp.escape(char));
      escape = false;
    } else if (char == r'\') {
      escape = true;
    } else if (char == '_') {
      buffer.write('.');
    } else if (char == '%') {
      buffer.write('.*');
    } else {
      buffer.write(RegExp.escape(char));
    }
  }
  final regexp = RegExp('^(?:$buffer)\$',
      caseSensitive: !ignoreCase, dotAll: true, unicode: true);
  return regexp.hasMatch(value);
}

/// Evaluates `a <operator> b`. Unknown operators (`child_of`, `where`, …)
/// are true, like in SAO and Python.
bool _applyOperator(String operator, dynamic a, dynamic b) {
  switch (operator) {
    case '=':
      return domainEquals(a, b);
    case '!=':
      return !domainEquals(a, b);
    case '>':
      final c = _compare(a, b);
      return c != null && c > 0;
    case '<':
      final c = _compare(a, b);
      return c != null && c < 0;
    case '>=':
      final c = _compare(a, b);
      return c != null && c >= 0;
    case '<=':
      final c = _compare(a, b);
      return c != null && c <= 0;
    case 'in':
      return domainIn(a, b);
    case 'not in':
      return !domainIn(a, b);
    case 'like':
      return sqlLike(a, b, ignoreCase: false);
    case 'ilike':
      return sqlLike(a, b);
    case 'not like':
      return !sqlLike(a, b, ignoreCase: false);
    case 'not ilike':
      return !sqlLike(a, b);
    default:
      return true;
  }
}

// ── Leaves ──────────────────────────────────────────────────────────────────

String _localePart(String expression, String? fieldName,
    [String localeName = 'id']) {
  if (expression == fieldName) return localeName;
  final idx = expression.indexOf('.');
  if (idx >= 0) return expression.substring(idx + 1);
  return expression;
}

/// A leaf that another inversion will satisfy: `=` (and, like SAO 8.2,
/// `in` with one value).
bool constrainedLeaf(List part) {
  final operator = part[1];
  final value = part[2];
  return operator == '=' ||
      (operator == 'in' && value is List && value.length == 1);
}

/// Evaluates one leaf against [context]. Returns null when it cannot be
/// decided (a comparison with null), like Python's `None`.
bool? evalLeaf(List part, Map context) {
  final field = part[0] as String;
  var operator = part[1] as String;
  dynamic value = part[2];
  if (field.contains('.')) {
    // In the case where the leaf concerns a m2o then having a value in the
    // evaluation context is deemed sufficient.
    return PYSONEvaluator.truthy(context[field.split('.').first]);
  }
  dynamic contextField = context[field];
  if (operator != '=' &&
      operator != '!=' &&
      (contextField == null || value == null) &&
      !((operator == 'in' || operator == 'not in') &&
          contextField == null &&
          value is List &&
          value.contains(null))) {
    return null;
  }
  if ((contextField is TrytonDate || contextField is DateTime) &&
      !PYSONEvaluator.truthy(value)) {
    value = contextField is DateTime ? _minDateTime : _minDate;
  }
  if ((value is TrytonDate || value is DateTime) &&
      !PYSONEvaluator.truthy(contextField)) {
    contextField = value is DateTime ? _minDateTime : _minDate;
  }
  if (contextField is List && value == null) value = [];
  if (contextField is String && value is List && value.length == 2) {
    value = '${value[0]},${value[1]}';
  } else if (contextField is List &&
      value is String &&
      contextField.length == 2) {
    contextField = '${contextField[0]},${contextField[1]}';
  }
  if ((operator == '=' || operator == '!=') &&
      contextField is List &&
      value is int) {
    operator = operator == '=' ? 'in' : 'not in';
  }
  return _applyOperator(operator, contextField, value);
}

final _minDate = const TrytonDate(1, 1, 1);
final _minDateTime = DateTime.utc(1);

/// Evaluates [domain] against the values in [context] (Python
/// `eval_domain`).
bool evalDomain(dynamic domain, Map context, {bool or = false}) {
  if (isLeaf(domain)) return evalLeaf(domain as List, context) ?? false;
  if (_isEmpty(domain)) return !or;
  final list = domain as List;
  if (list[0] == 'AND') return evalDomain(list.sublist(1), context);
  if (list[0] == 'OR') return evalDomain(list.sublist(1), context, or: true);
  final head = evalDomain(list[0], context);
  final tail = evalDomain(list.sublist(1), context, or: or);
  return or ? head || tail : head && tail;
}

/// For `child_of` leaves on the field itself, use the parent field (4th
/// element) as the field name.
dynamic inverseLeaf(dynamic domain) {
  if (_isBoolOp(domain)) return domain;
  if (isLeaf(domain)) {
    final leaf = domain as List;
    if ((leaf[1] as String).contains('child_of') &&
        !(leaf[0] as String).contains('.')) {
      if (leaf.length == 3) return leaf;
      return [leaf[3], ...leaf.sublist(1)];
    }
    return leaf;
  }
  return [for (final d in domain as List) inverseLeaf(d)];
}

/// Replaces leaves on [field] that target another model than [model] by
/// `['id', '=', null]` (Reference fields).
dynamic filterLeaf(dynamic domain, String field, String? model) {
  if (_isBoolOp(domain)) return domain;
  if (isLeaf(domain)) {
    final leaf = domain as List;
    if ((leaf[0] as String).startsWith(field) && leaf.length > 3) {
      if (leaf[3] != model) return ['id', '=', null];
    }
    return leaf;
  }
  return [for (final d in domain as List) filterLeaf(d, field, model)];
}

/// Removes the `field.` prefix for a search in the target model: the field
/// itself becomes `id` (or `rec_name` for a string value). With
/// [stripTarget] the target model (4th element) is dropped.
dynamic localizeDomain(dynamic domain,
    [String? fieldName, bool stripTarget = false]) {
  if (_isBoolOp(domain) || domain is bool) return domain;
  if (isLeaf(domain)) {
    final leaf = domain as List;
    final name = leaf[0] as String;
    if ((leaf[1] as String).contains('child_of')) {
      final idx = name.indexOf('.');
      if (idx >= 0) return [name.substring(idx + 1), ...leaf.sublist(1)];
      if (leaf.length == 3) return leaf;
      return [leaf[3], ...leaf.sublist(1, leaf.length - 1)];
    }
    final localName = leaf[2] is String ? 'rec_name' : 'id';
    final n = stripTarget ? 3 : 4;
    return [
      _localePart(name, fieldName, localName),
      ...leaf.sublist(1, n < leaf.length ? n : leaf.length),
      if (leaf.length > 4) ...leaf.sublist(4),
    ];
  }
  return [
    for (final part in domain as List)
      localizeDomain(part, fieldName, stripTarget)
  ];
}

// ── Sorting / simplification ────────────────────────────────────────────────

/// Sort key: (nestedness, content).
List<dynamic> _sortKey(dynamic domain) {
  if (domain is List && domain.isEmpty) return [0, domain];
  if (isLeaf(domain)) return [1, domain];
  if (_isBoolOp(domain)) return [0, domain];
  final content = [for (final e in domain as List) _sortKey(e)];
  final nestedness =
      content.map((k) => k[0] as int).fold<int>(0, (a, b) => a > b ? a : b);
  return [nestedness + 1, content];
}

/// Compares sort keys element-wise; values that cannot be ordered (e.g.
/// a string and null) count as equal so the stable sort keeps their order.
/// null sorts before numbers (Python orders `NoneType` before `int`).
int _domainCompare(dynamic a, dynamic b) {
  if (a is List && b is List) {
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final c = _domainCompare(a[i], b[i]);
      if (c != 0) return c;
    }
    return a.length.compareTo(b.length);
  }
  if (domainEquals(a, b)) return 0;
  if (a == null && _number(b) != null) return -1;
  if (b == null && _number(a) != null) return 1;
  return _compare(a, b) ?? 0;
}

/// Sorts a domain recursively (stable).
dynamic sortDomain(dynamic domain) {
  if (domain is List && domain.isEmpty) return <dynamic>[];
  if (isLeaf(domain) || _isBoolOp(domain)) return domain;
  final elements = [
    for (final (i, e) in (domain as List).indexed) (i, sortDomain(e))
  ]..sort((x, y) {
      final c = _domainCompare(_sortKey(x.$2), _sortKey(y.$2));
      return c != 0 ? c : x.$1.compareTo(y.$1);
    });
  return [for (final (_, e) in elements) e];
}

String _boolOperator(dynamic domain) {
  if (domain is List && domain.isNotEmpty && _isBoolOp(domain[0])) {
    return domain[0] as String;
  }
  return 'AND';
}

List<dynamic> _simplifyNested(dynamic domain) {
  if (domain is List && domain.isEmpty) return [];
  if (isLeaf(domain) || _isBoolOp(domain)) return [domain];
  final list = domain as List;
  if (list.length == 1) return _simplifyNested(list[0]);
  final simplified = <dynamic>[];
  final domainOp = _boolOperator(list);
  for (final branch in list) {
    final simplifiedBranch = _simplifyNested(branch);
    if (_boolOperator(simplifiedBranch) == domainOp ||
        simplifiedBranch.length == 1) {
      if (simplified.isNotEmpty &&
          simplifiedBranch.isNotEmpty &&
          _isBoolOp(simplifiedBranch[0])) {
        simplified.addAll(simplifiedBranch.sublist(1));
      } else {
        simplified.addAll(simplifiedBranch);
      }
    } else {
      simplified.add(simplifiedBranch);
    }
  }
  return simplified;
}

List<dynamic> _simplifyDuplicate(List domain) {
  final dedup = <dynamic>[];
  String? boolOp;
  var branches = domain;
  if (_isBoolOp(domain[0])) {
    boolOp = domain[0] as String;
    branches = domain.sublist(1);
  }
  for (final branch in branches) {
    if (branch is! List) continue;
    final simplifiedBranch = simplify(branch);
    if (simplifiedBranch.isEmpty) {
      if (boolOp == 'OR') return [];
      continue;
    }
    if (!dedup.any((d) => domainEquals(d, simplifiedBranch))) {
      dedup.add(simplifiedBranch);
    }
  }
  if (boolOp != null && dedup.length > 1) dedup.insert(0, boolOp);
  return dedup;
}

/// Removes duplicate expressions and useless AND/OR.
List<dynamic> simplify(dynamic domain) {
  if (isLeaf(domain)) return [domain];
  if (domain is! List || domain.isEmpty) return [];
  return _simplifyNested(_simplifyDuplicate(domain));
}

dynamic _simplifyAnd(dynamic domain) {
  if (isLeaf(domain) || domain == 'OR') return domain;
  if (domain is! List) return domain;
  return [
    for (final e in domain)
      if (e != 'AND') _simplifyAnd(e)
  ];
}

/// Simplified and sorted version of a domain (to compare domains).
dynamic canonicalize(dynamic domain) =>
    _simplifyAnd(sortDomain(simplify(domain)));

/// Flattens nested domains with the same operator; the result starts with
/// `AND`/`OR` (Python `merge`).
List<dynamic> merge(dynamic domain, [String? domOperator]) {
  if (_isEmpty(domain) || _isBoolOp(domain)) return [];
  if (isLeaf(domain)) return [domain];
  final list = domain as List;
  final domainType = list[0] == 'OR' ? 'OR' : 'AND';
  if (domOperator == null) {
    return [
      domainType,
      for (final e in list) ...merge(e, domainType),
    ];
  }
  if (domainType == domOperator) {
    return [for (final e in list) ...merge(e, domainType)];
  }
  // without setting the domoperator
  return [merge(list)];
}

/// Combines [domains] with AND (or [domOperator]) and simplifies.
List<dynamic> concat(List<dynamic> domains, {String? domOperator}) {
  final result = <dynamic>[
    ?domOperator,
    for (final d in domains)
      if (!_isEmpty(d)) d,
  ];
  return simplify(merge(result));
}

/// `(true, field, value)` if [domain] is exactly `[[f, '=', v]]` (or
/// `in [v]` with [singleValue]; `f.id` with a target model gives
/// `[model, v]`), otherwise `(false, null, null)`.
(bool, String?, dynamic) uniqueValue(dynamic domain,
    {bool singleValue = true}) {
  if (domain is List && domain.length == 1 && isLeaf(domain[0])) {
    final leaf = domain[0] as List;
    final name = leaf[0] as String;
    final operator = leaf[1];
    dynamic value = leaf[2];
    final model = leaf.sublist(3);
    final count = '.'.allMatches(name).length;
    if ((operator == '=' ||
            (singleValue &&
                operator == 'in' &&
                value is List &&
                value.length == 1)) &&
        (count == 0 ||
            (count == 1 && model.isNotEmpty && name.endsWith('.id')))) {
      if (operator == 'in' && singleValue) value = (value as List).first;
      if (model.isNotEmpty && name.endsWith('.id')) {
        value = [model.first, value];
      }
      return (true, name, value);
    }
  }
  return (false, null, null);
}

// ── Reference fields ────────────────────────────────────────────────────────

(String?, dynamic) _value2reference(dynamic value) {
  if (value is String && value.contains(',')) {
    final idx = value.indexOf(',');
    final model = value.substring(0, idx);
    final ref = value.substring(idx + 1);
    if (ref == '%') return (model, ref);
    final id = int.tryParse(ref);
    if (id == null) return (null, value);
    return (model, id);
  }
  if (value is List &&
      value.length == 2 &&
      value[0] is String &&
      (value[1] is int || value[1] == '%')) {
    return (value[0] as String, value[1]);
  }
  return (null, value);
}

/// Converts leaves on the Reference field [reference] (`'model,id'`
/// values) into `reference.id` leaves with the target model.
dynamic prepareReferenceDomain(dynamic domain, String reference) {
  if (_isBoolOp(domain)) return domain;
  if (isLeaf(domain)) {
    final leaf = domain as List;
    if (leaf[0] != reference) return leaf;
    final operator = leaf[1];
    if (operator == '=' || operator == '!=') {
      final (model, refId) = _value2reference(leaf[2]);
      if (model != null) {
        if (refId == '%') {
          if (operator == '=') return ['$reference.id', '!=', null, model];
          return [reference, 'not like', leaf[2]];
        }
        return ['$reference.id', operator, refId, model];
      }
    } else if ((operator == 'in' || operator == 'not in') &&
        leaf[2] is List) {
      final modelValues = <String, List<dynamic>>{};
      var complete = true;
      for (final value in leaf[2] as List) {
        final (model, refId) = _value2reference(value);
        if (model == null) {
          complete = false;
          break;
        }
        modelValues.putIfAbsent(model, () => []).add(refId);
      }
      if (complete) {
        return [
          operator == 'in' ? 'OR' : 'AND',
          for (final MapEntry(key: model, value: refIds)
              in modelValues.entries)
            if (refIds.contains('%'))
              operator == 'in'
                  ? ['$reference.id', '!=', null, model]
                  : [reference, 'not like', '$model,%']
            else
              ['$reference.id', operator, refIds, model],
        ];
      }
    }
    return <dynamic>[];
  }
  return [
    for (final d in domain as List) prepareReferenceDomain(d, reference)
  ];
}

/// Target models allowed for the Reference field [fieldName] (4th element
/// of its leaves), in order of appearance.
List<String> extractReferenceModels(dynamic domain, String fieldName) {
  if (_isBoolOp(domain)) return [];
  if (isLeaf(domain)) {
    final leaf = domain as List;
    final localPart = (leaf[0] as String).split('.').first;
    if (localPart == fieldName && leaf.length > 3) return [leaf[3] as String];
    return [];
  }
  final models = <String>[];
  for (final d in domain as List) {
    for (final m in extractReferenceModels(d, fieldName)) {
      if (!models.contains(m)) models.add(m);
    }
  }
  return models;
}

// ── Inversion ───────────────────────────────────────────────────────────────

/// Parsed AND expression (`parse`): leaves stay lists, sub-domains become
/// [DomainAnd]/[DomainOr].
class DomainAnd {
  final List<dynamic> branches;
  final Set<String> variables = {};

  DomainAnd(List<dynamic> expressions)
      : branches = [for (final e in expressions) parse(e)] {
    for (final expression in branches) {
      if (isLeaf(expression)) {
        variables.add(_base(expression[0] as String));
      } else if (expression is DomainAnd) {
        variables.addAll(expression.variables);
      }
    }
  }

  static String _base(String expression) => expression.split('.').first;

  /// Inversion for [symbol]: a domain, `true` or `false`.
  dynamic inverse(String symbol, Map context) {
    final result = <dynamic>[];
    for (final part in branches) {
      if (part is DomainAnd) {
        final partInversion = part.inverse(symbol, context);
        final evaluated = partInversion is bool;
        if (!part.variables.contains(symbol)) continue;
        if (!evaluated) {
          result.add(partInversion);
        } else if (partInversion) {
          continue;
        } else {
          return false;
        }
      } else if (isLeaf(part) && _base(part[0] as String) == symbol) {
        result.add(part);
      } else if (part is List) {
        final field = part[0];
        if (!context.containsKey(field) ||
            (evalLeaf(part, context) ?? false) ||
            constrainedLeaf(part)) {
          result.add(true);
        } else {
          return false;
        }
      }
    }
    result.removeWhere((e) => e == true);
    if (result.isEmpty) return true;
    return simplify(result);
  }
}

/// Parsed OR expression.
class DomainOr extends DomainAnd {
  DomainOr(super.expressions);

  @override
  dynamic inverse(String symbol, Map context) {
    final result = <dynamic>[];
    if (variables.any((v) => v != symbol && !context.containsKey(v))) {
      // In this case we don't know enough about this OR part, we consider
      // it to be True (because people will have the constraint on this
      // part later).
      return true;
    }
    for (final part in branches) {
      if (part is DomainAnd) {
        final partInversion = part.inverse(symbol, context);
        final evaluated = partInversion is bool;
        if (!part.variables.contains(symbol)) {
          if (evaluated && partInversion) return true;
          continue;
        }
        if (!evaluated) {
          result.add(partInversion);
        } else if (partInversion) {
          return true;
        } else {
          continue;
        }
      } else if (isLeaf(part) &&
          DomainAnd._base(part[0] as String) == symbol) {
        result.add(part);
      } else if (part is List) {
        final field = DomainAnd._base(part[0] as String);
        if (context.containsKey(field)) {
          if (evalLeaf(part, context) ?? false) return true;
          result.add(false);
        }
      }
    }
    result.removeWhere((e) => e == false);
    if (result.isEmpty) return false;
    return simplify(['OR', ...result]);
  }
}

/// Domain → tree: a leaf stays a list, otherwise [DomainAnd]/[DomainOr].
dynamic parse(dynamic domain) {
  if (isLeaf(domain) || (domain is! List && !_isEmpty(domain))) return domain;
  if (_isEmpty(domain)) return DomainAnd(const []);
  final list = domain as List;
  if (list[0] == 'OR') return DomainOr(list.sublist(1));
  return DomainAnd(list[0] == 'AND' ? list.sublist(1) : list);
}

/// Reduces [domain] to the conditions on [symbol]; leaves on other fields
/// are evaluated with the values in [context]. Returns a domain, `true`
/// (no constraint) or `false` (not satisfiable).
dynamic domainInversion(dynamic domain, String symbol,
    [Map context = const {}]) {
  final expression = parse(domain);
  if (expression is! DomainAnd) {
    // A single leaf as domain.
    return DomainAnd([expression]).inverse(symbol, context);
  }
  if (!expression.variables.contains(symbol)) return true;
  return expression.inverse(symbol, context);
}

/// Removes leaves on fields for which [isReadonly] is true before an
/// inversion (Python `Group.clean4inversion`).
List<dynamic> cleanForInversion(
    dynamic domain, bool Function(String field) isReadonly) {
  if (domain is! List || domain.isEmpty) return [];
  dynamic head = domain[0];
  final tail = domain.sublist(1);
  if (_isBoolOp(head)) {
    // keep
  } else if (isLeaf(head)) {
    if (isReadonly(head[0] as String)) head = <dynamic>[];
  } else {
    head = cleanForInversion(head, isReadonly);
  }
  return [head, ...cleanForInversion(tail, isReadonly)];
}
