import 'dart:convert';

import '../../core/serialization/tryton_serializer.dart';
import 'field_definition.dart';

/// Loads `[[key, label], …]` for method-based selection fields.
typedef SelectionFetcher = Future<List<List<dynamic>>> Function(
    String method, Map<String, dynamic>? values);

/// Dynamic selections like SAO's `selection_mixin` (spec 5.6, 9.2.4):
///
/// * without `selection_change_with`: `model.X.<method>(ctx)`, loaded once;
/// * with `selection_change_with`: `model.X.<method>(values, ctx)` where
///   `values` are the dependency fields and their current values; reloaded
///   when one of them changes.
///
/// Results are cached per method and value combination (SAO
/// `_values2selection`). Failed loads are not cached. One instance per form.
class SelectionLoader {
  final SelectionFetcher _fetch;
  final _cache = <String, List<List<dynamic>>>{};
  final _pending = <String, Future<List<List<dynamic>>>>{};

  SelectionLoader(this._fetch);

  /// True when [fd] needs a server call (selection given as method name).
  static bool isDynamic(FieldDefinition fd) =>
      fd.type == 'selection' && fd.selectionFunction != null;

  /// True when [fd]'s selection depends on [changedField].
  static bool dependsOn(FieldDefinition fd, String changedField) =>
      isDynamic(fd) && (fd.selectionChangeWith?.contains(changedField) ?? false);

  /// Values of [fd]'s `selection_change_with` fields as sent to the server
  /// (like SAO `_get_on_change_args` without `id`): many2one as id, empty
  /// as null. Null when the field has no `selection_change_with`.
  static Map<String, dynamic>? changeWithValues(
    FieldDefinition fd,
    Map<String, dynamic> record,
    Map<String, FieldDefinition> fields,
  ) {
    final names = fd.selectionChangeWith;
    if (names == null || names.isEmpty) return null;
    return {
      for (final name in names)
        if (name != 'id') name: _serverValue(record[name], fields[name]),
    };
  }

  static dynamic _serverValue(dynamic v, FieldDefinition? fd) {
    if (v == false && fd?.type != 'boolean') return null;
    if (fd?.type == 'many2one' || fd?.type == 'one2one') {
      if (v is List) return v.isNotEmpty ? v.first : null;
      if (v is Map) return v['id'];
    }
    return v;
  }

  /// Cache key: method + value combination (Tryton types encoded, so
  /// DateTime/Decimal values are comparable).
  static String cacheKey(String method, Map<String, dynamic>? values) =>
      '$method|${jsonEncode(TrytonSerializer.encode(values))}';

  /// Options for [fd] given the current [record] values. Returns `[]` on
  /// error (not cached, retried on the next call).
  Future<List<List<dynamic>>> load(
    FieldDefinition fd,
    Map<String, dynamic> record,
    Map<String, FieldDefinition> fields,
  ) async {
    final method = fd.selectionFunction;
    if (method == null) return fd.selection ?? const [];
    final values = changeWithValues(fd, record, fields);
    final key = cacheKey(method, values);
    final cached = _cache[key];
    if (cached != null) return cached;
    try {
      final result = await (_pending[key] ??= _fetch(method, values));
      _cache[key] = result;
      return result;
    } catch (_) {
      return const [];
    } finally {
      _pending.remove(key);
    }
  }
}
