part of 'model.dart';

/// Value equality for change detection (SAO `_has_changed` compares JSON,
/// Python `!=`): lists and maps deep, numbers/Decimals numerically.
bool _valuesEqual(dynamic a, dynamic b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_valuesEqual(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_valuesEqual(a[i], b[i])) return false;
    }
    return true;
  }
  return domainEquals(a, b);
}

/// Base field (SAO `Sao.field.Field`). [description] is the field
/// description from `fields_get` / `fields_view_get` (spec 5.2).
class Field {
  final Map<String, dynamic> description;

  Field(this.description);

  /// Field class for [description]`['type']` (SAO `Sao.field.get`).
  factory Field.create(Map<String, dynamic> description) {
    return switch (description['type']) {
      'char' => CharField(description),
      'text' => TextField(description),
      'selection' => SelectionField(description),
      'multiselection' => MultiSelectionField(description),
      'datetime' || 'timestamp' => DateTimeField(description),
      'date' => DateField(description),
      'time' => TimeField(description),
      'timedelta' => TimeDeltaField(description),
      'float' => FloatField(description),
      'numeric' => NumericField(description),
      'integer' => IntegerField(description),
      'boolean' => BooleanField(description),
      'many2one' => Many2OneField(description),
      'one2one' => One2OneField(description),
      'one2many' => One2ManyField(description),
      'many2many' => Many2ManyField(description),
      'reference' => ReferenceField(description),
      'binary' => BinaryField(description),
      'dict' => DictField(description),
      _ => CharField(description),
    };
  }

  String get name => description['name'] as String;

  /// Value of an unset field (SAO `_default`).
  dynamic get defaultValue => null;

  /// `in [v]` counts as a single value in `unique_value`.
  bool get singleValue => true;

  void set(Record record, dynamic value) => record._values[name] = value;

  dynamic get(Record record) => record._values.containsKey(name)
      ? record._values[name]
      : defaultValue;

  bool hasChanged(dynamic previous, dynamic value) =>
      !_valuesEqual(previous, value);

  /// Sets a value from the user: on a change on_change etc. are triggered
  /// and the field is marked modified.
  void setClient(Record record, dynamic value, {bool forceChange = false}) {
    final previous = get(record);
    set(record, value);
    if (hasChanged(previous, get(record))) {
      changed(record);
      record.validate(softValidation: true);
      record.setModified(name);
    } else if (forceChange) {
      changed(record);
      record.validate(softValidation: true);
      record.setModified();
    }
  }

  dynamic getClient(Record record) => get(record);

  void setDefault(Record record, dynamic value) {
    set(record, value);
    record.modifiedFields.add(name);
  }

  void setOnChange(Record record, dynamic value) {
    set(record, value);
    record.modifiedFields.add(name);
  }

  /// After a change: on_change, on_change_with, autocomplete (server,
  /// STUB(D1 part 2)) and the x2many field contexts.
  void changed(Record record) {
    record.onChange([name]);
    record.onChangeWith([name]);
    record.autocompleteWith(name);
    record.setFieldContext();
  }

  Map<String, String?> getTimestamp(Record record) => {};

  /// Record context ⊕ evaluated field `context`.
  Map<String, dynamic> getContext(Record record,
      {Map<String, dynamic>? recordContext, bool local = false}) {
    final context = <String, dynamic>{
      ...(recordContext ?? record.getContext(local: local)),
    };
    final evaluated = record.exprEval(description['context'] ?? const {});
    if (evaluated is Map) context.addAll(evaluated.cast<String, dynamic>());
    return context;
  }

  Map<String, dynamic> getSearchContext(Record record) {
    final context = getContext(record);
    final evaluated =
        record.exprEval(description['search_context'] ?? const {});
    if (evaluated is Map) context.addAll(evaluated.cast<String, dynamic>());
    return context;
  }

  dynamic getSearchOrder(Record record) =>
      record.exprEval(description['search_order']);

  /// `(screen_domain, attr_domain)`: the group domain inverted on this
  /// field and the evaluated field `domain` (Python `domains_get`).
  (List<dynamic>, dynamic) getDomains(Record record,
      {List<dynamic>? preValidate}) {
    final inverted = domainInversion(
        [record.group.domain4inversion, preValidate ?? const []],
        name,
        evalEnvironment(record));
    final List<dynamic> screenDomain;
    if (inverted == false) {
      screenDomain = [
        ['id', '=', null]
      ];
    } else if (inverted == true) {
      screenDomain = [];
    } else {
      screenDomain = inverted as List<dynamic>;
    }
    final attr = record.exprEval(description['domain'] ?? const []);
    return (screenDomain, attr ?? const []);
  }

  /// Domain for searching values of this field.
  List<dynamic> getDomain(Record record) {
    final (screen, attr) = getDomains(record);
    return concat([localizeDomain(screen), attr]);
  }

  /// Domain the value must satisfy (5.5).
  List<dynamic> validationDomains(Record record,
      {List<dynamic>? preValidate}) {
    final (screen, attr) = getDomains(record, preValidate: preValidate);
    return concat([screen, attr]);
  }

  /// Value for PYSON.
  dynamic getEval(Record record) => get(record);

  /// Value for on_change calls.
  dynamic getOnChangeValue(Record record) => getEval(record);

  /// Field states (SAO `get_state_attrs`): a copy of the description,
  /// readonly when the group or the record is readonly.
  Map<String, dynamic> stateAttrs(Record record) {
    final attrs = record.stateAttrs
        .putIfAbsent(name, () => <String, dynamic>{...description});
    if (record.group.readonly || record.readonly) attrs['readonly'] = true;
    return attrs;
  }

  /// Evaluates `states` into [stateAttrs] (SAO `set_state`).
  void setState(Record record,
      {List<String> states = const ['readonly', 'required', 'invisible']}) {
    final evaluated = record.exprEval(description['states'] ?? const {});
    final changes =
        evaluated is Map ? evaluated : const <String, dynamic>{};
    final attrs = stateAttrs(record);
    for (final state in states) {
      if (state == 'readonly' && description['readonly'] == true) continue;
      if (changes.containsKey(state)) {
        attrs[state] = changes[state];
      } else if (description.containsKey(state)) {
        attrs[state] = description[state];
      }
      if (state == 'readonly' &&
          changes.containsKey('editable') &&
          !PYSONEvaluator.truthy(changes['editable'])) {
        attrs['readonly'] = true;
      }
    }
    if (record.group.readonly ||
        attrs['domain_readonly'] == true ||
        record.group.parentName == name) {
      attrs['readonly'] = true;
    }
  }

  bool isEmpty(Record record) => !PYSONEvaluator.truthy(getEval(record));

  bool checkRequired(Record record) {
    final attrs = stateAttrs(record);
    if (PYSONEvaluator.truthy(attrs['required'])) {
      if (isEmpty(record) && !PYSONEvaluator.truthy(attrs['readonly'])) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() => '$runtimeType($name)';
}

/// `char`: `''` by default, `strip` when setting.
class CharField extends Field {
  CharField(super.description);

  @override
  dynamic get defaultValue => '';

  @override
  void set(Record record, dynamic value) {
    final strip = description['strip'];
    if (value is String && strip != null && strip != false) {
      value = switch (strip) {
        'leading' => value.trimLeft(),
        'trailing' => value.trimRight(),
        _ => value.trim(),
      };
    }
    super.set(record, value);
  }

  @override
  dynamic get(Record record) {
    final value = super.get(record);
    return PYSONEvaluator.truthy(value) ? value : defaultValue;
  }
}

/// `text` (multi-line char; SAO uses Char for it).
class TextField extends CharField {
  TextField(super.description);
}

/// `selection`: value or null; `<f>:string` holds the server label.
class SelectionField extends Field {
  SelectionField(super.description);

  @override
  void setClient(Record record, dynamic value, {bool forceChange = false}) {
    // delete before trigger the display
    record._values.remove('$name:string');
    super.setClient(record, value, forceChange: forceChange);
  }
}

/// `multiselection`: sorted list or null; `get_eval` gives `[]`.
class MultiSelectionField extends SelectionField {
  MultiSelectionField(super.description);

  @override
  bool get singleValue => false;

  @override
  dynamic get(Record record) {
    final value = super.get(record);
    if (value is! List || value.isEmpty) return defaultValue;
    return _sorted(value);
  }

  @override
  dynamic getEval(Record record) => super.getEval(record) ?? <dynamic>[];

  @override
  void setClient(Record record, dynamic value, {bool forceChange = false}) {
    value ??= <dynamic>[];
    if (value is String) value = [value];
    if (value is List) value = _sorted(value);
    super.setClient(record, value, forceChange: forceChange);
  }

  static List<dynamic> _sorted(List value) => [...value]
    ..sort((a, b) => a is Comparable && b is Comparable
        ? Comparable.compare(a, b)
        : '$a'.compareTo('$b'));
}

/// `datetime` / `timestamp`: local [DateTime].
class DateTimeField extends Field {
  DateTimeField(super.description);

  dynamic timeFormat(Record record) => record.exprEval(description['format']);

  @override
  void setClient(Record record, dynamic value, {bool forceChange = false}) {
    if (value is TrytonTime) {
      final current = get(record);
      value = current is DateTime ? _combine(current, value) : null;
    } else if (value is TrytonDate) {
      final current = get(record);
      final time = current is DateTime
          ? TrytonTime(current.hour, current.minute, current.second,
              current.millisecond * 1000 + current.microsecond)
          : const TrytonTime(0, 0, 0, 0);
      value = _combine(value.toDateTime(), time);
    }
    super.setClient(record, value, forceChange: forceChange);
  }

  static DateTime _combine(DateTime date, TrytonTime time) => DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
      time.second,
      0,
      time.microsecond);
}

/// `date`: [TrytonDate].
class DateField extends Field {
  DateField(super.description);

  @override
  void setClient(Record record, dynamic value, {bool forceChange = false}) {
    if (value is DateTime) value = TrytonDate.fromDateTime(value);
    super.setClient(record, value, forceChange: forceChange);
  }
}

/// `time`: [TrytonTime].
class TimeField extends Field {
  TimeField(super.description);

  dynamic timeFormat(Record record) => record.exprEval(description['format']);

  @override
  void setClient(Record record, dynamic value, {bool forceChange = false}) {
    if (value is DateTime) {
      value = TrytonTime(value.hour, value.minute, value.second,
          value.millisecond * 1000 + value.microsecond);
    }
    super.setClient(record, value, forceChange: forceChange);
  }
}

/// `timedelta`: [Duration]. The text form with the `converter` from the
/// context (`1d 02:30`) is not implemented yet (strings are ignored).
class TimeDeltaField extends Field {
  TimeDeltaField(super.description);

  /// Converter of the group context (`description.converter` key).
  dynamic converter(RecordGroup group) {
    final key = description['converter'];
    return key == null ? null : group.context[key];
  }
}

/// `float`: double; [factor] scales the client value, `digits` may be a
/// PYSON expression or the name of a field (`get_digits`, STUB).
class FloatField extends Field {
  FloatField(super.description);

  /// Converts user input; null for empty or invalid input.
  dynamic convert(dynamic value) {
    if (value == null || value == '' || value == false) return null;
    if (value is num) return value.toDouble();
    if (value is TrytonDecimal) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  /// `[int, dec]` or null (SAO `digits`). A field name needs
  /// `model.<relation>.get_digits` – STUB(D1 part 2): null.
  List<int?>? digits(Record record, {num factor = 1}) {
    final digits = record.exprEval(description['digits']);
    if (digits is! List || digits.length < 2) return null;
    final shift = (math.log(factor.abs()) / math.ln10).round();
    final intSize = digits[0] is num ? (digits[0] as num).toInt() + shift : null;
    final decSize = digits[1] is num ? (digits[1] as num).toInt() - shift : null;
    return [intSize, decSize];
  }

  /// Value ÷ [factor], rounded to the digits.
  dynamic applyFactor(Record record, dynamic value, num factor) {
    if (value == null || factor == 1) return value;
    final scaled = (value as num) / factor;
    final dec = digits(record)?[1];
    return convert(dec == null ? scaled : scaled.toStringAsFixed(dec));
  }

  @override
  void setClient(Record record, dynamic value,
      {bool forceChange = false, num factor = 1}) {
    super.setClient(record, applyFactor(record, convert(value), factor),
        forceChange: forceChange);
  }

  /// The value × [factor] (formatting is done by the widget).
  @override
  dynamic getClient(Record record, {num factor = 1}) {
    final value = get(record);
    if (value == null) return null;
    if (value is TrytonDecimal) {
      return factor == 1 ? value : TrytonDecimal('${value.toDouble() * factor}');
    }
    return (value as num) * factor;
  }

  @override
  bool isEmpty(Record record) => get(record) == null;
}

/// `numeric`: [TrytonDecimal].
class NumericField extends FloatField {
  NumericField(super.description);

  @override
  dynamic convert(dynamic value) {
    if (value == null || value == '' || value == false) return null;
    if (value is TrytonDecimal) return value;
    final text = value.toString().trim();
    return num.tryParse(text) == null ? null : TrytonDecimal(text);
  }

  @override
  dynamic applyFactor(Record record, dynamic value, num factor) {
    if (value == null || factor == 1) return value;
    final scaled = (value as TrytonDecimal).toDouble() / factor;
    final dec = digits(record)?[1];
    return convert(dec == null ? '$scaled' : scaled.toStringAsFixed(dec));
  }
}

/// `integer`: int.
class IntegerField extends FloatField {
  IntegerField(super.description);

  @override
  dynamic convert(dynamic value) {
    if (value == null || value == '' || value == false) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }
}

/// `boolean`: never null.
class BooleanField extends Field {
  BooleanField(super.description);

  @override
  dynamic get defaultValue => false;

  @override
  dynamic get(Record record) => PYSONEvaluator.truthy(record._values[name]);

  @override
  void setClient(Record record, dynamic value, {bool forceChange = false}) =>
      super.setClient(record, PYSONEvaluator.truthy(value),
          forceChange: forceChange);

  @override
  bool isEmpty(Record record) => false;
}

/// `many2one`: id or null; `<f>.` holds `{rec_name, …}`.
class Many2OneField extends Field {
  Many2OneField(super.description);

  Map<String, dynamic> _related(Record record) => (record._values
          .putIfAbsent('$name.', () => <String, dynamic>{}) as Map)
      .cast<String, dynamic>();

  @override
  bool isEmpty(Record record) => get(record) == null;

  /// `rec_name` of the value.
  @override
  dynamic getClient(Record record) {
    final related = record._values['$name.'];
    final recName = related is Map ? related['rec_name'] : null;
    return recName ?? '';
  }

  /// Sets the id. Also accepts `[id, rec_name]` (current screens).
  /// A missing rec_name would be read from the server – STUB(D1 part 2):
  /// it stays empty.
  @override
  void set(Record record, dynamic value) {
    if (value is List) {
      if (value.length > 1 && value[1] is String) {
        _related(record)['rec_name'] = value[1];
      }
      value = value.isEmpty ? null : value[0];
    }
    final related = _related(record);
    related['rec_name'] = related['rec_name'] ?? '';
    record._values[name] = value;
  }

  @override
  void setClient(Record record, dynamic value, {bool forceChange = false}) {
    String recName;
    if (value is List) {
      recName = value.length > 1 ? '${value[1] ?? ''}' : '';
      value = value.isEmpty ? null : value[0];
    } else if (domainEquals(value, get(record))) {
      recName = '${_related(record)['rec_name'] ?? ''}';
    } else {
      recName = '';
    }
    if (value is int && value < 0 && name != record.group.parentName) {
      value = null;
      recName = '';
    }
    _related(record)['rec_name'] = recName;
    super.setClient(record, value, forceChange: forceChange);
  }

  @override
  Map<String, dynamic> getContext(Record record,
      {Map<String, dynamic>? recordContext, bool local = false}) {
    final context = super
        .getContext(record, recordContext: recordContext, local: local);
    final datetimeField = description['datetime_field'];
    if (datetimeField != null) {
      context['_datetime'] = record.getEval()[datetimeField];
    }
    return context;
  }

  @override
  List<dynamic> validationDomains(Record record,
          {List<dynamic>? preValidate}) =>
      getDomains(record, preValidate: preValidate).$1;

  /// Python 8.0: `concat(localize_domain(inverse_leaf(screen), name),
  /// attr)` (SAO lacks `inverse_leaf`).
  @override
  List<dynamic> getDomain(Record record) {
    final (screen, attr) = getDomains(record);
    return concat([localizeDomain(inverseLeaf(screen), name), attr]);
  }

  @override
  dynamic getOnChangeValue(Record record) {
    final parent = record.group.parent;
    if (record.group.parentName == name && parent != null) {
      return parent.getOnChangeValue(skip: [record.group.childName]);
    }
    return super.getOnChangeValue(record);
  }
}

/// `one2one`: like many2one.
class One2OneField extends Many2OneField {
  One2OneField(super.description);
}

/// `one2many`: the value is a child [RecordGroup] (spec 5.7).
class One2ManyField extends Field {
  One2ManyField(super.description);

  @override
  bool get singleValue => false;

  String get relation => description['relation'] as String? ?? '';

  String get relationField => description['relation_field'] as String? ?? '';

  /// Fields of the sub-views sent with the description (`views`).
  Map<String, dynamic> get _viewFields {
    final fields = <String, dynamic>{};
    final views = description['views'];
    if (views is Map) {
      for (final view in views.values) {
        final f = view is Map ? view['fields'] : null;
        if (f is Map) fields.addAll(f.cast<String, dynamic>());
      }
    }
    return fields;
  }

  RecordGroup _group(Record record) {
    _setDefaultValue(record);
    return record._values[name] as RecordGroup;
  }

  /// Creates the child group (SAO `_set_default_value`).
  void _setDefaultValue(Record record, [TrytonModel? model]) {
    if (record._values[name] != null) return;
    if (record.model.name == relation) {
      model = record.model;
    } else {
      model ??= (record.model.related(relation)..addFields(_viewFields));
    }
    final group = RecordGroup(model)
      ..setParent(record)
      ..parentName = relationField
      ..childName = name
      ..parentDatetimeField = description['datetime_field'] as String?;
    record._values[name] = group;
  }

  /// [value] is a list of ids or of value dicts (defaults, on_change);
  /// [data] are preloaded values (`<f>.`).
  void _setValue(Record record, dynamic value,
      {bool isDefault = false, bool modified = false, dynamic data}) {
    final group = _group(record);
    final list = value is List ? value : const [];
    final listIds = list.isEmpty || list.first is int;
    // Unknown fields of the values would be fetched with fields_get –
    // STUB(D1 part 2): only fields from the sub-views are added.
    if (!listIds || data != null) {
      final viewFields = _viewFields;
      final names = <String>{
        for (final v in listIds ? (data as List? ?? const []) : list)
          if (v is Map) ...v.keys.cast<String>(),
      }.where((f) =>
          !group.model.fields.containsKey(f) &&
          !f.contains('.') &&
          !f.contains(':') &&
          !f.startsWith('_'));
      final fields = {
        for (final n in names)
          if (viewFields.containsKey(n)) n: viewFields[n],
      };
      if (fields.isNotEmpty) group.addFields(fields);
    }
    if (listIds) {
      final ids = list.cast<int>();
      for (final old in group.toList()) {
        if (!ids.contains(old.id)) {
          group.remove(old, remove: true, modified: false);
        }
      }
      final preloaded = <int, Map<String, dynamic>>{
        for (final d in (data as List? ?? const []))
          if (d is Map && d['id'] is int)
            d['id'] as int: d.cast<String, dynamic>(),
      };
      group.load(ids,
          modified: modified || isDefault, preloaded: preloaded);
    } else {
      for (final vals in list.cast<Map>()) {
        final values = vals.cast<String, dynamic>();
        Record? newRecord;
        if (values.containsKey('id')) {
          newRecord = group.get(values['id'] as int) ??
              group.newRecord(id: values['id'] as int);
        } else {
          newRecord = group.newRecord();
        }
        if (isDefault) {
          // Don't validate as parent will validate
          newRecord.setDefault(values, validate: false, modified: false);
          group.add(newRecord, modified: false);
        } else {
          newRecord.set(values, modified: false);
          group._records.add(newRecord);
        }
      }
      // Trigger modified only once
      group.recordModified();
    }
  }

  @override
  void set(Record record, dynamic value,
      {bool isDefault = false, dynamic data}) {
    final group = record._values[name];
    TrytonModel? model;
    if (group is RecordGroup) {
      model = group.model;
      group.destroy();
    } else if (record.model.name == relation) {
      model = record.model;
    }
    record._values.remove(name);
    _setDefaultValue(record, model);
    _setValue(record, value, isDefault: isDefault, data: data);
  }

  /// x2many write commands (spec 5.7): `add`, `create`, `write`,
  /// `remove`, `delete`.
  @override
  List<dynamic> get(Record record) {
    final group = record._values[name];
    if (group is! RecordGroup) return [];
    final result = <dynamic>[];
    final toAdd = <int>[];
    final toCreate = <Map<String, dynamic>>[];
    final toWrite = <dynamic>[];
    for (final record2 in group) {
      if (group.recordRemoved.contains(record2) ||
          group.recordDeleted.contains(record2)) {
        continue;
      }
      if (record2.id >= 0) {
        if (record2.modified) {
          final values = record2.get()..remove(relationField);
          if (values.isNotEmpty) {
            toWrite
              ..add([record2.id])
              ..add(values);
          }
          toAdd.add(record2.id);
        }
      } else {
        toCreate.add(record2.get()..remove(relationField));
      }
    }
    if (toAdd.isNotEmpty) result.add(['add', toAdd]);
    if (toCreate.isNotEmpty) result.add(['create', toCreate]);
    if (toWrite.isNotEmpty) result.add(['write', ...toWrite]);
    if (group.recordRemoved.isNotEmpty) {
      result.add(['remove', [for (final r in group.recordRemoved) r.id]]);
    }
    if (group.recordDeleted.isNotEmpty) {
      result.add(['delete', [for (final r in group.recordDeleted) r.id]]);
    }
    return result;
  }

  @override
  void setClient(Record record, dynamic value, {bool forceChange = false}) {
    // domain inversion try to set None / an id as value
    value ??= <int>[];
    if (value is int) value = [value];
    final previousIds = [...getEval(record) as List]..sort();
    final newIds = [...value as List];
    final modified = !(newIds.every((e) => e is int) &&
        _valuesEqual(previousIds, newIds..sort()));
    _setValue(record, value, modified: modified);
    if (modified) {
      changed(record);
      record.validate(softValidation: true);
      record.setModified(name);
    } else if (forceChange) {
      changed(record);
      record.validate(softValidation: true);
      record.setModified();
    }
  }

  @override
  RecordGroup getClient(Record record) => _group(record);

  @override
  void setDefault(Record record, dynamic value) {
    record.modifiedFields.add(name);
    set(record, value, isDefault: true);
  }

  /// on_change result: a list (replaces the content) or
  /// `{remove, delete, add: [[index, values]], update: [values]}`.
  @override
  void setOnChange(Record record, dynamic value) {
    record.modifiedFields.add(name);
    final group = _group(record);
    if (value is List) {
      _setValue(record, value, modified: true);
      return;
    }
    if (value is! Map) return;
    // New fields of add/update would be fetched with fields_get –
    // STUB(D1 part 2): unknown keys are ignored by Record.set_on_change.
    for (final id in (value['delete'] as List? ?? const [])) {
      final r = group.get(id as int);
      if (r != null) group.remove(r, remove: false, modified: false);
    }
    for (final id in (value['remove'] as List? ?? const [])) {
      final r = group.get(id as int);
      if (r != null) group.remove(r, remove: true, modified: false);
    }
    for (final add in (value['add'] as List? ?? const [])) {
      final index = (add as List)[0] as int;
      final data = Map<String, dynamic>.from(add[1] as Map);
      final id = data.remove('id');
      final newRecord =
          (id is int ? group.get(id) : null) ?? group.newRecord(id: id as int?);
      group.add(newRecord, position: index, modified: false);
      newRecord.setOnChange(data);
    }
    for (final vals in (value['update'] as List? ?? const [])) {
      final values = Map<String, dynamic>.from(vals as Map);
      final id = values['id'];
      if (id is! int) continue;
      group.get(id)?.setOnChange(values);
    }
  }

  /// Timestamps of modified, removed and deleted children.
  @override
  Map<String, String?> getTimestamp(Record record) {
    final group = record._values[name];
    if (group is! RecordGroup) return {};
    final timestamps = <String, String?>{};
    for (final r in [
      ...group.where((r) => r.modified),
      ...group.recordRemoved,
      ...group.recordDeleted,
    ]) {
      timestamps.addAll(r.getTimestamp());
    }
    return timestamps;
  }

  /// ids of the remaining children (without removed/deleted).
  @override
  List<int> getEval(Record record) {
    final group = record._values[name];
    if (group is! RecordGroup) return [];
    return [
      for (final r in group)
        if (!group.recordRemoved.contains(r) &&
            !group.recordDeleted.contains(r))
          r.id
    ];
  }

  @override
  dynamic getOnChangeValue(Record record) {
    final group = record._values[name];
    if (group is! RecordGroup) return [];
    return [
      for (final r in group)
        if (!r.deleted && !r.removed)
          r.getOnChangeValue(skip: [relationField])
    ];
  }

  /// Only the field domain: the screen domain means "at least one record",
  /// not all records.
  @override
  List<dynamic> getDomain(Record record) {
    final attr = getDomains(record).$2;
    return attr is List ? attr : const [];
  }

  @override
  List<dynamic> validationDomains(Record record,
          {List<dynamic>? preValidate}) =>
      getDomains(record, preValidate: preValidate).$1;

  @override
  void setState(Record record,
      {List<String> states = const ['readonly', 'required', 'invisible']}) {
    _setDefaultValue(record);
    super.setState(record, states: states);
  }

  @override
  bool isEmpty(Record record) => getEval(record).isEmpty;
}

/// `many2many`: like one2many; on_change value is the id list.
class Many2ManyField extends One2ManyField {
  Many2ManyField(super.description);

  @override
  dynamic getOnChangeValue(Record record) => getEval(record);
}

/// `reference`: internally `[model, id]`, `get` gives `"model,id"`.
class ReferenceField extends Field {
  ReferenceField(super.description);

  Map<String, dynamic> _related(Record record) => (record._values
          .putIfAbsent('$name.', () => <String, dynamic>{}) as Map)
      .cast<String, dynamic>();

  String? _model(Record record) {
    final value = record._values[name];
    return value is List && value.isNotEmpty ? value[0] as String? : null;
  }

  /// `[model, rec_name]` or null.
  @override
  dynamic getClient(Record record) {
    final model = _model(record);
    if (record._values[name] == null) return null;
    return [model, '${_related(record)['rec_name'] ?? ''}'];
  }

  @override
  dynamic get(Record record) {
    final value = record._values[name];
    if (value is List &&
        value.length == 2 &&
        PYSONEvaluator.truthy(value[0]) &&
        value[1] != null &&
        (value[1] is! num || (value[1] as num) >= -1)) {
      return '${value[0]},${value[1]}';
    }
    return null;
  }

  @override
  void setClient(Record record, dynamic value, {bool forceChange = false}) {
    if (PYSONEvaluator.truthy(value)) {
      if (value is String) value = value.split(',');
      final list = value as List;
      final refModel = list[0];
      dynamic refId = list.length > 1 ? list[1] : null;
      String recName;
      if (refId is List) {
        recName = '${refId.length > 1 ? refId[1] ?? '' : ''}';
        refId = refId.isEmpty ? null : refId[0];
      } else {
        if (refId is String) refId = int.tryParse(refId) ?? refId;
        recName = '$refModel,$refId' == get(record)
            ? '${_related(record)['rec_name'] ?? ''}'
            : '';
      }
      _related(record)['rec_name'] = recName;
      value = [refModel, refId];
    }
    super.setClient(record, value, forceChange: forceChange);
  }

  /// Accepts `"model,id"` or `[model, id]`. A missing rec_name would be
  /// read from the server – STUB(D1 part 2): it stays empty.
  @override
  void set(Record record, dynamic value) {
    if (!PYSONEvaluator.truthy(value)) {
      record._values[name] = defaultValue;
      return;
    }
    String? refModel;
    dynamic refId;
    if (value is String) {
      final idx = value.indexOf(',');
      refModel = idx < 0 ? value : value.substring(0, idx);
      final rest = idx < 0 ? '' : value.substring(idx + 1);
      refId = rest.isEmpty ? null : (int.tryParse(rest) ?? rest);
    } else {
      refModel = (value as List)[0] as String?;
      refId = value.length > 1 ? value[1] : null;
    }
    final related = _related(record);
    var recName = '${related['rec_name'] ?? ''}';
    if (PYSONEvaluator.truthy(refModel) && refId is int && refId >= 0) {
      // STUB(D1 part 2): read rec_name when missing
    } else if (PYSONEvaluator.truthy(refModel)) {
      recName = '';
    } else {
      recName = '${refId ?? ''}';
    }
    related['rec_name'] = recName;
    record._values[name] = [refModel, refId];
  }

  @override
  dynamic getOnChangeValue(Record record) {
    final parent = record.group.parent;
    if (record.group.parentName == name && parent != null) {
      return [
        parent.model.name,
        parent.getOnChangeValue(skip: [record.group.childName])
      ];
    }
    return super.getOnChangeValue(record);
  }

  @override
  Map<String, dynamic> getContext(Record record,
      {Map<String, dynamic>? recordContext, bool local = false}) {
    final context = super
        .getContext(record, recordContext: recordContext, local: local);
    final datetimeField = description['datetime_field'];
    if (datetimeField != null) {
      context['_datetime'] = record.getEval()[datetimeField];
    }
    return context;
  }

  @override
  List<dynamic> validationDomains(Record record,
          {List<dynamic>? preValidate}) =>
      getDomains(record, preValidate: preValidate).$1;

  /// The field `domain` is a dict model → domain.
  @override
  (List<dynamic>, dynamic) getDomains(Record record,
      {List<dynamic>? preValidate}) {
    final (screen, attr) = super.getDomains(record, preValidate: preValidate);
    final model = _model(record);
    final domain = attr is Map ? attr[model] : null;
    return (screen, domain is List ? domain : const []);
  }

  @override
  List<dynamic> getDomain(Record record) {
    final (screen, attr) = getDomains(record);
    final model = _model(record);
    final prepared =
        prepareReferenceDomain(filterLeaf(screen, name, model), name);
    return concat([localizeDomain(prepared, name, true), attr]);
  }

  @override
  dynamic getSearchOrder(Record record) {
    final order = super.getSearchOrder(record);
    return order is Map ? order[_model(record)] : order;
  }

  /// Allowed target models from the domains.
  List<String> getModels(Record record) {
    final (screen, attr) = getDomains(record);
    return extractReferenceModels(
        concat([prepareReferenceDomain(screen, name), attr]), name);
  }

  @override
  bool isEmpty(Record record) {
    if (super.isEmpty(record)) return true;
    final value = record._values[name];
    return value is List && value[1] is num && (value[1] as num) < 0;
  }
}

/// `binary`: bytes or the size (int) when only the size was loaded.
class BinaryField extends Field {
  BinaryField(super.description);

  @override
  bool hasChanged(dynamic previous, dynamic value) =>
      !identical(previous, value);

  dynamic getSize(Record record) {
    final data = record._values[name];
    if (data is TrytonBytes) return data.bytes.length;
    if (data is String) return data.length;
    return data;
  }

  /// STUB(D1 part 2): reads the content when only the size is known.
  Future<dynamic> getData(Record record) async {
    final data = record._values[name];
    if (data is TrytonBytes || data is String || data == null) return data;
    if (record.id < 0) return data;
    throw NotYetImplemented('BinaryField.getData');
  }
}

/// `dict`: map with sorted keys; key definitions come from
/// `schema_model` (STUB(D1 part 2)).
class DictField extends Field {
  DictField(super.description);

  /// Key definitions by name (`search_get_keys` / `get_keys`).
  final Map<String, Map<String, dynamic>> keys = {};

  @override
  dynamic get defaultValue => <String, dynamic>{};

  @override
  bool get singleValue => false;

  @override
  void set(Record record, dynamic value) {
    if (value is Map) {
      final sorted = value.keys.map((k) => k.toString()).toList()..sort();
      value = {for (final k in sorted) k: value[k]};
    }
    super.set(record, value);
  }

  @override
  dynamic get(Record record) {
    final value = super.get(record);
    return value is Map ? <String, dynamic>{...value} : <String, dynamic>{};
  }

  @override
  List<dynamic> validationDomains(Record record,
          {List<dynamic>? preValidate}) =>
      getDomains(record, preValidate: preValidate).$1;

  /// STUB(D1 part 2): `schema_model.search_get_keys`.
  Future<void> addKeys(List<String> keys, Record record) async =>
      throw NotYetImplemented('DictField.addKeys');

  /// STUB(D1 part 2): `schema_model.get_keys`.
  Future<List<String>> addNewKeys(List<int> ids, Record record) async =>
      throw NotYetImplemented('DictField.addNewKeys');
}
