import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/rpc/server_address.dart';
import '../shell/about_dialog.dart' show PrereleaseBadge, isPrerelease;
import '../../shared/dialogs/tryton_dialogs.dart' show showMessage;
import 'auth_provider.dart';
import 'login_errors.dart';
import 'profile_editor.dart';
import '../../../core/session/profiles.dart';
import '../../../core/l10n/locale_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/screen/tryton_url.dart';
import '../actions/url_opener.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}


class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  // the Tryton demo until the saved profile is applied
  final _serverCtrl = TextEditingController(text: demoServer);
  final _dbCtrl = TextEditingController(text: demoDatabase);
  final _userCtrl = TextEditingController(text: demoLogin);
  final _passCtrl = TextEditingController(text: demoPassword);
  final _mfaCtrl = TextEditingController();

  bool _passwordObscured = true;

  // Locale only for this screen – completely isolated from the app locale;
  // kept in `shared_preferences` for the next start.
  Locale _loginLocale = const Locale('en');
  static const _loginLanguageKey = 'tryton_login_language';

  /// Connection profiles (spec 3.1, H6) and the one selected.
  late final ProfileStore _profileStore = ProfileStore(
      storedLogin: () async =>
          (await ref.read(sessionProvider).storedSession())?.login);
  List<ConnectionProfile> _profiles = const [];
  String? _profileName;

  @override
  void initState() {
    super.initState();
    _loadSavedValues().then((_) {
      if (mounted) _restore(_profile);
    });
  }

  /// The profiles (the former settings migrated on the first start) and
  /// the one used last; then the session of that profile is resumed.
  Future<void> _loadSavedValues() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_loginLanguageKey);
    if (code != null && localeNames.containsKey(code) && mounted) {
      setState(() => _loginLocale = Locale(code));
    }
    final profiles = await _profileStore.load();
    final last = await _profileStore.last();
    if (!mounted) return;
    setState(() => _profiles = profiles);
    final profile = _profileForPendingUrl() ??
        profiles.where((p) => p.name == last).firstOrNull ??
        profiles.firstOrNull;
    if (profile != null) _apply(profile);
  }

  /// The language of the login screen, kept for the next start.
  Future<void> _setLoginLocale(Locale locale) async {
    setState(() => _loginLocale = locale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_loginLanguageKey, locale.languageCode);
  }

  /// The profile of a tryton:// link waiting for the login (E7).
  ConnectionProfile? _profileForPendingUrl() {
    final pending = ref.read(pendingTrytonUrlProvider);
    final url = pending == null ? null : TrytonUrl.parse(pending);
    return url == null ? null : profileFor(url, _profiles);
  }

  /// [profile]'s server, database and user in the form.
  void _apply(ConnectionProfile profile) {
    setState(() => _profileName = profile.name);
    _serverCtrl.text = profile.serverUrl;
    _dbCtrl.text = profile.database;
    _userCtrl.text = profile.login;
    // only the public demo gets its (public) password
    _passCtrl.text = profile.serverUrl == demoServer &&
            profile.database == demoDatabase &&
            profile.login == demoLogin
        ? demoPassword
        : '';
  }

  /// The session of [profile] (`login@host:port/db`, A8) is resumed.
  Future<void> _restore(ConnectionProfile? profile) =>
      ref.read(authProvider.notifier).tryRestore(profile?.sessionKeyOrNull);

  ConnectionProfile? get _profile =>
      _profiles.where((p) => p.name == _profileName).firstOrNull;

  /// After a login: the profile keeps the server, database and user
  /// used, and is the one preselected at the next start.
  Future<void> _saveValues() async {
    final current = _profile ??
        ConnectionProfile(
            name: ProfileStore.uniqueName(_profiles, ProfileStore.defaultName));
    final profile = current.copyWith(
      serverUrl: _serverCtrl.text.trim(),
      database: _dbCtrl.text.trim(),
      login: _userCtrl.text.trim(),
    );
    _profiles = ProfileStore.put(_profiles, profile);
    await _profileStore.save(_profiles);
    await _profileStore.setLast(profile.name);
  }

  Future<void> _editProfiles() async {
    final result = await showProfileEditor(context,
        profiles: _profiles, selected: _profileName);
    if (result == null || !mounted) return;
    await _profileStore.save(result.profiles);
    if (!mounted) return;
    setState(() => _profiles = result.profiles);
    final selected =
        result.profiles.where((p) => p.name == result.selected).firstOrNull;
    if (selected != null) {
      _apply(selected);
      await _profileStore.setLast(selected.name);
    }
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _dbCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _mfaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    // a tryton:// link arriving at the login screen: its profile
    ref.listen<String?>(pendingTrytonUrlProvider, (_, url) {
      final profile = _profileForPendingUrl();
      if (url != null && profile != null && profile.name != _profileName) {
        _apply(profile);
        _restore(profile);
      }
    });

    ref.listen(authProvider, (_, next) {
      if (next.status == AuthStatus.authenticated) {
        _saveValues();
        context.go('/app');
      }
    });

    // Localizations.override scopes the login locale to this screen only.
    // The app-wide localeProvider is never read or written here.
    return Localizations.override(
      context: context,
      locale: _loginLocale,
      delegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child: Builder(
        builder: (localizedCtx) => Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _TrytonLogo(),
                      const SizedBox(height: 32),
                      _LanguageSelector(
                        current: _loginLocale,
                        onChanged: (locale) =>
                            _setLoginLocale(locale),
                      ),
                      const SizedBox(height: 12),
                      _ProfileField(
                        profiles: _profiles,
                        selected: _profileName,
                        onChanged: (profile) {
                          _apply(profile);
                          _profileStore.setLast(profile.name);
                          _restore(profile);
                        },
                        onEdit: _editProfiles,
                      ),
                      const SizedBox(height: 12),
                      _ServerField(ctrl: _serverCtrl, auth: auth),
                      const SizedBox(height: 12),
                      _DatabaseField(
                          ctrl: _dbCtrl,
                          auth: auth,
                          serverCtrl: _serverCtrl),
                      const SizedBox(height: 12),
                      if (!auth.needsMfa) ...[
                        TextFormField(
                          controller: _userCtrl,
                          decoration: InputDecoration(
                            labelText: localizedCtx.l10n.username,
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                          validator: (v) =>
                              v!.isEmpty ? localizedCtx.l10n.required : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passCtrl,
                          obscureText: _passwordObscured,
                          decoration: InputDecoration(
                            labelText: localizedCtx.l10n.password,
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_passwordObscured
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setState(
                                  () => _passwordObscured = !_passwordObscured),
                            ),
                          ),
                          validator: (v) =>
                              v!.isEmpty ? localizedCtx.l10n.required : null,
                          onFieldSubmitted: (_) => _submit(auth),
                        ),
                        _ResetPasswordButton(
                            onPressed: () => _resetPassword(localizedCtx)),
                      ] else ...[
                        Text(
                          auth.pendingMfaMessage ??
                              localizedCtx.l10n.additionalInputRequired,
                          style: Theme.of(localizedCtx).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _mfaCtrl,
                          obscureText: auth.pendingMfaType == 'password',
                          decoration: InputDecoration(
                            labelText: auth.pendingMfaField ?? 'Code',
                            prefixIcon: const Icon(Icons.security),
                          ),
                          onFieldSubmitted: (_) => _submitMfa(auth),
                        ),
                        if (auth.pendingMfaType == 'password')
                          _ResetPasswordButton(
                              onPressed: () => _resetPassword(localizedCtx)),
                      ],
                      if (auth.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _localizeError(auth.errorMessage!, localizedCtx),
                          style: TextStyle(
                              color: Theme.of(localizedCtx).colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: auth.status == AuthStatus.loading
                            ? null
                            : () => auth.needsMfa
                                ? _submitMfa(auth)
                                : _submit(auth),
                        child: auth.status == AuthStatus.loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : Text(localizedCtx.l10n.signIn),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Translates structured error codes into localised messages.
  String _localizeError(String msg, BuildContext ctx) =>
      localizeLoginError(msg, ctx.l10n);

  /// „Reset forgotten password“ (Python `AskPasswordDialog`): the server
  /// sends the user an email with a temporary password.
  Future<void> _resetPassword(BuildContext ctx) async {
    final l = ctx.l10n;
    final server = _serverCtrl.text.trim();
    final db = _dbCtrl.text.trim();
    final user = _userCtrl.text.trim();
    if (server.isEmpty || db.isEmpty || user.isEmpty) {
      await showMessage(ctx, l.resetPasswordNeedsUser);
      return;
    }
    String text;
    try {
      await ref.read(authProvider.notifier).resetPassword(server, db, user,
          language: _loginLocale.languageCode);
      text = l.resetPasswordSent;
    } catch (e) {
      text = localizeLoginError(loginErrorCode(e), l);
    }
    if (ctx.mounted) await showMessage(ctx, text);
  }

  void _submit(AuthState auth) {
    if (!_formKey.currentState!.validate()) return;
    ref.read(authProvider.notifier).login(
          _serverCtrl.text.trim(),
          _dbCtrl.text.trim(),
          _userCtrl.text.trim(),
          _passCtrl.text,
          language: _loginLocale.languageCode,
        );
  }

  void _submitMfa(AuthState auth) {
    ref
        .read(authProvider.notifier)
        .submitMfaResponse(auth.pendingMfaField!, _mfaCtrl.text);
  }
}

/// The link „Reset forgotten password“ below the password field.
class _ResetPasswordButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ResetPasswordButton({required this.onPressed});

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Tooltip(
          message: context.l10n.resetPasswordTooltip,
          child: TextButton(
            key: const ValueKey('login-reset-password'),
            onPressed: onPressed,
            child: Text(context.l10n.resetPassword),
          ),
        ),
      );
}

// ─── Logo ─────────────────────────────────────────────────────────────────────

class _TrytonLogo extends StatelessWidget {
  const _TrytonLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.dns_outlined,
            size: 64, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 8),
        Text(
          'Tryton Flutter Client',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        // a test version (tag with suffix) says so before the login
        if (isPrerelease()) ...[
          const SizedBox(height: 6),
          const PrereleaseBadge(),
        ],
      ],
    );
  }
}

// ─── Language selector ────────────────────────────────────────────────────────

class _LanguageSelector extends StatelessWidget {
  final Locale current;
  final ValueChanged<Locale> onChanged;

  const _LanguageSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: current.languageCode,
      decoration: const InputDecoration(
        labelText: 'Language / Sprache',
        prefixIcon: Icon(Icons.language),
      ),
      items: localeNames.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: (code) {
        if (code != null) onChanged(Locale(code));
      },
    );
  }
}

// ─── Profile field ────────────────────────────────────────────────────────────

/// Profile selection (spec 3.1, H6) with „Edit profiles…“.
class _ProfileField extends StatelessWidget {
  final List<ConnectionProfile> profiles;
  final String? selected;
  final ValueChanged<ConnectionProfile> onChanged;
  final VoidCallback onEdit;

  const _ProfileField({
    required this.profiles,
    required this.selected,
    required this.onChanged,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Row(children: [
      Expanded(
        child: DropdownButtonFormField<String>(
          key: ValueKey('login-profile-$selected-${profiles.length}'),
          isExpanded: true,
          initialValue:
              profiles.any((p) => p.name == selected) ? selected : null,
          decoration: InputDecoration(
            labelText: l.profile,
            prefixIcon: const Icon(Icons.bookmarks_outlined),
          ),
          items: [
            for (final p in profiles)
              DropdownMenuItem(value: p.name, child: Text(p.name)),
          ],
          onChanged: (name) {
            final p = profiles.where((p) => p.name == name).firstOrNull;
            if (p != null) onChanged(p);
          },
        ),
      ),
      IconButton(
        key: const ValueKey('login-edit-profiles'),
        icon: const Icon(Icons.edit_note),
        tooltip: l.editProfiles,
        onPressed: onEdit,
      ),
    ]);
  }
}

// ─── Server field ─────────────────────────────────────────────────────────────

class _ServerField extends ConsumerWidget {
  final TextEditingController ctrl;
  final AuthState auth;
  const _ServerField({required this.ctrl, required this.auth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refresh = IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: context.l10n.loadDatabases,
      onPressed: () =>
          ref.read(authProvider.notifier).loadDatabases(ctrl.text.trim()),
    );
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: context.l10n.serverUrl,
        hintText: demoServer,
        prefixIcon: const Icon(Icons.dns_outlined),
        // the server reached for this address: HTTPS or plain HTTP
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: ctrl,
          builder: (context, value, _) {
            final reached = auth.serverUrl;
            final same = reached != null &&
                ServerAddress.parse(value.text)?.hostPort ==
                    ServerAddress.parse(reached)?.hostPort;
            if (!same) return refresh;
            final secure = reached.startsWith('https://');
            final cs = Theme.of(context).colorScheme;
            return Row(mainAxisSize: MainAxisSize.min, children: [
              Tooltip(
                message: secure
                    ? context.l10n.connectionSecure
                    : context.l10n.connectionInsecure,
                child: Icon(
                  secure ? Icons.lock_outline : Icons.lock_open_outlined,
                  key: ValueKey(secure ? 'server-https' : 'server-http'),
                  size: 18,
                  color: secure ? cs.primary : cs.error,
                ),
              ),
              refresh,
            ]);
          },
        ),
      ),
      validator: (v) => v!.isEmpty ? context.l10n.required : null,
    );
  }
}

// ─── Database field ───────────────────────────────────────────────────────────

class _DatabaseField extends ConsumerWidget {
  final TextEditingController ctrl;
  final TextEditingController serverCtrl;
  final AuthState auth;
  const _DatabaseField(
      {required this.ctrl, required this.auth, required this.serverCtrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (auth.databases.isEmpty) {
      return TextFormField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: context.l10n.database,
          prefixIcon: const Icon(Icons.storage_outlined),
        ),
        validator: (v) => v!.isEmpty ? context.l10n.required : null,
      );
    }
    if (ctrl.text.isEmpty && auth.databases.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ctrl.text.isEmpty) ctrl.text = auth.databases.first;
      });
    }
    final currentDb = auth.databases.contains(ctrl.text)
        ? ctrl.text
        : auth.databases.first;
    return DropdownButtonFormField<String>(
      initialValue: currentDb,
      decoration: InputDecoration(
        labelText: context.l10n.database,
        prefixIcon: const Icon(Icons.storage_outlined),
      ),
      items: auth.databases
          .map((db) => DropdownMenuItem(value: db, child: Text(db)))
          .toList(),
      onChanged: (v) => ctrl.text = v ?? ctrl.text,
    );
  }
}
