part of 'model.dart';

/// Texts of [Record.invalidMessage] (SAO `screen.invalid_message`); the
/// UI passes translated texts, `%s` is the field label.
class InvalidMessages {
  final String required;
  final String domain;
  final String children;

  const InvalidMessages({
    this.required = '"%s" is required.',
    this.domain = '"%s" is not valid according to its domain.',
    this.children = 'The values of "%s" are not valid.',
  });
}

/// A record of a [RecordGroup] (SAO `Sao.Record`, spec 5.4).
///
/// A negative [id] marks a new record (global counter −1, −2, …).
class Record {
  /// Next id for new records (SAO `Sao.Record.prototype.id_counter`).
  static int _idCounter = -1;

  final TrytonModel model;
  late RecordGroup group;
  int id;

  /// Field values; x2many fields hold a [RecordGroup], many2one/reference
  /// additionally `<f>.` (`{rec_name, …}`), selections `<f>:string`.
  final Map<String, dynamic> _values = {};

  /// Fields loaded from the server (or set by [set]).
  final Set<String> _loaded = {};

  /// Locally modified fields (`id` when added/removed in a group).
  final Set<String> modifiedFields = {};

  /// `_timestamp` from the server, sent back unchanged.
  String? timestamp;

  /// Rights of this record from the server (`_write`, `_delete`).
  bool canWrite = true;
  bool canDelete = true;

  /// Evaluated field states (`get_state_attrs`).
  final Map<String, Map<String, dynamic>> stateAttrs = {};
  Map<String, dynamic>? resources;
  final Map<String, dynamic> buttonClicks = {};
  final Map<String, dynamic> linksCounts = {};
  final Map<String, List<dynamic>> autocompletion = {};

  /// Loading failed → readonly.
  bool exception = false;
  bool destroyed = false;

  /// on_change chain of this record: tasks run one after another (the
  /// order SAO guarantees with synchronous calls).
  Future<void> _queue = Future.value();

  /// Running save (parallel saves are serialised).
  Future<void> _saving = Future.value();

  Record(this.model, {int? id, RecordGroup? group})
      : id = id ?? _idCounter {
    if (this.id < 0) _idCounter--;
    this.group = group ?? RecordGroup(model);
  }

  /// Read-only view of the values (for tests/debugging).
  Map<String, dynamic> get values => UnmodifiableMapView(_values);

  Set<String> get loaded => UnmodifiableSetView(_loaded);

  bool get modified => modifiedFields.isNotEmpty;

  bool get deleted => group.recordDeleted.contains(this);
  bool get removed => group.recordRemoved.contains(this);

  bool get readonly =>
      deleted || removed || exception || group.readonly || !canWrite;

  bool get deletable => canDelete;

  bool isLoaded(String name) => id < 0 || _loaded.contains(name);

  /// True when all [fields] (default: all) are loaded or modified.
  bool getLoaded([Iterable<String>? fields]) {
    if (id < 0) return true;
    final names = fields ?? model.fields.keys;
    return names.every((n) => _loaded.contains(n) || modifiedFields.contains(n));
  }

  /// Runs [task] after all queued tasks of this record.
  Future<T> _enqueue<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Completes when all queued on_change tasks have finished.
  Future<void> get idle => _queue;

  // ── Setting / getting ─────────────────────────────────────────────────────

  /// Takes server values (SAO `set`): keeps the oldest `_timestamp`, sets
  /// One2Many fields last and marks the fields as loaded.
  void set(Map<String, dynamic> values,
      {bool modified = true, bool validate = true}) {
    final later = <String, dynamic>{};
    final fieldNames = <String>[];
    for (final MapEntry(key: name, value: value) in values.entries) {
      if (name == '_timestamp') {
        // Always keep the older timestamp
        timestamp ??= value?.toString();
        continue;
      }
      if (name == '_write') {
        canWrite = value != false;
        continue;
      }
      if (name == '_delete') {
        canDelete = value != false;
        continue;
      }
      final field = model.fields[name];
      if (field == null) {
        if (name == 'rec_name') _values[name] = value;
        continue;
      }
      if (field is One2ManyField) {
        later[name] = value;
        continue;
      }
      if (field is Many2OneField || field is ReferenceField) {
        _values['$name.'] = _related(values['$name.']);
      } else if (field is SelectionField) {
        if (values.containsKey('$name:string')) {
          _values['$name:string'] = values['$name:string'];
        } else {
          _values.remove('$name:string');
        }
      }
      field.set(this, value);
      _loaded.add(name);
      fieldNames.add(name);
    }
    for (final MapEntry(key: name, value: value) in later.entries) {
      (model.fields[name] as One2ManyField)
          .set(this, value, data: values['$name.']);
      _loaded.add(name);
      fieldNames.add(name);
    }
    if (validate) this.validate(fields: fieldNames, softValidation: true);
    if (modified) setModified();
  }

  static Map<String, dynamic> _related(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : <String, dynamic>{};

  /// Values for `create`/`write`: only modified fields (all for a new
  /// record), no readonly fields except One2Many, no empty x2many
  /// commands.
  Map<String, dynamic> get() {
    final value = <String, dynamic>{};
    for (final MapEntry(key: name, value: field) in model.fields.entries) {
      if (field.description['readonly'] == true &&
          !(field is One2ManyField && field is! Many2ManyField)) {
        continue;
      }
      if (!modifiedFields.contains(name) && id >= 0) continue;
      final v = field.get(this);
      // Sending an empty x2MField breaks ModelFieldAccess.check
      if (field is One2ManyField && (v as List).isEmpty) continue;
      value[name] = v;
    }
    return value;
  }

  /// Values for PYSON (many2one id, x2many id list, reference
  /// `"model,id"`); `id` always included.
  Map<String, dynamic> getEval() {
    final value = <String, dynamic>{};
    for (final MapEntry(key: name, value: field) in model.fields.entries) {
      if (!_loaded.contains(name) && id >= 0) continue;
      value[name] = field.getEval(this);
    }
    value['id'] = id;
    return value;
  }

  /// Values for on_change calls (saved records: only loaded and modified
  /// fields).
  Map<String, dynamic> getOnChangeValue({Iterable<String>? skip}) {
    final value = <String, dynamic>{};
    for (final MapEntry(key: name, value: field) in model.fields.entries) {
      if (skip != null && skip.contains(name)) continue;
      if (id >= 0 &&
          (!_loaded.contains(name) || !modifiedFields.contains(name))) {
        continue;
      }
      value[name] = field.getOnChangeValue(this);
    }
    value['id'] = id;
    return value;
  }

  /// Values of the on_change dependencies [args] (paths like
  /// `_parent_party.name`); a path that does not exist is left out
  /// (Python `_get_on_change_args`).
  Map<String, dynamic> getOnChangeArgs(Iterable<String> args) {
    final values = evalEnvironment(this, onChange: true);
    final result = <String, dynamic>{};
    for (final arg in args) {
      dynamic scope = values;
      var found = true;
      for (final part in arg.split('.')) {
        if (scope is Map && scope.containsKey(part)) {
          scope = scope[part];
        } else {
          found = false;
          break;
        }
      }
      if (found) result[arg] = scope;
    }
    return result;
  }

  Map<String, dynamic> getContext({bool local = false}) =>
      local ? group.localContext : group.context;

  dynamic fieldGet(String name) => model.fields[name]!.get(this);
  void fieldSet(String name, dynamic value) =>
      model.fields[name]!.set(this, value);
  dynamic fieldGetClient(String name) => model.fields[name]!.getClient(this);

  /// Sets a value from the user; the returned future completes after the
  /// on_change chain (errors are reported there).
  Future<void> fieldSetClient(String name, dynamic value,
          {bool forceChange = false}) =>
      model.fields[name]!.setClient(this, value, forceChange: forceChange);

  /// Sets default values, then on_change/on_change_with for them (SAO
  /// `set_default`).
  Future<void> setDefault(Map<String, dynamic> values,
      {bool validate = true, bool modified = true}) async {
    final fieldNames = <String>[];
    for (final MapEntry(key: name, value: value) in values.entries) {
      if (name == '_write') {
        canWrite = value != false;
        continue;
      }
      if (name == '_delete') {
        canDelete = value != false;
        continue;
      }
      if (name == '_timestamp') {
        timestamp = value?.toString();
        continue;
      }
      final field = model.fields[name];
      if (field == null || name == group.excludeField) continue;
      if (field is Many2OneField || field is ReferenceField) {
        _values['$name.'] = _related(values['$name.']);
      }
      await field.setDefault(this, value);
      _loaded.add(name);
      fieldNames.add(name);
    }
    await onChange(fieldNames);
    await onChangeWith(fieldNames);
    if (validate) this.validate(softValidation: true);
    if (modified) setModified();
  }

  /// Applies the result of on_change/on_change_with (SAO `set_on_change`):
  /// sets the values and marks them modified without a new on_change.
  Future<void> setOnChange(Map<String, dynamic> values) async {
    for (final MapEntry(key: name, value: value) in values.entries) {
      final field = model.fields[name];
      if (field == null) continue;
      if (field is Many2OneField || field is ReferenceField) {
        _values['$name.'] = _related(values['$name.']);
      }
      // Load the field before setting the value
      await load(name);
      await field.setOnChange(this, value);
    }
  }

  /// `{"model,id": timestamp}` of this record and of the modified, removed
  /// and deleted records of its loaded x2many fields.
  Map<String, String?> getTimestamp() {
    final timestamps = <String, String?>{'${model.name},$id': timestamp};
    for (final MapEntry(key: name, value: field) in model.fields.entries) {
      if (!_loaded.contains(name)) continue;
      timestamps.addAll(field.getTimestamp(this));
    }
    return timestamps;
  }

  /// Evaluates a PYSON expression (string as from the server, or an already
  /// decoded value) with `get_eval()` + `context`, `active_model`,
  /// `active_id` and `_parent_<parent_name>`.
  dynamic exprEval(dynamic expr) {
    if (expr is String) {
      if (expr.isEmpty) return null;
      if (expr == '[]') return <dynamic>[];
      if (expr == '{}') return <String, dynamic>{};
      expr = jsonDecode(expr);
    } else if (expr is! List && expr is! Map) {
      return expr;
    }
    final ctx = getEval()
      ..['context'] = getContext()
      ..['active_model'] = model.name
      ..['active_id'] = id;
    final parent = group.parent;
    if (parent != null && group.parentName.isNotEmpty) {
      ctx['_parent_${group.parentName}'] = evalEnvironment(parent);
    }
    return PYSONEvaluator(ctx).eval(expr);
  }

  /// Discards all local values and flags (SAO `cancel`).
  void cancel() {
    _loaded.clear();
    _values.clear();
    modifiedFields.clear();
    timestamp = null;
    buttonClicks.clear();
    linksCounts.clear();
    exception = false;
  }

  /// cancel + set, then the parent's on_change (SAO `reset`).
  Future<void> reset(Map<String, dynamic> value) async {
    cancel();
    set(value);
    final parent = group.parent;
    if (parent != null) {
      await parent.onChange([group.childName]);
      await parent.onChangeWith([group.childName]);
    }
  }

  Record get rootParent {
    var parent = this;
    while (parent.group.parent != null) {
      parent = parent.group.parent!;
    }
    return parent;
  }

  /// `[(child_name, id), …]` from [group] (or the root) to this record.
  List<(String, int)> getPath([RecordGroup? group]) {
    final path = <(String, int)>[];
    Record? r = this;
    var childName = '';
    while (r != null) {
      path.add((childName, r.id));
      if (identical(r.group, group)) break;
      childName = r.group.childName;
      r = r.group.parent;
    }
    return path.reversed.toList();
  }

  List<int> getIndexPath([RecordGroup? group]) {
    final path = <int>[];
    Record? r = this;
    while (r != null) {
      path.add(r.group.indexOf(r));
      if (identical(r.group, group)) break;
      r = r.group.parent;
    }
    return path.reversed.toList();
  }

  /// The x2many group of [fieldName] prepared for a tree of the same
  /// model (SAO `children_group`).
  RecordGroup? childrenGroup(String fieldName) {
    final value = _values[fieldName];
    if (value is! RecordGroup) return null;
    if (!identical(value.model.fields, group.model.fields)) {
      group.model.fields.addAll(value.model.fields);
    }
    value.onWrite = group.onWrite;
    value.readonly = group.readonly;
    value._context.addAll(group._context);
    return value;
  }

  /// Sets the context of x2many groups from the field `context` attribute.
  void setFieldContext() {
    for (final MapEntry(key: name, value: field) in model.fields.entries) {
      final value = _values[name];
      final context = field.description['context'];
      if (value is RecordGroup && context != null) {
        final evaluated = exprEval(context);
        if (evaluated is Map) value.context = evaluated.cast<String, dynamic>();
      }
    }
  }

  void setModified([String? field]) {
    if (field != null) modifiedFields.add(field);
    group.recordModified();
  }

  void destroy() {
    for (final value in _values.values) {
      if (value is RecordGroup) value.destroy();
    }
    destroyed = true;
  }

  // ── Loading (5.4.2) ───────────────────────────────────────────────────────

  /// Loads [name] (`'*'` = all fields) with `read` (SAO `load`):
  ///
  /// * eager fields: all eager fields of the field's views, plus neighbour
  ///   records of the group (up to `limit / min(fields, 10)`);
  /// * lazy fields: all fields of the views, this record only, x2many with
  ///   sub-view fields pre-loaded (`<f>.<sub>`, `related_read_limit`);
  /// * extra fields `<f>.rec_name`, `<f>:string`, `rec_name`,
  ///   `_timestamp`, `_write`, `_delete`; binary fields as size only.
  ///
  /// Locally modified fields are not overwritten. On error the records
  /// get null values and `exception = true`, and the error is rethrown.
  Future<void> load(String name, {bool processException = true}) async {
    if (destroyed || isLoaded(name)) return;
    final pending = group._loading;
    if (pending != null) {
      await pending.catchError((Object _) {});
      if (destroyed || isLoaded(name)) return;
    }
    final future = _load(name, processException);
    group._loading = future;
    try {
      await future;
    } finally {
      if (identical(group._loading, future)) group._loading = null;
    }
  }

  Future<void> _load(String name, bool processException) async {
    final id2record = <int, Record>{id: this};
    String loading;
    Set<Object> views;
    var checkName = name;
    if (name == '*') {
      loading = 'eager';
      views = {};
      for (final field in model.fields.values) {
        if (field.loading == 'lazy') loading = 'lazy';
        views.addAll(field.views);
      }
      // A valid name for the "already loaded" check of the neighbours
      checkName = model.fields.entries
          .firstWhere((e) => e.value.loading == loading,
              orElse: () => model.fields.entries.first)
          .key;
    } else {
      final field = model.fields[name]!;
      loading = field.loading;
      views = field.views;
    }

    final fields = loading == 'eager'
        ? model.fields.entries.where((e) => e.value.loading == 'eager')
        : model.fields.entries;
    final fnames = <String>[
      for (final MapEntry(key: fname, value: field) in fields)
        if (!_loaded.contains(fname) &&
            (views.isEmpty ||
                (loading == 'eager'
                    ? views.every(field.views.contains)
                    : field.views.any(views.contains))))
          fname,
    ];
    final toFetch = [...fnames];
    var relatedRead = false;
    for (final fname in fnames) {
      final desc = model.fields[fname]!.description;
      final type = desc['type'];
      if (type == 'many2one' || type == 'one2one' || type == 'reference') {
        toFetch.add('$fname.rec_name');
      } else if ((type == 'selection' || type == 'multiselection') &&
          (desc['loading'] ?? 'lazy') == 'eager') {
        toFetch.add('$fname:string');
      } else if ((type == 'one2many' || type == 'many2many') &&
          loading == 'lazy') {
        final sub = _x2mSubFields(desc, fname);
        toFetch.addAll(sub);
        if (sub.isNotEmpty) relatedRead = true;
      }
    }
    if (!fnames.contains('rec_name')) toFetch.add('rec_name');
    toFetch.addAll(['_timestamp', '_write', '_delete']);

    final context = <String, dynamic>{...getContext()};
    if (relatedRead) context['related_read_limit'] = model.session.displaySize;

    if (loading == 'eager') {
      final limit =
          model.session.limit ~/ math.min(toFetch.length, 10);
      bool filterGroup(Record r) =>
          !r.destroyed && r.id >= 0 && !r._loaded.contains(checkName);
      final List<Record> neighbours;
      bool Function(Record) filter;
      final parent = group.parent;
      if (parent != null && parent.model.name == model.name) {
        neighbours = [for (final g in parent.group.children) ...g];
        final ctxJson = jsonEncode(TrytonSerializer.encode(context));
        filter = (r) =>
            filterGroup(r) &&
            !id2record.containsKey(r.id) &&
            (identical(r.group, group) ||
                jsonEncode(TrytonSerializer.encode(r.getContext())) ==
                    ctxJson);
      } else {
        neighbours = group.toList();
        filter = filterGroup;
      }
      final idx = neighbours.indexOf(this);
      if (idx >= 0) {
        final length = neighbours.length;
        var n = 1;
        while (id2record.length < limit &&
            (idx - n >= 0 || idx + n < length) &&
            n < 2 * limit) {
          if (idx - n >= 0 && filter(neighbours[idx - n])) {
            id2record[neighbours[idx - n].id] = neighbours[idx - n];
          }
          if (idx + n < length && filter(neighbours[idx + n])) {
            id2record[neighbours[idx + n].id] = neighbours[idx + n];
          }
          n++;
        }
      }
    }

    for (final MapEntry(key: fname, value: field) in model.fields.entries) {
      if (field is BinaryField && toFetch.contains(fname)) {
        context['${model.name}.$fname'] = 'size';
      }
    }

    final ids = id2record.keys.toList();
    final values = <Map<String, dynamic>>[];
    try {
      // ID lists in batches of 1000
      for (var i = 0; i < ids.length; i += 1000) {
        final batch = ids.sublist(i, math.min(i + 1000, ids.length));
        final result = await model.execute('read', [batch, toFetch],
            context: context, processException: processException);
        for (final v in result as List) {
          values.add(Map<String, dynamic>.from(v as Map));
        }
      }
    } catch (_) {
      for (final record in id2record.values) {
        record.exception = true;
        if (!record.destroyed) {
          record.set({
            for (final f in toFetch)
              if (f != 'id') f: null,
          }, modified: false, validate: false);
        }
      }
      rethrow;
    }
    final id2value = {for (final v in values) v['id']: v};
    for (final MapEntry(key: rid, value: record) in id2record.entries) {
      final value = id2value[rid];
      if (record.destroyed || value == null) continue;
      // Locally modified fields keep their value
      for (final key in record.modifiedFields) {
        value.remove(key);
        value.remove('$key.');
        value.remove('$key:string');
      }
      record.set(value, modified: false);
    }
  }

  /// `<f>.<sub>` fields of the x2many sub-views (Python
  /// `get_x2m_sub_fields`).
  static List<String> _x2mSubFields(Map<String, dynamic> desc, String prefix) {
    final views = desc['views'];
    if (desc['visible'] != true || views is! Map || views.isEmpty) return [];
    final subFields = <String, dynamic>{};
    for (final view in views.values) {
      final f = view is Map ? view['fields'] : null;
      if (f is Map) subFields.addAll(f.cast<String, dynamic>());
    }
    final result = <String>[];
    for (final MapEntry(key: name, value: def) in subFields.entries) {
      final type = (def as Map)['type'];
      result.add('$prefix.$name');
      if (type == 'many2one' || type == 'one2one' || type == 'reference') {
        result.add('$prefix.$name.rec_name');
      } else if (type == 'selection' || type == 'multiselection') {
        result.add('$prefix.$name:string');
      } else if (type == 'one2many' || type == 'many2many') {
        result.addAll(
            _x2mSubFields(def.cast<String, dynamic>(), '$prefix.$name'));
      }
    }
    result.addAll(
        ['$prefix._timestamp', '$prefix._write', '$prefix._delete']);
    return result;
  }

  /// Reloads [fields] (default: all).
  Future<void> reload([List<String>? fields]) async {
    if (id < 0) return;
    if (fields == null || fields.isEmpty) return load('*');
    for (final f in fields) {
      await load(f);
    }
  }

  // ── Saving (5.4.4) ───────────────────────────────────────────────────────

  /// Saves the record (SAO/Python `save`): `create` for a new record,
  /// `write` with `_timestamp` (from [getTimestamp], incl. children) for a
  /// modified one; then cancel, reload and on_write. A record of a child
  /// group is saved through its parent (x2many commands). Parallel saves
  /// are serialised. Returns false when the user cancelled a conflict.
  Future<bool> save({bool forceReload = true}) {
    final result = _saving.then((_) => _save(forceReload));
    _saving = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<bool> _save(bool forceReload) async {
    final parent = group.parent;
    if (parent != null) return parent.save(forceReload: forceReload);
    await idle; // pending on_change results belong to the saved values
    if (id >= 0 && !modified) return true;
    final values = get();
    if (id < 0) {
      final ids = await model.execute('create', [
        [values]
      ], context: getContext());
      id = (ids as List).first as int;
    } else if (values.isNotEmpty) {
      Future<void> write(bool withTimestamp) =>
          model.execute('write', [
            [id],
            values
          ], context: {
            ...getContext(),
            if (withTimestamp) '_timestamp': getTimestamp(),
          });
      final runner = model.session.concurrencyRunner;
      if (runner == null) {
        await write(true);
      } else if (!await runner(model.name, [id], write)) {
        return false;
      }
    }
    cancel();
    if (forceReload) await reload();
    await group.written([id]);
    return true;
  }

  // ── default_get (5.4.6) ──────────────────────────────────────────────────

  /// `default_get` of all fields; [defaults] go to the context as
  /// `default_<field>`. In a child group the parent field points to the
  /// parent. Then on_change/on_change_with of the set fields.
  Future<Map<String, dynamic>> defaultGet(
      [Map<String, dynamic>? defaults]) async {
    if (model.fields.isEmpty) return {};
    final context = getContext();
    defaults?.forEach((name, value) {
      context.putIfAbsent('default_$name', () => value);
    });
    final result = await model.execute(
        'default_get', [model.fields.keys.toList()],
        context: context);
    final values = Map<String, dynamic>.from(result as Map? ?? const {});
    final parent = group.parent;
    final parentField = model.fields[group.parentName];
    if (parent != null && parentField != null) {
      if (parentField is ReferenceField) {
        values[group.parentName] = [parent.model.name, parent.id];
      } else if (parentField.description['relation'] == parent.model.name) {
        values[group.parentName] = parent.id;
      }
    }
    await setDefault(values);
    return values;
  }

  // ── on_change chain (5.4.5) ──────────────────────────────────────────────

  /// `on_change_<field>` (one field) or `on_change` (several) with the
  /// declared dependencies, then `on_change_notify`.
  Future<void> onChange(List<String> fieldNames) async {
    final values = <String, dynamic>{};
    for (final name in fieldNames) {
      final onChange = model.fields[name]?.description['on_change'];
      if (onChange is List && onChange.isNotEmpty) {
        values.addAll(getOnChangeArgs(onChange.cast<String>()));
      }
    }
    final modified = {...fieldNames};
    if (values.isNotEmpty) {
      values['id'] = id;
      final changes = <dynamic>[];
      if (fieldNames.length == 1) {
        for (final name in fieldNames) {
          changes.add(await model.execute('on_change_$name', [values],
              context: getContext()));
        }
      } else {
        changes.add(await model.execute('on_change', [values, fieldNames],
            context: getContext()));
      }
      for (final change in changes) {
        if (change is! Map) continue;
        await setOnChange(change.cast<String, dynamic>());
        modified.addAll(change.keys.cast<String>());
      }
    }
    await _notify(modified);
  }

  /// on_change_with for all fields depending on [fieldNames]; fields whose
  /// dependencies are computed in the same round come in a second round
  /// ("later").
  Future<void> onChangeWith(List<String> fieldNames) async {
    final changedNames = {...fieldNames};
    final names = <String>{};
    final later = <String>{};
    var values = <String, dynamic>{};
    for (final MapEntry(key: name, value: field) in model.fields.entries) {
      final deps = _onChangeWith(field);
      if (deps.isEmpty || !deps.any(changedNames.contains)) continue;
      if (deps.any(names.contains)) {
        later.add(name);
        continue;
      }
      names.add(name);
      values.addAll(getOnChangeArgs([...deps, name]));
      if (field is Many2OneField || field is ReferenceField) {
        _values.remove('$name.');
      }
    }
    if (names.isNotEmpty) {
      await setOnChange(await _callOnChangeWith(names, values));
    }
    if (later.isNotEmpty) {
      values = {};
      for (final name in later) {
        values.addAll(
            getOnChangeArgs([..._onChangeWith(model.fields[name]!), name]));
      }
      await setOnChange(await _callOnChangeWith(later, values));
    }
    await _notify(changedNames);
  }

  static List<String> _onChangeWith(Field field) {
    final deps = field.description['on_change_with'];
    return deps is List ? deps.cast<String>() : const [];
  }

  Future<Map<String, dynamic>> _callOnChangeWith(
      Set<String> names, Map<String, dynamic> values) async {
    final changed = <String, dynamic>{};
    if (names.length == 1 || !values.containsKey('id')) {
      for (final name in names) {
        final result = await model.execute('on_change_with_$name', [values],
            context: getContext());
        if (result is Map) changed.addAll(result.cast<String, dynamic>());
      }
    } else {
      values['id'] = id;
      final result = await model.execute(
          'on_change_with', [values, names.toList()],
          context: getContext());
      if (result is Map) changed.addAll(result.cast<String, dynamic>());
    }
    return changed;
  }

  /// `on_change_notify` when one of [fieldNames] is a notification field;
  /// the messages go to [RecordGroup.recordNotify].
  Future<void> _notify(Set<String> fieldNames) async {
    final fields = await model.session.notificationFieldsOf(model.name);
    if (!fields.any(fieldNames.contains)) return;
    final values = getOnChangeArgs(fields);
    final notifications = await model.execute('on_change_notify', [values],
        context: getContext());
    group.recordNotify(notifications is List ? notifications : const []);
  }

  /// `autocomplete_<field>` for the fields whose `autocomplete` contains
  /// [fieldName] (without error dialog; errors give no suggestions).
  Future<void> autocompleteWith(String fieldName) async {
    for (final MapEntry(key: name, value: field) in model.fields.entries) {
      final autocomplete = field.description['autocomplete'];
      if (autocomplete is List && autocomplete.contains(fieldName)) {
        await doAutocomplete(name);
      }
    }
  }

  Future<void> doAutocomplete(String fieldName) async {
    autocompletion[fieldName] = [];
    final deps = (model.fields[fieldName]!.description['autocomplete'] as List)
        .cast<String>();
    try {
      final result = await model.execute(
          'autocomplete_$fieldName', [getOnChangeArgs(deps)],
          context: getContext(), processException: false);
      autocompletion[fieldName] = result is List ? result : [];
    } catch (_) {
      autocompletion[fieldName] = [];
    }
  }

  /// `on_scan_code(values, code)`; true when something changed.
  Future<bool> onScanCode(String code, dynamic depends) async {
    final deps = exprEval(depends);
    final values = getOnChangeArgs(deps is List ? deps.cast<String>() : []);
    values['id'] = id;
    final changes = await model.execute('on_scan_code', [values, code],
        context: getContext(), processException: false);
    if (changes is! Map) return false;
    await setOnChange(changes.cast<String, dynamic>());
    setModified();
    return changes.isNotEmpty;
  }

  // ── Validation (5.5) ─────────────────────────────────────────────────────

  /// Validates the loaded, not readonly fields (except `exclude_field` and
  /// the parent field): states, required (not with [softValidation]),
  /// domain incl. setting unique values, children, dict keys.
  bool validate(
      {Iterable<String>? fields,
      bool softValidation = false,
      List<dynamic>? preValidate}) {
    var result = true;
    for (final MapEntry(key: name, value: field) in model.fields.entries) {
      if (fields != null && !fields.contains(name)) continue;
      if (!getLoaded([name])) continue;
      if (field.description['readonly'] == true) continue;
      if (name == group.excludeField || name == group.parentName) continue;
      field.setState(this);
      if (!field.validate(this,
          softValidation: softValidation, preValidate: preValidate)) {
        result = false;
      }
    }
    return result;
  }

  /// `{field: invalid}` (`'required'`, `'domain'`, `'children'` or the
  /// violated domain).
  Map<String, dynamic> invalidFields() => {
        for (final MapEntry(key: name, value: field) in model.fields.entries)
          if (field.stateAttrs(this)['invalid'] case final invalid?
              when invalid != false)
            name: invalid,
      };

  /// Message for the invalid fields (max. 5 lines + `…`), SAO
  /// `invalid_message`. Domains are shown with the generic domain text
  /// until the DomainParser (C4) can render them.
  String invalidMessage([InvalidMessages texts = const InvalidMessages()]) {
    final invalid = invalidFields();
    final lines = <String>[];
    for (final name in invalid.keys.toList()..sort()) {
      final value = invalid[name];
      final label = '${model.fields[name]!.description['string'] ?? name}';
      final String text;
      if (value == 'required' ||
          domainEquals(value, [
            [name, '!=', null]
          ])) {
        text = texts.required;
      } else if (value == 'children') {
        text = texts.children;
      } else {
        text = texts.domain;
      }
      lines.add(text.replaceAll('%s', label));
    }
    if (lines.length > 5) {
      lines
        ..removeRange(5, lines.length)
        ..add('...');
    }
    return lines.join('\n');
  }

  // ── Further server calls (5.4.6) ─────────────────────────────────────────

  /// `pre_validate(values)` with the modified fields and `id`.
  Future<void> preValidate() async {
    if (modifiedFields.isEmpty) return;
    final values = getOnChangeArgs([...modifiedFields, 'id']);
    await model.execute('pre_validate', [values], context: getContext());
  }

  /// `read([id], ['rec_name'])`.
  Future<String> recName() async {
    final result = await model.execute('read', [
      [id],
      ['rec_name']
    ], context: getContext());
    return '${(result as List).first['rec_name'] ?? ''}';
  }

  /// `resources(id)` → `{attachment_count, note_count, note_unread}`,
  /// cached; without error dialog (counters).
  Future<Map<String, dynamic>?> getResources({bool reload = false}) async {
    if (id >= 0 && (resources == null || reload)) {
      final result = await model.execute('resources', [id],
          context: getContext(), processException: false);
      resources = result is Map ? result.cast<String, dynamic>() : null;
    }
    return resources;
  }

  /// `ir.model.button.click.get_click(model, button, id)`, cached.
  Future<dynamic> getButtonClicks(String name) async {
    if (id < 0) return null;
    if (buttonClicks.containsKey(name)) return buttonClicks[name];
    final rpc = model.session.rpc;
    if (rpc == null) throw NoModelRpc('ir.model.button.click.get_click');
    final clicks = await rpc.execute('ir.model.button.click', 'get_click',
        [model.name, name, id],
        context: model.sessionContext());
    buttonClicks[name] = clicks;
    return clicks;
  }

  @override
  String toString() => 'Record(${model.name}, $id)';
}

/// PYSON environment of a record as `_parent_<field>` target (SAO
/// `Sao.common.EvalEnvironment`): `get_eval()` (or, with [onChange], the
/// on_change values of all fields) plus `id`, nested `_parent_` for the
/// record's own parent.
Map<String, dynamic> evalEnvironment(Record record, {bool onChange = false}) {
  final Map<String, dynamic> values;
  if (onChange) {
    values = {
      for (final MapEntry(key: name, value: field)
          in record.model.fields.entries)
        name: field.getOnChangeValue(record),
    };
  } else {
    values = record.getEval();
  }
  final parent = record.group.parent;
  final parentName = record.group.parentName;
  return parentEnvironment(
    values: values,
    id: record.id,
    parentName: parent != null && parentName.isNotEmpty ? parentName : null,
    parent: parent != null && parentName.isNotEmpty
        ? evalEnvironment(parent, onChange: onChange)
        : null,
  );
}
