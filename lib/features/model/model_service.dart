import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rpc/error_processing.dart';
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

  /// Central error processing for [execute] with `processException: true`
  /// (dialogs, UserWarning repetition). Null = errors go to the caller
  /// unchanged (current screens handle them with `ErrorHandler.run`).
  RpcErrorProcessor? errorProcessor;

  String get _db => _getDatabase();
  Map<String, dynamic> get _ctx => _getContext();

  /// The current session context.
  Map<String, dynamic> sessionContext() => _getContext();

  /// Calls `model.<model>.<method>` (spec 2.3). The context is always
  /// appended as the last parameter: session context ⊕ [context] – keys of
  /// [context] override the session context, like SAO's
  /// `params[-1] = {...session.context, ...params[-1]}`. Callers never
  /// append a context to [params] themselves.
  ///
  /// With [processException] (default) an error goes through
  /// [errorProcessor] (shown to the user, then a [HandledRpcError]); with
  /// false no dialog is shown and the error reaches the caller unchanged
  /// (counters, autocomplete, background loading).
  Future<T> execute<T>(
    String model,
    String method,
    List<dynamic> params, {
    Map<String, dynamic>? context,
    bool processException = true,
  }) {
    Future<T> call() => _execute<T>('model.$model.$method', params, context);
    final processor = errorProcessor;
    if (!processException || processor == null) return call();
    return processor.process<T>(call);
  }

  Future<T> _execute<T>(
    String fullMethod,
    List<dynamic> params,
    Map<String, dynamic>? context,
  ) async {
    final result = await _rpc.call(_db, fullMethod, [
      ...params,
      mergeContext(_ctx, context),
    ]);
    return result as T;
  }

  /// Session context ⊕ [context]; [context] wins on equal keys.
  static Map<String, dynamic> mergeContext(
          Map<String, dynamic> session, Map<String, dynamic>? context) =>
      {...session, ...?context};

  /// Calls a selection classmethod on a model and returns [[key, label], ...].
  /// Used for selection fields where `fields_get` returns the method name as a
  /// String instead of an evaluated list.
  ///
  /// With `selection_change_with`, [values] holds the dependency fields and
  /// their current values: `model.X.<method>(values, ctx)`; without it the
  /// method is called with the context only. Errors are thrown (the caller
  /// must not cache a failed load).
  Future<List<List<dynamic>>> getSelectionOptions(
    String model,
    String method, {
    Map<String, dynamic>? values,
  }) async {
    final raw = await execute<List>(model, method, [?values]);
    return raw
        .map((e) => e is List ? e.cast<dynamic>() : <dynamic>[e, e.toString()])
        .toList();
  }

  /// Returns the field descriptions for a model.
  Future<Map<String, FieldDefinition>> fieldsGet(
    String model, {
    List<String>? fields,
  }) async {
    final raw = await execute<Map<String, dynamic>>(
        model, 'fields_get', [fields ?? []]);
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
    final raw = await execute<List>(
        model, 'search_read', [domain, offset, limit, order, fields]);
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
    final raw = await execute<List>(model, 'read', [ids, fields]);
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
    final result = await execute<List>(model, 'create', [valuesList]);
    return result.cast<int>();
  }

  /// `_timestamp` context for optimistic locking (null = none).
  static Map<String, dynamic>? _timestampContext(
      String model, List<int> ids, String? timestamp) {
    if (timestamp == null) return null;
    return {
      '_timestamp': {for (final id in ids) '$model,$id': timestamp},
    };
  }

  /// Writes fields to existing records.
  /// [timestamp] is sent as `_timestamp` for concurrency control. A conflict
  /// is NOT resolved here: the [ConcurrencyException] reaches the caller,
  /// which asks the user (see `runWithConcurrencyCheck`). Calling again
  /// without [timestamp] is "Write Anyway".
  Future<void> write(
    String model,
    List<int> ids,
    Map<String, dynamic> values, {
    String? timestamp,
  }) async {
    // write/delete sometimes return null instead of true → no cast.
    await execute<dynamic>(model, 'write', [ids, values],
        context: _timestampContext(model, ids, timestamp));
  }

  /// Deletes records. [timestamp] works like in [write].
  Future<void> delete(String model, List<int> ids, {String? timestamp}) async {
    await execute<dynamic>(model, 'delete', [ids],
        context: _timestampContext(model, ids, timestamp));
  }

  /// Returns default values for a new form.
  Future<Map<String, dynamic>> defaultGet(
    String model,
    List<String> fields,
  ) async {
    final raw = await execute<Map<String, dynamic>>(
        model, 'default_get', [fields]);
    return raw;
  }

  /// Duplicates records and returns the new IDs.
  Future<List<int>> copy(String model, List<int> ids) async {
    final result = await execute<List>(model, 'copy', [ids, {}]);
    return result.cast<int>();
  }

  /// Loads the view definition (XML layout + field descriptions) from the server.
  /// Corresponds to `fields_view_get` in SAO.
  Future<ViewDefinition> fieldsViewGet(
    String model, {
    String viewType = 'form',
    int? viewId,
  }) async {
    final raw = await execute<Map<String, dynamic>>(
        model, 'fields_view_get', [viewId, viewType]);
    return ViewDefinition.fromJson(raw);
  }

  /// Returns the current user's preferences (context fields only).
  /// context_only=true avoids avatar binary data in the response.
  Future<dynamic> getUserPreferences() async {
    return execute<dynamic>('res.user', 'get_preferences', [true]);
  }

  /// Returns the toolbar actions (actions, reports, relations, email templates)
  /// for a model. Corresponds to `view_toolbar_get` in SAO.
  Future<TrytonToolbar> viewToolbarGet(String model) async {
    final raw = await execute<Map<String, dynamic>>(
        model, 'view_toolbar_get', []);
    return TrytonToolbar.fromJson(raw);
  }

  /// Returns the attachment count for a resource.
  Future<int> attachmentCount(String model, int id) async {
    final raw = await execute<List>('ir.attachment', 'search_read', [
      [['resource', '=', '$model,$id']],
      0,
      1,
      null,
      ['id'],
    ]);
    // For the real count without a limit search again – here only an existence check
    return raw.length;
  }

  /// Executes a report. Returns `[format, base64data, name]`.
  Future<List<dynamic>> executeReport(
    String reportName,
    List<int> ids,
    String model,
  ) async {
    final result = await _execute<List>(
      'report.$reportName.execute',
      [
        ids,
        {'ids': ids, 'model': model},
      ],
      null,
    );
    return result;
  }

  /// Fetches the currency/unit symbol for a given record.
  /// Mirrors SAO's `field.get_symbol(record, symbolFieldName)` which calls
  /// `model.{relation}.get_symbol(id, sign, context)`.
  /// Returns `[symbol, position]` where position < 0.5 = prefix, ≥ 0.5 = suffix.
  Future<(String, double)> getSymbol(String relation, int id, int sign) async {
    try {
      final result =
          await execute<List>(relation, 'get_symbol', [id, sign]);
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
    final result =
        await execute<int>(model, 'search_count', [domain, 0, null]);
    return result;
  }

  /// Many2One search: returns matching [id, name] pairs.
  Future<List<Map<String, dynamic>>> searchName(
    String model,
    String query, {
    List<dynamic> domain = const [],
    int limit = 10,
  }) async {
    final raw = await execute<List>(model, 'search_read', [
      [if (query.isNotEmpty) ['rec_name', 'ilike', '%$query%'], ...domain],
      0,
      limit,
      null,
      ['rec_name'],
    ]);
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
