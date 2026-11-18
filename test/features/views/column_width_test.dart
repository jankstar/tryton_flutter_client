import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/features/views/tree_view.dart';

import 'form_harness.dart';

/// Issue #3: column widths of lists like the Python client 8.0
/// (`_set_column_width`, `reset_width`, `save_width`), fit to the content
/// by a double click on the separator, columns moved by their header.
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);
  setUp(clearListCaches);

  const fields = {
    'name': {'type': 'char', 'string': 'Name'},
    'qty': {'type': 'integer', 'string': 'Qty'},
    'state': {
      'type': 'selection',
      'string': 'State',
      'selection': [
        ['a', 'A']
      ]
    },
    'doc': {
      'type': 'reference',
      'string': 'Doc',
      'selection': [
        ['test.x', 'X']
      ]
    },
    'lines': {'type': 'one2many', 'string': 'Lines', 'relation': 'test.x'},
    'tags': {'type': 'many2many', 'string': 'Tags', 'relation': 'test.x'},
    'ok': {'type': 'boolean', 'string': 'OK'},
    'amount': {'type': 'numeric', 'string': 'Amount', 'digits': '[16, 2]'},
    'note': {'type': 'char', 'string': 'Note'},
  };

  FakeFormRpc server(String arch,
          {List<Map<String, dynamic>>? rows,
          Map<String, Object? Function(List<dynamic>)> extra = const {}}) {
    final data = rows ??
        [
          {'id': 1, 'name': 'A', 'note': 'N'}
        ];
    return FakeFormRpc({
      'model.test.line.fields_view_get': (p) =>
          {'type': 'tree', 'view_id': 7, 'arch': arch, 'fields': fields},
      'model.test.line.search': (_) => [for (final r in data) r['id']],
      'model.test.line.search_count': (_) => data.length,
      'model.test.line.read': (p) => [
            for (final id in p[0] as List)
              {...data.firstWhere((r) => r['id'] == id), '_timestamp': '1'}
          ],
      'model.ir.ui.view_tree_width.set_width': (_) => null,
      'model.ir.ui.view_tree_width.reset_width': (_) => null,
      'model.ir.model.search_read': (_) => <dynamic>[],
      'model.ir.model.get_notification': (_) => <String, dynamic>{},
      ...extra,
    });
  }

  Future<void> pumpList(WidgetTester tester, FakeFormRpc rpc) async {
    await pumpScreen(tester, rpc, const ScreenAttributes('test.line', mode: ['tree']),
        settle: false);
    await pumpFrames(tester, 20);
  }

  Finder header(String key) => find.byKey(ValueKey('header-$key'));
  double width(WidgetTester tester, String key) => tester.getSize(header(key)).width;

  /// [text] is shown completely (no ellipsis).
  bool whole(WidgetTester tester, Finder text) =>
      !tester.renderObject<RenderParagraph>(text).didExceedMaxLines;

  testWidgets('initial widths per type: Python × 1.3; the last '
      'column fills the rest', (tester) async {
    await pumpList(
        tester,
        server('<tree><field name="qty"/><field name="state"/>'
            '<field name="doc"/><field name="lines"/><field name="tags"/>'
            '<field name="ok"/><field name="name"/>'
            '<field name="amount" symbol="currency"/>'
            '<button name="go" string="Go"/><field name="note"/></tree>'));
    const f = treeWidthFactor;
    expect(width(tester, 'qty#0'), 80 * f);
    expect(width(tester, 'state#0'), 90 * f);
    expect(width(tester, 'doc#0'), 200 * f);
    expect(width(tester, 'lines#0'), 50 * f);
    expect(width(tester, 'tags#0'), 50 * f);
    expect(width(tester, 'ok#0'), 30 * f);
    expect(width(tester, 'name#0'), 100 * f);
    expect(width(tester, 'amount#0'), (100 + 20) * f, reason: '+20 with symbol');
    expect(width(tester, 'button:8'), 80 * f, reason: 'no field: 80');
    // the last column takes the free width up to the column menu
    expect(width(tester, 'note#0'), greaterThan(100 * f));
    expect(tester.getTopRight(header('note#0')).dx + 36, 1400);
  }, variant: desktop);

  testWidgets('expand takes the rest, the last column keeps its width',
      (tester) async {
    await pumpList(
        tester, server('<tree><field name="name" expand="1"/><field name="note"/></tree>'));
    expect(width(tester, 'note#0'), 100 * treeWidthFactor);
    expect(width(tester, 'name#0'), greaterThan(800));
  }, variant: desktop);

  testWidgets('stored width (width of the view) wins; reset → computed width',
      (tester) async {
    // the server puts the stored ir.ui.view_tree_width into `width`
    final rpc = server('<tree><field name="name" width="210"/><field name="note"/></tree>');
    await pumpList(tester, rpc);
    expect(width(tester, 'name#0'), 210, reason: 'real pixels, no factor');

    await tester.tap(find.byKey(const ValueKey('list-column-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset column widths'));
    await tester.pumpAndSettle();
    expect(width(tester, 'name#0'), 100 * treeWidthFactor);
    expect(rpc.named('model.ir.ui.view_tree_width.reset_width').single.params[0],
        'test.line');
  }, variant: desktop);

  testWidgets('a dragged width wins over the view width for the session',
      (tester) async {
    final rpc = server('<tree><field name="name" width="210"/><field name="note"/></tree>');
    await pumpList(tester, rpc);
    final edge = tester.getTopRight(header('name#0')) + const Offset(-3, 17);
    await tester.dragFrom(edge, const Offset(50, 0));
    await pumpFrames(tester, 5);
    final dragged = width(tester, 'name#0');
    expect(dragged, greaterThan(220), reason: 'dragged by 50 minus the drag slop');
    // a new list of the model in the same session (the server would put the
    // stored width into the view only after a new fields_view_get)
    await tester.pumpWidget(const SizedBox());
    await pumpList(tester, rpc);
    expect(width(tester, 'name#0'), dragged);
  }, variant: desktop);

  testWidgets('double click on the separator: longest content, saved',
      (tester) async {
    final rpc = server('<tree><field name="name"/><field name="note"/></tree>', rows: [
      {'id': 1, 'name': 'Short', 'note': 'x'},
      {'id': 2, 'name': 'A much longer name', 'note': 'y'},
    ]);
    await pumpList(tester, rpc);
    expect(width(tester, 'name#0'), 100 * treeWidthFactor);
    Future<void> doubleClick(String key) async {
      final edge = tester.getTopRight(header(key)) + const Offset(-3, 17);
      await tester.tapAt(edge);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(edge);
      await tester.pumpAndSettle();
    }

    await doubleClick('name#0');
    final fitted = width(tester, 'name#0');
    expect(fitted, greaterThan(100 * treeWidthFactor));
    expect(whole(tester, find.text('A much longer name')), isTrue);
    // not wider than needed: the text plus the padding (2 × 6 and 4)
    expect(fitted - tester.getSize(find.text('A much longer name')).width,
        lessThanOrEqualTo(12 + 4 + 1));
    final call = rpc.named('model.ir.ui.view_tree_width.set_width').single;
    expect(call.params[1], {
      'name': [fitted.round()],
      'note': [null],
    });
  }, variant: desktop);

  testWidgets('double click: the header counts; at most 600 px',
      (tester) async {
    final rpc = server('<tree><field name="ok"/><field name="name"/>'
        '<field name="note"/></tree>', rows: [
      {'id': 1, 'ok': true, 'name': 'x' * 80, 'note': 'y'},
    ]);
    await pumpList(tester, rpc);
    for (final key in ['ok#0', 'name#0']) {
      final edge = tester.getTopRight(header(key)) + const Offset(-3, 17);
      await tester.tapAt(edge);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(edge);
      await tester.pumpAndSettle();
    }
    // boolean (39 px): the header „OK“ needs more
    expect(width(tester, 'ok#0'), greaterThan(30 * treeWidthFactor));
    expect(whole(tester, find.text('OK')), isTrue);
    expect(width(tester, 'name#0'), treeAutoWidthMax);
  }, variant: desktop);

  testWidgets('dragging a header moves the column (for the session)',
      (tester) async {
    final rpc = server('<tree><field name="name"/><field name="qty"/>'
        '<field name="note"/></tree>');
    await pumpList(tester, rpc);
    double left(String key) => tester.getTopLeft(header(key)).dx;
    expect(left('name#0'), lessThan(left('qty#0')));

    final gesture = await tester.startGesture(tester.getCenter(header('qty#0')),
        kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(-15, 0));
      await tester.pump();
    }
    await gesture.moveTo(tester.getCenter(header('name#0')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(left('qty#0'), lessThan(left('name#0')));
    expect(find.text('A'), findsOneWidget);
    // the cells follow the headers
    expect(tester.getTopLeft(find.text('A')).dx, greaterThan(left('name#0')));

    // the order stays for the session, not on the server
    await tester.pumpWidget(const SizedBox());
    await pumpList(tester, rpc);
    expect(left('qty#0'), lessThan(left('name#0')));
    expect(rpc.calls.where((c) => c.method.startsWith('model.ir.ui.view_tree')),
        isEmpty);
  }, variant: desktop);

  testWidgets('a click on the header still sorts', (tester) async {
    final rpc = server('<tree><field name="name"/><field name="note"/></tree>');
    await pumpList(tester, rpc);
    await tester.tap(header('name#0'));
    await pumpFrames(tester, 20);
    expect(rpc.named('model.test.line.search').last.params[3], [
      ['name', 'ASC']
    ]);
  }, variant: desktop);

  for (final dx in [0.0, 2.0, 4.0]) {
    testWidgets('a click with $dx px mouse movement sorts (below '
        '$treeHeaderDragThreshold px)', (tester) async {
      final rpc = server('<tree><field name="name"/><field name="qty"/>'
          '<field name="note"/></tree>');
      await pumpList(tester, rpc);
      final x = tester.getTopLeft(header('name#0')).dx;
      final gesture = await tester.startGesture(tester.getCenter(header('name#0')),
          kind: PointerDeviceKind.mouse);
      await gesture.moveBy(Offset(dx, 0));
      await tester.pump();
      await gesture.up();
      await pumpFrames(tester, 20);
      expect(rpc.named('model.test.line.search').last.params[3], [
        ['name', 'ASC']
      ]);
      expect(tester.getTopLeft(header('name#0')).dx, x, reason: 'not moved');
    }, variant: desktop);
  }

  testWidgets('more than $treeHeaderDragThreshold px drags the column, no sort',
      (tester) async {
    final rpc = server('<tree><field name="name"/><field name="qty"/>'
        '<field name="note"/></tree>');
    await pumpList(tester, rpc);
    final searches = rpc.named('model.test.line.search').length;
    final gesture = await tester.startGesture(tester.getCenter(header('name#0')),
        kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(5, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(header('qty#0')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header('qty#0')).dx,
        lessThan(tester.getTopLeft(header('name#0')).dx));
    expect(rpc.named('model.test.line.search'), hasLength(searches));
  }, variant: desktop);
}
