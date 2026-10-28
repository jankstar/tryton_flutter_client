import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/shell/tab_manager.dart';

void main() {
  test('requestCloseTab asks the guards of the tab (topmost first)',
      () async {
    final tabs = TabsNotifier()
      ..openTab(title: 'A', model: 'a')
      ..openTab(title: 'B', model: 'b');
    final id = tabs.state.tabs.first.id;
    final asked = <String>[];
    var answer = false;
    Future<bool> lower() async {
      asked.add('lower');
      return true;
    }

    Future<bool> upper() async {
      asked.add('upper');
      return answer;
    }

    tabs
      ..addCloseGuard(id, lower)
      ..addCloseGuard(id, upper);
    expect(await tabs.requestCloseTab(id), isFalse);
    expect(asked, ['upper'], reason: 'cancelled by the topmost screen');
    expect(tabs.state.tabs, hasLength(2));

    answer = true;
    asked.clear();
    expect(await tabs.requestCloseTab(id), isTrue);
    expect(asked, ['upper', 'lower']);
    expect(tabs.state.tabs.map((t) => t.title), ['B']);

    // Without guards the tab closes at once; removed guards are not asked.
    final b = tabs.state.tabs.single.id;
    tabs
      ..addCloseGuard(b, upper)
      ..removeCloseGuard(b, upper);
    answer = false;
    expect(await tabs.requestCloseTab(b), isTrue);
    expect(tabs.state.tabs, isEmpty);
  });
}
