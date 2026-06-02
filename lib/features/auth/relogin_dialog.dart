import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rpc/reauth_service.dart';
import '../../core/l10n/locale_provider.dart';
import 'auth_provider.dart';

/// Compact re-login dialog – shown when the session expires (401).
///
/// Like SAO's Session.renew: only asks for username + password.
/// URL and database are already known and pre-filled.
class ReLoginDialog extends ConsumerStatefulWidget {
  const ReLoginDialog({super.key});

  @override
  ConsumerState<ReLoginDialog> createState() => _ReLoginDialogState();
}

class _ReLoginDialogState extends ConsumerState<ReLoginDialog> {
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final session = ref.read(sessionProvider);
    final login = session.login ?? '';
    final database = session.database ?? '';

    if (login.isEmpty || database.isEmpty) {
      ReAuthService.fail();
      if (mounted) Navigator.of(context).pop();
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      await ref.read(authProvider.notifier).reAuthenticate(
        _passCtrl.text,
      );
      ReAuthService.complete();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.read(sessionProvider);
    final l = context.l10n;

    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.lock_outline, size: 20),
        const SizedBox(width: 8),
        Text(context.l10n.sessionExpired, style: const TextStyle(fontSize: 16)),
      ]),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Info: user + database (pre-filled, not editable)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(children: [
              const Icon(Icons.person_outline, size: 16),
              const SizedBox(width: 8),
              Text(
                '${session.login ?? ""} @ ${session.database ?? ""}',
                style: const TextStyle(fontSize: 13),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          // Password only
          TextField(
            controller: _passCtrl,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l.password,
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12)),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () {
            ReAuthService.fail();
            Navigator.of(context).pop();
          },
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l.signIn),
        ),
      ],
    );
  }
}

/// Shows the re-login dialog modally and waits for completion.
Future<void> showReLoginDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const ReLoginDialog(),
  );
}
