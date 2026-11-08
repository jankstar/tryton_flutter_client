import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/locale_provider.dart';
import '../../features/model/concurrency.dart';
import '../errors/error_handler.dart' show WarningChoice;

/// The standard dialogs of spec 11.3 (Python `common.message`, `warning`,
/// `userwarning`, `sur`, `sur_3b`, `ask`, `selection`, `concurrency`,
/// `error`). Every dialog kind is unique: while one is open, another call
/// of the same kind returns at once with the "cancel" answer (Python
/// `UniqueDialog.running`).

/// Answer of [showSur3] (Python `sur_3b`: `ok`/`ko`/`cancel`).
enum Sur3Choice { yes, no, cancel }

/// URL of „Report Bug“ (Python `CONFIG['bug.url']`).
const bugTrackerUrl = 'https://bugs.tryton.org/';

/// Dialog kinds shown right now.
final Set<String> _open = {};

/// Kinds of dialogs open now (tests).
@visibleForTesting
Set<String> get openDialogKinds => Set.unmodifiable(_open);

Future<T?> _unique<T>(
    BuildContext context, String kind, WidgetBuilder builder,
    {bool dismissible = true}) async {
  if (!context.mounted || !_open.add(kind)) return null;
  try {
    return await showDialog<T>(
        context: context, barrierDismissible: dismissible, builder: builder);
  } finally {
    _open.remove(kind);
  }
}

Widget _text(String text) => SingleChildScrollView(child: SelectableText(text));

/// Message: information (or an error text) with OK.
Future<void> showMessage(BuildContext context, String message,
        {String? description, IconData icon = Icons.info_outline}) =>
    _unique<void>(
        context,
        'message',
        (ctx) => AlertDialog(
              icon: Icon(icon),
              title: Text(message),
              content: description == null || description.isEmpty
                  ? null
                  : _text(description),
              actions: [
                FilledButton(
                  key: const ValueKey('dialog-ok'),
                  autofocus: true,
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(ctx.l10n.ok),
                ),
              ],
            ));

/// Warning (UserError, invalid record): title [message], text
/// [description], OK.
Future<void> showWarning(BuildContext context, String message,
        [String description = '']) =>
    _unique<void>(
        context,
        'warning',
        (ctx) => AlertDialog(
              icon: const Icon(Icons.warning_amber_rounded),
              title: Text(message),
              content: description.isEmpty ? null : _text(description),
              actions: [
                FilledButton(
                  key: const ValueKey('dialog-ok'),
                  autofocus: true,
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(ctx.l10n.ok),
                ),
              ],
            ));

/// UserWarning (spec 2.6): Always ignore / Cancel / OK; closing = cancel.
Future<WarningChoice> showUserWarning(
    BuildContext context, String message, String description) async {
  final choice = await _unique<WarningChoice>(
      context,
      'userwarning',
      (ctx) => AlertDialog(
            icon: const Icon(Icons.info_outline),
            title: Text(message),
            content: description.isEmpty ? null : _text(description),
            actions: [
              TextButton(
                key: const ValueKey('dialog-always'),
                onPressed: () => Navigator.pop(ctx, WarningChoice.always),
                child: Text(ctx.l10n.alwaysIgnore),
              ),
              TextButton(
                key: const ValueKey('dialog-cancel'),
                onPressed: () => Navigator.pop(ctx, WarningChoice.cancel),
                child: Text(ctx.l10n.cancel),
              ),
              FilledButton(
                key: const ValueKey('dialog-ok'),
                autofocus: true,
                onPressed: () => Navigator.pop(ctx, WarningChoice.ok),
                child: Text(ctx.l10n.ok),
              ),
            ],
          ));
  return choice ?? WarningChoice.cancel;
}

/// Sur (confirmation): OK (or [okLabel]) / Cancel; true = OK.
Future<bool> showSur(BuildContext context, String message,
    {String? title, String? okLabel, bool destructive = false}) async {
  final ok = await _unique<bool>(
      context,
      'sur',
      (ctx) => AlertDialog(
            icon: const Icon(Icons.help_outline),
            title: title == null ? null : Text(title),
            content: Text(message),
            actions: [
              TextButton(
                key: const ValueKey('dialog-cancel'),
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.l10n.cancel),
              ),
              FilledButton(
                key: const ValueKey('dialog-ok'),
                autofocus: true,
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(ctx).colorScheme.error)
                    : null,
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(okLabel ?? ctx.l10n.ok),
              ),
            ],
          ));
  return ok ?? false;
}

/// Sur 3 buttons (save prompt, spec 10.4): Yes / No / Cancel; closing =
/// cancel.
Future<Sur3Choice> showSur3(BuildContext context, String message) async {
  final choice = await _unique<Sur3Choice>(
      context,
      'sur3',
      dismissible: false,
      (ctx) => AlertDialog(
            icon: const Icon(Icons.help_outline),
            content: Text(message),
            actions: [
              TextButton(
                key: const ValueKey('dialog-cancel'),
                onPressed: () => Navigator.pop(ctx, Sur3Choice.cancel),
                child: Text(ctx.l10n.cancel),
              ),
              TextButton(
                key: const ValueKey('dialog-no'),
                onPressed: () => Navigator.pop(ctx, Sur3Choice.no),
                child: Text(ctx.l10n.no),
              ),
              FilledButton(
                key: const ValueKey('dialog-yes'),
                autofocus: true,
                onPressed: () => Navigator.pop(ctx, Sur3Choice.yes),
                child: Text(ctx.l10n.yes),
              ),
            ],
          ));
  return choice ?? Sur3Choice.cancel;
}

/// Ask: a text (masked with [password]); null = cancelled.
Future<String?> showAsk(BuildContext context, String question,
    {bool password = false, String initial = ''}) {
  return _unique<String>(
      context, 'ask', (ctx) => _AskDialog(question, password, initial));
}

class _AskDialog extends StatefulWidget {
  final String question;
  final bool password;
  final String initial;
  const _AskDialog(this.question, this.password, this.initial);

  @override
  State<_AskDialog> createState() => _AskDialogState();
}

class _AskDialogState extends State<_AskDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        icon: const Icon(Icons.help_outline),
        title: Text(widget.question),
        content: TextField(
          key: const ValueKey('dialog-ask'),
          controller: _ctrl,
          autofocus: true,
          obscureText: widget.password,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            key: const ValueKey('dialog-cancel'),
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('dialog-ok'),
            onPressed: () => Navigator.pop(context, _ctrl.text),
            child: Text(context.l10n.ok),
          ),
        ],
      );
}

/// Selection (Python `common.selection`): one of [values] (label →
/// value, sorted by label). No values → null; exactly one → that one
/// without dialog unless [alwaysAsk]; double click / Enter = OK. Returns
/// the chosen entry (label and value) or null.
Future<MapEntry<String, T>?> showSelection<T>(
    BuildContext context, String? title, Map<String, T> values,
    {bool alwaysAsk = false, T? defaultValue}) async {
  if (values.isEmpty) return null;
  if (values.length == 1 && !alwaysAsk) return values.entries.single;
  final entries = values.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return _unique<MapEntry<String, T>>(context, 'selection',
      (ctx) => _SelectionDialog<T>(title, entries, defaultValue));
}

class _SelectionDialog<T> extends StatefulWidget {
  final String? title;
  final List<MapEntry<String, T>> entries;
  final T? defaultValue;
  const _SelectionDialog(this.title, this.entries, this.defaultValue);

  @override
  State<_SelectionDialog<T>> createState() => _SelectionDialogState<T>();
}

class _SelectionDialogState<T> extends State<_SelectionDialog<T>> {
  late int? _selected = () {
    final i = widget.entries.indexWhere((e) => e.value == widget.defaultValue);
    return widget.defaultValue == null || i < 0 ? null : i;
  }();

  DateTime? _lastTap;

  /// A click selects at once; a second click on the same entry within the
  /// double click time is OK (Python row-activated).
  void _tap(int i) {
    final now = DateTime.now();
    final last = _lastTap;
    _lastTap = now;
    if (_selected == i &&
        last != null &&
        now.difference(last) < kDoubleTapTimeout) {
      _ok();
      return;
    }
    setState(() => _selected = i);
  }

  void _ok() {
    final i = _selected;
    Navigator.pop(context, i == null ? null : widget.entries[i]);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter): _ok},
      child: AlertDialog(
        title: Text(l.selectionTitle),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title ?? l.yourSelection),
              const Divider(),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final (i, e) in widget.entries.indexed)
                      ListTile(
                        key: ValueKey('dialog-selection-$i'),
                        dense: true,
                        selected: _selected == i,
                        title: Text(e.key),
                        onTap: () => _tap(i),
                        selectedTileColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withAlpha(90),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('dialog-cancel'),
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('dialog-ok'),
            onPressed: _selected == null ? null : _ok,
            child: Text(l.ok),
          ),
        ],
      ),
    );
  }
}

/// Concurrency (spec 2.6): Cancel (default) / Compare / Write Anyway.
Future<ConcurrencyChoice> showConcurrency(BuildContext context) async {
  final choice = await _unique<ConcurrencyChoice>(
      context,
      'concurrency',
      (ctx) => AlertDialog(
            icon: const Icon(Icons.warning_amber_rounded),
            title: Text(ctx.l10n.concurrencyWarning),
            content: Text(ctx.l10n.concurrencyMessage),
            actions: [
              TextButton(
                key: const ValueKey('dialog-write-anyway'),
                onPressed: () =>
                    Navigator.pop(ctx, ConcurrencyChoice.writeAnyway),
                child: Text(ctx.l10n.writeAnyway),
              ),
              OutlinedButton(
                key: const ValueKey('dialog-compare'),
                onPressed: () => Navigator.pop(ctx, ConcurrencyChoice.compare),
                child: Text(ctx.l10n.compare),
              ),
              // Default action (focused, Enter): Cancel – never overwrite
              // by accident.
              FilledButton(
                key: const ValueKey('dialog-cancel'),
                autofocus: true,
                onPressed: () => Navigator.pop(ctx, ConcurrencyChoice.cancel),
                child: Text(ctx.l10n.cancel),
              ),
            ],
          ));
  return choice ?? ConcurrencyChoice.cancel;
}

/// Error: „Application Error“ with [title], the [details] (traceback)
/// expandable, „Report Bug“ (the bug tracker) and Close.
Future<void> showApplicationError(
        BuildContext context, String title, String details) =>
    _unique<void>(
        context,
        'error',
        (ctx) => AlertDialog(
              icon: Icon(Icons.error_outline,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text(ctx.l10n.applicationError),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(title,
                          style: Theme.of(ctx).textTheme.titleSmall),
                      if (details.trim().isNotEmpty)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(ctx.l10n.details),
                          children: [
                            SelectableText(details,
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 12)),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton.icon(
                  key: const ValueKey('dialog-report-bug'),
                  icon: const Icon(Icons.bug_report_outlined),
                  label: Text(ctx.l10n.reportBug),
                  onPressed: () => launchUrl(Uri.parse(bugTrackerUrl),
                      mode: LaunchMode.externalApplication),
                ),
                FilledButton(
                  key: const ValueKey('dialog-close'),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(ctx.l10n.close),
                ),
              ],
            ));
