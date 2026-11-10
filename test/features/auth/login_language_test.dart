import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tryton_flutter_client/app.dart';

/// The language of the login screen is kept for the next start.
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('the saved language is used at the start', (tester) async {
    SharedPreferences.setMockInitialValues({'tryton_login_language': 'de'});
    await tester.pumpWidget(const ProviderScope(child: TrytonFlutterClientApp()));
    await tester.pumpAndSettle();
    expect(find.text('Benutzername'), findsOneWidget);
    expect(find.text('Username'), findsNothing);
  });

  testWidgets('a chosen language is saved', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: TrytonFlutterClientApp()));
    await tester.pumpAndSettle();
    expect(find.text('Username'), findsOneWidget, reason: 'default English');
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deutsch').last);
    await tester.pumpAndSettle();
    expect(find.text('Benutzername'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tryton_login_language'), 'de');
  });
}
