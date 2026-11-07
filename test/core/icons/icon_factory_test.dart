import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/icons/tryton_icon.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';

import '../../features/views/form_harness.dart';

const _svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<path d="M0 0h24v24H0z"/></svg>';

/// Icons like SAO's IconFactory: own icons from the assets, module icons
/// from ir.ui.icon (list_icons, read in batches).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFormRpc rpc;

  setUp(() {
    IconFactory.clear();
    rpc = FakeFormRpc({
      'model.ir.ui.icon.list_icons': (_) => [
            for (var i = 1; i <= 30; i++) [i, 'module-icon-$i']
          ],
      'model.ir.ui.icon.read': (p) => [
            for (final id in p[0] as List)
              {'id': id, 'name': 'module-icon-$id', 'icon': _svg}
          ],
    });
    IconFactory.setService(ModelService(
        rpc: rpc, getContext: () => const {}, getDatabase: () => 'test'));
  });
  tearDown(() {
    IconFactory.clear();
    IconFactory.setService(null);
  });

  test('own icons come from the assets, not from the server', () async {
    expect(localIcons, contains('tryton-ok'));
    expect(localIcons, contains('tryton-switch'));
    await IconFactory.ensure('tryton-ok');
    expect(isIconCached('tryton-ok'), isTrue);
    expect(rpc.calls, isEmpty);
  });

  test('module icon: list_icons once, read of the icon and its neighbours',
      () async {
    await Future.wait([
      IconFactory.ensure('module-icon-15'),
      IconFactory.ensure('module-icon-15'), // shared
    ]);
    expect(rpc.named('model.ir.ui.icon.list_icons'), hasLength(1));
    final read = rpc.named('model.ir.ui.icon.read').single;
    final ids = read.params[0] as List;
    expect(ids, contains(15));
    expect(ids, hasLength(IconFactory.batch));
    expect(read.params[1], ['name', 'icon']);
    // the neighbours are cached now: no further call
    await IconFactory.ensure('module-icon-16');
    expect(rpc.named('model.ir.ui.icon.read'), hasLength(1));
  });

  test('unknown icon: null, Material fallback', () async {
    await IconFactory.ensure('nope');
    expect(isIconCached('nope'), isTrue);
    expect(rpc.named('model.ir.ui.icon.read'), isEmpty);
  });

  testWidgets('TrytonIcon loads module and own icons and shows the SVG',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Row(children: [
        TrytonIcon(iconName: 'module-icon-3', fallback: Icons.play_arrow),
        TrytonIcon(iconName: 'tryton-ok', fallback: Icons.play_arrow),
      ]),
    ));
    expect(find.byType(SvgPicture), findsNothing, reason: 'still loading');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsNWidgets(2));
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });
}
