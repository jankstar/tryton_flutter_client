import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/model/model.dart';
import 'package:tryton_flutter_client/core/rpc/error_processing.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_exceptions.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';
import 'package:tryton_flutter_client/core/xml/view_definition.dart';
import 'package:tryton_flutter_client/features/model/model_rpc.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/features/views/record_widget_values.dart';

class _Processor implements RpcErrorProcessor {
  final errors = <Object>[];
  @override
  Future<T> process<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (e) {
      errors.add(e);
      throw HandledRpcError(e);
    }
  }
}

class _FailingRpc extends RpcClient {
  _FailingRpc() : super(baseUrl: 'http://localhost');
  @override
  Future<dynamic> call(String database, String method, List<dynamic> params,
          {bool reAuth = true}) async =>
      throw const UserError('Nein');
}

void main() {
  late TrytonModel model;
  late Record record;

  setUp(() {
    model = TrytonModel('test.w')
      ..addFields({
        'name': {'type': 'char'},
        'party': {'type': 'many2one', 'relation': 'party.party'},
        'flag': {'type': 'boolean'},
        'day': {'type': 'date'},
        'amount': {'type': 'numeric'},
        'lines': {'type': 'one2many', 'relation': 'test.l'},
      });
    record = RecordGroup(model).newRecord();
  });

  test('values in FieldWidget format', () async {
    record.set({
      'name': 'A',
      'party': 7,
      'party.': {'rec_name': 'Jan'},
      'day': const TrytonDate(2024, 5, 17),
      'amount': const TrytonDecimal('1.50'),
    }, modified: false);
    expect(recordWidgetValue(record, 'party'), [7, 'Jan']);
    expect(recordWidgetValue(record, 'name'), 'A');
    expect(recordWidgetValue(record, 'flag'), isFalse);
    expect(recordWidgetValue(record, 'day'), const TrytonDate(2024, 5, 17));
    expect(recordWidgetValue(record, 'lines'), <int>[]);
    expect(recordWidgetValue(record, 'unknown'), isNull);
    final all = recordWidgetValues(record);
    expect(all['party'], [7, 'Jan']);
    expect(all['id'], record.id);
  });

  test('writing goes through setClient (modified, conversions)', () async {
    await setRecordWidgetValue(record, 'party', [8, 'Eva']);
    expect(record.fieldGet('party'), 8);
    expect(record.fieldGetClient('party'), 'Eva');
    expect(record.modifiedFields, contains('party'));
    await setRecordWidgetValue(record, 'party', <dynamic>[]);
    expect(record.fieldGet('party'), isNull);
    await setRecordWidgetValue(record, 'amount', 2.5);
    expect(record.fieldGet('amount'), const TrytonDecimal('2.5'));
    await setRecordWidgetValue(record, 'flag', true);
    expect(record.fieldGet('flag'), isTrue);
  });

  test('ViewDefinition keeps the raw field descriptions', () {
    final view = ViewDefinition.fromJson({
      'arch': '<form/>',
      'fields': {
        'name': {'type': 'char', 'string': 'Name', 'size': 20}
      },
    });
    expect(view.rawFields['name'], {'type': 'char', 'string': 'Name', 'size': 20});
    expect(view.fields['name']!.label, 'Name');
  });

  test('ModelServiceRpc: processor of the form for processException',
      () async {
    final svc = ModelService(
        rpc: _FailingRpc(), getContext: () => {}, getDatabase: () => 'db');
    final processor = _Processor();
    final rpc = ModelServiceRpc(svc, processor: processor);
    await expectLater(rpc.execute('x', 'm', []), throwsA(isA<HandledRpcError>()));
    expect(processor.errors.single, isA<UserError>());
    await expectLater(rpc.execute('x', 'm', [], processException: false),
        throwsA(isA<UserError>()));
    expect(processor.errors, hasLength(1));
  });
}
