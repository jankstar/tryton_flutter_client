import 'package:flutter/material.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/rpc/rpc_client.dart';
import '../../core/rpc/server_address.dart';
import '../../core/session/profiles.dart';
import '../../core/session/session.dart';

/// Version and databases of a server (Python `DBListEditor`): `version`
/// null = unknown, `databases` null = no connection, empty = list
/// disabled (free text).
typedef ServerProbe = Future<({String? version, List<String>? databases})>
    Function(String serverUrl);

/// `common.server.version` and `common.db.list` against [serverUrl].
/// An address without scheme (`localhost:8000`) is tried with HTTPS,
/// then HTTP, like at the login.
Future<({String? version, List<String>? databases})> probeServer(
    String serverUrl) async {
  final rpc = RpcClient(baseUrl: serverUrl);
  String? version;
  List<String>? databases;
  try {
    final url = await ServerResolver().resolve(serverUrl, (url) async {
      rpc.baseUrl = url;
      version = await rpc.serverVersion();
    });
    rpc.baseUrl = url;
    // an address with scheme is not probed by resolve
    version ??= await rpc.serverVersion();
  } catch (_) {}
  try {
    databases = await rpc.listDatabases();
  } catch (_) {}
  return (version: version, databases: databases);
}

/// The profile editor (spec 3.1, Python `DBListEditor`): the list of the
/// profiles (name, server URL, database, user), New, Rename, Delete; per
/// server the version check and the database list. Returns the edited
/// profiles and the name selected, null when cancelled.
Future<({List<ConnectionProfile> profiles, String? selected})?>
    showProfileEditor(BuildContext context,
        {required List<ConnectionProfile> profiles,
        String? selected,
        ServerProbe probe = probeServer}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProfileEditor(profiles, selected, probe),
  );
}

class _ProfileEditor extends StatefulWidget {
  final List<ConnectionProfile> profiles;
  final String? selected;
  final ServerProbe probe;
  const _ProfileEditor(this.profiles, this.selected, this.probe);

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late List<ConnectionProfile> _profiles = [...widget.profiles];
  late String? _selected = widget.selected ??
      (widget.profiles.isEmpty ? null : widget.profiles.first.name);

  final _name = TextEditingController();
  final _server = TextEditingController();
  final _database = TextEditingController();
  final _login = TextEditingController();
  String? _nameError;

  /// Result of the server check: databases (null: none checked), message.
  List<String>? _databases;
  String? _serverMessage;
  bool _checking = false;

  ConnectionProfile? get _current =>
      _profiles.where((p) => p.name == _selected).firstOrNull;

  @override
  void initState() {
    super.initState();
    _show();
  }

  @override
  void dispose() {
    for (final c in [_name, _server, _database, _login]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The fields of the selected profile.
  void _show() {
    final p = _current;
    _name.text = p?.name ?? '';
    _server.text = p?.serverUrl ?? '';
    _database.text = p?.database ?? '';
    _login.text = p?.login ?? '';
    _nameError = null;
    _databases = null;
    _serverMessage = null;
  }

  /// Takes the fields into the selected profile (not the name: see
  /// [_rename]).
  void _store() {
    final p = _current;
    if (p == null) return;
    _profiles = ProfileStore.put(
        _profiles,
        p.copyWith(
          serverUrl: _server.text.trim(),
          database: _database.text.trim(),
          login: _login.text.trim(),
        ));
  }

  void _select(String name) {
    _store();
    setState(() {
      _selected = name;
      _show();
    });
  }

  void _create() {
    _store();
    final name = ProfileStore.uniqueName(_profiles, context.l10n.newProfile);
    final base = _current;
    setState(() {
      _profiles = [
        ..._profiles,
        ConnectionProfile(name: name, serverUrl: base?.serverUrl ?? ''),
      ];
      _selected = name;
      _show();
    });
  }

  void _delete() {
    final p = _current;
    if (p == null) return;
    setState(() {
      final i = _profiles.indexOf(p);
      _profiles = [..._profiles]..remove(p);
      _selected = _profiles.isEmpty
          ? null
          : _profiles[i.clamp(0, _profiles.length - 1)].name;
      _show();
    });
  }

  /// Renames the selected profile to the text of the name field.
  bool _rename() {
    final from = _selected;
    if (from == null) return true;
    final renamed = ProfileStore.rename(_profiles, from, _name.text);
    if (renamed == null) {
      setState(() => _nameError = context.l10n.profileNameTaken);
      return false;
    }
    setState(() {
      _profiles = renamed;
      _selected = _name.text.trim();
      _nameError = null;
    });
    return true;
  }

  /// Version check and database list of the server (Python
  /// `refresh_databases`).
  Future<void> _check() async {
    final url = _server.text.trim();
    if (url.isEmpty) return;
    final l = context.l10n;
    setState(() => _checking = true);
    final result = await widget.probe(url);
    if (!mounted) return;
    setState(() {
      _checking = false;
      final version = result.version;
      if (version != null &&
          version.isNotEmpty &&
          version.split('.').take(2).join('.') != kClientVersion) {
        _serverMessage = l.incompatibleServer;
        _databases = null;
      } else if (result.databases == null) {
        _serverMessage = l.couldNotConnect;
        _databases = null;
      } else {
        _serverMessage = version == null ? null : 'Tryton $version';
        _databases = result.databases;
        if (_databases!.isNotEmpty && !_databases!.contains(_database.text)) {
          _database.text = _databases!.first;
        }
      }
    });
  }

  void _ok() {
    if (!_rename()) return;
    _store();
    Navigator.pop(context, (profiles: _profiles, selected: _selected));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final current = _current;
    final databases = _databases;
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(4)),
            child: ListView(children: [
              for (final p in _profiles)
                ListTile(
                  key: ValueKey('profile-${p.name}'),
                  dense: true,
                  selected: p.name == _selected,
                  title: Text(p.name),
                  subtitle: Text(
                      [p.login, p.database].where((s) => s.isNotEmpty).join(' @ '),
                      overflow: TextOverflow.ellipsis),
                  onTap: () => _select(p.name),
                ),
            ]),
          ),
        ),
        Row(children: [
          IconButton(
            key: const ValueKey('profile-new'),
            icon: const Icon(Icons.add),
            tooltip: l.newProfile,
            onPressed: _create,
          ),
          IconButton(
            key: const ValueKey('profile-delete'),
            icon: const Icon(Icons.remove),
            tooltip: l.deleteProfile,
            onPressed: current == null ? null : _delete,
          ),
        ]),
      ],
    );
    final fields = current == null
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('profile-name'),
                controller: _name,
                decoration: InputDecoration(
                  labelText: l.profileName,
                  errorText: _nameError,
                  suffixIcon: IconButton(
                    key: const ValueKey('profile-rename'),
                    icon: const Icon(Icons.drive_file_rename_outline),
                    tooltip: l.renameProfile,
                    onPressed: _rename,
                  ),
                ),
                onSubmitted: (_) => _rename(),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('profile-server'),
                controller: _server,
                decoration: InputDecoration(
                  labelText: l.serverUrl,
                  suffixIcon: _checking
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(
                          key: const ValueKey('profile-check'),
                          icon: const Icon(Icons.refresh),
                          tooltip: l.loadDatabases,
                          onPressed: _check,
                        ),
                ),
                onSubmitted: (_) => _check(),
              ),
              if (_serverMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_serverMessage!,
                      key: const ValueKey('profile-server-message'),
                      style: TextStyle(
                          fontSize: 12,
                          color: databases == null ? cs.error : cs.outline)),
                ),
              const SizedBox(height: 12),
              if (databases != null && databases.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: const ValueKey('profile-database-list'),
                  initialValue: databases.contains(_database.text)
                      ? _database.text
                      : databases.first,
                  decoration: InputDecoration(labelText: l.database),
                  items: [
                    for (final db in databases)
                      DropdownMenuItem(value: db, child: Text(db)),
                  ],
                  onChanged: (v) => _database.text = v ?? _database.text,
                )
              else
                TextField(
                  key: const ValueKey('profile-database'),
                  controller: _database,
                  decoration: InputDecoration(labelText: l.database),
                ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('profile-login'),
                controller: _login,
                decoration: InputDecoration(labelText: l.username),
              ),
            ],
          );
    final wide = MediaQuery.sizeOf(context).width >= 640;
    return AlertDialog(
      title: Text(l.profiles),
      content: SizedBox(
        width: wide ? 640 : 360,
        height: wide ? 340 : 560,
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(width: 220, child: list),
                const SizedBox(width: 16),
                Expanded(child: SingleChildScrollView(child: fields)),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(height: 200, child: list),
                const SizedBox(height: 12),
                Expanded(child: SingleChildScrollView(child: fields)),
              ]),
      ),
      actions: [
        TextButton(
          key: const ValueKey('profile-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('profile-ok'),
          onPressed: _ok,
          child: Text(l.ok),
        ),
      ],
    );
  }
}
