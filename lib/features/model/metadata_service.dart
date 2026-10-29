import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/model/model.dart';
import 'model_service.dart';

/// Client-side metadata caches (spec 4, SAO `MODELACCESS`, `MODELHISTORY`,
/// `MODELNAME`, `MODELNOTIFICATION`, `MODELCHAT`, `VIEW_SEARCH`), loaded
/// in the start sequence after `get_preferences` (3.2) and cleared at
/// logout.
class MetadataService {
  final ModelService _svc;

  MetadataService(this._svc);

  /// Models per `get_access` call (SAO `batchnum`).
  static const batchSize = 100;

  List<String>? _models;
  final Map<String, ModelAccess> _access = {};
  Set<String> _history = const {};
  Map<String, String> _names = const {};
  Map<String, List<String>>? _notification;
  Set<String>? _chat;
  Map<String, List<dynamic>> _searches = const {};

  /// Start sequence (3.2): model list, history models, notification
  /// fields and saved searches in parallel; errors leave a cache empty.
  Future<void> load() async {
    _access.clear();
    await Future.wait([
      loadModels(),
      loadHistory(),
      loadNotification(),
      loadSearches(),
    ]);
  }

  /// Everything is forgotten (logout).
  void clear() {
    _models = null;
    _access.clear();
    _history = const {};
    _names = const {};
    _notification = null;
    _chat = null;
    _searches = const {};
  }

  Future<dynamic> _call(String model, String method,
          [List<dynamic> params = const []]) =>
      _svc.execute<dynamic>(model, method, params, processException: false);

  // ── MODELACCESS ──────────────────────────────────────────────────────────

  /// `ir.model.list_models()` (all model names, in server order).
  Future<void> loadModels() async {
    try {
      final result = await _call('ir.model', 'list_models');
      _models = [for (final m in (result as List? ?? const [])) '$m'];
    } catch (_) {
      _models ??= const [];
    }
  }

  /// Known access rights of [model] (null = not loaded yet).
  ModelAccess? accessOf(String model) => _access[model];

  /// Access rights of [model]: loaded with `ir.model.access.get_access`
  /// for the [batchSize] models around it (SAO `MODELACCESS.get`). On
  /// error the model is read only.
  Future<ModelAccess> access(String model) async {
    final known = _access[model];
    if (known != null) return known;
    var models = _models;
    if (models == null || !models.contains(model)) {
      await loadModels();
      models = _models!;
    }
    final idx = models.indexOf(model);
    final half = batchSize ~/ 2;
    final batch = idx < 0
        ? [model]
        : models.sublist(math.max(0, idx - half),
            math.min(models.length, idx + half));
    try {
      final result = await _call('ir.model.access', 'get_access', [batch]);
      if (result is Map) {
        for (final MapEntry(:key, :value) in result.entries) {
          if (value is Map) _access['$key'] = _toAccess(value);
        }
      }
    } catch (_) {
      _access[model] = const ModelAccess(
          read: true, write: false, create: false, delete: false);
    }
    return _access[model] ??= const ModelAccess(
        read: true, write: false, create: false, delete: false);
  }

  /// Loads the rights of all [models] not known yet.
  Future<void> ensureAccess(Iterable<String> models) async {
    for (final model in {...models}) {
      if (!_access.containsKey(model)) await access(model);
    }
  }

  /// `{read, write, create, delete}` as 0/1 (or bool) → bools.
  static ModelAccess _toAccess(Map value) {
    bool flag(String key) {
      final v = value[key];
      return v == true || (v is num && v != 0);
    }

    return ModelAccess(
      read: flag('read'),
      write: flag('write'),
      create: flag('create'),
      delete: flag('delete'),
    );
  }

  // ── MODELHISTORY ─────────────────────────────────────────────────────────

  Future<void> loadHistory() async {
    try {
      final result = await _call('ir.model', 'list_history');
      _history = {for (final m in (result as List? ?? const [])) '$m'};
    } catch (_) {
      _history = const {};
    }
  }

  /// Model with history (menu "Revisions…").
  bool hasHistory(String model) => _history.contains(model);

  // ── MODELNAME ────────────────────────────────────────────────────────────

  /// Translated name of [model] (`ir.model.get_names`, loaded once per
  /// language); '' when unknown.
  Future<String> name(String model) async {
    if (_names.isEmpty) {
      try {
        final result = await _call('ir.model', 'get_names');
        _names = {
          if (result is Map)
            for (final MapEntry(:key, :value) in result.entries) '$key': '$value'
        };
      } catch (_) {
        _names = const {};
      }
    }
    return _names[model] ?? '';
  }

  /// After a language change the names are loaded again.
  void clearNames() => _names = const {};

  // ── MODELNOTIFICATION ────────────────────────────────────────────────────

  Future<void> loadNotification() async {
    try {
      final result = await _call('ir.model', 'get_notification');
      _notification = {
        if (result is Map)
          for (final MapEntry(:key, :value) in result.entries)
            '$key': [for (final f in (value as List? ?? const [])) '$f'],
      };
    } catch (_) {
      _notification = null;
    }
  }

  /// `{model: fields}` of `on_change_notify` (null = not loaded).
  Map<String, List<String>>? get notificationFields => _notification;

  // ── MODELCHAT ────────────────────────────────────────────────────────────

  /// Model with chat (`ir.chat.channel.get_models`, loaded on first use).
  Future<bool> hasChat(String model) async {
    if (_chat == null) {
      try {
        final result = await _call('ir.chat.channel', 'get_models');
        _chat = {
          for (final m in (result as List? ?? const []))
            m is List && m.isNotEmpty ? '${m[0]}' : '$m'
        };
      } catch (_) {
        _chat = const {};
      }
    }
    return _chat!.contains(model);
  }

  // ── VIEW_SEARCH ──────────────────────────────────────────────────────────

  Future<void> loadSearches() async {
    try {
      final result = await _call('ir.ui.view_search', 'get');
      _searches = {
        if (result is Map)
          for (final MapEntry(:key, :value) in result.entries)
            '$key': value is List ? value : const [],
      };
    } catch (_) {
      _searches = const {};
    }
  }

  /// Saved searches of [model]: `[[id, name, domain, access], …]`.
  List<dynamic> searches(String model) => _searches[model] ?? const [];
}

final metadataServiceProvider = Provider<MetadataService>((ref) {
  final svc = ref.read(modelServiceProvider);
  return svc.metadata = MetadataService(svc);
});
