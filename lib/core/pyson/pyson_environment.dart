import 'dart:convert';

import 'pyson_evaluator.dart';

/// Builders for PYSON evaluation environments (spec 03-pyson-domains.md 6).
///
/// The [PYSONEvaluator] gets its environment from outside; these functions
/// build the standard ones like SAO's `record.expr_eval`,
/// `Sao.common.EvalEnvironment` and `Sao.Action.exec_action`.

/// Converts current form/list values to the `get_eval` format
/// (SAO `record.get_eval()`): a Many2One `[id, rec_name]` becomes its id.
///
/// Transitional helper until the data layer delivers `get_eval` values
/// itself. With [fieldTypes] (field name → Tryton type) only `many2one`
/// fields are converted; without it every `[int, String?]` pair is treated
/// as a Many2One. One2Many/Many2Many id lists stay lists.
Map<String, dynamic> formEvalValues(
  Map<String, dynamic> values, {
  Map<String, String>? fieldTypes,
}) {
  return {
    for (final e in values.entries)
      e.key: _evalValue(e.value, fieldTypes == null ? null : fieldTypes[e.key]),
  };
}

dynamic _evalValue(dynamic v, String? type) {
  final isPair = v is List &&
      v.length == 2 &&
      v[0] is int &&
      (v[1] == null || v[1] is String);
  if (type == null) return isPair ? v[0] : v;
  if (type != 'many2one') return v;
  if (v is List) return v.isEmpty ? null : v[0];
  return v;
}

/// Environment of a record (SAO `record.expr_eval`): the values in
/// `get_eval` format plus `id`, `context`, `active_model`, `active_id` and,
/// for a record inside a One2Many, `_parent_<parentName>` with the
/// parent's environment (see [parentEnvironment]).
Map<String, dynamic> recordEnvironment({
  required Map<String, dynamic> values,
  Map<String, dynamic> context = const {},
  String? activeModel,
  int? activeId,
  String? parentName,
  Map<String, dynamic>? parent,
}) {
  return {
    'id': activeId,
    ...values,
    'context': context,
    'active_model': activeModel,
    'active_id': activeId,
    if (parentName != null && parent != null) '_parent_$parentName': parent,
  };
}

/// Environment of a parent record for `_parent_<field>` (SAO
/// `Sao.common.EvalEnvironment`): values in `get_eval` format plus `id`;
/// nested further via [parentName] / [parent] (`_parent_x._parent_y.z`).
Map<String, dynamic> parentEnvironment({
  required Map<String, dynamic> values,
  int? id,
  String? parentName,
  Map<String, dynamic>? parent,
}) {
  return {
    ...values,
    'id': id,
    if (parentName != null && parent != null) '_parent_$parentName': parent,
  };
}

/// Environment of an action (SAO `Sao.Action.exec_action`): `active_model`,
/// `active_id`, `active_ids`, the session context, `_user` and the
/// evaluated `pyson_context` (JSON string or decoded value); `context` is
/// the whole environment again.
Map<String, dynamic> actionEnvironment({
  Map<String, dynamic> sessionContext = const {},
  int? userId,
  String? activeModel,
  int? activeId,
  List<int> activeIds = const [],
  dynamic pysonContext,
}) {
  final env = <String, dynamic>{
    'active_model': activeModel,
    'active_id': activeId,
    'active_ids': activeIds,
    ...sessionContext,
    '_user': userId,
  };
  var decoded = pysonContext;
  if (decoded is String) {
    try {
      decoded = decoded.isEmpty ? null : jsonDecode(decoded);
    } catch (_) {
      decoded = null;
    }
  }
  if (decoded != null) {
    final evaluated = PYSONEvaluator(env).eval(decoded);
    if (evaluated is Map) {
      env.addAll(evaluated.map((k, v) => MapEntry(k.toString(), v)));
    }
  }
  env['context'] = env;
  return env;
}
