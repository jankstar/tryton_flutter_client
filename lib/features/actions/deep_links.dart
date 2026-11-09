import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// The `tryton://` links the operating system hands to the app (spec 12.7,
/// E7): the link the app was started with and those arriving later
/// (macOS, iOS: `CFBundleURLTypes`; Android: intent filter). Other schemes
/// are ignored; the same link delivered twice in a row (start link and
/// stream) counts once.
class DeepLinks {
  final Stream<Uri> _links;
  final Future<Uri?> Function() _initial;
  StreamSubscription<Uri>? _subscription;
  String? _last;
  DateTime? _lastAt;

  DeepLinks({Stream<Uri>? links, Future<Uri?> Function()? initial})
      : _links = links ?? _platform().uriLinkStream,
        _initial = initial ?? (() => _platform().getInitialLink());

  static AppLinks? _appLinks;
  static AppLinks _platform() => _appLinks ??= AppLinks();

  /// Calls [onUrl] for every `tryton://` link; errors of the platform
  /// (e.g. no plugin in tests) are ignored.
  Future<void> start(void Function(String url) onUrl) async {
    void handle(Uri? uri) {
      if (uri == null || uri.scheme != 'tryton') return;
      final url = uri.toString();
      final now = DateTime.now();
      if (url == _last &&
          _lastAt != null &&
          now.difference(_lastAt!) < const Duration(seconds: 2)) {
        return;
      }
      _last = url;
      _lastAt = now;
      onUrl(url);
    }

    try {
      _subscription = _links.listen(handle, onError: (Object _) {});
      handle(await _initial());
    } catch (e) {
      debugPrint('deep links not available: $e');
    }
  }

  void dispose() => _subscription?.cancel();
}
