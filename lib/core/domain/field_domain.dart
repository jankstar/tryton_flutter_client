import 'dart:convert';

import '../pyson/pyson_evaluator.dart';
import 'domain_inversion.dart';

/// Result of the domain check of one field (spec 02-datenmodell.md 5.5).
/// Mirrors the `domain_readonly` part of `Field.validate` in the Python
/// client / SAO.
class DomainReadonlyResult {
  /// The field is locked because the (AND) domain allows only one value.
  final bool readonly;

  /// True when [forcedValue] must be set (it may be null).
  final bool forced;
  final dynamic forcedValue;

  const DomainReadonlyResult({
    this.readonly = false,
    this.forced = false,
    this.forcedValue,
  });
}

/// Field types whose validation uses only the screen domain (their own
/// `domain` restricts the search in the target model).
const _screenDomainOnly = {
  'many2one',
  'one2one',
  'reference',
  'one2many',
  'many2many',
  'dict',
};

/// Field types with `_single_value = False`.
const _multiValue = {'multiselection', 'one2many', 'many2many', 'dict'};

/// Field `domain` (PYSON string or list) evaluated in [environment]
/// (`record.expr_eval`).
List<dynamic> evalFieldDomain(dynamic raw, Map<String, dynamic> environment) {
  dynamic decoded = raw;
  if (raw is String) {
    if (raw.isEmpty) return const [];
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
  }
  final result = PYSONEvaluator(environment).eval(decoded);
  return result is List ? result : const [];
}

/// Screen domain inverted on [fieldName] (Python `Field.domains_get`):
/// `false` → `[['id', '=', null]]`, `true` → `[]`.
List<dynamic> screenDomainFor(
  String fieldName,
  List<dynamic> screenDomain,
  Map<String, dynamic> environment, {
  bool Function(String field)? isReadonlyField,
}) {
  final domain4inversion = isReadonlyField == null
      ? screenDomain
      : cleanForInversion(screenDomain, isReadonlyField);
  final inverted = domainInversion(domain4inversion, fieldName, environment);
  if (inverted == false) {
    return [
      ['id', '=', null]
    ];
  }
  if (inverted == true) return [];
  return inverted as List<dynamic>;
}

/// Whether [fieldName] is forced to one value by the screen domain
/// ([screenDomain], e.g. from the action) and its own `domain`
/// ([fieldDomainRaw]), like `Field.validate` in the Python client:
///
/// * the screen domain (without leaves on readonly fields, see
///   [isReadonlyField]) is inverted on the field with the record values
///   ([environment], `get_eval` format) and combined with the field domain
///   (not for relation fields);
/// * if the result is a unique value (`[f, '=', v]` / `in [v]`) it is set,
///   and the field becomes readonly when the original domain is an AND;
/// * an empty, optional, visible field is only set when the screen domain
///   alone makes the value unique.
DomainReadonlyResult evaluateDomainReadonly({
  required String fieldName,
  required String fieldType,
  required dynamic fieldDomainRaw,
  required List<dynamic> screenDomain,
  required Map<String, dynamic> environment,
  bool fieldReadonly = false,
  bool required = false,
  bool invisible = false,
  bool Function(String field)? isReadonlyField,
}) {
  const none = DomainReadonlyResult();
  if (fieldReadonly) return none;
  try {
    final screen = screenDomainFor(fieldName, screenDomain, environment,
        isReadonlyField: isReadonlyField);
    final validation = _screenDomainOnly.contains(fieldType)
        ? screen
        : concat([screen, evalFieldDomain(fieldDomainRaw, environment)]);
    final domain = simplify(validation);
    if (domainEquals(domain, [
      ['id', '=', null]
    ])) {
      return none; // invalid, nothing to force
    }
    final singleValue = !_multiValue.contains(fieldType);
    final (unique, leftPart, value) =
        uniqueValue(domain, singleValue: singleValue);
    final (uniqueFromScreen, _, _) =
        uniqueValue(screen, singleValue: singleValue);
    final isEmpty = !PYSONEvaluator.truthy(environment[fieldName]);
    if (isEmpty && !required && !invisible && !uniqueFromScreen) return none;
    if (!unique) return none;
    // If the inverted domain is so constraint that only one value is
    // possible we use it. But the original domain might be an 'OR' domain
    // and thus not preventing the modification of the field.
    final original = merge(screenDomain.isNotEmpty ? screenDomain : domain);
    final readonly = original.isNotEmpty && original[0] == 'AND';
    final idx = leftPart!.indexOf('.');
    final setDefault = idx < 0 || leftPart.substring(idx + 1) == 'id';
    if (!setDefault) return none;
    return DomainReadonlyResult(
      readonly: readonly,
      forced: true,
      // XXX like Python/SAO: false from the server means null
      forcedValue: value == false ? null : value,
    );
  } catch (_) {
    return none;
  }
}
