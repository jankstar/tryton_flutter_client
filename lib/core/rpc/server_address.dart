import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// The server address of the login (Python client 8.0: `host[:port]`,
// common.get_hostname/get_port, jsonrpc.make_connection): without a
// scheme the port defaults to 8000 and HTTPS is tried before HTTP; the
// scheme that worked is remembered per host:port (Python `known_hosts`).
// With a scheme (`http://…`, `https://…`) the address is taken as given.

/// Port of an address without scheme and port (Python `get_port`).
const defaultServerPort = 8000;

/// Preference key of the remembered schemes (`{host:port: scheme}`).
const knownHostsKey = 'tryton_known_hosts';

/// A server address as entered: [scheme] null when none was given.
class ServerAddress {
  final String? scheme;
  final String host;
  final int port;

  /// Path below the host (reverse proxy), without trailing slash.
  final String path;

  const ServerAddress(this.scheme, this.host, this.port, [this.path = '']);

  /// Parses [input] (`localhost:8000`, `erp.example.com`,
  /// `[::1]:8000`, `https://erp.example.com/tryton`); null when empty or
  /// malformed.
  static ServerAddress? parse(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text);
    if (!hasScheme) text = 'http://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    if (hasScheme && uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return ServerAddress(
      hasScheme ? uri.scheme : null,
      uri.host,
      hasScheme ? uri.port : (uri.hasPort ? uri.port : defaultServerPort),
      path,
    );
  }

  /// `host:port` (IPv6 in brackets): key of the remembered scheme and of
  /// the stored sessions.
  String get hostPort => host.contains(':') ? '[$host]:$port' : '$host:$port';

  /// The URL with [scheme].
  String url(String scheme) => '$scheme://$hostPort$path';

  /// URLs to try in this order: the given scheme, else HTTPS, then HTTP.
  List<String> get candidates =>
      scheme != null ? [url(scheme!)] : [url('https'), url('http')];
}

/// Finds the URL of an address: a given scheme as is; otherwise the first
/// URL [probe] reaches – the remembered scheme first, then HTTPS before
/// HTTP – and remembers its scheme.
class ServerResolver {
  /// Remembered schemes; replaceable in tests.
  final Future<Map<String, String>> Function() load;
  final Future<void> Function(Map<String, String> known) save;

  ServerResolver({
    Future<Map<String, String>> Function()? load,
    Future<void> Function(Map<String, String> known)? save,
  })  : load = load ?? _loadPrefs,
        save = save ?? _savePrefs;

  /// The URL for [input]; [probe] throws when a URL can't be reached.
  /// The error of the last candidate is rethrown.
  Future<String> resolve(
      String input, Future<void> Function(String url) probe) async {
    final address = ServerAddress.parse(input);
    if (address == null) return input.trim();
    if (address.scheme != null) return address.url(address.scheme!);
    final known = await load();
    final remembered = known[address.hostPort];
    // the remembered scheme first; the server may have changed since
    final urls = [
      if (remembered != null) address.url(remembered),
      for (final url in address.candidates)
        if (remembered == null || !url.startsWith('$remembered://')) url,
    ];
    Object? error;
    StackTrace? trace;
    for (final url in urls) {
      try {
        await probe(url);
        final scheme = Uri.parse(url).scheme;
        if (scheme != remembered) {
          await save({...known, address.hostPort: scheme});
        }
        return url;
      } catch (e, s) {
        error = e;
        trace = s;
      }
    }
    Error.throwWithStackTrace(error!, trace!);
  }

  static Future<Map<String, String>> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(knownHostsKey);
      if (raw == null) return {};
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? {for (final e in decoded.entries) '${e.key}': '${e.value}'}
          : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _savePrefs(Map<String, String> known) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(knownHostsKey, jsonEncode(known));
    } catch (_) {}
  }
}
