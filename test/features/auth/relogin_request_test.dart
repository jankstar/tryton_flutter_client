import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tryton_flutter_client/app.dart';
import 'package:tryton_flutter_client/core/rpc/reauth_service.dart';
import 'package:tryton_flutter_client/features/auth/relogin_dialog.dart';

/// HTTP 401 (expired session, `fresh_session` methods like
/// set_preferences): the app asks for the password; cancelling fails the
/// waiting request instead of leaving it hanging.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a re-auth request opens the password dialog', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TrytonFlutterClientApp()));
    await tester.pumpAndSettle();

    Object? error;
    var done = false;
    ReAuthService.requestReAuth().then((_) {
      done = true;
    }, onError: (Object e) {
      error = e;
      done = true;
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ReLoginDialog), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(ReLoginDialog), findsNothing);
    expect(done, isTrue);
    expect(error, isNotNull, reason: 'the request fails (no retry)');
  });
}
