import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/main.dart' show registerAppLicenses;

/// The licences of the app for showLicensePage ("About" → third-party
/// licences): this client, the Lato font, Tryton's icons. A file of its
/// own: in a file with testWidgets the assets don't load in the stream.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the licences of the app are registered', () async {
    // only the app's entries (the packages' NOTICES are not needed here)
    LicenseRegistry.reset();
    addTearDown(LicenseRegistry.reset);
    registerAppLicenses();
    final packages = <String>{};
    await for (final entry in LicenseRegistry.licenses) {
      packages.addAll(entry.packages);
      expect(entry.paragraphs, isNotEmpty);
    }
    expect(packages, {'tryton_flutter_client', 'Lato font', 'Tryton icons'});
  });
}
