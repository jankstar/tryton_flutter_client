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
import '../shell/app_shell.dart';
import '../shell/tab_manager.dart';
import '../../shared/widgets/toolbar_dropdown_button.dart';
import '../../shared/errors/error_dialogs.dart';
import '../../shared/errors/error_handler.dart';
import '../model/selection_loader.dart';
import 'record_form.dart';
import 'record_widget_values.dart';
import '../../core/l10n/locale_provider.dart';
import '../../shared/utils/date_format_utils.dart';

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
  }

  /// Attachment and note counters (`resources`, without error dialog).
  Future<void> _loadResources() async {
    final record = _record;
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

  Future<void> _showInvalid(String message) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: Text(ctx.l10n.invalidRecordTitle),
          content: SingleChildScrollView(child: Text(message)),
          actions: [
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.l10n.ok),
            ),
          ],
        ),
      );

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.deleteRecord),
        content: Text(context.l10n.reallyDelete),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
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

  /// Shown revision with milliseconds (SAO `%H:%M:%S.%f`).
  static String _revisionText(DateTime dt) =>
      '${formatDateTimeValue(dt)}.${dt.toLocal().millisecond.toString().padLeft(3, '0')}';

  /// Revisions (spec 11.7): `history_revisions(ids)` → choice of a
  /// revision or "Current"; the group gets `_datetime` (+1 ms) and the
  /// records are read again – everything read only in the revision.
  Future<void> _revisions() async {
    if (!await _confirmDiscard() || !mounted) return;
    final record = _record;
    if (record == null || record.id < 0) return;
    final List revisions;
    try {
      revisions = await _screen.model.execute('history_revisions', [
        [record.id]
      ], context: _screen.context) as List? ?? const [];
    } on HandledRpcError {
      return;
    }
    if (!mounted) return;
    final l = context.l10n;
    final choice = await showDialog<Object>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.selectRevision),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'current'),
            child: Text(l.currentRevision),
          ),
          for (final r in revisions)
            if (r is List && r.isNotEmpty && r[0] is DateTime)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, r[0]),
                child: Text('${_revisionText(r[0] as DateTime)}'
                    '${r.length > 2 ? '  ${r[2]}' : ''}'),
              ),
        ],
      ),
    );
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

  Future<void> _viewLogs() async {
    if (_isNew) return;
    ref.read(tabsProvider.notifier).openTab(
      title: 'Logs',
      model: 'ir.model.log',
      initialDomain: [['resource', '=', '$_model,$_recordId']],
    );
  }

  Future<void> _openNote() async {
    if (_isNew) return;
    ref.read(tabsProvider.notifier).openTab(
      title: 'Notes',
      model: 'ir.note',
      initialDomain: [['resource', '=', '$_model,$_recordId']],
    );
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
    final l = context.l10n;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Text(l.recordModified),
        actions: [
          // Cancel – stay in form
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text(l.cancel),
          ),
          // No – discard changes and leave
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'no'),
            child: Text(l.no),
          ),
          // Yes – save and leave
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'yes'),
            child: Text(l.yes),
          ),
        ],
      ),
    );
    if (result == 'cancel' || result == null) return null;
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard()) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Primary title: translated model name when available
            Text(
                _screen.group.revision == null
                    ? _effectiveTitle
                    : '$_effectiveTitle @ ${_revisionText(_screen.group.revision!)}',
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
        ),
        actions: [
          // ── Navigation ────────────────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 16),
            tooltip: context.l10n.previousRecord,
            onPressed: hasPrev ? () => _navigate(next: false) : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 16),
            tooltip: context.l10n.nextRecord,
            onPressed: hasNext ? () => _navigate(next: true) : null,
          ),
          // Switch: like SAO's tryton-switch – the list of the screen
          if (_screen.numberOfViews > 1)
            IconButton(
              icon: TrytonIcon(
                iconName: 'tryton-switch',
                size: 20,
                color: Theme.of(context).colorScheme.primary,
                fallback: Icons.compare_arrows,
              ),
              tooltip: context.l10n.switchView,
              onPressed: _saving ? null : _switchView,
            ),

          // ── CRUD ──────────────────────────────────────────────────────
          // Rights and revision view (spec 10.3, MODELACCESS)
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l.createNew,
            onPressed: _saving || !_screen.canCreate ? null : _newRecord,
          ),
          IconButton(
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            tooltip: l.save,
            onPressed: _saving ||
                    !_screen.canSave(modified: _isDirty || _isNew) ||
                    (_record?.readonly ?? true)
                ? null
                : _save,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l.reload,
            onPressed: _saving ? null : _reload,
          ),
          if (!_isNew) ...[
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: l.duplicate,
              onPressed: _saving || !_screen.canCreate ? null : _duplicate,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: _saving || !_screen.canDelete
                      ? Theme.of(context).disabledColor
                      : Theme.of(context).colorScheme.error),
              tooltip: l.delete,
              onPressed: _saving || !_screen.canDelete ? null : _delete,
            ),
          ],

          // ── Logs / Attachment / Note ──────────────────────────────────
          if (!_isNew) ...[
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: context.l10n.viewLogs,
              onPressed: _viewLogs,
            ),
            // Revisions only for models with history (MODELHISTORY):
            // otherwise the server answers "No history table".
            if (_hasHistory)
              IconButton(
                icon: const Icon(Icons.manage_history),
                tooltip: context.l10n.revisions,
                onPressed: _saving ? null : _revisions,
              ),
            _AttachmentIconButton(
              model: _model,
              recordId: _recordId,
              count: (resources?['attachment_count'] as num?)?.toInt() ?? 0,
            ),
            _NoteIconButton(
              total: (resources?['note_count'] as num?)?.toInt() ?? 0,
              unread: (resources?['note_unread'] as num?)?.toInt() ?? 0,
              onPressed: _openNote,
            ),
          ],

          // ── Action / Relate / Print / Email ──────────────────────────
          // Always shown like in SAO original (disabled when no items).
          if (!_isNew) ...[
            ToolbarDropdownButton(
              screen: _screen,
              icon: Icons.rocket_launch_outlined, // tryton-launch
              tooltip: l.launchActions,
              items: _toolbar.actions,
              model: _model,
              selectedIds: _isNew ? [] : [_recordId],
              beforeExecute: _confirmDiscard,
              buttons: [
                for (final b in buttons)
                  if ((b.keyword ?? 'action') == 'action') b
              ],
              onButton: _executeButton,
            ),
            ToolbarDropdownButton(
              screen: _screen,
              icon: Icons.link,                   // tryton-link
              tooltip: l.relatedRecords,
              items: _toolbar.relate,
              model: _model,
              selectedIds: _isNew ? [] : [_recordId],
              beforeExecute: _confirmDiscard,
              buttons: [
                for (final b in buttons)
                  if ((b.keyword ?? 'action') == 'relate') b
              ],
              onButton: _executeButton,
            ),
            ToolbarDropdownButton(
              screen: _screen,
              icon: Icons.print_outlined,         // tryton-print
              tooltip: l.reports,
              items: _toolbar.print,
              model: _model,
              selectedIds: _isNew ? [] : [_recordId],
              beforeExecute: _confirmDiscard,
              buttons: [
                for (final b in buttons)
                  if ((b.keyword ?? 'action') == 'print') b
              ],
              onButton: _executeButton,
            ),
            ToolbarDropdownButton(
              screen: _screen,
              icon: Icons.email_outlined,         // tryton-email
              tooltip: l.email,
              items: _toolbar.emails,
              model: _model,
              selectedIds: _isNew ? [] : [_recordId],
              beforeExecute: _confirmDiscard,
            ),
          ],

          // ── Close – back to menu ──────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.close),  // tryton-close
            tooltip: context.l10n.close,
            // Tab: asks via the tab's close guard; route: via PopScope.
            onPressed: () => widget.onClose?.call(),
          ),
        ],
      ),
      body: _buildBody(),
    ), // Scaffold
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
    final rootChildren = _formRoot!.children;
    final buttonNodes = rootChildren.whereType<ButtonNode>().toList();
    final contentRoot = buttonNodes.isEmpty
        ? _formRoot!
        : FormRoot(
            col: _formRoot!.col,
            children: rootChildren.where((n) => n is! ButtonNode).toList(),
          );

    final scrollBody = LayoutBuilder(
      builder: (context, constraints) {
        final hPad = (constraints.maxWidth * 0.03).clamp(12.0, 40.0);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 16),
          child: RecordForm(
            // Another record (Prev/Next, New, …): new field states.
            key: ObjectKey(record),
            model: _model,
            root: contentRoot,
            viewDef: _viewDef!,
            record: record,
            onTextChanged: _onTextChanged,
            onBlur: _onFieldBlur,
            onChangedImmediate: _onFieldChangedImmediate,
            isReadOnly: record.readonly,
            onButton: _executeButton,
          ),
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildNotifications(),
        Expanded(child: scrollBody),
        if (buttonNodes.isNotEmpty)
          FormButtonFooter(
            nodes: buttonNodes,
            record: record,
            onButton: _executeButton,
          ),
      ],
    );
  }
}

/// Notes button with badge `unread/total` (spec 10.3; coloured when there
/// are unread notes).
class _NoteIconButton extends StatelessWidget {
  final int total;
  final int unread;
  final VoidCallback onPressed;

  const _NoteIconButton(
      {required this.total, required this.unread, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.sticky_note_2_outlined),
          tooltip: context.l10n.note,
          onPressed: onPressed,
        ),
        if (total > 0)
          Positioned(
            right: 2,
            top: 4,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: unread > 0 ? cs.error : cs.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  unread > 0 ? '$unread/$total' : '$total',
                  style: const TextStyle(color: Colors.white, fontSize: 9),
                ),
              ),
            ),
          ),
      ],
    );
  }
}


// ─── Attachment button with count badge ──────────────────────────────────────

/// Attachment button with count badge and dropdown (Add / Manage)
/// – like SAO's attachment dropdown with Add, Preview, Manage.
class _AttachmentIconButton extends ConsumerWidget {
  final String model;
  final int recordId;
  final int count;

  const _AttachmentIconButton({
    required this.model,
    required this.recordId,
    required this.count,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final badge = count > 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.attach_file),
          tooltip: l.attachments,
          position: PopupMenuPosition.under,
          onSelected: (choice) {
            switch (choice) {
              case 'add':
                pushFormScreen(context,
                    model: 'ir.attachment',
                    recordId: -1,
                    title: 'Add Attachment',
                    screenDomain: const []);
              case 'manage':
                ref.read(tabsProvider.notifier).openTab(
                  title: 'Attachments',
                  model: 'ir.attachment',
                  initialDomain: [
                    ['resource', '=', '$model,$recordId']
                  ],
                );
            }
          },
          itemBuilder: (ctx) => [
            // Header
            PopupMenuItem<String>(
              enabled: false,
              height: 28,
              child: Text(
                '${l.attachments}${badge ? " ($count)" : ""}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
              ),
            ),
            const PopupMenuDivider(height: 1),
            // Add
            PopupMenuItem<String>(
              value: 'add',
              child: Row(children: [
                const Icon(Icons.add, size: 16),
                const SizedBox(width: 8),
                Text('Add'),
              ]),
            ),
            // Manage (always available)
            PopupMenuItem<String>(
              value: 'manage',
              child: Row(children: [
                const Icon(Icons.folder_outlined, size: 16),
                const SizedBox(width: 8),
                Text('Manage${badge ? " ($count)" : ""}'),
              ]),
            ),
          ],
        ),
        // Count badge
        if (badge)
          Positioned(
            right: 4,
            top: 4,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints:
                    const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(color: Colors.white, fontSize: 9),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

