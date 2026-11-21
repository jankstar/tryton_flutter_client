import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/icons/tryton_icon.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/features/tabs/menu_sidebar.dart';

/// ir.ui.icon of the server: module icons only (here `tryton-list`).
class _Server extends RpcClient {
  _Server() : super(baseUrl: 'http://localhost');
  final domains = <dynamic>[];

  @override
  Future<dynamic> call(String database, String method, List<dynamic> params,
      {bool reAuth = true}) async {
    if (method == 'model.ir.ui.icon.search_read') {
      domains.add(params.first);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return [
        {'id': 1, 'name': 'tryton-list', 'icon': '<svg/>'}
      ];
    }
    return null;
  }
}

/// Menu icons like the Python client: a wizard entry has `tryton-launch`
/// (the propeller SVG shipped with the client), which is not in
/// ir.ui.icon – the menu's preload must not mark it as missing, else the
/// Material fallback is drawn.
void main() {
  // the icon cache is global
  setUp(IconFactory.clear);

  test('rows of a group loading at once share one icon query; loaded '
      'and loading icons are not asked again', () async {
    final rpc = _Server();
    final svc = ModelService(
        rpc: rpc, getContext: () => const {}, getDatabase: () => 'tryton');
    // the menu after the login: every row of the group preloads its icons
    final rows = [
      for (var i = 0; i < 16; i++)
        preloadIconSvgs(svc, {'tryton-party', 'tryton-sale'})
    ];
    // a sub-menu while that query runs: only its new icon is asked
    final sub = preloadIconSvgs(svc, {'tryton-sale', 'tryton-stock'});
    await Future.wait([...rows, sub]);
    expect(rpc.domains, hasLength(2));
    expect('${rpc.domains[0]}',
        allOf(contains('tryton-party'), contains('tryton-sale')));
    expect('${rpc.domains[1]}',
        allOf(contains('tryton-stock'), isNot(contains('tryton-sale'))));
    expect(isIconCached('tryton-party'), isTrue);
    expect(isIconCached('tryton-stock'), isTrue);

    await preloadIconSvgs(svc, {'tryton-party', 'tryton-stock'});
    expect(rpc.domains, hasLength(2), reason: 'all cached');
  });

  testWidgets('the preload asks the server only for module icons; '
      'tryton-launch is drawn from its SVG', (tester) async {
    final rpc = _Server();
    final svc = ModelService(
        rpc: rpc, getContext: () => const {}, getDatabase: () => 'tryton');
    await tester.runAsync(
        () => preloadIconSvgs(svc, {'tryton-launch', 'tryton-list'}));
    expect('${rpc.domains.single}', isNot(contains('tryton-launch')));
    expect(isIconCached('tryton-launch'), isFalse);

    await tester.pumpWidget(const MaterialApp(
      home: Center(child: TrytonIcon(iconName: 'tryton-launch', size: 24)),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.byType(SvgPicture), findsOneWidget,
        reason: 'the propeller SVG, not a Material icon');
    expect(find.byIcon(Icons.launch), findsNothing);
  });
}
