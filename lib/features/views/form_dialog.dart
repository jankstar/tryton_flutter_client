import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart';
import '../../core/rpc/error_processing.dart';
import '../../core/screen/screen.dart';
import '../../core/xml/view_definition.dart';
import '../model/model_service.dart';
import '../model/selection_loader.dart';
import 'record_form.dart';
import 'record_widget_values.dart';
import 'wizard_widget.dart' show wizardInvalidTexts;

/// Form popup (spec 11.1, SAO `Sao.Window.Form`) on [screen]: a new record
/// ([newRecord], with [defaults]) or the current record. With
/// [saveCurrent] the dialog saves itself (many2one open/new), otherwise
/// the record stays in its group (x2many: saved with the parent).
/// [many] allows "… and New" (−1 unlimited, n remaining). [x2many] adds
/// the mini toolbar (Previous/Next, New, Delete, Undelete); there
/// [removeOnDelete] unlinks (many2many) instead of deleting.
///
/// Returns true for OK on a writable record (SAO `callback(result)`).
Future<bool> showFormDialog(
  BuildContext context,
  TrytonScreen screen, {
  bool newRecord = false,
  Map<String, dynamic>? defaults,
  int many = 0,
  bool saveCurrent = false,
  String? title,
  List<String> breadcrumb = const [],
  bool x2many = false,
  bool removeOnDelete = false,
}) async {
  if (screen.currentView?.viewType != 'form') {
    await screen.switchView(viewType: 'form');
  }
  if (newRecord) await screen.newRecord(values: defaults);
  if (!context.mounted || screen.currentView?.viewType != 'form') {
    return false;
  }
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => FormDialog(
      screen: screen,
      newRecord: newRecord,
      many: many,
      saveCurrent: saveCurrent,
      title: title,
      breadcrumb: breadcrumb,
      x2many: x2many,
      removeOnDelete: removeOnDelete,
    ),
  );
  return result ?? false;
}

/// Title with breadcrumb: the last two levels before the title,
/// `… › ` when there are more (SAO `Window.Form`).
String breadcrumbTitle(List<String> breadcrumb, String? title) {
  final parts = [...breadcrumb, if (title != null && title.isNotEmpty) title];
  if (parts.isEmpty) return '';
  String short(String s) => s.length > 30 ? '${s.substring(0, 29)}…' : s;
  final start = math.max(0, parts.length - 3);
  final shown = [
    for (var i = start; i < parts.length - 1; i++) short(parts[i]),
    parts.last,
  ].join(' › ');
  return parts.length > 3 ? '… › $shown' : shown;
}

class FormDialog extends ConsumerStatefulWidget {
  final TrytonScreen screen;
  final bool newRecord;
  final int many;
  final bool saveCurrent;
  final String? title;
  final List<String> breadcrumb;
  final bool x2many;
  final bool removeOnDelete;

  const FormDialog({
    super.key,
    required this.screen,
    this.newRecord = false,
    this.many = 0,
    this.saveCurrent = false,
    this.title,
    this.breadcrumb = const [],
    this.x2many = false,
    this.removeOnDelete = false,
  });

  @override
  ConsumerState<FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends ConsumerState<FormDialog> {
  final Map<String, dynamic> _pending = {};
  ViewDefinition? _viewDef;
  SelectionLoader? _selections;
  Record? _record;
  String? _message;
  bool _busy = false;
  late int _many = widget.many;

  TrytonScreen get _screen => widget.screen;
  bool get _readonly => _screen.group.readonly;

  @override
  void initState() {
    super.initState();
    _screen.addListener(_onChanged);
    _onChanged();
  }

  @override
  void dispose() {
    _screen.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final record = _screen.currentRecord;
    if (!identical(record, _record)) {
      _record = record;
      _pending.clear();
      _viewDef = null;
      _loadRecord();
    }
    if (mounted) setState(() {});
  }

  /// All fields of the record and the options of method-based selections.
  Future<void> _loadRecord() async {
    final record = _record;
    final view = _screen.currentView;
    if (record == null || view == null) return;
    try {
      await record.load('*');
    } on HandledRpcError {
      // shown
    }
    if (!view.definition.fields.values.any(SelectionLoader.isDynamic)) {
      return;
    }
    final svc = ref.read(modelServiceProvider);
    final model = _screen.model.name;
    final loader = _selections ??= SelectionLoader((method, values) =>
        svc.getSelectionOptions(model, method, values: values));
    final viewDef =
        await loader.applyTo(view.definition, recordWidgetValues(record));
    if (mounted && identical(_record, record)) {
      setState(() => _viewDef = viewDef);
    }
  }

  Future<void> _write(String name, dynamic value) async {
    final record = _record;
    if (record == null) return;
    try {
      await setRecordWidgetValue(record, name, value);
    } on HandledRpcError {
      // shown
    }
    if (!mounted) return;
    setState(() {});
    final view = _screen.currentView;
    if (view != null && SelectionLoader.hasChangeWith(view.definition)) {
      final viewDef = await _selections?.applyTo(
          view.definition, recordWidgetValues(record));
      if (mounted && viewDef != null) setState(() => _viewDef = viewDef);
    }
  }

  Future<void> _flushPending() async {
    final record = _record;
    if (record == null) return;
    final pending = Map<String, dynamic>.from(_pending);
    _pending.clear();
    for (final MapEntry(key: name, value: value) in pending.entries) {
      await setRecordWidgetValue(record, name, value);
    }
    await record.idle;
  }

  /// Valid record of the view, else the message in the info bar.
  bool _validate() {
    final record = _record;
    if (record == null || _readonly) return true;
    if (record.validate(fields: _screen.currentView?.fields)) {
      _message = null;
      return true;
    }
    setState(() => _message = record.invalidMessage(wizardInvalidTexts(context)));
    return false;
  }

  /// OK / "… and New" (SAO `response(RESPONSE_OK/ACCEPT)`).
  Future<void> _accept({bool andNew = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _flushPending();
      if (!mounted) return;
      if (_readonly || _record == null) {
        Navigator.of(context).pop(false);
        return;
      }
      if (!_validate()) return;
      if (widget.saveCurrent && !await _screen.saveCurrent()) return;
      if (!mounted) return;
      if (andNew) {
        await _screen.newRecord();
        _many -= 1;
      } else {
        Navigator.of(context).pop(true);
      }
    } on HandledRpcError {
      // shown; the dialog stays
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Cancel / Delete / Discard changes: a new record is removed, changes
  /// are discarded (a record added to the group keeps its mark).
  Future<void> _cancel() async {
    if (_busy) return;
    final record = _record;
    if (!_readonly && record != null) {
      _pending.clear();
      final added = record.modifiedFields.contains('id');
      try {
        if (record.id < 0 || widget.saveCurrent) {
          await _screen.cancelCurrent();
        } else if (record.modified) {
          record.cancel();
          await record.load('*');
        }
      } on HandledRpcError {
        // shown
      }
      if (added && !record.destroyed) record.modifiedFields.add('id');
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  Future<void> _navigate({required bool next}) async {
    await _flushPending();
    if (!mounted || !_validate()) return;
    next ? await _screen.displayNext() : await _screen.displayPrevious();
  }

  Future<void> _newInGroup() async {
    await _flushPending();
    if (!mounted || !_validate()) return;
    await _screen.newRecord();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final record = _record;
    final view = _screen.currentView;
    final size = MediaQuery.sizeOf(context);
    final title = breadcrumbTitle(widget.breadcrumb, widget.title);

    final Widget body = record == null || view?.formRoot == null
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: RecordForm(
              key: ObjectKey(record),
              model: _screen.model.name,
              root: view!.formRoot!,
              viewDef: _viewDef ?? view.definition,
              record: record,
              onTextChanged: (name, value) => _pending[name] = value,
              onBlur: (name) {
                if (_pending.containsKey(name)) {
                  _write(name, _pending.remove(name));
                }
              },
              onChangedImmediate: _write,
              isReadOnly: _readonly || record.readonly || record.deleted ||
                  record.removed,
            ),
          );

    final String okLabel;
    if (widget.saveCurrent && !_readonly) {
      okLabel = l.save;
    } else if (_readonly) {
      okLabel = l.close;
    } else if (widget.newRecord) {
      okLabel = l.add;
    } else {
      okLabel = l.applyChanges;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _cancel,
        },
        child: Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            width: math.min(size.width * 0.9, 960),
            height: size.height * 0.85,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                if (widget.x2many) _buildToolbar(),
                if (_message != null)
                  Container(
                    key: const ValueKey('form-dialog-invalid'),
                    color: cs.errorContainer,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(_message!,
                        style: TextStyle(color: cs.onErrorContainer)),
                  ),
                Expanded(child: body),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (!_readonly)
                        TextButton(
                          onPressed: _busy ? null : _cancel,
                          child: Text(
                              widget.newRecord ? l.delete : l.discardChanges),
                        ),
                      if (widget.newRecord && widget.many != 0)
                        OutlinedButton(
                          onPressed: _busy || _many == 0
                              ? null
                              : () => _accept(andNew: true),
                          child: Text(widget.saveCurrent && !_readonly
                              ? l.saveAndNew
                              : l.addAndNew),
                        ),
                      FilledButton(
                        onPressed: _busy ? null : _accept,
                        child: Text(okLabel),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// x2many mini toolbar: Previous/Next with position, New, Delete,
  /// Undelete (spec 11.1).
  Widget _buildToolbar() {
    final l = context.l10n;
    final record = _record;
    final group = _screen.group;
    final index = record == null ? -1 : group.indexOf(record);
    final marked = record != null && (record.deleted || record.removed);
    final readonly = _readonly;
    Widget button(IconData icon, String tip, VoidCallback? onPressed) =>
        IconButton(
          icon: Icon(icon, size: 18),
          tooltip: tip,
          onPressed: _busy ? null : onPressed,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        button(Icons.arrow_back_ios, l.previousRecord,
            index > 0 ? () => _navigate(next: false) : null),
        Text(index < 0 ? '_/${group.length}' : '${index + 1}/${group.length}',
            style: const TextStyle(fontSize: 12)),
        button(Icons.arrow_forward_ios, l.nextRecord,
            index >= 0 && index < group.length - 1
                ? () => _navigate(next: true)
                : null),
        const SizedBox(width: 8),
        button(Icons.add, l.createNew,
            readonly || _many == 0 && widget.many != 0 ? null : _newInGroup),
        button(widget.removeOnDelete ? Icons.link_off : Icons.delete_outline,
            widget.removeOnDelete ? l.remove : l.delete,
            readonly || record == null || marked
                ? null
                : () => _screen.remove(
                    records: [record], remove: widget.removeOnDelete)),
        button(Icons.restore_from_trash_outlined, l.undelete,
            readonly || !marked ? null : _screen.unremove),
      ]),
    );
  }
}
