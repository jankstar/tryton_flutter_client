import 'package:flutter/material.dart';

import '../../core/l10n/locale_provider.dart';
import '../../features/model/concurrency.dart';

/// SAO-style "Concurrency Warning" dialog: Cancel / Compare / Write Anyway.
/// Cancel is the default (focused) action; dismissing counts as Cancel too.
Future<ConcurrencyChoice> showConcurrencyDialog(BuildContext context) async {
  final l = context.l10n;
  final choice = await showDialog<ConcurrencyChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded),
      title: Text(l.concurrencyWarning),
      content: Text(l.concurrencyMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, ConcurrencyChoice.writeAnyway),
          child: Text(l.writeAnyway),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, ConcurrencyChoice.compare),
          child: Text(l.compare),
        ),
        // Default action (focused, Enter): Cancel – never overwrite by accident.
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.pop(ctx, ConcurrencyChoice.cancel),
          child: Text(l.cancel),
        ),
      ],
    ),
  );
  return choice ?? ConcurrencyChoice.cancel;
}

/// Plain "Concurrency Exception" message (several records involved).
Future<void> showConcurrencyMessage(BuildContext context) {
  final l = context.l10n;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded),
      content: Text(l.concurrencyException),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l.close),
        ),
      ],
    ),
  );
}
