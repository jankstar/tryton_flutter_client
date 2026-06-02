import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_provider.dart';
import '../../../core/l10n/locale_provider.dart';
import '../../../l10n/app_localizations.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

const _keyServerUrl = 'login_server_url';
const _keyDatabase  = 'login_database';

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverCtrl = TextEditingController(text: 'http://localhost:8000');
  final _dbCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _mfaCtrl = TextEditingController();

  bool _passwordObscured = true;

  // Locale only for this screen – completely isolated from the app locale.
  Locale _loginLocale = const Locale('en');

  @override
  void initState() {
    super.initState();
    _loadSavedValues();
  }

  Future<void> _loadSavedValues() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_keyServerUrl);
    final db  = prefs.getString(_keyDatabase);
    if (url != null && url.isNotEmpty) _serverCtrl.text = url;
    if (db  != null && db.isNotEmpty)  _dbCtrl.text  = db;
  }

  Future<void> _saveValues() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyServerUrl, _serverCtrl.text.trim());
    await prefs.setString(_keyDatabase,  _dbCtrl.text.trim());
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

    ref.listen(authProvider, (_, next) {
      if (next.status == AuthStatus.authenticated) {
        _saveValues();
        context.go('/models');
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
                            setState(() => _loginLocale = locale),
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
  String _localizeError(String msg, BuildContext ctx) {
    if (msg.startsWith('version_mismatch:')) {
      final parts = msg.split(':');
      if (parts.length == 3) {
        return ctx.l10n.versionMismatch(parts[1], parts[2]);
      }
    }
    return msg;
  }

  void _submit(AuthState auth) {
    if (!_formKey.currentState!.validate()) return;
    ref.read(authProvider.notifier).login(
          _serverCtrl.text.trim(),
          _dbCtrl.text.trim(),
          _userCtrl.text.trim(),
          _passCtrl.text,
        );
  }

  void _submitMfa(AuthState auth) {
    ref
        .read(authProvider.notifier)
        .submitMfaResponse(auth.pendingMfaField!, _mfaCtrl.text);
  }
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

// ─── Server field ─────────────────────────────────────────────────────────────

class _ServerField extends ConsumerWidget {
  final TextEditingController ctrl;
  final AuthState auth;
  const _ServerField({required this.ctrl, required this.auth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: context.l10n.serverUrl,
        prefixIcon: const Icon(Icons.dns_outlined),
        suffixIcon: IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: context.l10n.loadDatabases,
          onPressed: () {
            final dbCtrl = context
                .findAncestorStateOfType<_LoginScreenState>()
                ?._dbCtrl;
            ref.read(authProvider.notifier).loadDatabases(
                  ctrl.text.trim(),
                  dbCtrl?.text.trim() ?? 'tryton',
                );
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
