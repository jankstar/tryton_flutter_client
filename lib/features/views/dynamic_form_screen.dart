import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/model/model.dart';
import '../../core/screen/screen.dart';
import '../../core/rpc/error_processing.dart';
import '../../core/xml/view_definition.dart';
import '../auth/auth_provider.dart';
import '../auth/session_bootstrap.dart';
import '../model/model_service.dart';
import '../model/toolbar_data.dart';
import '../shell/tab_manager.dart';
import '../../shared/widgets/toolbar_dropdown_button.dart';
import '../../shared/dialogs/tryton_dialogs.dart';
import '../../shared/errors/error_dialogs.dart';
import '../../shared/errors/error_handler.dart';
import '../model/selection_loader.dart';
import 'code_scanner.dart';
import 'record_form.dart';
import 'csv_dialogs.dart';
import 'record_menu.dart';
import 'resource_dialogs.dart';
import 'record_widget_values.dart';
import '../../core/l10n/locale_provider.dart';
import 'email_dialog.dart';
import '../actions/url_opener.dart';
import 'chat_panel.dart';

/// Server-driven form – loads the view definition via
/// `fields_view_get` and renders layout, groups and tabs dynamically.
class DynamicFormScreen extends ConsumerStatefulWidget {
  /// The screen; its current view is a form view and the form shows the
  /// screen's current record (spec 8: list and form share group and
  /// record).
  final TrytonScreen screen;
  final String title;

  /// "Close": closes the tab or pops the route.
  final Future<void> Function()? onClose;

  /// After saving a new record the route is popped with its id (form
  /// opened only to create a record, e.g. "Add attachment").
  final bool closeOnSaveNew;

  const DynamicFormScreen({
    super.key,
    required this.screen,
    required this.title,
    this.onClose,
    this.closeOnSaveNew = false,
  });

  @override
  ConsumerState<DynamicFormScreen> createState() => _DynamicFormScreenState();
}


/// Session-level cache: model technical name → translated display name.
/// Populated from ir.model on first access per model.
final _modelDisplayNameCache = <String, String>{};

class _DynamicFormScreenState extends ConsumerState<DynamicFormScreen>
    with TickerProviderStateMixin {
  // View definition from the server
  ViewDefinition? _viewDef;
  FormRoot? _formRoot;
  TrytonToolbar _toolbar = const TrytonToolbar();

  /// Translated model display name loaded from ir.model (e.g. "Base Object").
  String? _modelDisplayName;

  /// The screen's current record (data layer, spec 5.3/5.4). Widgets read
  /// with `field.get/getClient` and write with `field.setClient`; the
  /// screen (listening to its group) triggers a rebuild.
  TrytonScreen get _screen => widget.screen;
  Record? get _record => _screen.currentRecord;
  String get _model => _screen.model.name;

  /// Record the form was prepared for (values loaded, states, side data).
  Record? _shown;

  /// Text input not yet written to the record (written on focus loss, like
  /// SAO's focus-out; flushed before saving).
  final Map<String, dynamic> _pending = {};

  /// `on_change_notify` messages (`[[type, message], …]`), info bar.
  List<dynamic> _notifications = const [];

  /// `resources(id)`: attachment/note counters.
  Map<String, dynamic>? _resources;

  bool _loading = false;
  bool _saving = false;
  String? _error;

  bool get _isNew => (_record?.id ?? -1) < 0;
  int get _recordId => _record?.id ?? -1;
  bool get _isDirty => (_record?.modified ?? false) || _pending.isNotEmpty;

  /// Method-based selections incl. `selection_change_with`, cached per
  /// value combination for the lifetime of this form.
  late final SelectionLoader _selections = SelectionLoader((method, values) =>
      ref
          .read(modelServiceProvider)
          .getSelectionOptions(_model, method, values: values));

  @override
  void initState() {
    super.initState();
    _setup();
  }

  /// Tab of this form and its notifier: closing the tab asks first.
  String? _tabId;
  TabsNotifier? _tabs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabId = TabScope.of(context);
    if (tabId != _tabId) {
      if (_tabId != null) _tabs?.removeCloseGuard(_tabId!, _confirmDiscard);
      _tabId = tabId;
      _tabs = ref.read(tabsProvider.notifier);
      if (tabId != null) _tabs!.addCloseGuard(tabId, _confirmDiscard);
    }
  }

  @override
  void dispose() {
    if (_tabId != null) _tabs?.removeCloseGuard(_tabId!, _confirmDiscard);
    _screen.removeListener(_onScreenChanged);
    super.dispose();
  }

  /// Another current record (Prev/Next, New, Duplicate, Delete) is
  /// prepared; other changes only rebuild.
  void _onScreenChanged() {
    if (!mounted) return;
    if (!identical(_record, _shown)) {
      _showRecord();
    } else {
      setState(() {});
    }
  }

  // ─── Load data ───────────────────────────────────────────────────────────

  /// The form view of the screen; then the current record.
  void _setup() {
    final view = _screen.currentView!;
    _viewDef = view.definition;
    _formRoot = view.formRoot;
    _screen.addListener(_onScreenChanged);
    // Load translated model name early (also cached for subsequent opens)
    if (widget.title == _model) {
      _loadModelDisplayName(ref.read(modelServiceProvider));
    }
    _loadSideData(ref.read(modelServiceProvider));
    _showRecord();
  }

  /// Prepares the current record: all fields loaded, unique values of
  /// the screen domain set and locked (domain_readonly, like SAO's
  /// validation on display), selections for its values, resources.
  Future<void> _showRecord() async {
    final record = _record;
    _shown = record;
    setState(() {
      _pending.clear();
      _notifications = const [];
      _resources = null;
      _error = null;
    });
    _screen.group.onNotify = (notifications) {
      if (mounted) setState(() => _notifications = notifications);
    };
    if (record == null) return;
    setState(() => _loading = !record.getLoaded());
    try {
      await record.load('*');
      record.validate(softValidation: true);
      await record.idle;
      final view = _screen.currentView;
      if (view != null) {
        final viewDef = await _withSelections(view.definition, record);
        if (mounted && identical(_record, record)) {
          setState(() => _viewDef = viewDef);
        }
      }
      _loadResources();
    } on HandledRpcError catch (e) {
      // Already shown by the error dialog; the page keeps a short text.
      if (mounted) setState(() => _error = ErrorHandler.describe(e));
    } catch (e) {
      if (mounted) {
        errorHandlerOf(context, ref).show(e);
        setState(() => _error = ErrorHandler.describe(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// [viewDef] with the options of all method-based selections for the
  /// current values of [record].
  Future<ViewDefinition> _withSelections(
          ViewDefinition viewDef, Record record) =>
      _selections.applyTo(viewDef, recordWidgetValues(record));

  /// Reloads the selections that depend on changed values (cached per
  /// value combination, like SAO's update_selection).
  Future<void> _refreshSelections() async {
    final viewDef = _screen.currentView?.definition;
    final record = _record;
    if (viewDef == null || record == null) return;
    if (!SelectionLoader.hasChangeWith(viewDef)) return;
    final updated = await _withSelections(viewDef, record);
    if (mounted && identical(_record, record)) {
      setState(() => _viewDef = updated);
    }
  }

  Future<void> _loadSideData(ModelService svc) async {
    // Toolbar actions (view_toolbar_get)
    try {
      final t = await svc.viewToolbarGet(_model);
      if (mounted) setState(() => _toolbar = t);
    } catch (_) {}

    // Translated model display name from ir.model (cached per model)
    await _loadModelDisplayName(svc);

    // Chat only for the models of MODELCHAT (spec 14.2)
    final hasChat = await svc.metadata?.hasChat(_model) ?? false;
    if (mounted && hasChat != _hasChat) setState(() => _hasChat = hasChat);
  }

  /// Attachment and note counters (`resources`, without error dialog).
  Future<void> _loadResources() async {
    final record = _record;
    unawaited(_updateResourceRef());
    if (record == null || record.id < 0) return;
    try {
      final resources = await record.getResources(reload: true);
      if (mounted) setState(() => _resources = resources);
    } catch (_) {}
  }

  /// Loads the human-readable, translated model name from ir.model.
  /// Only fetches once per model per session (cached in _modelDisplayNameCache).
  Future<void> _loadModelDisplayName(ModelService svc) async {
    if (_modelDisplayNameCache.containsKey(_model)) {
      if (mounted) {
        setState(() =>
            _modelDisplayName = _modelDisplayNameCache[_model]);
      }
      return;
    }
    try {
      // In Tryton 8.x, ir.model.name IS the technical model name (e.g. "res.user").
      // We search by 'name' and then get the translated rec_name (display name).
      final result = await svc.searchRead(
        'ir.model',
        domain: [['name', '=', _model]],
        fields: ['name', 'rec_name'],
        limit: 1,
      );
      if (result.isNotEmpty) {
        // rec_name is the translated display name; if identical to technical
        // name, it means no translation available → don't bother showing it.
        final displayName = result.first['rec_name']?.toString()
            ?? result.first['name']?.toString()
            ?? '';
        if (displayName.isNotEmpty && displayName != _model) {
          _modelDisplayNameCache[_model] = displayName;
          if (mounted) setState(() => _modelDisplayName = displayName);
          return;
        }
      }
      // No result or name equals technical name → mark as "no display name"
      _modelDisplayNameCache[_model] = '';
    } catch (e) {
      debugPrint('ir.model load error for "$_model": $e');
    }
  }

  /// Returns the best available title for the AppBar.
  /// When the widget title IS the technical model name → use the translated name.
  /// Otherwise the title was set explicitly (e.g. from a menu action) → keep it.
  String get _effectiveTitle {
    final isTechnicalName = widget.title == _model;
    if (isTechnicalName && _modelDisplayName != null && _modelDisplayName!.isNotEmpty) {
      return _modelDisplayName!;
    }
    return widget.title;
  }

  /// Subtitle line below the primary title: model display name (when it
  /// differs from the title) and the position of the record in the
  /// screen (status `3/47`, spec 8.3).
  String get _subtitleText {
    final pos = _screen.loadedCount > 1 ? _screen.statusText : '';
    final showModelName = _modelDisplayName != null &&
        _modelDisplayName!.isNotEmpty &&
        _modelDisplayName != _effectiveTitle;
    if (showModelName && pos.isNotEmpty) return '$_modelDisplayName · $pos';
    if (showModelName) return _modelDisplayName!;
    return pos;
  }

  // ─── Language sync ───────────────────────────────────────────────────────

  /// Called after saving res.user – reloads session context and preferences.
  /// Mirrors what SAO does after preferences are changed:
  /// 1. reload_context() → refreshes session.context incl. language for all RPCs
  /// 2. apply new language to Flutter locale
  /// 3. clear userPreferences cache so name/currency in header chip refreshes
  Future<void> _reloadUserContext() async {
    try {
      // Context, preferences, language, menu and user chip (spec 3.2/3.4).
      await ref.read(sessionBootstrapProvider).reload();
    } catch (_) {}
  }

  // ─── Field changes ───────────────────────────────────────────────────────

  /// Keystroke in a text field: kept until focus loss.
  void _onTextChanged(String name, dynamic value) {
    setState(() => _pending[name] = value);
  }

  /// Focus loss of a text field: the value goes to the record (on_change).
  void _onFieldBlur(String name) {
    if (!_pending.containsKey(name)) return;
    _writeField(name, _pending.remove(name));
  }

  /// Selection, date, many2one, boolean: written at once.
  void _onFieldChangedImmediate(String name, dynamic value) {
    _writeField(name, value);
  }

  /// `setClient` on the record; errors of the on_change chain were shown by
  /// the form's error handler.
  Future<void> _writeField(String name, dynamic value) async {
    final record = _record;
    if (record == null) return;
    try {
      await setRecordWidgetValue(record, name, value);
    } on HandledRpcError {
      // shown
    } catch (e) {
      if (mounted) await errorHandlerOf(context, ref).show(e);
    }
    if (mounted) setState(() {});
    await _refreshSelections();
  }

  /// Writes all pending text input to the record.
  Future<void> _flushPending() async {
    // Focused inputs (also of an inline x2many form) write on focus loss.
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    final record = _record;
    if (record == null) return;
    final pending = Map<String, dynamic>.from(_pending);
    _pending.clear();
    for (final MapEntry(key: name, value: value) in pending.entries) {
      await setRecordWidgetValue(record, name, value);
    }
    await record.idle;
  }

  // ─── Save ────────────────────────────────────────────────────────────────

  InvalidMessages _invalidTexts() {
    final l = context.l10n;
    return InvalidMessages(
      required: l.invalidRequired('%s'),
      domain: l.invalidDomain('%s'),
      children: l.invalidChildren('%s'),
    );
  }

  /// Validates and saves the record (spec 5.4.4/5.5). Returns true when it
  /// was written. Invalid fields block saving and are listed in a dialog;
  /// server errors are shown by the form's error handler.
  Future<bool> _saveRecord() async {
    final record = _record;
    if (record == null) return false;
    try {
      await _flushPending();
      if (!record.validate()) {
        if (mounted) {
          setState(() {});
          await _showInvalid(record.invalidMessage(_invalidTexts()));
        }
        return false;
      }
      if (mounted) setState(() => _saving = true);
      final isUserRecord = _model == 'res.user' &&
          record.id == ref.read(sessionProvider).userId;
      if (!await record.save()) return false;
      // After saving the current user's own record: reload session context
      // so language + name changes take effect immediately everywhere.
      if (isUserRecord) await _reloadUserContext();
      _loadResources();
      return true;
    } on HandledRpcError {
      return false;
    } catch (e) {
      if (mounted) await errorHandlerOf(context, ref).show(e);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Toolbar "Save"; a form opened only to create a record closes
  /// afterwards and returns the new id.
  Future<bool> _save() async {
    final wasNew = _isNew;
    if (!await _saveRecord()) return false;
    if (!mounted) return true;
    if (wasNew) {
      _showSnack(context.l10n.recordCreated);
      if (widget.closeOnSaveNew) Navigator.of(context).pop(_recordId);
    } else {
      _showSnack(context.l10n.saved);
    }
    return true;
  }

  Future<void> _showInvalid(String message) =>
      showWarning(context, context.l10n.invalidRecordTitle, message);

  Future<void> _delete() async {
    final l = context.l10n;
    final ok = await showSur(context, l.reallyDelete,
        title: l.deleteRecord, okLabel: l.delete, destructive: true);
    final record = _record;
    if (ok != true || !mounted || record == null) return;
    try {
      // delete with _timestamp; conflicts go to the A1 dialog
      if (!await _screen.remove(
              delete: true, forceRemove: true, records: [record]) ||
          !mounted) {
        return;
      }
      // Without further record: back to the list or close.
      if (_record == null) {
        if (_screen.numberOfViews > 1) {
          await _screen.switchView(viewType: 'tree');
        } else {
          await widget.onClose?.call();
        }
      }
    } on HandledRpcError {
      // shown
    } catch (e) {
      if (mounted) await errorHandlerOf(context, ref).show(e);
    }
  }

  /// A form button through the screen (spec 8.6: pre-validation,
  /// confirm, instance/class button, result); the dialogs come from the
  /// ScreenWidget's hooks.
  Future<void> _executeButton(ButtonNode node) async {
    if (_record == null) return;
    try {
      await _flushPending();
      await _screen.button(node);
      _loadResources();
    } on HandledRpcError {
      // shown
    } catch (e) {
      if (mounted) await errorHandlerOf(context, ref).show(e);
    }
  }

  /// Discards the local values and reads the record again.
  Future<void> _reloadRecord() async {
    final record = _record;
    if (record == null) return;
    record.cancel();
    _pending.clear();
    try {
      if (record.id < 0) {
        await record.defaultGet();
      } else {
        await record.load('*');
      }
      record.validate(softValidation: true);
    } on HandledRpcError {
      // shown
    }
    if (mounted) setState(() => _notifications = const []);
    _loadResources();
  }

  /// Toolbar "Reload": discards the changes after the save prompt.
  Future<void> _reload() async {
    final answer = await _askSave();
    // "No" has already discarded and read the record again.
    if (answer == null || answer == 'no') return;
    if (mounted) await _reloadRecord();
  }

  /// Copy of the record (`copy`), loaded into the group at
  /// `new_position` and shown (spec 8.5).
  Future<void> _duplicate() async {
    if (_isNew) return;
    if (!await _confirmDiscard() || !mounted) return;
    try {
      await _screen.copy();
    } on HandledRpcError {
      // shown
    } catch (e) {
      if (mounted) await errorHandlerOf(context, ref).show(e);
    }
  }

  /// New record in the screen (defaults, `new_position`).
  Future<void> _newRecord() async {
    if (!await _confirmDiscard() || !mounted) return;
    try {
      await _screen.newRecord();
    } on HandledRpcError {
      // shown
    } catch (e) {
      if (mounted) await errorHandlerOf(context, ref).show(e);
    }
  }

  /// Switch to the list of the screen (same group and record).
  Future<void> _switchView() async {
    if (!await _confirmDiscard() || !mounted) return;
    await _flushPending();
    if (!await _screen.switchView() && mounted) {
      final record = _record;
      if (record != null) {
        await _showInvalid(record.invalidMessage(_invalidTexts()));
      }
    }
  }

  /// Model with history (MODELHISTORY): menu "Revisions…".
  bool get _hasHistory =>
      ref.read(modelServiceProvider).metadata?.hasHistory(_model) ?? false;

  /// Revisions (spec 11.7): `history_revisions(ids)` → choice of a
  /// revision or "Current"; the group gets `_datetime` (+1 ms) and the
  /// records are read again – everything read only in the revision.
  Future<void> _revisions() async {
    if (!await _confirmDiscard() || !mounted) return;
    final record = _record;
    if (record == null || record.id < 0) return;
    final choice = await chooseRevision(context, _screen, [record.id]);
    if (choice == null || !mounted) return;
    _screen.group.revision = choice is DateTime
        ? choice.add(const Duration(milliseconds: 1))
        : null;
    try {
      for (final r in _screen.group) {
        r.cancel();
      }
      await _screen.reload([for (final r in _screen.group) r.id]);
      await record.load('*');
    } on HandledRpcError {
      // shown
    }
    if (mounted) setState(() {});
  }

  /// CSV export (spec 11.9) of the form's records, after the save
  /// prompt (Python `Form.sig_export`).
  Future<void> _exportCsv() async {
    if (!await _confirmDiscard() || !mounted) return;
    await showCsvExport(context, screen: _screen, name: _effectiveTitle);
  }

  /// A predefined export of the print menu (Python `Form.do_export`).
  Future<void> _predefinedExport(Map<String, dynamic> export) async {
    if (!await _confirmDiscard() || !mounted) return;
    await runPredefinedExport(context, _screen, export);
  }

  /// CSV import (spec 11.8) into the model of the form.
  Future<void> _importCsv() async {
    await showCsvImport(context,
        model: _model, importContext: _screen.context, name: _effectiveTitle);
  }

  /// The record for the resource dialogs (attachments, notes, logs).
  ResourceRef? _resourceRef;

  Future<void> _updateResourceRef() async {
    final r = await resourceOf(_isNew ? null : _record);
    if (mounted) setState(() => _resourceRef = r);
  }

  /// Logs (spec 11.6): header and `ir.model.log` of the record.
  Future<void> _viewLogs() async {
    final r = await resourceOf(_isNew ? null : _record);
    if (r == null || !mounted) return;
    try {
      await showLogs(context, ref, r);
    } on HandledRpcError {
      // shown
    } catch (e) {
      if (mounted) await errorHandlerOf(context, ref).show(e);
    }
  }

  /// Notes (spec 11.5): marked as read when closed; counters again.
  Future<void> _openNote() async {
    final r = await resourceOf(_isNew ? null : _record);
    if (r == null || !mounted) return;
    await showNotes(context, r, onChanged: _loadResources);
  }

  /// Shows the SAO-style "This record has been modified" dialog (spec
  /// 10.4) when the screen is modified (changed or new record, pending
  /// input) before switch, navigation, close, new, reload, duplicate and
  /// actions. Returns true if the operation should proceed: "Yes" saved
  /// the record (a failed save stays in the form), "No" discards the
  /// changes (`cancel_current`: a new record is removed, another read
  /// again), "Cancel" stays.
  Future<bool> _confirmDiscard() async => await _askSave() != null;

  /// The save prompt of [_confirmDiscard]: `'clean'` (nothing to ask),
  /// `'yes'` (saved), `'no'` (discarded) or null (cancelled / not saved).
  Future<String?> _askSave() async {
    if (!_screen.modified() && _pending.isEmpty) return 'clean';
    final result = switch (await showSur3(context, context.l10n.recordModified)) {
      Sur3Choice.yes => 'yes',
      Sur3Choice.no => 'no',
      Sur3Choice.cancel => null,
    };
    if (result == null) return null;
    if (result == 'yes') {
      // If save failed or was cancelled, stay in form
      if (!await _saveRecord()) return null;
    } else {
      _pending.clear();
      try {
        await _screen.cancelCurrent();
      } on HandledRpcError {
        // shown
      }
    }
    return result;
  }

  /// Previous/next record of the screen's group (spec 8.5).
  Future<void> _navigate({required bool next}) async {
    if (!await _confirmDiscard() || !mounted) return;
    try {
      next ? await _screen.displayNext() : await _screen.displayPrevious();
    } on HandledRpcError {
      // shown
    }
  }

  // Dropdown buttons opened by the record menu and its shortcuts.
  final _attachKey = GlobalKey();
  final _actionKey = GlobalKey();
  final _relateKey = GlobalKey();
  final _printKey = GlobalKey();
  final _printDirectKey = GlobalKey();
  final _emailKey = GlobalKey();

  /// Email (spec 11.10, Python `Form.sig_email`): save prompt, template,
  /// then the email dialog of the record.
  Future<void> _email() async {
    if (!await _confirmDiscard() || !mounted) return;
    final record = _record;
    if (record == null || record.id < 0) return;
    await showEmailFlow(context,
        record: record, toolbar: _toolbar, title: widget.title);
  }

  /// „Search“ (Python `Form.sig_search`): the searchable view with the
  /// focus in its search entry.
  Future<void> _searchView() async {
    if (!await _confirmDiscard() || !mounted) return;
    await _flushPending();
    _screen.searchFocusRequested = true;
    if (!await _screen.switchView(searchable: true)) {
      _screen.searchFocusRequested = false;
    }
  }

  /// The entries of the record menu and their shortcuts with the
  /// activation of the toolbar buttons (spec 10.3).
  RecordActions _recordActions(List<ButtonNode> buttons) {
    final idle = !_saving;
    final saved = !_isNew;
    List<ButtonNode> keyword(String k) =>
        [for (final b in buttons) if ((b.keyword ?? 'action') == k) b];
    VoidCallback? menu(GlobalKey key, bool active) =>
        idle && active ? () => pressButtonOf(key) : null;
    return {
      RecordAction.switchView:
          idle && _screen.numberOfViews > 1 ? _switchView : null,
      RecordAction.previous:
          idle && _screen.hasPrevious ? () => _navigate(next: false) : null,
      RecordAction.next:
          idle && _screen.hasNext ? () => _navigate(next: true) : null,
      RecordAction.search:
          idle && _screen.numberOfViews > 1 ? _searchView : null,
      RecordAction.newRecord: idle && _screen.canCreate ? _newRecord : null,
      RecordAction.save: idle &&
              _screen.canSave(modified: _isDirty || _isNew) &&
              !(_record?.readonly ?? true)
          ? _save
          : null,
      RecordAction.reload: idle ? _reload : null,
      RecordAction.copy: idle && saved && _screen.canCreate ? _duplicate : null,
      RecordAction.delete: idle && saved && _screen.canDelete ? _delete : null,
      RecordAction.logs: saved ? _viewLogs : null,
      if (_hasHistory) RecordAction.revision: idle && saved ? _revisions : null,
      RecordAction.attach: menu(_attachKey, _resourceRef != null),
      RecordAction.note: saved ? _openNote : null,
      if (_hasChat) RecordAction.chat: saved ? _toggleChat : null,
      RecordAction.action: menu(_actionKey,
          saved && (_toolbar.actions.isNotEmpty || keyword('action').isNotEmpty)),
      RecordAction.relate: menu(_relateKey,
          saved && (_toolbar.relate.isNotEmpty || keyword('relate').isNotEmpty)),
      RecordAction.print: menu(
          _printKey,
          saved && (_toolbar.print.isNotEmpty || keyword('print').isNotEmpty) ||
              _toolbar.exports.isNotEmpty),
      RecordAction.printDirect: menu(_printDirectKey,
          saved && (_toolbar.print.isNotEmpty || keyword('print').isNotEmpty)),
      RecordAction.email: idle && saved ? _email : null,
      RecordAction.export: idle ? _exportCsv : null,
      RecordAction.import: idle && _screen.canCreate ? _importCsv : null,
      RecordAction.copyUrl: () =>
          copyScreenUrl(context, ref, _screen, widget.title),
      RecordAction.close: () => widget.onClose?.call(),
    };
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;

    final buttons = _record == null ? const <ButtonNode>[] : _screen.getButtons();
    final hasPrev = _screen.hasPrevious;
    final hasNext = _screen.hasNext;
    final resources = _resources;
    final actions = _recordActions(buttons);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard()) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: RecordShortcuts(
      actions: actions,
      // the toolbar follows the width of the tab (SAO hidden-xs/-sm)
      child: LayoutBuilder(builder: (context, box) => Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        scrolledUnderElevation: 0,
        // record menu at the title (spec 10.3)
        title: RecordTitleMenu(actions: actions, title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Primary title: translated model name when available
            Text(
                _screen.group.revision == null
                    ? _effectiveTitle
                    : '$_effectiveTitle @ ${revisionText(_screen.group.revision!)}',
                style: const TextStyle(fontSize: 14)),
            // Subtitle: model display name + record position (3 / 47)
            // Show both together, separated by · when both are available.
            if (_subtitleText.isNotEmpty)
              Text(
                _subtitleText,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline),
              ),
          ],
        )),
        // Narrow tabs hide buttons by level (adaptiveToolbar); should the
        // rest still not fit, the actions scroll instead of overflowing
        // and the title keeps a part of the bar.
        actions: [
          // Flexible: also bounded by the space the AppBar really has
          Flexible(child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: (box.maxWidth - toolbarTitleWidth / 2)
                    .clamp(0, double.infinity)),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: adaptiveToolbar(box.maxWidth, [
          // ── Navigation ────────────────────────────────────────────────
          ToolbarSlot(1, IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 16),
            tooltip: context.l10n.previousRecord,
            onPressed: hasPrev ? () => _navigate(next: false) : null,
          )),
          ToolbarSlot(1, IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 16),
            tooltip: context.l10n.nextRecord,
            onPressed: hasNext ? () => _navigate(next: true) : null,
          )),
          // Switch: like SAO's tryton-switch – the list of the screen.
          // All buttons are always shown; their activation is the one of
          // the record menu (spec 10.3, Python `_update_sensitive`).
          ToolbarSlot(0, IconButton(
            icon: TrytonIcon(
              iconName: 'tryton-switch',
              size: 20,
              color: actions[RecordAction.switchView] == null
                  ? Theme.of(context).disabledColor
                  : Theme.of(context).colorScheme.primary,
              fallback: Icons.compare_arrows,
            ),
            tooltip: context.l10n.switchView,
            onPressed: actions[RecordAction.switchView],
          )),

          // ── CRUD ──────────────────────────────────────────────────────
          // Rights and revision view (spec 10.3, MODELACCESS)
          ToolbarSlot(0, IconButton(
            icon: const Icon(Icons.add),
            tooltip: l.createNew,
            onPressed: _saving || !_screen.canCreate ? null : _newRecord,
          )),
          ToolbarSlot(0, IconButton(
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            tooltip: l.save,
            onPressed: _saving ||
                    !_screen.canSave(modified: _isDirty || _isNew) ||
                    (_record?.readonly ?? true)
                ? null
                : _save,
          )),
          ToolbarSlot(0, IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l.reload,
            onPressed: _saving ? null : _reload,
          )),
          ToolbarSlot(3, IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: l.duplicate,
            onPressed: actions[RecordAction.copy],
          )),
          ToolbarSlot(1, IconButton(
            icon: Icon(Icons.delete_outline,
                color: actions[RecordAction.delete] == null
                    ? Theme.of(context).disabledColor
                    : Theme.of(context).colorScheme.error),
            tooltip: l.delete,
            onPressed: actions[RecordAction.delete],
          )),

          // ── Logs / Attachment / Note ──────────────────────────────────
          ToolbarSlot(3, IconButton(
            icon: const Icon(Icons.history),
            tooltip: context.l10n.viewLogs,
            onPressed: actions[RecordAction.logs],
          )),
          // Revisions only for models with history (MODELHISTORY):
          // otherwise the server answers "No history table".
          if (_hasHistory)
            ToolbarSlot(3, IconButton(
              icon: const Icon(Icons.manage_history),
              tooltip: context.l10n.revisions,
              onPressed: actions[RecordAction.revision],
            )),
          ToolbarSlot(1, AttachmentMenuButton(
            key: _attachKey,
            resource: _resourceRef,
            count: (resources?['attachment_count'] as num?)?.toInt() ?? 0,
            onChanged: _loadResources,
            onPreview: () => setState(() => _preview = !_preview),
          )),
          ToolbarSlot(1, NoteIconButton(
            total: (resources?['note_count'] as num?)?.toInt() ?? 0,
            unread: (resources?['note_unread'] as num?)?.toInt() ?? 0,
            onPressed: actions[RecordAction.note],
          )),
          if (_hasChat)
            ToolbarSlot(1, IconButton(
              key: const ValueKey('chat-button'),
              icon: const Icon(Icons.forum_outlined), // tryton-chat
              tooltip: context.l10n.chat,
              isSelected: _chat,
              onPressed: actions[RecordAction.chat],
            )),

          // ── Action / Relate / Print / Email ──────────────────────────
          // Always shown like in SAO original (disabled when not
          // available).
          ...[
            ToolbarSlot(2, ToolbarDropdownButton(
              key: _actionKey,
              screen: _screen,
              icon: Icons.rocket_launch_outlined, // tryton-launch
              tooltip: l.launchActions,
              items: _toolbar.actions,
              model: _model,
              selectedIds: _isNew ? [] : [_recordId],
              enabled: !_isNew && !_saving,
              beforeExecute: _confirmDiscard,
              buttons: [
                for (final b in buttons)
                  if ((b.keyword ?? 'action') == 'action') b
              ],
              onButton: _executeButton,
            )),
            ToolbarSlot(2, ToolbarDropdownButton(
              key: _relateKey,
              screen: _screen,
              icon: Icons.link,                   // tryton-link
              tooltip: l.relatedRecords,
              items: _toolbar.relate,
              model: _model,
              selectedIds: _isNew ? [] : [_recordId],
              enabled: !_isNew && !_saving,
              beforeExecute: _confirmDiscard,
              buttons: [
                for (final b in buttons)
                  if ((b.keyword ?? 'action') == 'relate') b
              ],
              onButton: _executeButton,
            )),
            ToolbarSlot(2, ToolbarDropdownButton(
              key: _printKey,
              screen: _screen,
              icon: Icons.open_in_new,            // tryton-open
              tooltip: l.openReport,
              items: _toolbar.print,
              model: _model,
              selectedIds: _isNew ? [] : [_recordId],
              enabled: !_isNew && !_saving,
              beforeExecute: _confirmDiscard,
              buttons: [
                for (final b in buttons)
                  if ((b.keyword ?? 'action') == 'print') b
              ],
              onButton: _executeButton,
              exports: _toolbar.exports,
              onExport: _predefinedExport,
            )),
            // the same reports straight to the printer (Python „Print“)
            ToolbarSlot(2, ToolbarDropdownButton(
              key: _printDirectKey,
              screen: _screen,
              icon: Icons.print_outlined,         // tryton-print
              tooltip: l.printReport,
              items: _toolbar.print,
              model: _model,
              selectedIds: _isNew ? [] : [_recordId],
              enabled: !_isNew && !_saving,
              beforeExecute: _confirmDiscard,
              buttons: [
                for (final b in buttons)
                  if ((b.keyword ?? 'action') == 'print') b
              ],
              onButton: _executeButton,
              directPrint: true,
            )),
            ToolbarSlot(2, IconButton(
              key: _emailKey,
              icon: const Icon(Icons.email_outlined), // tryton-email
              tooltip: l.email,
              onPressed: actions[RecordAction.email],
            )),
          ],

          // ── Close – back to menu ──────────────────────────────────────
          ToolbarSlot(0, IconButton(
            icon: const Icon(Icons.close),  // tryton-close
            tooltip: context.l10n.close,
            // Tab: asks via the tab's close guard; route: via PopScope.
            onPressed: () => widget.onClose?.call(),
          )),
              ])),
            ),
          )),
        ],
      ),
      body: _withPreview(_buildBody()),
    )), // Scaffold
    ), // RecordShortcuts
    ); // PopScope
  }

  /// Info bar with the `on_change_notify` messages (spec 10.3), above the
  /// form; closable, replaced by each notify.
  Widget _buildNotifications() {
    final cs = Theme.of(context).colorScheme;
    final items = [
      for (final n in _notifications)
        if (n is List && n.length >= 2) (n[0].toString(), n[1].toString())
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    (IconData, Color) style(String type) => switch (type) {
          'warning' => (Icons.warning_amber_rounded, Colors.orange),
          'danger' || 'error' => (Icons.error_outline, cs.error),
          'success' => (Icons.check_circle_outline, Colors.green),
          _ => (Icons.info_outline, cs.primary),
        };
    return Container(
      key: const ValueKey('form-notifications'),
      color: cs.surfaceContainerHigh,
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (type, message) in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Icon(style(type).$1, size: 18, color: style(type).$2),
                      const SizedBox(width: 8),
                      Expanded(child: Text(message)),
                    ]),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: context.l10n.close,
            onPressed: () => setState(() => _notifications = const []),
          ),
        ],
      ),
    );
  }

  /// The attachment preview is shown beside the form (spec 10.5).
  bool _preview = false;

  /// The model has a chat (MODELCHAT) / the chat is shown (spec 14.2).
  bool _hasChat = false;
  bool _chat = false;

  bool get _wide => MediaQuery.sizeOf(context).width >= 900;

  /// `<model>,<id>` of the saved record (chat), else null.
  String? get _chatResource {
    final record = _record;
    return record == null || record.id < 0 ? null : '$_model,${record.id}';
  }

  /// Chat (Python `Form.sig_chat`): the side panel on wide windows, a
  /// bottom sheet on narrow ones (mobile).
  Future<void> _toggleChat() async {
    final resource = _chatResource;
    if (resource == null) return;
    if (_wide) {
      setState(() => _chat = !_chat);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.8,
        child: ChatPanel(
            resource: resource, onClose: () => Navigator.of(ctx).pop()),
      ),
    );
  }

  /// [body] with the side panel (spec 10.5): attachment preview and chat
  /// at the right (wide windows), the preview below the form otherwise.
  Widget _withPreview(Widget body) {
    final resource = _resourceRef;
    final chatResource = _chatResource;
    final wide = _wide;
    final panels = [
      if (_preview && resource != null)
        AttachmentPreviewPanel(
          resource: resource,
          revision: (_resources?['attachment_count'] as num?)?.toInt() ?? 0,
          onClose: () => setState(() => _preview = false),
        ),
      if (_chat && wide && chatResource != null)
        // a new record: another channel (the panel follows `resource`)
        ChatPanel(
          resource: chatResource,
          onClose: () => setState(() => _chat = false),
        ),
    ];
    if (panels.isEmpty) return body;
    return wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: body),
            SizedBox(
              width: 380,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final p in panels) Expanded(child: p)],
              ),
            ),
          ])
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 3, child: body),
            Expanded(flex: 2, child: panels.first),
          ]);
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(_error!),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _showRecord, child: Text(context.l10n.reload)),
        ]),
      );
    }
    final record = _record;
    if (_formRoot == null || _viewDef == null || record == null) {
      return const SizedBox.shrink();
    }

    // Separate root-level buttons from field content so they stay in a
    // sticky footer while only the fields scroll.
    // The buttons of the top level (and of button-only groups there) are
    // in a fixed footer, always visible (spec 9.2.2).
    final split = FormButtonFooter.split(_formRoot!);
    final scrollBody = LayoutBuilder(
      builder: (context, constraints) {
        final hPad = (constraints.maxWidth * 0.03).clamp(12.0, 40.0);
        const vPad = 16.0;
        // the visible height is the form's minimum height: notebook and
        // lists (yexpand) take the rest down to the footer (spec 9.2.2)
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: constraints.hasBoundedHeight
                    ? math.max(0, constraints.maxHeight - 2 * vPad)
                    : 0),
            child: RecordForm(
            // Another record (Prev/Next, New, …): new field states.
            key: ObjectKey(record),
            model: _model,
            root: split.content,
            viewDef: _viewDef!,
            record: record,
            onTextChanged: _onTextChanged,
            onBlur: _onFieldBlur,
            onChangedImmediate: _onFieldChangedImmediate,
            isReadOnly: record.readonly,
            onButton: _executeButton,
          ),
          ),
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildNotifications(),
        Expanded(child: scrollBody),
        // `scan_code` (spec 11.11): submit saves the record
        ScanCodeButton(
          root: _formRoot!,
          record: record,
          readOnly: record.readonly || _saving,
          onSubmit: _save,
        ),
        if (split.buttons.isNotEmpty)
          FormButtonFooter(
            nodes: split.buttons,
            record: record,
            onButton: _executeButton,
          ),
      ],
    );
  }
}

/// Notes button with badge `unread/total` (spec 10.3; coloured when there
/// are unread notes).



