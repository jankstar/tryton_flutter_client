import 'dart:convert';

import 'package:tryton_flutter_client/core/model/model.dart';

import '../pyson/pyson_test_helpers.dart';

Map<String, dynamic> fieldDesc(String type,
        [Map<String, dynamic> extra = const {}]) =>
    {'type': type, ...extra};

/// `sale.sale` → `lines` (sale.line, relation_field `sale`) → `details`
/// (sale.line.detail, relation_field `line`): three levels for parent,
/// context and timestamp tests. The x2many fields carry their sub-view
/// fields in `views` like `fields_view_get`.
TrytonModel saleModel({
  Map<String, dynamic> session = const {'language': 'de', 'company': 1},
  ModelAccess access = const ModelAccess(),
  ModelSession? modelSession,
}) {
  final model = TrytonModel('sale.sale',
      session: modelSession, sessionContext: () => session, access: access);
  model.addFields({
    'name': fieldDesc('char', {'strip': true}),
    'state': fieldDesc('selection', {
      'selection': [
        ['draft', 'Draft'],
        ['done', 'Done']
      ],
      'states': jsonEncode({'readonly': equal(eval_('state'), 'done')}),
    }),
    'party': fieldDesc('many2one', {'relation': 'party.party'}),
    'total': fieldDesc('numeric', {'readonly': true}),
    'sale_date': fieldDesc('date'),
    'lines': fieldDesc('one2many', {
      'relation': 'sale.line',
      'relation_field': 'sale',
      'context': jsonEncode({'sale_state': eval_('state')}),
      'views': {
        'tree': {
          'fields': {
            'sale': fieldDesc('many2one', {'relation': 'sale.sale'}),
            'product': fieldDesc('many2one', {'relation': 'product.product'}),
            'quantity': fieldDesc('float'),
            'details': fieldDesc('one2many', {
              'relation': 'sale.line.detail',
              'relation_field': 'line',
              'context': jsonEncode({'line_quantity': eval_('quantity')}),
              'views': {
                'tree': {
                  'fields': {
                    'line': fieldDesc('many2one', {'relation': 'sale.line'}),
                    'note': fieldDesc('char'),
                  }
                }
              },
            }),
          }
        }
      },
    }),
    'tags': fieldDesc('many2many', {'relation': 'sale.tag'}),
    'readonly_lines': fieldDesc('one2many', {
      'relation': 'sale.line',
      'relation_field': 'sale',
      'readonly': true,
      'views': {
        'tree': {
          'fields': {
            'sale': fieldDesc('many2one', {'relation': 'sale.sale'}),
          }
        }
      },
    }),
  });
  return model;
}

/// A saved sale (id 1) with two loaded lines (10, 11), as `read` returns
/// them with `lines.` preloaded values.
Record loadedSale(RecordGroup group) {
  group.load([1]);
  final sale = group.get(1)!;
  sale.set({
    'name': 'S1',
    'state': 'draft',
    'party': 7,
    'party.': {'rec_name': 'Jan'},
    'sale_date': null,
    '_timestamp': '100.0',
    '_write': true,
    '_delete': true,
    'lines': [10, 11],
    'lines.': [
      {
        'id': 10,
        'quantity': 1.0,
        'product': 3,
        'product.': {'rec_name': 'P3'},
        '_timestamp': '110.0'
      },
      {
        'id': 11,
        'quantity': 2.0,
        'product': 4,
        'product.': {'rec_name': 'P4'},
        '_timestamp': '111.0'
      },
    ],
  }, modified: false);
  return sale;
}
