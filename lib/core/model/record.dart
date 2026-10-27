part of 'model.dart';

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
  /// `_parent_party.name`), SAO `_get_on_change_args`.
  Map<String, dynamic> getOnChangeArgs(Iterable<String> args) {
    final values = evalEnvironment(this, onChange: true);
    return {
      for (final arg in args)
        arg: arg.split('.').fold<dynamic>(
            values, (scope, e) => scope is Map ? scope[e] : null),
    };
  }

  Map<String, dynamic> getContext({bool local = false}) =>
      local ? group.localContext : group.context;

  dynamic fieldGet(String name) => model.fields[name]!.get(this);
  void fieldSet(String name, dynamic value) =>
      model.fields[name]!.set(this, value);
  dynamic fieldGetClient(String name) => model.fields[name]!.getClient(this);
  void fieldSetClient(String name, dynamic value, {bool forceChange = false}) =>
      model.fields[name]!.setClient(this, value, forceChange: forceChange);

  /// Sets default values (SAO `set_default`, local part).
  void setDefault(Map<String, dynamic> values,
      {bool validate = true, bool modified = true}) {
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
      field.setDefault(this, value);
      _loaded.add(name);
      fieldNames.add(name);
    }
    onChange(fieldNames);
    onChangeWith(fieldNames);
    if (validate) this.validate(softValidation: true);
    if (modified) setModified();
  }

  /// Applies the result of on_change/on_change_with (SAO `set_on_change`).
  void setOnChange(Map<String, dynamic> values) {
    for (final MapEntry(key: name, value: value) in values.entries) {
      final field = model.fields[name];
      if (field == null) continue;
      if (field is Many2OneField || field is ReferenceField) {
        _values['$name.'] = _related(values['$name.']);
      }
      field.setOnChange(this, value);
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
  void reset(Map<String, dynamic> value) {
    cancel();
    set(value);
    final parent = group.parent;
    if (parent != null) {
      parent.onChange([group.childName]);
      parent.onChangeWith([group.childName]);
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

  // ── Validation (D8) ──────────────────────────────────────────────────────

  /// STUB(D8): field validation (5.5) is not implemented yet; always valid.
  bool validate(
          {Iterable<String>? fields,
          bool softValidation = false,
          List<dynamic>? preValidate}) =>
      true;

  // ── Server calls: STUB(D1 part 2) ────────────────────────────────────────

  /// STUB(D1 part 2): `read` of the missing fields (5.4.2).
  Future<void> load(String name) async {
    if (destroyed || isLoaded(name)) return;
    throw NotYetImplemented('Record.load');
  }

  /// STUB(D1 part 2): `read` of [fields] (or all).
  Future<void> reload([List<String>? fields]) async {
    if (id < 0) return;
    throw NotYetImplemented('Record.reload');
  }

  /// STUB(D1 part 2): `create`/`write` (5.4.4).
  Future<void> save({bool forceReload = true}) async =>
      throw NotYetImplemented('Record.save');

  /// STUB(D1 part 2): `default_get` (5.4.6).
  Future<Map<String, dynamic>> defaultGet([Map<String, dynamic>? defaults]) async =>
      throw NotYetImplemented('Record.defaultGet');

  /// STUB(D1 part 2): on_change (5.4.5). Called by [Field.changed]; does
  /// nothing until the server connection exists.
  void onChange(List<String> fieldNames) {}

  /// STUB(D1 part 2): on_change_with (5.4.5); does nothing yet.
  void onChangeWith(List<String> fieldNames) {}

  /// STUB(D1 part 2): autocomplete (5.4.5); does nothing yet.
  void autocompleteWith(String fieldName) {}

  /// STUB(D1 part 2): `pre_validate` (5.4.6).
  Future<void> preValidate() async => throw NotYetImplemented('Record.preValidate');

  /// STUB(D1 part 2): `on_scan_code` (5.4.6).
  Future<bool> onScanCode(String code, dynamic depends) async =>
      throw NotYetImplemented('Record.onScanCode');

  /// STUB(D1 part 2): `read([id], ['rec_name'])`.
  Future<String> recName() async => throw NotYetImplemented('Record.recName');

  /// STUB(D1 part 2): `resources(id)` (5.4.6).
  Future<Map<String, dynamic>?> getResources({bool reload = false}) async =>
      throw NotYetImplemented('Record.getResources');

  /// STUB(D1 part 2): `ir.model.button.click.get_click` (5.4.6).
  Future<dynamic> getButtonClicks(String name) async =>
      throw NotYetImplemented('Record.getButtonClicks');

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
