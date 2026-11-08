import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart' show Record;
import '../../core/rpc/error_processing.dart';
import '../../core/serialization/tryton_serializer.dart';
import '../../shared/dialogs/tryton_dialogs.dart';
import '../../shared/errors/error_dialogs.dart';
import '../../shared/utils/file_actions.dart';
import '../model/model_service.dart';
import '../model/toolbar_data.dart';
import 'record_richtext.dart';
import 'richtext_html.dart';

/// Email of [record] (spec 11.10, Python `Form.sig_email` + `Email`): the
/// template is chosen from [toolbar] `emails` (always asked; none or
/// cancelled = without template), then the dialog is shown. The caller
/// asks to save first; a record not saved yet has no email.
Future<void> showEmailFlow(
  BuildContext context, {
  required Record record,
  required TrytonToolbar toolbar,
  required String title,
}) async {
  if (record.id < 0) return;
  final l = context.l10n;
  int? template;
  if (toolbar.emails.isNotEmpty) {
    final chosen = await showSelection(
        context, l.emailTemplate, {for (final e in toolbar.emails) e.name: e.id},
        alwaysAsk: true);
    template = chosen?.value;
  }
  if (!context.mounted) return;
  final name = '$title: ${await record.recName()}';
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => EmailDialog(
      name: name,
      record: record,
      reports: [
        for (final p in toolbar.print)
          if (p.type == 'ir.action.report') p
      ],
      template: template,
    ),
  );
}

/// The email dialog (spec 11.10): To/Cc/Bcc with completion
/// (`ir.email.complete`), subject, body as rich text, the reports of the
/// print actions, the attachments of the record and further files; Send
/// calls `ir.email.send`. Prefilled by `ir.email.template.get` /
/// `get_default`.
class EmailDialog extends ConsumerStatefulWidget {
  final String name;
  final Record record;

  /// Print actions of type `ir.action.report` (checkboxes).
  final List<TrytonActionItem> reports;

  /// Id of the `ir.email.template` (null: `get_default`).
  final int? template;

  const EmailDialog({
    super.key,
    required this.name,
    required this.record,
    required this.reports,
    this.template,
  });

  @override
  ConsumerState<EmailDialog> createState() => _EmailDialogState();
}

class _EmailDialogState extends ConsumerState<EmailDialog> {
  final _to = TextEditingController();
  final _cc = TextEditingController();
  final _bcc = TextEditingController();
  final _subject = TextEditingController();
  late final QuillController _body = QuillController.basic();
  final _bodyFocus = FocusNode();
  final _bodyScroll = ScrollController();

  final Set<int> _reports = {};

  /// `[id, rec_name]` of the attachments of the record (with data).
  List<(int, String)> _attachments = const [];
  final Set<int> _selectedAttachments = {};
  final List<PickedFile> _files = [];

  bool _invalidTo = false;
  bool _invalidSubject = false;
  bool _sending = false;

  ModelService get _svc => ref.read(modelServiceProvider);
  Record get _record => widget.record;

  @override
  void initState() {
    super.initState();
    _loadAttachments();
    _fill();
  }

  @override
  void dispose() {
    for (final c in [_to, _cc, _bcc, _subject]) {
      c.dispose();
    }
    _body.dispose();
    _bodyFocus.dispose();
    _bodyScroll.dispose();
    super.dispose();
  }

  /// Attachments with content (Python: `data` or `file_id` set).
  Future<void> _loadAttachments() async {
    try {
      final rows = await _svc.execute<List>(
          'ir.attachment',
          'search_read',
          [
            [
              ['resource', '=', '${_record.model.name},${_record.id}'],
              [
                'OR',
                ['data', '!=', null],
                ['file_id', '!=', null],
              ],
            ],
            0,
            null,
            null,
            ['rec_name'],
          ],
          context: _record.getContext(),
          processException: false);
      if (!mounted) return;
      setState(() => _attachments = [
            for (final r in rows)
              if (r is Map) ((r['id'] as num).toInt(), '${r['rec_name']}')
          ]);
    } catch (_) {
      // without attachments (Python logs the error)
    }
  }

  /// Prefill from the template or the default (Python `_fill_with`).
  Future<void> _fill() async {
    final Map values;
    try {
      values = widget.template != null
          ? await _svc.execute<Map>('ir.email.template', 'get',
              [widget.template, _record.id],
              context: _record.getContext())
          : await _svc.execute<Map>('ir.email.template', 'get_default',
              [_record.model.name, _record.id],
              context: _record.getContext());
    } on HandledRpcError {
      return;
    } catch (e) {
      if (mounted) await showErrorDialog(context, e);
      return;
    }
    if (!mounted) return;
    String join(dynamic v) => v is List ? v.join(', ') : '${v ?? ''}';
    setState(() {
      _to.text = join(values['to']);
      _cc.text = join(values['cc']);
      _bcc.text = join(values['bcc']);
      _subject.text = '${values['subject'] ?? ''}';
      _body.document = Document.fromDelta(htmlToDelta('${values['body'] ?? ''}'));
      _reports
        ..clear()
        ..addAll([
          for (final id in (values['reports'] as List? ?? const []))
            if (id is num) id.toInt()
        ]);
    });
  }

  bool _validate() {
    setState(() {
      _invalidTo = _to.text.trim().isEmpty;
      _invalidSubject = _subject.text.trim().isEmpty;
    });
    return !_invalidTo && !_invalidSubject;
  }

  Future<void> _addFiles() async {
    final files = await FileActions.instance.pick(multiple: true);
    if (files.isNotEmpty && mounted) setState(() => _files.addAll(files));
  }

  /// `ir.email.send(to, cc, bcc, subject, body, files, [model, id],
  /// reports, attachments)`; the dialog stays open on an error.
  Future<void> _send() async {
    if (_sending || !_validate()) return;
    setState(() => _sending = true);
    try {
      await _svc.execute<dynamic>('ir.email', 'send', [
        _to.text,
        _cc.text,
        _bcc.text,
        _subject.text,
        deltaToHtml(_body.document.toDelta()),
        [
          for (final f in _files) [f.name, TrytonBytes(f.bytes)]
        ],
        [_record.model.name, _record.id],
        [
          for (final r in widget.reports)
            if (_reports.contains(r.id)) r.id
        ],
        [
          for (final (id, _) in _attachments)
            if (_selectedAttachments.contains(id)) id
        ],
      ], context: _record.getContext());
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      final sent = context.l10n.emailSent;
      Navigator.pop(context);
      messenger?.showSnackBar(SnackBar(content: Text(sent)));
    } on HandledRpcError {
      // shown
    } catch (e) {
      if (mounted) await showErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    Widget section(String title, Widget child) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Text(title, style: theme.textTheme.titleSmall),
            ),
            child,
          ],
        );
    return AlertDialog(
      title: Text(l.emailTitle(widget.name), overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _EmailEntry(
                key: const ValueKey('email-to'),
                controller: _to,
                label: '${l.emailTo} *',
                invalid: _invalidTo,
              ),
              const SizedBox(height: 8),
              _EmailEntry(
                  key: const ValueKey('email-cc'),
                  controller: _cc,
                  label: l.emailCc),
              const SizedBox(height: 8),
              _EmailEntry(
                  key: const ValueKey('email-bcc'),
                  controller: _bcc,
                  label: l.emailBcc),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('email-subject'),
                controller: _subject,
                decoration: InputDecoration(
                  labelText: '${l.emailSubject} *',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: _invalidSubject ? '' : null,
                ),
              ),
              section(
                l.emailBody,
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      richTextToolbar(_body,
                          key: const ValueKey('email-body-toolbar')),
                      QuillEditor(
                        key: const ValueKey('email-body'),
                        controller: _body,
                        focusNode: _bodyFocus,
                        scrollController: _bodyScroll,
                        config: const QuillEditorConfig(
                          minHeight: 160,
                          padding: EdgeInsets.all(8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.reports.isNotEmpty)
                section(
                  l.emailReports,
                  Wrap(spacing: 8, children: [
                    for (final r in widget.reports)
                      FilterChip(
                        key: ValueKey('email-report-${r.id}'),
                        label: Text(r.name),
                        selected: _reports.contains(r.id),
                        onSelected: (v) => setState(() =>
                            v ? _reports.add(r.id) : _reports.remove(r.id)),
                      ),
                  ]),
                ),
              if (_attachments.isNotEmpty)
                section(
                  l.emailAttachments,
                  Wrap(spacing: 8, children: [
                    for (final (id, name) in _attachments)
                      FilterChip(
                        key: ValueKey('email-attachment-$id'),
                        avatar: const Icon(Icons.attach_file, size: 16),
                        label: Text(name),
                        selected: _selectedAttachments.contains(id),
                        onSelected: (v) => setState(() => v
                            ? _selectedAttachments.add(id)
                            : _selectedAttachments.remove(id)),
                      ),
                  ]),
                ),
              section(
                l.emailFiles,
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final (i, f) in _files.indexed)
                      InputChip(
                        key: ValueKey('email-file-$i'),
                        label: Text(f.name),
                        deleteButtonTooltipMessage: l.emailRemoveFile,
                        onDeleted: () => setState(() => _files.removeAt(i)),
                      ),
                    TextButton.icon(
                      key: const ValueKey('email-add-file'),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(l.emailAddFile),
                      onPressed: _addFiles,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('email-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton.icon(
          key: const ValueKey('email-send'),
          icon: _sending
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send, size: 18),
          label: Text(l.emailSend),
          onPressed: _sending ? null : _send,
        ),
      ],
    );
  }
}

/// An address entry with completion (Python `EmailEntry`):
/// `ir.email.complete(text, limit)` while typing at the end of the text
/// (300 ms delay); a choice replaces the text by the completed list of
/// addresses.
class _EmailEntry extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool invalid;

  const _EmailEntry({
    super.key,
    required this.controller,
    required this.label,
    this.invalid = false,
  });

  @override
  ConsumerState<_EmailEntry> createState() => _EmailEntryState();
}

class _EmailEntryState extends ConsumerState<_EmailEntry> {
  final _focus = FocusNode();
  Timer? _timer;

  /// The delay of the completion asked last (false: replaced by a newer
  /// text).
  Completer<bool>? _waiting;

  /// Number of completions asked for (Python `client.limit`).
  static const _limit = 1000;

  @override
  void dispose() {
    _timer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  /// `[address, addresses]` for [text] (empty on errors, like Python).
  Future<List<(String, String)>> _complete(String text) async {
    final selection = widget.controller.selection;
    if (text.trim().isEmpty ||
        (selection.isValid && selection.baseOffset < text.length - 1)) {
      return const [];
    }
    // the delay of the Python client: only the text typed last is asked
    _timer?.cancel();
    if (!(_waiting?.isCompleted ?? true)) _waiting!.complete(false);
    final waiting = _waiting = Completer<bool>();
    _timer = Timer(const Duration(milliseconds: 300), () => waiting.complete(true));
    if (!await waiting.future || text != widget.controller.text) {
      return const [];
    }
    try {
      final results = await ref.read(modelServiceProvider).execute<List>(
          'ir.email', 'complete', [text, _limit],
          processException: false);
      return [
        for (final r in results)
          if (r is List && r.length >= 3) ('${r[1]}', '${r[2]}')
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<(String, String)>(
      textEditingController: widget.controller,
      focusNode: _focus,
      displayStringForOption: (o) => o.$2,
      optionsBuilder: (value) => _complete(value.text),
      fieldViewBuilder: (context, controller, focus, onSubmitted) => TextField(
        controller: controller,
        focusNode: focus,
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
          isDense: true,
          errorText: widget.invalid ? '' : null,
        ),
        onSubmitted: (_) => onSubmitted(),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 560),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final (i, o) in options.indexed)
                  ListTile(
                    key: ValueKey('email-completion-$i'),
                    dense: true,
                    title: Text(o.$1),
                    onTap: () => onSelected(o),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
