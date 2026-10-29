/// UI-independent data layer (spec 02-datenmodell.md 5.1–5.7):
/// [TrytonModel], [RecordGroup], [Record] and the field classes.
///
/// Port of `Sao.Model`, `Sao.Group`, `Sao.Record` and `Sao.field.*` from
/// SAO's model.js (names follow model.js so code and reference can be read
/// side by side), checked against the Python client
/// `tryton/gui/window/view_form/model/{group,record,field}.py` 8.0.
///
/// No widgets, no Riverpod: changes are announced through
/// [RecordGroup] (a [ChangeNotifier]); server calls go through
/// [ModelRpc] (implemented by the ModelService adapter).
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../domain/domain_inversion.dart';
import '../pyson/pyson_environment.dart';
import '../pyson/pyson_evaluator.dart';
import '../serialization/tryton_serializer.dart';

part 'field.dart';
part 'group.dart';
part 'record.dart';

/// Server access of the data layer: `model.<model>.<method>(params…, ctx)`.
/// [context] is the complete context (it already contains the session
/// context). With [processException] false no error dialog is shown.
abstract interface class ModelRpc {
  Future<dynamic> execute(String model, String method, List<dynamic> params,
      {Map<String, dynamic>? context, bool processException = true});
}

/// Resolves a ConcurrencyException of a `write`/`delete` (A1,
/// `runWithConcurrencyCheck`): [action] is called with `withTimestamp`;
/// returns false when the user cancelled.
typedef ConcurrencyRunner = Future<bool> Function(String model, List<int> ids,
    Future<void> Function(bool withTimestamp) action);

/// Access rights of a model (`ir.model.access` / SAO `MODELACCESS`).
class ModelAccess {
  final bool read, write, create, delete;

  const ModelAccess({
    this.read = true,
    this.write = true,
    this.create = true,
    this.delete = true,
  });
}

/// Raised when a server call is made without a [ModelRpc].
class NoModelRpc extends StateError {
  NoModelRpc(String what) : super('$what needs a ModelRpc');
}

/// Shared settings of all models of a session (SAO `Sao.Session` /
/// `Sao.config`).
class ModelSession {
  final ModelRpc? rpc;

  /// Session context, read on every use.
  final Map<String, dynamic> Function() context;

  /// Conflict handling for write/delete; null → the ConcurrencyException
  /// reaches the caller.
  ConcurrencyRunner? concurrencyRunner;

  /// `ir.model.get_notification`: model → fields that trigger
  /// `on_change_notify`. Loaded on first use when null.
  Map<String, List<String>>? notificationFields;

  /// Access rights per model (SAO `MODELACCESS.get`); null = not known
  /// (then full access is assumed, see [TrytonModel.access]).
  ModelAccess? Function(String model)? accessOf;

  /// Loads the access rights of [models] (batches, spec 4) so that
  /// [accessOf] knows them.
  Future<void> Function(Iterable<String> models)? loadAccess;

  /// Record limit for eager loading (`client.limit`).
  int limit;

  /// Rows of pre-loaded x2many records (`display_size`).
  int displaySize;

  ModelSession({
    this.rpc,
    Map<String, dynamic> Function()? context,
    this.concurrencyRunner,
    this.notificationFields,
    this.accessOf,
    this.loadAccess,
    this.limit = 1000,
    this.displaySize = 20,
  }) : context = context ?? _emptyContext;

  static Map<String, dynamic> _emptyContext() => const {};

  /// Fields of [model] that trigger `on_change_notify`.
  Future<List<String>> notificationFieldsOf(String model) async {
    var fields = notificationFields;
    if (fields == null) {
      try {
        final result = await rpc?.execute('ir.model', 'get_notification', [],
            context: context(), processException: false);
        fields = {
          if (result is Map)
            for (final MapEntry(key: k, value: v) in result.entries)
              '$k': [for (final f in (v as List? ?? const [])) '$f'],
        };
      } catch (_) {
        fields = {};
      }
      notificationFields = fields;
    }
    return fields[model] ?? const [];
  }
}

/// A Tryton model (SAO `Sao.Model`): name and field descriptions.
class TrytonModel {
  final String name;
  final ModelSession session;

  /// Field objects by name (SAO `model.fields`).
  final Map<String, Field> fields = {};

  /// Access rights (SAO `Sao.common.MODELACCESS.get(name)`): set
  /// explicitly, else from the session's metadata, else full access.
  ModelAccess get access =>
      _access ?? session.accessOf?.call(name) ?? const ModelAccess();
  set access(ModelAccess value) => _access = value;
  ModelAccess? _access;

  TrytonModel(
    this.name, {
    ModelSession? session,
    Map<String, dynamic> Function()? sessionContext,
    ModelAccess? access,
  }) : session = session ?? ModelSession(context: sessionContext) {
    _access = access;
  }

  /// Session context (SAO `model.session.context`).
  Map<String, dynamic> sessionContext() => session.context();

  /// A model for [name] sharing this model's session (for x2many groups).
  TrytonModel related(String name) => TrytonModel(name, session: session);

  /// Adds new fields; descriptions of existing fields are extended
  /// (SAO `add_fields`). Returns the names of the added fields.
  List<String> addFields(Map<String, dynamic> descriptions) {
    final added = <String>[];
    for (final MapEntry(key: name, value: desc) in descriptions.entries) {
      final description = <String, dynamic>{
        'name': name,
        ...(desc as Map).cast<String, dynamic>(),
      };
      final existing = fields[name];
      if (existing == null) {
        fields[name] = Field.create(description);
        added.add(name);
      } else {
        existing.description.addAll(description);
      }
    }
    return added;
  }

  /// `model.<name>.<method>(params…, context)`.
  Future<dynamic> execute(String method, List<dynamic> params,
      {Map<String, dynamic>? context, bool processException = true}) async {
    final rpc = session.rpc;
    if (rpc == null) throw NoModelRpc('model.$name.$method');
    return rpc.execute(name, method, params,
        context: context ?? sessionContext(),
        processException: processException);
  }
}
