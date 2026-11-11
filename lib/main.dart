import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  registerAppLicenses();
  runApp(const ProviderScope(child: TrytonFlutterClientApp()));
}

/// The licences of the app's own content for `showLicensePage` ("About"
/// → third-party licences): this client (COPYRIGHT), the Lato font (OFL)
/// and Tryton's icons (Apache 2.0).
void registerAppLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (package, asset) in const [
      ('tryton_flutter_client', 'COPYRIGHT'),
      ('Lato font', 'assets/fonts/Lato-OFL.txt'),
      ('Tryton icons', 'assets/icons/tryton/LICENSE'),
    ]) {
      yield LicenseEntryWithLineBreaks(
          [package], await rootBundle.loadString(asset));
    }
  });
}
