import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/xml/view_definition.dart';
import 'package:tryton_flutter_client/features/model/field_definition.dart';
import 'package:tryton_flutter_client/features/model/field_support.dart';

FieldDefinition fd(String name, String type) =>
    FieldDefinition.fromJson(name, {'type': type, 'string': name});

void main() {
  group('isUnsupportedField', () {
    for (final type in [
      'binary', 'dict', 'multiselection', 'timedelta', 'time',
    ]) {
      test('type $type', () => expect(isUnsupportedField(type), isTrue));
    }
    for (final widget in [
      'image', 'document', 'richtext', 'html', 'color', 'pyson',
    ]) {
      test('widget $widget',
          () => expect(isUnsupportedField('char', widget), isTrue));
    }
    for (final type in [
      'char', 'text', 'integer', 'float', 'numeric', 'boolean', 'date',
      'datetime', 'selection', 'many2one', 'one2many', 'many2many',
    ]) {
      test('supported type $type',
          () => expect(isUnsupportedField(type), isFalse));
    }
    test('supported widgets stay supported', () {
      expect(isUnsupportedField('char', 'url'), isFalse);
      expect(isUnsupportedField('char', 'password'), isFalse);
      expect(isUnsupportedField('float', 'progressbar'), isFalse);
    });
  });

  group('unsupportedFieldNames', () {
    final fields = {
      'name': fd('name', 'char'),
      'photo': fd('photo', 'binary'),
      'attrs': fd('attrs', 'dict'),
      'origin': fd('origin', 'reference'),
      'colour': fd('colour', 'char'),
      'notes': fd('notes', 'text'),
      'duration': fd('duration', 'timedelta'),
    };

    test('without a view: only unsupported types', () {
      expect(unsupportedFieldNames(fields), {'photo', 'attrs', 'duration'},
          reason: 'reference has its own widget');
    });

    test('unsupported widgets anywhere in the form tree', () {
      const root = FormRoot(children: [
        FieldNode(name: 'name'),
        GroupNode(children: [FieldNode(name: 'colour', widget: 'color')]),
        NotebookNode(pages: [
          PageNode(string: 'P', children: [
            FieldNode(name: 'notes', widget: 'richtext'),
          ]),
        ]),
      ]);
      expect(unsupportedFieldNames(fields, root),
          {'photo', 'attrs', 'duration', 'colour', 'notes'});
    });

    test('a supported second occurrence keeps the field writable', () {
      const root = FormRoot(children: [
        FieldNode(name: 'notes', widget: 'html'),
        FieldNode(name: 'notes'),
      ]);
      expect(unsupportedFieldNames(fields, root), isNot(contains('notes')));
    });

    test('unsupported type is excluded even with a supported widget', () {
      const root = FormRoot(children: [FieldNode(name: 'photo', widget: 'url')]);
      expect(unsupportedFieldNames(fields, root), contains('photo'));
    });
  });
}
