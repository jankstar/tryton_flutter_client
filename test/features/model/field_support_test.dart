import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/xml/view_definition.dart';
import 'package:tryton_flutter_client/features/model/field_definition.dart';
import 'package:tryton_flutter_client/features/model/field_support.dart';

FieldDefinition fd(String name, String type) =>
    FieldDefinition.fromJson(name, {'type': type, 'string': name});

/// Since E13 every field type and widget of spec 9.2.4 has its own widget:
/// nothing is a read-only placeholder any more.
void main() {
  test('all types and widgets are supported', () {
    for (final type in [
      'char', 'text', 'integer', 'float', 'numeric', 'boolean', 'date',
      'datetime', 'time', 'timedelta', 'selection', 'multiselection',
      'many2one', 'one2one', 'reference', 'one2many', 'many2many', 'dict',
      'binary',
    ]) {
      expect(isUnsupportedField(type), isFalse, reason: type);
    }
    for (final widget in [
      'image', 'document', 'richtext', 'html', 'color', 'pyson', 'url',
      'password', 'progressbar',
    ]) {
      expect(isUnsupportedField('char', widget), isFalse, reason: widget);
    }
  });

  test('unsupportedFieldNames: none', () {
    final fields = {
      'photo': fd('photo', 'binary'),
      'notes': fd('notes', 'text'),
    };
    const root = FormRoot(children: [
      FieldNode(name: 'photo', widget: 'image'),
      FieldNode(name: 'notes', widget: 'richtext'),
    ]);
    expect(unsupportedFieldNames(fields, root), isEmpty);
  });
}
