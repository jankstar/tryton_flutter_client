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

/// Reads the missing `rec_name` of a many2one/reference value in the
/// background (without error dialog; on error the name stays empty) and
/// notifies the listeners when it arrives.
void _fetchRecName(Record record, String field, String relation, int id,
    dynamic expected) {
  final rpc = record.model.session.rpc;
  if (rpc == null) return;
  unawaited(() async {
    try {
      final result = await rpc.execute(relation, 'read', [
        [id],
        ['rec_name']
      ], context: record.getContext(), processException: false);
      if (result is! List || result.isEmpty) return;
      if (!_valuesEqual(record._values[field], expected)) return;
      final related = record._values['$field.'];
      if (related is Map) {
        related['rec_name'] = '${(result.first as Map)['rec_name'] ?? ''}';
        record.group.notifyScreens();
      }
    } catch (_) {}
  }());
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

  /// Views showing this field (set by the screens); loading takes the
  /// fields of the same views.
  final Set<Object> views = {};

  /// `eager` (default) or `lazy` (5.4.2).
  String get loading => description['loading'] as String? ?? 'eager';

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

  /// Sets a value from the user. On a change the field is marked modified
  /// at once; on_change etc., validation and the modification
  /// notification run in the record's queue. The returned future
  /// completes after that chain and carries its errors.
  Future<void> setClient(Record record, dynamic value,
      {bool forceChange = false}) {
    final previous = get(record);
    set(record, value);
    final isChanged = hasChanged(previous, get(record));
    return _afterSetClient(record, isChanged, forceChange);
  }

  Future<void> _afterSetClient(
      Record record, bool isChanged, bool forceChange) {
    if (!isChanged && !forceChange) return Future.value();
    if (isChanged) record.modifiedFields.add(name);
    return record._enqueue(() async {
      await changed(record);
      record.validate(softValidation: true);
      record.setModified(isChanged ? name : null);
    });
  }

  dynamic getClient(Record record) => get(record);

  FutureOr<void> setDefault(Record record, dynamic value) {
    set(record, value);
    record.modifiedFields.add(name);
  }

  FutureOr<void> setOnChange(Record record, dynamic value) {
    set(record, value);
    record.modifiedFields.add(name);
  }

  /// After a change: on_change, on_change_with, autocomplete and the
  /// x2many field contexts (SAO `changed`).
  Future<void> changed(Record record) async {
    await record.onChange([name]);
    await record.onChangeWith([name]);
    await record.autocompleteWith(name);
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

  /// Validates the value (spec 5.5, SAO/Python `Field.validate`):
  /// required (not with [softValidation]); the domain (screen domain
  /// inverted on the field ⊕ field domain): unsatisfiable → `'domain'`, a
  /// unique value is set and makes the field `domain_readonly` (AND
  /// domain), otherwise the value is checked with `eval_domain`. The
  /// result is stored as `stateAttrs['invalid']`.
  bool validate(Record record,
      {bool softValidation = false, List<dynamic>? preValidate}) {
    if (description['readonly'] == true) return true;
    final attrs = stateAttrs(record);
    final isRequired = PYSONEvaluator.truthy(attrs['required']);
    final isInvisible = PYSONEvaluator.truthy(attrs['invisible']);
    dynamic invalid = false;
    attrs['domain_readonly'] = false;
    final domain =
        simplify(validationDomains(record, preValidate: preValidate));
    if (!softValidation && !checkRequired(record)) invalid = 'required';
    if (domainEquals(domain, [
      ['id', '=', null]
    ])) {
      invalid = 'domain';
    } else {
      final (screenDomain, _) = getDomains(record, preValidate: preValidate);
      final (unique, leftPart, uniqueValue_) =
          uniqueValue(domain, singleValue: singleValue);
      final (uniqueFromScreen, _, _) =
          uniqueValue(screenDomain, singleValue: singleValue);
      if (isEmpty(record) &&
          !isRequired &&
          !isInvisible &&
          !uniqueFromScreen) {
        // Do nothing
      } else if (unique) {
        // If the inverted domain is so constraint that only one value is
        // possible we should use it. But we must also pay attention to the
        // fact that the original domain might be a 'OR' domain and thus
        // not preventing the modification of fields.
        final value = uniqueValue_ == false ? null : uniqueValue_;
        // Like SAO/Python: the group domain unless it is empty.
        final groupDomain = record.group.domain;
        final original = merge(groupDomain.isNotEmpty ? groupDomain : domain);
        final domainReadonly = original.isNotEmpty && original[0] == 'AND';
        final idx = leftPart!.indexOf('.');
        final setDefault = idx < 0 || leftPart.substring(idx + 1) == 'id';
        if (setDefault && (preValidate == null || preValidate.isEmpty)) {
          unawaited(setClient(record, value));
          attrs['domain_readonly'] = domainReadonly;
        }
      }
      if (!evalDomain(domain, evalEnvironment(record))) invalid = domain;
    }
    attrs['invalid'] = invalid;
    return invalid == false;
  }


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
  Future<void> setClient(Record record, dynamic value,
      {bool forceChange = false}) {
    // delete before trigger the display
    record._values.remove('$name:string');
    return super.setClient(record, value, forceChange: forceChange);
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
  Future<void> setClient(Record record, dynamic value,
      {bool forceChange = false}) {
    value ??= <dynamic>[];
    if (value is String) value = [value];
    if (value is List) value = _sorted(value);
    return super.setClient(record, value, forceChange: forceChange);
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
  Future<void> setClient(Record record, dynamic value,
      {bool forceChange = false}) {
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
    return super.setClient(record, value, forceChange: forceChange);
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
  Future<void> setClient(Record record, dynamic value,
      {bool forceChange = false}) {
    if (value is DateTime) value = TrytonDate.fromDateTime(value);
    return super.setClient(record, value, forceChange: forceChange);
  }
}

/// `time`: [TrytonTime].
class TimeField extends Field {
  TimeField(super.description);

  dynamic timeFormat(Record record) => record.exprEval(description['format']);

  @override
  Future<void> setClient(Record record, dynamic value,
      {bool forceChange = false}) {
    if (value is DateTime) {
      value = TrytonTime(value.hour, value.minute, value.second,
          value.millisecond * 1000 + value.microsecond);
    }
    return super.setClient(record, value, forceChange: forceChange);
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
  Future<void> setClient(Record record, dynamic value,
      {bool forceChange = false, num factor = 1}) {
    return super.setClient(record, applyFactor(record, convert(value), factor),
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
  Future<void> setClient(Record record, dynamic value,
          {bool forceChange = false}) =>
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
  /// A missing rec_name is read in the background (SAO reads it
  /// synchronously).
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
    final relation = description['relation'];
    if (related['rec_name'] == '' && value is int && value >= 0 &&
        relation is String) {
      _fetchRecName(record, name, relation, value, value);
    }
  }

  @override
  Future<void> setClient(Record record, dynamic value,
      {bool forceChange = false}) {
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
    return super.setClient(record, value, forceChange: forceChange);
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

  /// Names in [valuesList] that are no field of [group]'s model yet.
  static Set<String> _unknownFields(
          RecordGroup group, Iterable<dynamic> valuesList) =>
      {
        for (final v in valuesList)
          if (v is Map)
            for (final f in v.keys.cast<String>())
              if (!group.model.fields.containsKey(f) &&
                  f != 'id' &&
                  !f.contains('.') &&
                  !f.contains(':') &&
                  !f.startsWith('_'))
                f,
      };

  /// Adds the fields of [valuesList] that the child model does not know:
  /// from the sub-views or with `fields_get` (SAO `_set_value`); new
  /// records get their defaults. Returns the added names.
  Future<Set<String>> _fetchFields(
      Record record, RecordGroup group, Iterable<dynamic> valuesList) async {
    final names = _unknownFields(group, valuesList);
    if (names.isEmpty) return names;
    final viewFields = _viewFields;
    final fields = <String, dynamic>{
      for (final n in names)
        if (viewFields.containsKey(n)) n: viewFields[n],
    };
    final toFetch = [for (final n in names) if (!fields.containsKey(n)) n];
    if (toFetch.isNotEmpty) {
      final result = await group.model.execute('fields_get', [toFetch],
          context: getContext(record));
      if (result is Map) fields.addAll(result.cast<String, dynamic>());
    }
    if (fields.isNotEmpty) await group.addFieldsWithDefaults(fields);
    return names;
  }

  /// [value] is a list of ids (with [data] = preloaded values `<f>.`) or of
  /// value dicts. Synchronous: only fields of the sub-views are added
  /// (server values from `read`).
  void _setValue(Record record, dynamic value,
      {bool modified = false, dynamic data}) {
    final group = _group(record);
    final list = value is List ? value : const [];
    final listIds = list.isEmpty || list.first is int;
    final names = _unknownFields(group, listIds ? (data as List? ?? []) : list);
    if (names.isNotEmpty) {
      final viewFields = _viewFields;
      group.addFields({
        for (final n in names)
          if (viewFields.containsKey(n)) n: viewFields[n],
      });
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
      group.load(ids, modified: modified, preloaded: preloaded);
    } else {
      for (final vals in list.cast<Map>()) {
        final record2 = _recordFor(group, vals.cast<String, dynamic>());
        record2.set(vals.cast<String, dynamic>(), modified: false);
        if (!group.contains(record2)) group._records.add(record2);
      }
      // Trigger modified only once
      group.recordModified();
    }
  }

  /// Like [_setValue], but unknown fields are fetched (`fields_get`) and
  /// value dicts can be defaults (`set_default`).
  Future<void> _setValueAsync(Record record, dynamic value,
      {bool isDefault = false, bool modified = false}) async {
    final group = _group(record);
    final list = value is List ? value : const [];
    final listIds = list.isEmpty || list.first is int;
    if (listIds) {
      _setValue(record, list, modified: modified || isDefault);
      return;
    }
    await _fetchFields(record, group, list);
    for (final vals in list.cast<Map>()) {
      final values = vals.cast<String, dynamic>();
      final record2 = _recordFor(group, values);
      if (isDefault) {
        // Don't validate as parent will validate
        await record2.setDefault(values, validate: false, modified: false);
        group.add(record2, modified: false);
      } else {
        record2.set(values, modified: false);
        if (!group.contains(record2)) group._records.add(record2);
      }
    }
    // Trigger modified only once
    group.recordModified();
  }

  static Record _recordFor(RecordGroup group, Map<String, dynamic> values) {
    final id = values['id'];
    if (id is int) return group.get(id) ?? group.newRecord(id: id);
    return group.newRecord();
  }

  /// Replaces the child group (server values).
  @override
  void set(Record record, dynamic value, {dynamic data}) {
    _resetGroup(record);
    _setValue(record, value, data: data);
  }

  void _resetGroup(Record record) {
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
  Future<void> setClient(Record record, dynamic value,
      {bool forceChange = false}) {
    // domain inversion try to set None / an id as value
    value ??= <int>[];
    if (value is int) value = [value];
    final previousIds = [...getEval(record) as List]..sort();
    final newIds = [...value as List];
    final modified = !(newIds.every((e) => e is int) &&
        _valuesEqual(previousIds, newIds..sort()));
    _setValue(record, value, modified: modified);
    return _afterSetClient(record, modified, forceChange);
  }

  @override
  RecordGroup getClient(Record record) => _group(record);

  @override
  Future<void> setDefault(Record record, dynamic value) async {
    record.modifiedFields.add(name);
    _resetGroup(record);
    await _setValueAsync(record, value, isDefault: true);
  }

  /// on_change result: a list (replaces the content) or
  /// `{remove, delete, add: [[index, values]], update: [values]}`; unknown
  /// fields of add/update are fetched with `fields_get`.
  @override
  Future<void> setOnChange(Record record, dynamic value) async {
    record.modifiedFields.add(name);
    final group = _group(record);
    if (value is List) {
      await _setValueAsync(record, value, modified: true);
      return;
    }
    if (value is! Map) return;
    final adds = [
      for (final add in (value['add'] as List? ?? const []))
        (
          (add as List)[0] as int,
          Map<String, dynamic>.from(add[1] as Map),
        )
    ];
    final updates = [
      for (final u in (value['update'] as List? ?? const []))
        Map<String, dynamic>.from(u as Map)
    ];
    // Names unknown before (set after add_fields, SAO)
    final newFields =
        _unknownFields(group, [for (final a in adds) a.$2, ...updates]);

    for (final id in (value['delete'] as List? ?? const [])) {
      final r = group.get(id as int);
      if (r != null) group.remove(r, remove: false, modified: false);
    }
    for (final id in (value['remove'] as List? ?? const [])) {
      final r = group.get(id as int);
      if (r != null) group.remove(r, remove: true, modified: false);
    }
    if (adds.isEmpty && updates.isEmpty) return;

    // First set already known fields to prevent a second on_change call
    final setFirst = <int, Set<String>>{};
    for (final vals in updates) {
      final r = vals['id'] is int ? group.get(vals['id'] as int) : null;
      if (r == null) continue;
      final known = {
        for (final e in vals.entries)
          if (!newFields.contains(e.key)) e.key: e.value
      };
      setFirst[r.id] = known.keys.toSet();
      await r.setOnChange(known);
    }
    await _fetchFields(record, group, [for (final a in adds) a.$2, ...updates]);
    for (final (index, data) in adds) {
      final id = data.remove('id');
      final r = (id is int ? group.get(id) : null) ??
          group.newRecord(id: id is int ? id : null);
      group.add(r, position: index, modified: false);
      await r.setOnChange(data);
    }
    for (final vals in updates) {
      final r = vals['id'] is int ? group.get(vals['id'] as int) : null;
      if (r == null) continue;
      final rest = {
        for (final e in vals.entries)
          if (!(setFirst[r.id]?.contains(e.key) ?? false)) e.key: e.value
      };
      if (rest.isNotEmpty) await r.setOnChange(rest);
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

  /// Validates the loaded children too (against the pre_validate domain
  /// inverted on this field); an invalid child gives `'children'`.
  @override
  bool validate(Record record,
      {bool softValidation = false, List<dynamic>? preValidate}) {
    dynamic invalid = false;
    var ldomain = localizeDomain(
        domainInversion(record.group.clean4inversion(preValidate ?? []),
            name, evalEnvironment(record)),
        name);
    if (ldomain == true) {
      ldomain = <dynamic>[];
    } else if (ldomain == false) {
      ldomain = [
        ['id', '=', null]
      ];
    }
    final group = record._values[name];
    if (group is RecordGroup) {
      for (final r in group) {
        if (!r.getLoaded() &&
            r.id >= 0 &&
            (preValidate == null || preValidate.isEmpty)) {
          continue;
        }
        if (!r.validate(
            softValidation: softValidation,
            preValidate: ldomain as List<dynamic>)) {
          invalid = 'children';
        }
      }
    }
    final test = super.validate(record,
        softValidation: softValidation, preValidate: preValidate);
    if (test && invalid != false) {
      stateAttrs(record)['invalid'] = invalid;
      return false;
    }
    return test;
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
  Future<void> setClient(Record record, dynamic value,
      {bool forceChange = false}) {
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
    return super.setClient(record, value, forceChange: forceChange);
  }

  /// Accepts `"model,id"` or `[model, id]`. A missing rec_name is read in
  /// the background.
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
    final fetch = recName.isEmpty &&
        refModel != null &&
        refModel.isNotEmpty &&
        refId is int &&
        refId >= 0;
    if (PYSONEvaluator.truthy(refModel) && refId is int && refId >= 0) {
      // keep the known rec_name (missing → read below)
    } else if (PYSONEvaluator.truthy(refModel)) {
      recName = '';
    } else {
      recName = '${refId ?? ''}';
    }
    related['rec_name'] = recName;
    record._values[name] = [refModel, refId];
    if (fetch) {
      _fetchRecName(record, name, refModel, refId, [refModel, refId]);
    }
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

  /// The content; when only the size was loaded it is read now.
  Future<dynamic> getData(Record record) async {
    final data = record._values[name];
    if (data is TrytonBytes || data is String || data == null) return data;
    if (record.id < 0) return data;
    final result = await record.model.execute('read', [
      [record.id],
      [name]
    ], context: record.getContext());
    final content = ((result as List).first as Map)[name];
    set(record, content);
    return content;
  }
}

/// `dict`: map with sorted keys; key definitions come from
/// `schema_model` (`search_get_keys` / `get_keys`).
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

  TrytonModel _schemaModel(Record record) =>
      record.model.related(description['schema_model'] as String);

  /// Loads the definitions of [keys] (`search_get_keys` in batches of 10).
  Future<void> addKeys(List<String> keys, Record record) async {
    final context = getContext(record);
    final domain = getDomain(record);
    final limit = record.model.session.limit;
    final batch = math.min(10, limit);
    for (var i = 0; i < keys.length; i += batch) {
      final sub = keys.sublist(i, math.min(i + batch, keys.length));
      final result = await _schemaModel(record).execute('search_get_keys', [
        [
          ['name', 'in', sub],
          domain
        ],
        limit
      ], context: context);
      for (final k in (result as List? ?? const [])) {
        final key = (k as Map).cast<String, dynamic>();
        this.keys['${key['name']}'] = key;
      }
    }
  }

  /// Loads the keys with [ids] (`get_keys`); returns their names.
  Future<List<String>> addNewKeys(List<int> ids, Record record) async {
    final result = await _schemaModel(record)
        .execute('get_keys', [ids], context: getContext(record));
    final names = <String>[];
    for (final k in (result as List? ?? const [])) {
      final key = (k as Map).cast<String, dynamic>();
      keys['${key['name']}'] = key;
      names.add('${key['name']}');
    }
    return names;
  }

  /// Also checks the domains of the known keys against the value.
  @override
  bool validate(Record record,
      {bool softValidation = false, List<dynamic>? preValidate}) {
    final valid = super.validate(record,
        softValidation: softValidation, preValidate: preValidate);
    if (description['readonly'] == true) return valid;
    final value = getEval(record) as Map<String, dynamic>;
    final domain = <dynamic>[
      for (final key in value.keys)
        if (keys[key]?['domain'] case final String d when d.isNotEmpty)
          const PYSONEvaluator({}).eval(jsonDecode(d)),
    ];
    final validValue = evalDomain(domain, value);
    if (!validValue) stateAttrs(record)['invalid'] = 'domain';
    return valid && validValue;
  }
}
