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
  /// (SAO `new_`). With [defaults] true `default_get` would be called –
  /// STUB(D1 part 2).
  Record newRecord({int? id, bool defaults = false}) {
    final record = Record(model, id: id, group: this);
    if (defaults) record.defaultGet();
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
      p.model.fields[childName]?.changed(p);
      p.validate(softValidation: true);
      p.group.recordModified();
    }
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

  /// Adds fields to the model; new records would get their defaults
  /// (`default_get`, STUB(D1 part 2)).
  List<String> addFields(Map<String, dynamic> fields) =>
      model.addFields(fields);

  void destroy() {
    parent?.group.children.remove(this);
    parent = null;
  }

  // ── Server calls: STUB(D1 part 2) ────────────────────────────────────────

  /// STUB(D1 part 2): `delete` with `_timestamp` (5.3).
  Future<void> delete(List<Record> records) async =>
      throw NotYetImplemented('RecordGroup.delete');

  /// STUB(D1 part 2): save all records, delete the deleted ones.
  Future<void> save() async => throw NotYetImplemented('RecordGroup.save');

  /// STUB(D1 part 2): on_write methods after a write.
  Future<void> written(List<int> ids) async =>
      throw NotYetImplemented('RecordGroup.written');

  @override
  String toString() => 'RecordGroup(${model.name}, $length)';
}
