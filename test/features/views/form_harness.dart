import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/features/auth/auth_provider.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/features/views/dynamic_form_screen.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';

/// One recorded RPC call of the form (`model.X.method`, params without the
/// trailing context).
class FormCall {
  final String method;
  final List<dynamic> params;
  final Map<String, dynamic> context;
  FormCall(this.method, this.params, this.context);

  @override
  String toString() => '$method$params';
}

/// RpcClient fake for widget tests: answers with [handlers] (key
/// `model.X.method`), unknown calls give null.
class FakeFormRpc extends RpcClient {
  FakeFormRpc(this.handlers) : super(baseUrl: 'http://localhost');
  final Map<String, Object? Function(List<dynamic> params)> handlers;
  final calls = <FormCall>[];

  List<FormCall> named(String method) =>
      [for (final c in calls) if (c.method == method) c];

  @override
  Future<dynamic> call(String database, String method, List<dynamic> params,
      {bool reAuth = true}) async {
    final args = params.isEmpty ? <dynamic>[] : params.sublist(0, params.length - 1);
    final context = params.isEmpty || params.last is! Map
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(params.last as Map);
    calls.add(FormCall(method, args, context));
    final handler = handlers[method];
    return handler == null ? null : handler(args);
  }
}

/// `fields_view_get` answer for a form.
Map<String, dynamic> formView(String arch, Map<String, dynamic> fields) =>
    {'arch': arch, 'fields': fields, 'view_id': 1, 'type': 'form'};

/// Pumps a DynamicFormScreen on [rpc] (English texts).
Future<void> pumpForm(WidgetTester tester, FakeFormRpc rpc,
    {required String model, required int recordId, bool settle = true}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final svc = ModelService(
      rpc: rpc,
      getContext: () => {'language': 'en'},
      getDatabase: () => 'test');
  await tester.pumpWidget(ProviderScope(
    overrides: [
      rpcClientProvider.overrideWithValue(rpc),
      modelServiceProvider.overrideWithValue(svc),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DynamicFormScreen(model: model, title: 'Form', recordId: recordId),
    ),
  ));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await pumpFrames(tester);
  }
}

/// Fixed number of frames instead of pumpAndSettle (the embedded table's
/// always-visible scrollbar keeps scheduling frames in tests).
Future<void> pumpFrames(WidgetTester tester, [int count = 30]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The TextField of the form field labelled [label] (also the RichText
/// label `label *` of a required field).
Finder textFieldOf(String label) => find
    .ancestor(
        of: find.byWidgetPredicate((w) =>
            (w is Text && w.data == label) ||
            (w is RichText && w.text.toPlainText() == '$label *')),
        matching: find.byType(TextField))
    .first;
