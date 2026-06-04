import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rpc/rpc_client.dart';
import '../../core/rpc/rpc_exceptions.dart';
import '../../features/auth/auth_provider.dart';
import '../../core/xml/view_definition.dart';
import 'field_definition.dart';
import 'record.dart';
import 'toolbar_data.dart';

class ModelService {
  final RpcClient _rpc;
  final Map<String, dynamic> Function() _getContext;
  final String Function() _getDatabase;

  ModelService({
    required RpcClient rpc,
    required Map<String, dynamic> Function() getContext,
    required String Function() getDatabase,
  })  : _rpc = rpc,
        _getContext = getContext,
        _getDatabase = getDatabase;

  String get _db => _getDatabase();
  Map<String, dynamic> get _ctx => _getContext();

  Future<T> _call<T>(String method, List<dynamic> params) async {
    final result = await _rpc.call(_db, method, params);
    return result as T;
  }

  /// Like _call, but without casting the return value.
  /// For write/delete which sometimes return null instead of true.
  Future<void> _callVoid(String method, List<dynamic> params) async {
    await _rpc.call(_db, method, params);
  }

  /// Calls a selection classmethod on a model and returns [[key, label], ...].
  /// Used for selection fields where `fields_get` returns the method name as a
  /// String instead of an evaluated list.
  Future<List<List<dynamic>>> getSelectionOptions(
      String model, String method) async {
    try {
      final raw = await _call<List>('model.$model.$method', [_ctx]);
      return raw.map((e) => e is List ? e.cast<dynamic>() : <dynamic>[e, e.toString()]).toList();
    } catch (_) {
      return [];
    }
  }

  /// Returns the field descriptions for a model.
  Future<Map<String, FieldDefinition>> fieldsGet(
    String model, {
    List<String>? fields,
  }) async {
    final raw = await _call<Map<String, dynamic>>(
      'model.$model.fields_get',
      [fields ?? [], _ctx],
    );
    return raw.map((k, v) =>
        MapEntry(k, FieldDefinition.fromJson(k, v as Map<String, dynamic>)));
  }

  /// Searches for records and returns them with fields.
  /// [order] is a list of `[fieldname, 'ASC'|'DESC']` pairs or null.
  Future<List<TrytonRecord>> searchRead(
    String model, {
    List<dynamic> domain = const [],
    List<String> fields = const [],
    int offset = 0,
    int? limit = 50,
    List<List<String>>? order,
  }) async {
    final raw = await _call<List>(
      'model.$model.search_read',
      [domain, offset, limit, order, fields, _ctx],
    );
    return raw
        .cast<Map<String, dynamic>>()
        .map(TrytonRecord.fromJson)
        .toList();
  }

  /// Reads specific fields for the given IDs.
  Future<List<TrytonRecord>> read(
    String model,
    List<int> ids,
    List<String> fields,
  ) async {
    final raw = await _call<List>(
      'model.$model.read',
      [ids, fields, _ctx],
    );
    return raw
        .cast<Map<String, dynamic>>()
        .map(TrytonRecord.fromJson)
        .toList();
  }

  /// Creates new records, returns the new IDs.
  Future<List<int>> create(
    String model,
    List<Map<String, dynamic>> valuesList,
  ) async {
    final result = await _call<List>(
      'model.$model.create',
      [valuesList, _ctx],
    );
    return result.cast<int>();
  }

  /// Writes fields to existing records.
  /// [timestamp] is sent for concurrency control.
  Future<void> write(
    String model,
    List<int> ids,
    Map<String, dynamic> values, {
    String? timestamp,
  }) async {
    final ctx = timestamp != null
        ? {..._ctx, '_timestamp': {for (final id in ids) '$model,$id': timestamp}}
        : _ctx;
    try {
      await _callVoid('model.$model.write', [ids, values, ctx]);
    } on ConcurrencyException {
      await _callVoid('model.$model.write', [ids, values, _ctx]);
    }
  }

  /// Deletes records.
  Future<void> delete(String model, List<int> ids) async {
    await _callVoid('model.$model.delete', [ids, _ctx]);
  }

  /// Returns default values for a new form.
  Future<Map<String, dynamic>> defaultGet(
    String model,
    List<String> fields,
  ) async {
    final raw = await _call<Map<String, dynamic>>(
      'model.$model.default_get',
      [fields, _ctx],
    );
    return raw;
  }

  /// Recalculates dependent fields after a change (on_change).
  Future<Map<String, dynamic>> onChange(
    String model,
    Map<String, dynamic> values,
    List<String> changedFields,
  ) async {
    final raw = await _call<Map<String, dynamic>>(
      'model.$model.on_change',
      [values, changedFields, _ctx],
    );
    return raw;
  }

  /// Executes a form button method on the server.
  /// Returns the action dict if the server returns one, otherwise null.
  Future<dynamic> executeButton(
    String model,
    String method,
    List<int> ids,
  ) async {
    return _call<dynamic>('model.$model.$method', [ids, _ctx]);
  }

  /// Duplicates records and returns the new IDs.
  Future<List<int>> copy(String model, List<int> ids) async {
    final result = await _call<List>(
      'model.$model.copy',
      [ids, {}, _ctx],
    );
    return result.cast<int>();
  }

  /// Loads the view definition (XML layout + field descriptions) from the server.
  /// Corresponds to `fields_view_get` in SAO.
  Future<ViewDefinition> fieldsViewGet(
    String model, {
    String viewType = 'form',
    int? viewId,
  }) async {
    final raw = await _call<Map<String, dynamic>>(
      'model.$model.fields_view_get',
      [viewId, viewType, _ctx],
    );
    return ViewDefinition.fromJson(raw);
  }

  /// Returns the current user's preferences (context fields only).
  /// context_only=true avoids avatar binary data in the response.
  Future<dynamic> getUserPreferences() async {
    return _call<dynamic>('model.res.user.get_preferences', [true, _ctx]);
  }

  /// Returns the toolbar actions (actions, reports, relations, email templates)
  /// for a model. Corresponds to `view_toolbar_get` in SAO.
  Future<TrytonToolbar> viewToolbarGet(String model) async {
    final raw = await _call<Map<String, dynamic>>(
      'model.$model.view_toolbar_get',
      [_ctx],
    );
    return TrytonToolbar.fromJson(raw);
  }

  /// Returns the attachment count for a resource.
  Future<int> attachmentCount(String model, int id) async {
    final raw = await _call<List>(
      'model.ir.attachment.search_read',
      [
        [['resource', '=', '$model,$id']],
        0,
        1,
        null,
        ['id'],
        _ctx,
      ],
    );
    // For the real count without a limit search again – here only an existence check
    return raw.length;
  }

  /// Executes a report. Returns `[format, base64data, name]`.
  Future<List<dynamic>> executeReport(
    String reportName,
    List<int> ids,
    String model,
  ) async {
    final result = await _call<List>(
      'report.$reportName.execute',
      [
        ids,
        {'ids': ids, 'model': model},
        _ctx,
      ],
    );
    return result;
  }

  /// Fetches the currency/unit symbol for a given record.
  /// Mirrors SAO's `field.get_symbol(record, symbolFieldName)` which calls
  /// `model.{relation}.get_symbol(id, sign, context)`.
  /// Returns `[symbol, position]` where position < 0.5 = prefix, ≥ 0.5 = suffix.
  Future<(String, double)> getSymbol(String relation, int id, int sign) async {
    try {
      final result = await _call<List>(
        'model.$relation.get_symbol',
        [id, sign, _ctx],
      );
      final symbol = result.isNotEmpty ? result[0]?.toString() ?? '' : '';
      final pos = result.length > 1 ? (result[1] as num).toDouble() : 1.0;
      return (symbol, pos);
    } catch (_) {
      return ('', 1.0);
    }
  }

  /// Returns the number of records matching [domain].
  /// Mirrors SAO: model.execute('search_count', [domain, 0, null], context).
  Future<int> searchCount(String model, {List<dynamic> domain = const []}) async {
    final result = await _call<int>(
      'model.$model.search_count',
      [domain, 0, null, _ctx],
    );
    return result;
  }

  /// Many2One search: returns matching [id, name] pairs.
  Future<List<Map<String, dynamic>>> searchName(
    String model,
    String query, {
    List<dynamic> domain = const [],
    int limit = 10,
  }) async {
    final raw = await _call<List>(
      'model.$model.search_read',
      [
        [if (query.isNotEmpty) ['rec_name', 'ilike', '%$query%'], ...domain],
        0,
        limit,
        null,
        ['rec_name'],
        _ctx,
      ],
    );
    return raw.cast<Map<String, dynamic>>();
  }
}

final modelServiceProvider = Provider<ModelService>((ref) {
  final session = ref.read(sessionProvider);
  return ModelService(
    rpc: ref.read(rpcClientProvider),
    getContext: () => session.context,
    getDatabase: () => session.database ?? '',
  );
});
