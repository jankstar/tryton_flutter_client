import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/model/field_definition.dart';

/// Selection options are sorted by label unless `sort` is false
/// (Python client `SelectionMixin.init_selection`, SAO `selection_mixin`).
void main() {
  Map<String, dynamic> json({bool? sort, Object? selection}) => {
        'type': 'selection',
        'string': 'State',
        'selection': selection ??
            [
              ['draft', 'Entwurf'],
              ['done', 'Erledigt'],
              [null, ''],
              ['cancel', 'Annulliert'],
            ],
        'sort': ?sort,
      };

  List<dynamic> keys(FieldDefinition fd) =>
      fd.selection!.map((o) => o[0]).toList();

  test('static selection sorted by label by default', () {
    final fd = FieldDefinition.fromJson('state', json());
    expect(fd.selectionSort, isTrue);
    expect(keys(fd), [null, 'cancel', 'draft', 'done']);
  });

  test('sort: false keeps the server order', () {
    final fd = FieldDefinition.fromJson('state', json(sort: false));
    expect(fd.selectionSort, isFalse);
    expect(keys(fd), ['draft', 'done', null, 'cancel']);
  });

  test('dynamic selection (copyWithSelection) follows sort', () {
    final options = [
      ['b', 'Beta'],
      ['a', 'Alpha'],
    ];
    final sorted = FieldDefinition.fromJson('x', json(selection: 'get_x'));
    expect(keys(sorted.copyWithSelection(options)), ['a', 'b']);
    final unsorted =
        FieldDefinition.fromJson('x', json(selection: 'get_x', sort: false));
    expect(keys(unsorted.copyWithSelection(options)), ['b', 'a']);
  });

  test('equal labels keep their order (stable)', () {
    final sorted = FieldDefinition.sortSelection([
      ['2', 'Same'],
      ['1', 'Same'],
      ['0', 'A'],
    ]);
    expect(sorted.map((o) => o[0]), ['0', '2', '1']);
  });
}
