/// UI-independent data layer (spec 02-datenmodell.md 5.1–5.4, 5.6, 5.7):
/// [TrytonModel], [RecordGroup], [Record] and the field classes.
///
/// Port of `Sao.Model`, `Sao.Group`, `Sao.Record` and `Sao.field.*` from
/// SAO's model.js (names follow model.js so code and reference can be read
/// side by side), checked against the Python client
/// `tryton/gui/window/view_form/model/{group,record,field}.py` 8.0.
///
/// No widgets, no Riverpod: changes are announced through
/// [RecordGroup] (a [ChangeNotifier]).
///
/// Part 1 (structures) only. Everything that needs the server (loading,
/// saving, on_change, default_get, fields_get for unknown fields,
/// rec_name lookups, digits/symbol, dict keys) is a stub marked
/// `STUB(D1 part 2)`.
library;

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

/// Error of a server method that is not available before D1 part 2.
class NotYetImplemented extends UnsupportedError {
  NotYetImplemented(String what)
      : super('$what needs the server – STUB(D1 part 2)');
}

/// A Tryton model (SAO `Sao.Model`): name and field descriptions.
class TrytonModel {
  final String name;

  /// Field objects by name (SAO `model.fields`).
  final Map<String, Field> fields = {};

  /// Session context (SAO `model.session.context`), read on every use.
  final Map<String, dynamic> Function() sessionContext;

  /// Access rights (SAO `Sao.common.MODELACCESS.get(name)`).
  ModelAccess access;

  TrytonModel(
    this.name, {
    Map<String, dynamic> Function()? sessionContext,
    this.access = const ModelAccess(),
  }) : sessionContext = sessionContext ?? _emptyContext;

  static Map<String, dynamic> _emptyContext() => const {};

  /// A model for [name] sharing this model's session (for x2many groups).
  TrytonModel related(String name) =>
      TrytonModel(name, sessionContext: sessionContext);

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
  /// STUB(D1 part 2): no server connection in the data layer yet.
  Future<dynamic> execute(String method, List<dynamic> params,
      [Map<String, dynamic> context = const {}]) async {
    throw NotYetImplemented('model.$name.$method');
  }
}
