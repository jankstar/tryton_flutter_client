import 'dart:convert';

import '../pyson/pyson_evaluator.dart';

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
