import 'dart:convert';

import '../serialization/tryton_serializer.dart';
import 'screen.dart';

/// `tryton://` URLs (spec 8.9, 12.7; Python `Screen.get_url`,
/// `Main._open_url`): `tryton://<host>[:port]/<db>/<type>/<path>;<params>`
/// with `key=value&…` parameters whose values are URL-encoded JSON with
/// the Tryton type serialisation (2.4).

/// JSON of [value] with the Tryton types (`__class__` markers), compact
/// like Python `json.dumps(separators=(',', ':'))`.
String _dumps(Object? value) => jsonEncode(TrytonSerializer.encode(value));

/// `host[:port]` of [baseUrl] (the port only when the URL names one).
String urlHost(String baseUrl) {
  final uri = Uri.parse(baseUrl);
  return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
}

/// The URL of [screen] (Python `Screen.get_url(name)`): `domain`,
/// `context_domain`, `context` (the local context), `context_model`,
/// `name`; a list adds `tab_domain` and `search_value`, a form the id of
/// the record in the path; `views` with the current view first (form).
String screenUrl(TrytonScreen screen,
    {required String baseUrl, required String database, String name = ''}) {
  final query = <(String, String)>[];
  if (screen.domain.isNotEmpty) query.add(('domain', _dumps(screen.domain)));
  final contextDomain = screen.contextDomain;
  if (contextDomain is String && contextDomain.isNotEmpty) {
    query.add(('context_domain', contextDomain));
  }
  final context = {...screen.localContext}..remove('context_model');
  if (context.isNotEmpty) query.add(('context', _dumps(context)));
  final contextScreen = screen.contextScreen;
  if (contextScreen != null) {
    query.add(('context_model', contextScreen.model.name));
  }
  if (name.isNotEmpty) query.add(('name', _dumps(name)));
  final path = [database, 'model', screen.model.name];
  var viewIds = <int?>[
    for (final v in screen.views) v.viewId,
    ...screen.attributes.viewIds.skip(screen.views.length),
  ];
  final view = screen.currentView;
  final record = screen.currentRecord;
  if (view != null && view.viewType != 'form') {
    if (screen.tabDomain.isNotEmpty) {
      query.add((
        'tab_domain',
        _dumps([
          for (final t in screen.tabDomain) [t.name, t.domain, t.count]
        ])
      ));
    }
    final search = screen.searchValue;
    if (search.isNotEmpty) query.add(('search_value', _dumps(search)));
  } else if (record != null && record.id > -1) {
    path.add('${record.id}');
    final i = view == null ? -1 : screen.views.indexOf(view);
    if (i > 0) viewIds = [...viewIds.sublist(i), ...viewIds.sublist(0, i)];
  }
  final ids = [for (final id in viewIds) ?id];
  if (ids.isNotEmpty) query.add(('views', _dumps(ids)));
  final params = query
      .map((p) =>
          '${Uri.encodeQueryComponent(p.$1)}=${Uri.encodeQueryComponent(p.$2)}')
      .join('&');
  final encodedPath = path.map(Uri.encodeComponent).join('/');
  return 'tryton://${urlHost(baseUrl)}/$encodedPath'
      '${params.isEmpty ? '' : ';$params'}';
}

/// A parsed `tryton://` URL; null fields of [params] are not given.
class TrytonUrl {
  final String host;

  /// The port of the URL (null: none given).
  final int? port;
  final String database;

  /// `model`, `wizard`, `report` or `url`.
  final String type;

  /// The rest of the path (`<model>[/<id>]`, `<wiz_name>`, …).
  final String path;
  final Map<String, String> params;

  const TrytonUrl({
    required this.host,
    this.port,
    required this.database,
    required this.type,
    this.path = '',
    this.params = const {},
  });

  /// `host[:port]/database` for messages.
  String get target => '${port == null ? host : '$host:$port'}/$database';

  /// Parses [url] (Python `_open_url`); null when it is no tryton URL or
  /// malformed.
  static TrytonUrl? parse(String url) {
    url = url.trim();
    if (!url.startsWith('tryton://')) return null;
    final rest = url.substring('tryton://'.length);
    final semicolon = rest.indexOf(';');
    final location = semicolon < 0 ? rest : rest.substring(0, semicolon);
    final query = semicolon < 0 ? '' : rest.substring(semicolon + 1);
    final slash = location.indexOf('/');
    if (slash <= 0) return null;
    final hostPort = location.substring(0, slash);
    final parts = location.substring(slash + 1).split('/');
    if (parts.length < 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
    String host = hostPort;
    int? port;
    final colon = hostPort.lastIndexOf(':');
    if (colon > 0 && !hostPort.endsWith(']')) {
      port = int.tryParse(hostPort.substring(colon + 1));
      if (port == null) return null;
      host = hostPort.substring(0, colon);
    }
    final params = <String, String>{};
    if (query.isNotEmpty) {
      try {
        for (final pair in query.split('&')) {
          if (pair.isEmpty) continue;
          final eq = pair.indexOf('=');
          if (eq <= 0) return null; // Python `strict_parsing`
          params[Uri.decodeQueryComponent(pair.substring(0, eq))] =
              Uri.decodeQueryComponent(pair.substring(eq + 1));
        }
      } on ArgumentError {
        return null;
      } on FormatException {
        return null;
      }
    }
    try {
      return TrytonUrl(
        host: host,
        port: port,
        database: Uri.decodeComponent(parts[0]),
        type: parts[1],
        path: parts.skip(2).map(Uri.decodeComponent).join('/'),
        params: params,
      );
    } on ArgumentError {
      return null;
    }
  }

  /// The JSON value of [key] with the Tryton types, [fallback] when not
  /// given; throws [FormatException] when malformed.
  dynamic value(String key, Object? fallback) {
    final raw = params[key];
    if (raw == null) return fallback;
    return TrytonSerializer.decode(jsonDecode(raw));
  }

  /// Attributes of a `model` URL (Python `open_model`): `views`, `limit`,
  /// `search_value`, `domain`, `context_domain`, `context`,
  /// `context_model`, `tab_domain`; with an id the form first. Null when
  /// a parameter is malformed (ignored silently, spec 12.7).
  ScreenAttributes? modelAttributes() {
    if (type != 'model') return null;
    final segments = path.split('/');
    final model = segments.first;
    if (model.isEmpty) return null;
    try {
      int? id;
      if (segments.length > 1 && segments[1].isNotEmpty) {
        id = int.tryParse(segments[1]);
        if (id == null) return null;
      }
      final views = value('views', const []) as List;
      final limit = value('limit', null);
      final tabs = value('tab_domain', const []) as List;
      return ScreenAttributes(
        model,
        mode: id != null ? const ['form', 'tree'] : const ['tree', 'form'],
        viewIds: [for (final v in views) v as int?],
        limit: limit is int ? limit : 1000,
        searchValue: (value('search_value', const []) as List).isEmpty
            ? null
            : value('search_value', const []) as List,
        domain: value('domain', const []) as List,
        contextDomain: params['context_domain'],
        context: Map<String, dynamic>.from(value('context', const {}) as Map),
        contextModel: params['context_model'],
        tabDomain: [
          for (final t in tabs)
            if (t is List && t.length >= 2)
              TabDomain('${t[0]}', t[1] as List,
                  count: t.length > 2 && t[2] == true),
        ],
        resId: id,
      );
    } catch (_) {
      return null;
    }
  }

  /// `name` of the URL (JSON string), empty when not given or malformed.
  String get name {
    try {
      final n = value('name', '');
      return n is String ? n : '';
    } catch (_) {
      return '';
    }
  }
}
