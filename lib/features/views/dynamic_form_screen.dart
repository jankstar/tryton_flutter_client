import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/model/model.dart';
import '../../core/rpc/error_processing.dart';
import '../../core/xml/form_xml_parser.dart';
import '../../core/xml/view_definition.dart';
import '../model/field_definition.dart';
import '../auth/auth_provider.dart';
import '../auth/user_preferences_provider.dart';
import '../model/model_service.dart';
import '../model/toolbar_data.dart';
import '../shell/app_shell.dart';
import '../shell/tab_manager.dart';
import '../../shared/widgets/toolbar_dropdown_button.dart';
import '../../shared/errors/error_dialogs.dart';
import '../../shared/errors/error_handler.dart';
import '../../shared/widgets/concurrency_dialog.dart';
import '../model/concurrency.dart';
import '../model/field_support.dart';
import '../model/model_rpc.dart';
import '../model/selection_loader.dart';
import 'navigation_context.dart';
import 'record_form.dart';
import 'record_widget_values.dart';
import '../../core/l10n/locale_provider.dart';

/// Server-driven form – loads the view definition via
/// `fields_view_get` and renders layout, groups and tabs dynamically.
class DynamicFormScreen extends ConsumerStatefulWidget {
  final String model;
  final String title;
  final int recordId; // < 0 for new records
  /// Domain from the action that opened this form (screen domain).
  /// Used for domain_readonly evaluation, like SAO's record.group.domain.
  final List<dynamic> screenDomain;

  const DynamicFormScreen({
    super.key,
    required this.model,
    required this.title,
    required this.recordId,
    this.screenDomain = const [],
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

  /// The record of this form and its group (data layer, spec 5.3/5.4).
  /// Widgets read with `field.get/getClient` and write with
  /// `field.setClient`; the group's ChangeNotifier triggers a rebuild.
  RecordGroup? _group;
  Record? _record;

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

  bool get _isNew => (_record?.id ?? widget.recordId) < 0;
  int get _recordId => _record?.id ?? widget.recordId;
  bool get _isDirty => (_record?.modified ?? false) || _pending.isNotEmpty;

  /// Method-based selections incl. `selection_change_with`, cached per
  /// value combination for the lifetime of this form.
  late final SelectionLoader _selections = SelectionLoader((method, values) =>
      ref
          .read(modelServiceProvider)
          .getSelectionOptions(widget.model, method, values: values));

  @override
  void initState() {
    super.initState();
    _load();
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
    _group?.removeListener(_onGroupChanged);
    super.dispose();
  }

  void _onGroupChanged() {
    if (mounted) setState(() {});
  }

  // ─── Load data ───────────────────────────────────────────────────────────

  /// Data-layer session of this form: errors of the record's server calls
  /// go to this form's error dialogs, conflicts to the A1 dialog.
  ModelSession _modelSession(ModelService svc) => modelSessionFor(
        svc,
        processor: errorHandlerOf(context, ref),
        concurrencyRunner: concurrencyRunner(
          ask: () async => mounted
              ? showConcurrencyDialog(context)
              : ConcurrencyChoice.cancel,
          onCompare: (_, _) => _openCompareTab(),
          onMessage: () async {
            if (mounted) await showConcurrencyMessage(context);
          },
        ),
      );

  /// View attributes of the `<field>` nodes extend the field description
  /// (SAO `field_attrs`): readonly/required/invisible from the XML.
  static void _applyViewAttributes(TrytonModel model, List<FormNode> nodes) {
    for (final node in nodes) {
      switch (node) {
        case FieldNode():
          final desc = model.fields[node.name]?.description;
          if (desc == null) continue;
          if (node.readonly != null) desc['readonly'] = node.readonly;
          if (node.required != null) desc['required'] = node.required;
          if (node.invisible != null) desc['invisible'] = node.invisible;
        case GroupNode():
          _applyViewAttributes(model, node.children);
        case NotebookNode():
          _applyViewAttributes(model, node.pages);
        case PageNode():
          _applyViewAttributes(model, node.children);
        default:
          break;
      }
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final svc = ref.read(modelServiceProvider);

      // Load translated model name early (also cached for subsequent opens)
      // Do this first so it's available as soon as possible.
      if (widget.title == widget.model) {
        _loadModelDisplayName(svc); // fire-and-forget, updates via setState
      }

      // 1. Load view definition
      final rawViewDef = await svc.fieldsViewGet(widget.model, viewType: 'form');
      final formRoot = FormXmlParser().parse(rawViewDef.arch);

      // 2. Model, group and record of the data layer
      if (!mounted) return;
      final model = TrytonModel(widget.model, session: _modelSession(svc))
        ..addFields(rawViewDef.rawFields);
      _applyViewAttributes(model, formRoot.children);
      // Fields without an own widget (E13) are never written: as readonly
      // they are left out of create/write (Record.get).
      for (final name in unsupportedFieldNames(rawViewDef.fields, formRoot)) {
        model.fields[name]?.description['readonly'] = true;
      }
      final group = RecordGroup(model);
      if (widget.screenDomain.isNotEmpty) {
        group.screenDomains.add(widget.screenDomain);
      }
      final Record record;
      if (widget.recordId < 0) {
        record = group.add(await group.newRecordWithDefaults(), modified: false);
      } else {
        group.load([widget.recordId]);
        record = group.get(widget.recordId)!;
        await record.load('*');
      }
      // Domain inversion: unique values of the screen domain are set and
      // locked (domain_readonly), like SAO's validation on display.
      record.validate(softValidation: true);
      await record.idle;

      // 3. Options of method-based selections. With selection_change_with
      // they depend on the record values, so load after the record.
      final viewDef = await _withSelections(rawViewDef, record);

      group.onNotify = (notifications) {
        if (mounted) setState(() => _notifications = notifications);
      };
      _group?.removeListener(_onGroupChanged);
      group.addListener(_onGroupChanged);
      setState(() {
        _viewDef = viewDef;
        _formRoot = formRoot;
        _group = group;
        _record = record;
        _pending.clear();
        _notifications = const [];
      });

      // Load toolbar, resources and translated model name in background
      _loadSideData(svc);  // also called for new records to get model display name
    } on HandledRpcError catch (e) {
      // Already shown by the error dialog; the page keeps a short text.
      if (mounted) setState(() => _error = ErrorHandler.describe(e));
    } catch (e) {
      // Dialog via the central handler; the page keeps a short text + Reload.
      if (mounted) errorHandlerOf(context, ref).show(e);
      if (mounted) setState(() => _error = ErrorHandler.describe(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// [viewDef] with the options of all method-based selections for the
  /// current values of [record].
  Future<ViewDefinition> _withSelections(
      ViewDefinition viewDef, Record record) async {
    final values = recordWidgetValues(record);
    final fields = Map<String, FieldDefinition>.from(viewDef.fields);
    await Future.wait(viewDef.fields.values
        .where(SelectionLoader.isDynamic)
        .map((fd) async {
      final opts = await _selections.load(fd, values, viewDef.fields);
      fields[fd.name] = fd.copyWithSelection(opts);
    }));
    return ViewDefinition(
      arch: viewDef.arch,
      fields: fields,
      viewId: viewDef.viewId,
      type: viewDef.type,
      fieldChilds: viewDef.fieldChilds,
      rawFields: viewDef.rawFields,
    );
  }

  /// Reloads the selections that depend on changed values (cached per
  /// value combination, like SAO's update_selection).
  Future<void> _refreshSelections() async {
    final viewDef = _viewDef;
    final record = _record;
    if (viewDef == null || record == null) return;
    if (!viewDef.fields.values.any((fd) =>
        SelectionLoader.isDynamic(fd) &&
        (fd.selectionChangeWith?.isNotEmpty ?? false))) {
      return;
    }
    final updated = await _withSelections(viewDef, record);
    if (mounted && identical(_viewDef, viewDef)) {
      setState(() => _viewDef = updated);
    }
  }

  Future<void> _loadSideData(ModelService svc) async {
    // Toolbar actions (view_toolbar_get)
    try {
      final t = await svc.viewToolbarGet(widget.model);
      if (mounted) setState(() => _toolbar = t);
    } catch (_) {}

    await _loadResources();

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
    if (_modelDisplayNameCache.containsKey(widget.model)) {
      if (mounted) {
        setState(() =>
            _modelDisplayName = _modelDisplayNameCache[widget.model]);
      }
      return;
    }
    try {
      // In Tryton 8.x, ir.model.name IS the technical model name (e.g. "res.user").
      // We search by 'name' and then get the translated rec_name (display name).
      final result = await svc.searchRead(
        'ir.model',
        domain: [['name', '=', widget.model]],
        fields: ['name', 'rec_name'],
        limit: 1,
      );
      if (result.isNotEmpty) {
        // rec_name is the translated display name; if identical to technical
        // name, it means no translation available → don't bother showing it.
        final displayName = result.first['rec_name']?.toString()
            ?? result.first['name']?.toString()
            ?? '';
        if (displayName.isNotEmpty && displayName != widget.model) {
          _modelDisplayNameCache[widget.model] = displayName;
          if (mounted) setState(() => _modelDisplayName = displayName);
          return;
        }
      }
      // No result or name equals technical name → mark as "no display name"
      _modelDisplayNameCache[widget.model] = '';
    } catch (e) {
      debugPrint('ir.model load error for "${widget.model}": $e');
    }
  }

  /// Returns the best available title for the AppBar.
  /// When the widget title IS the technical model name → use the translated name.
  /// Otherwise the title was set explicitly (e.g. from a menu action) → keep it.
  String get _effectiveTitle {
    final isTechnicalName = widget.title == widget.model;
    if (isTechnicalName && _modelDisplayName != null && _modelDisplayName!.isNotEmpty) {
      return _modelDisplayName!;
    }
    return widget.title;
  }

  /// Subtitle line below the primary title.
  /// Combines model display name (when it differs from the primary title)
  /// and the record position from the navigation context (e.g. "3 / 47").
  /// Examples:
  ///   "Base Object · 3 / 47"   – navigated via list, model name available
  ///   "3 / 47"                 – model name same as title or unavailable
  ///   "Base Object"            – no navigation context
  String get _subtitleText {
    final nav = ref.read(navContextProvider);
    final pos = nav?.positionLabel ?? '';

    final showModelName = _modelDisplayName != null &&
        _modelDisplayName!.isNotEmpty &&
        _modelDisplayName != _effectiveTitle;

    if (showModelName && pos.isNotEmpty) return '$_modelDisplayName · $pos';
    if (showModelName) return _modelDisplayName!;
    if (pos.isNotEmpty) return pos;
    return '';
  }

  // ─── Language sync ───────────────────────────────────────────────────────

  /// Called after saving res.user – reloads session context and preferences.
  /// Mirrors what SAO does after preferences are changed:
  /// 1. reload_context() → refreshes session.context incl. language for all RPCs
  /// 2. apply new language to Flutter locale
  /// 3. clear userPreferences cache so name/currency in header chip refreshes
  Future<void> _reloadUserContext() async {
    try {
      final session = ref.read(sessionProvider);
      // Refresh session.context (language, company, employee, …)
      await session.reloadContext();
      // Apply new language to Flutter UI
      final langCode = session.context['language']?.toString();
      if (langCode != null) {
        await ref.read(localeProvider.notifier).applyServerLanguage(langCode);
      }
      // Clear cached preferences so header chip reloads name/currency
      clearUserPreferencesCache();
      ref.invalidate(userPreferencesProvider);
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
      final isUserRecord = widget.model == 'res.user' &&
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

  /// Toolbar "Save": like before, a new record closes the form afterwards.
  Future<bool> _save() async {
    final wasNew = _isNew;
    if (!await _saveRecord()) return false;
    if (!mounted) return true;
    if (wasNew) {
      _showSnack(context.l10n.recordCreated);
      Navigator.of(context).pop(_recordId);
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

  /// "Compare": opens the current server version in a new tab.
  Future<void> _openCompareTab() async {
    final svc = ref.read(modelServiceProvider);
    final records =
        await svc.read(widget.model, [_recordId], ['rec_name']);
    final name = records.isNotEmpty
        ? records.first.values['rec_name']?.toString() ?? ''
        : '';
    if (!mounted) return;
    ref.read(tabsProvider.notifier).openTab(
      title: context.l10n.compareTabTitle(name),
      model: widget.model,
      initialDomain: [['id', '=', _recordId]],
      resId: _recordId,
    );
  }

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
      if (await record.group.delete([record]) && mounted) {
        Navigator.of(context).pop();
      }
    } on HandledRpcError {
      // shown
    } catch (e) {
      if (mounted) await errorHandlerOf(context, ref).show(e);
    }
  }

  Future<void> _executeButton(ButtonNode node) async {
    if (node.confirm != null && node.confirm!.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(node.confirm!),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final record = _record;
    if (record == null) return;
    // Like SAO: the record is saved before the button runs.
    if (_isDirty || _isNew) {
      if (!await _saveRecord() || !mounted) return;
    }
    setState(() => _saving = true);
    final ok = await errorHandlerOf(context, ref).run(() =>
        ref
            .read(modelServiceProvider)
            .executeButton(widget.model, node.name, [record.id]));
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) await _reloadRecord();
  }

  /// Discards the local values and reads the record again.
  Future<void> _reloadRecord() async {
    final record = _record;
    if (record == null || record.id < 0) return _load();
    record.cancel();
    _pending.clear();
    try {
      await record.load('*');
      record.validate(softValidation: true);
    } on HandledRpcError {
      // shown
    }
    if (mounted) setState(() => _notifications = const []);
    _loadResources();
  }

  /// Toolbar "Reload": discards the changes after the save prompt.
  Future<void> _reload() async {
    if (!await _confirmDiscard()) return;
    if (mounted) await _load();
  }

  Future<void> _duplicate() async {
    if (_isNew) return;
    if (!await _confirmDiscard() || !mounted) return;
    await errorHandlerOf(context, ref).run(() async {
      final svc = ref.read(modelServiceProvider);
      final newIds = await svc.copy(widget.model, [_recordId]);
      if (newIds.isNotEmpty && mounted) {
        pushFormScreen(context,
            model: widget.model,
            recordId: newIds.first,
            title: widget.title,
            screenDomain: widget.screenDomain,
            replace: true);
      }
    });
  }

  Future<void> _viewLogs() async {
    if (_isNew) return;
    ref.read(tabsProvider.notifier).openTab(
      title: 'Logs',
      model: 'ir.model.log',
      initialDomain: [['resource', '=', '${widget.model},$_recordId']],
    );
  }

  Future<void> _openNote() async {
    if (_isNew) return;
    ref.read(tabsProvider.notifier).openTab(
      title: 'Notes',
      model: 'ir.note',
      initialDomain: [['resource', '=', '${widget.model},$_recordId']],
    );
  }

  /// Shows the SAO-style "This record has been modified" dialog (spec
  /// 10.4) before navigation, close, new, reload, duplicate and actions.
  /// Returns true if the operation should proceed: "Yes" saved the record
  /// (a failed save stays in the form), "No" discards the changes (with
  /// [reloadOnNo] the record is read again first), "Cancel" stays.
  Future<bool> _confirmDiscard({bool reloadOnNo = false}) async {
    if (!_isDirty) return true;
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
    if (result == 'cancel' || result == null) return false;
    if (result == 'yes') {
      // If save failed or was cancelled, stay in form
      if (!await _saveRecord()) return false;
    } else if (reloadOnNo) {
      await _reloadRecord();
    }
    return true; // 'no' or successful save
  }

  Future<void> _navigatePrev() async {
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    final nav = ref.read(navContextProvider);
    final prevId = nav?.previousId;
    if (prevId == null) return;
    ref.read(navContextProvider.notifier).state =
        nav!.withIndex(nav.currentIndex - 1);
    if (mounted) {
      pushFormScreen(context,
          model: widget.model,
          recordId: prevId,
          title: widget.title,
          screenDomain: widget.screenDomain,
          replace: true);
    }
  }

  Future<void> _navigateNext() async {
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    final nav = ref.read(navContextProvider);
    final nextId = nav?.nextId;
    if (nextId == null) return;
    ref.read(navContextProvider.notifier).state =
        nav!.withIndex(nav.currentIndex + 1);
    if (mounted) {
      pushFormScreen(context,
          model: widget.model,
          recordId: nextId,
          title: widget.title,
          screenDomain: widget.screenDomain,
          replace: true);
    }
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;

    final nav = ref.watch(navContextProvider);
    final hasPrev = nav?.hasPrevious ?? false;
    final hasNext = nav?.hasNext ?? false;
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
            Text(_effectiveTitle, style: const TextStyle(fontSize: 14)),
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
            onPressed: hasPrev ? _navigatePrev : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 16),
            tooltip: context.l10n.nextRecord,
            onPressed: hasNext ? _navigateNext : null,
          ),

          // ── CRUD ──────────────────────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l.createNew,
            onPressed: _saving ? null : () async {
              final ok = await _confirmDiscard();
              if (ok && mounted) {
                pushFormScreen(context,
                    model: widget.model,
                    recordId: -1,
                    title: widget.title,
                    screenDomain: widget.screenDomain);
              }
            },
          ),
          IconButton(
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            tooltip: l.save,
            onPressed: (_saving || (!_isDirty && !_isNew)) ? null : _save,
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
              onPressed: _saving ? null : _duplicate,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: _saving
                      ? Theme.of(context).disabledColor
                      : Theme.of(context).colorScheme.error),
              tooltip: l.delete,
              onPressed: _saving ? null : _delete,
            ),
          ],

          // ── Logs / Attachment / Note ──────────────────────────────────
          if (!_isNew) ...[
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: context.l10n.viewLogs,
              onPressed: _viewLogs,
            ),
            _AttachmentIconButton(
              model: widget.model,
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
              icon: Icons.rocket_launch_outlined, // tryton-launch
              tooltip: l.launchActions,
              items: _toolbar.actions,
              model: widget.model,
              selectedIds: _isNew ? [] : [_recordId],
              beforeExecute: () => _confirmDiscard(reloadOnNo: true),
            ),
            ToolbarDropdownButton(
              icon: Icons.link,                   // tryton-link
              tooltip: l.relatedRecords,
              items: _toolbar.relate,
              model: widget.model,
              selectedIds: _isNew ? [] : [_recordId],
              beforeExecute: () => _confirmDiscard(reloadOnNo: true),
            ),
            ToolbarDropdownButton(
              icon: Icons.print_outlined,         // tryton-print
              tooltip: l.reports,
              items: _toolbar.print,
              model: widget.model,
              selectedIds: _isNew ? [] : [_recordId],
              beforeExecute: () => _confirmDiscard(reloadOnNo: true),
            ),
            ToolbarDropdownButton(
              icon: Icons.email_outlined,         // tryton-email
              tooltip: l.email,
              items: _toolbar.emails,
              model: widget.model,
              selectedIds: _isNew ? [] : [_recordId],
              beforeExecute: () => _confirmDiscard(reloadOnNo: true),
            ),
          ],

          // ── Close – back to menu ──────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.close),  // tryton-close
            tooltip: context.l10n.close,
            onPressed: () async {
              final ok = await _confirmDiscard();
              if (ok && mounted) Navigator.of(context).pop();
            },
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
          FilledButton(onPressed: _load, child: Text(context.l10n.reload)),
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
            model: widget.model,
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
            isReadOnly: record.readonly,
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

