import '../../core/model/model.dart';

/// Bridge between a [Record] of the data layer and the value-based
/// `FieldWidget` (which is shared with the list's context forms).
///
/// Reading uses the field (`get` / `getClient`), writing goes through
/// `field.setClient`, so on_change etc. run in the record.

/// Value of [name] in the format `FieldWidget` expects: many2one /
/// one2one as `[id, rec_name]` (or null), x2many as id list, everything
/// else as `field.get(record)`.
dynamic recordWidgetValue(Record record, String name) {
  final field = record.model.fields[name];
  if (field == null) return null;
  if (field is Many2OneField) {
    final id = field.get(record);
    return id == null ? null : [id, field.getClient(record)];
  }
  if (field is One2ManyField) return field.getEval(record);
  return field.get(record);
}

/// All values of [record] in `FieldWidget` format (for widgets that look
/// at sibling fields, e.g. the currency of an amount).
Map<String, dynamic> recordWidgetValues(Record record) => {
      for (final name in record.model.fields.keys)
        name: recordWidgetValue(record, name),
      'id': record.id,
    };

/// Writes a value coming from a `FieldWidget` into [record] (SAO
/// `set_client`); the future completes after the on_change chain.
Future<void> setRecordWidgetValue(Record record, String name, dynamic value,
    {bool forceChange = false}) {
  final field = record.model.fields[name];
  if (field == null) return Future.value();
  // Many2One widgets send [id, rec_name], an id or null – setClient takes
  // all of them; an empty list means "no value".
  if (field is Many2OneField && value is List && value.isEmpty) value = null;
  return field.setClient(record, value, forceChange: forceChange);
}
