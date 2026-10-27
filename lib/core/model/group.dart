part of 'model.dart';

/// Ordered list of [Record]s (SAO `Sao.Group`, spec 5.3).
///
/// For x2many fields the group is a child group: [parent] is the parent
/// record, [childName] the x2many field in the parent and [parentName]
/// the `relation_field` back to the parent.
///
/// Listeners are notified when a record of the (root) group is modified
/// (SAO calls `screen.record_modified()`).
class RecordGroup extends ChangeNotifier with IterableMixin<Record> {
  final TrytonModel model;
  final List<Record> _records = [];

  /// Own context (SAO `_context`).
  Map<String, dynamic> _context;

  /// Methods called after a write (`on_write`).
  List<String> onWrite = [];

  Record? parent;
  String parentName = '';
  String childName = '';
  String? parentDatetimeField;

  /// Groups of the same model in tree views (SAO `children`).
  final List<RecordGroup> children = [];

  /// Records whose link is removed / that are deleted on save.
  final List<Record> recordRemoved = [];
  final List<Record> recordDeleted = [];

  bool _readonly = false;
  String? excludeField;
  bool skipModelAccess = false;

  /// Domains of the screens showing this group (SAO
  /// `screen.attributes.domain`).
  final List<List<dynamic>> screenDomains = [];

  /// Messages of `on_change_notify` (`[[type, message], …]`) for the UI
  /// (SAO `screen.record_notify`).
  void Function(List<dynamic> notifications)? onNotify;

  /// Running `read` of this group (SAO `group.prm`).
  Future<void>? _loading;

  RecordGroup(this.model,
      {Map<String, dynamic>? context, Iterable<Record> records = const []})
      : _context = {...?context} {
    for (final r in records) {
      r.group = this;
      _records.add(r);
    }
  }

  // ── List access ───────────────────────────────────────────────────────────

  @override
  Iterator<Record> get iterator => _records.iterator;

  @override
  int get length => _records.length;

  Record operator [](int index) => _records[index];

  int indexOf(Record record) => _records.indexOf(record);

  /// The record with [id] (SAO `get`).
  Record? get(int id) {
    for (final r in _records) {
      if (r.id == id) return r;
    }
    return null;
  }

  // ── State ─────────────────────────────────────────────────────────────────

  /// `_datetime` in the context (history) or no write/create access
  /// (unless [skipModelAccess]) or explicitly set.
  bool get readonly {
    final access = model.access;
    if (PYSONEvaluator.truthy(context['_datetime']) ||
        (!(access.write || access.create) && !skipModelAccess)) {
      return true;
    }
    return _readonly;
  }

  set readonly(bool value) => _readonly = value;

  RecordGroup get rootGroup {
    var root = this;
    var p = parent;
    while (p != null) {
      root = p.group;
      p = p.group.parent;
    }
    return root;
  }

  /// Session context ⊕ parent context ⊕ context of the parent field ⊕ own
  /// context ⊕ `_datetime` from [parentDatetimeField].
  Map<String, dynamic> get context => _getContext();

  set context(Map<String, dynamic> value) => _context = {...value};

  /// [context] without the session context (for URLs, actions).
  Map<String, dynamic> get localContext => _getContext(local: true);

  Map<String, dynamic> _getContext({bool local = false}) {
    final context = local
        ? <String, dynamic>{}
        : <String, dynamic>{...model.sessionContext()};
    final p = parent;
    if (p != null) {
      final parentContext = p.getContext(local: local);
      context.addAll(parentContext);
      final field = p.model.fields[childName];
      if (field != null) {
        context.addAll(
            field.getContext(p, recordContext: parentContext, local: local));
      }
    }
    context.addAll(_context);
    if (parentDatetimeField != null && p != null) {
      context['_datetime'] = p.getEval()[parentDatetimeField];
    }
    return context;
  }

  /// Screen domains; for a child group combined with the parent field's
  /// domain (SAO `domain`).
  List<dynamic> get domain {
    final domain = <dynamic>[...screenDomains];
    final p = parent;
    if (p != null && childName.isNotEmpty) {
      final field = p.model.fields[childName];
      if (field != null) return [domain, field.getDomain(p)];
    }
    return domain;
  }

  /// Domain without leaves on readonly fields (SAO `clean4inversion`).
  List<dynamic> clean4inversion(List<dynamic> domain) =>
      cleanForInversion(domain,
          (name) => model.fields[name]?.description['readonly'] == true);

  List<dynamic> get domain4inversion => clean4inversion(domain);

  // ── Operations ────────────────────────────────────────────────────────────

  /// Creates placeholder records for [ids] (values are loaded lazily);
  /// [preloaded] values (`id → values`) are set directly.
  void load(List<int> ids,
      {bool modified = false,
      int position = -1,
      Map<int, Map<String, dynamic>>? preloaded}) {
    if (position == -1) position = _records.length;
    final newRecords = <Record>[];
    for (final id in ids) {
      var record = get(id);
      if (record == null) {
        record = Record(model, id: id, group: this);
        _records.insert(position, record);
        position++;
      }
      final values = preloaded?[id];
      if (values != null) record.set(values, modified: false, validate: false);
      newRecords.add(record);
    }
    // Records loaded again are no longer removed or deleted
    recordRemoved.removeWhere((r) => ids.contains(r.id));
    recordDeleted.removeWhere((r) => ids.contains(r.id));
    if (newRecords.isNotEmpty && modified) {
      for (final r in newRecords) {
        r.modifiedFields.add('id');
      }
      recordModified();
    }
  }

  /// A new record (negative id unless [id] is given), not yet added
  /// (SAO `new_` without default).
  Record newRecord({int? id}) => Record(model, id: id, group: this);

  /// A new record with its server defaults (SAO `new_(true, …)`):
  /// `default_get`, [defaults] as `default_<field>` context.
  Future<Record> newRecordWithDefaults(
      {int? id, Map<String, dynamic>? defaults}) async {
    final record = newRecord(id: id);
    await record.defaultGet(defaults);
    return record;
  }

  /// Adds [record] at [position]; in a child group the parent field
  /// (Many2One/Reference back to the parent) is set via `set_client`.
  Record add(Record record, {int position = -1, bool modified = true}) {
    if (position == -1) position = _records.length;
    position = math.min(position, _records.length);
    if (!identical(record.group, this)) record.group = this;
    if (!_records.contains(record)) _records.insert(position, record);
    recordRemoved.removeWhere((r) => r.id == record.id);
    recordDeleted.removeWhere((r) => r.id == record.id);
    record.modifiedFields.add('id');
    final p = parent;
    if (modified && p != null) {
      // Set parent field to trigger on_change
      final field = model.fields[parentName];
      if (field is Many2OneField) {
        field.setClient(record, [p.id, '']);
      } else if (field is ReferenceField) {
        field.setClient(record, [
          p.model.name,
          [p.id, '']
        ]);
      }
    }
    return record;
  }

  /// [remove] true → unlink (`record_removed`), false → delete
  /// (`record_deleted`). New records, records of a new parent or
  /// [forceRemove] leave the list immediately.
  void remove(Record record,
      {required bool remove, bool forceRemove = false, bool modified = true}) {
    if (record.id >= 0) {
      if (remove) {
        recordDeleted.remove(record);
        if (!recordRemoved.contains(record)) recordRemoved.add(record);
      } else {
        recordRemoved.remove(record);
        if (!recordDeleted.contains(record)) recordDeleted.add(record);
      }
    }
    record.modifiedFields.add('id');
    if (record.id < 0 || (parent != null && parent!.id < 0) || forceRemove) {
      _remove(record);
    }
    if (modified) recordModified();
  }

  void _remove(Record record) {
    _records.remove(record);
    record.destroy();
  }

  void unremove(Record record) {
    recordRemoved.remove(record);
    recordDeleted.remove(record);
    record.group.recordModified();
  }

  void clear() {
    _records.clear();
    recordRemoved.clear();
    recordDeleted.clear();
  }

  /// Propagates a modification: in a child group to the parent
  /// (`modified_fields[child_name]`, `field.changed`, validate), in the
  /// root group to the listeners.
  void recordModified() {
    final p = parent;
    if (p == null) {
      notifyListeners();
    } else {
      p.modifiedFields.add(childName);
      final field = p.model.fields[childName];
      // The parent's on_change runs in the parent's queue (not awaited
      // here: this may be called from inside a queued task).
      if (field != null) {
        unawaited(p._enqueue(() async {
          await field.changed(p);
          p.validate(softValidation: true);
          p.group.notifyScreens();
        }));
      }
      p.group.recordModified();
    }
  }

  /// Notifies the listeners of the root group (display update).
  void notifyScreens() => rootGroup.notifyListeners();

  /// Hands `on_change_notify` messages to [onNotify] (of this group or,
  /// if unset, of the root group).
  void recordNotify(List<dynamic> notifications) {
    final handler = onNotify ?? rootGroup.onNotify;
    handler?.call(notifications);
  }

  /// Unchanged records with [ids] are reset so they are loaded again.
  void reload(Iterable<int> ids) {
    for (final child in children) {
      child.reload(ids);
    }
    for (final id in ids) {
      final record = get(id);
      if (record != null && record.modifiedFields.isEmpty) record.cancel();
    }
  }

  void setParent(Record? parent) {
    this.parent = parent;
    if (parent != null && parent.model.name == model.name) {
      parent.group.children.add(this);
    }
  }

  /// Adds fields to the model (without defaults, see
  /// [addFieldsWithDefaults]).
  List<String> addFields(Map<String, dynamic> fields) =>
      model.addFields(fields);

  /// Adds fields; new records get the defaults of the added fields
  /// (SAO `add_fields`).
  Future<List<String>> addFieldsWithDefaults(
      Map<String, dynamic> fields) async {
    final added = model.addFields(fields);
    final newRecords = [for (final r in _records) if (r.id < 0) r];
    if (newRecords.isNotEmpty && added.isNotEmpty) {
      final values =
          await model.execute('default_get', [added], context: context);
      if (values is Map && values.isNotEmpty) {
        for (final r in newRecords) {
          await r.setDefault(values.cast<String, dynamic>(), modified: false);
        }
        recordModified();
      }
    }
    return added;
  }

  void destroy() {
    parent?.group.children.remove(this);
    parent = null;
  }

  // ── Server calls ──────────────────────────────────────────────────────────

  /// Deletes [records] (`delete` with `_timestamp`); on_write ids are
  /// reloaded afterwards. A conflict goes to the session's
  /// [ConcurrencyRunner]. Returns false when the user cancelled.
  Future<bool> delete(List<Record> records) async {
    final saved = [for (final r in records) if (r.id >= 0) r];
    if (saved.isEmpty) return true;
    final ids = [for (final r in saved) r.id];
    final timestamps = <String, String?>{
      for (final r in saved) ...r.getTimestamp(),
    };
    final root = rootGroup;
    final reloadIds = [
      for (final id in await root.onWriteIds(ids))
        if (!ids.contains(id)) id
    ];
    Future<void> delete(bool withTimestamp) => model.execute('delete', [
          ids
        ], context: {
          ...context,
          if (withTimestamp) '_timestamp': timestamps,
        });
    final runner = model.session.concurrencyRunner;
    if (runner == null) {
      await delete(true);
    } else if (!await runner(model.name, ids, delete)) {
      return false;
    }
    for (final r in saved) {
      r.destroy();
    }
    root.reload(reloadIds);
    return true;
  }

  /// Saves all records and deletes the deleted ones.
  Future<bool> save() async {
    var ok = true;
    for (final r in [..._records]) {
      // Deleted records are deleted below (saving would drop their
      // timestamp).
      if (recordDeleted.contains(r)) continue;
      if (!await r.save(forceReload: false)) ok = false;
    }
    if (recordDeleted.isNotEmpty) {
      final deleted = [...recordDeleted];
      for (final r in deleted) {
        _remove(r);
      }
      recordDeleted.clear();
      if (!await delete(deleted)) ok = false;
    }
    return ok;
  }

  /// After a write: on_write methods give further ids, which are reloaded.
  Future<void> written(List<int> ids) async {
    final toReload = [
      for (final id in await onWriteIds(ids))
        if (!ids.contains(id)) id
    ];
    rootGroup.reload(toReload);
  }

  /// `model.X.<fnct>(ids)` for each [onWrite] method; unique ids.
  Future<List<int>> onWriteIds(List<int> ids) async {
    final result = <int>[];
    for (final fnct in onWrite) {
      final res = await model.execute(fnct, [ids], context: _context);
      for (final id in (res as List? ?? const [])) {
        if (id is int && !result.contains(id)) result.add(id);
      }
    }
    return result;
  }

  @override
  String toString() => 'RecordGroup(${model.name}, $length)';
}
