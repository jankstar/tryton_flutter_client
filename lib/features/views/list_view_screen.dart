import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart' hide TextField;
import '../../core/rpc/error_processing.dart';
import '../../core/screen/screen.dart';
import '../../core/xml/form_xml_parser.dart';
import '../../core/xml/view_definition.dart';
import '../../shared/errors/error_dialogs.dart';
import '../../shared/widgets/toolbar_dropdown_button.dart';
import '../model/model_service.dart';
import '../model/toolbar_data.dart';
import '../actions/action_service.dart';
import 'csv_dialogs.dart';
import 'record_menu.dart';
import 'resource_dialogs.dart';
import 'search_box.dart';
import 'record_form.dart';
import 'record_widget_values.dart';
import 'tree_view.dart';

export 'tree_view.dart' show clearListCaches;

/// List of a [TrytonScreen] (spec 8, 9.3): the records of the screen's
/// group in a [TreeView] with search, tab domains, context form and the
/// toolbar (New, Delete, Copy, Actions, Reports, Relations, Attachments).
///
/// The table shows the group in steps of [_displayStep] rows and appends
/// the next search page at the end (endless scrolling).
class ListViewScreen extends ConsumerStatefulWidget {
  /// The screen; its current view is a tree view.
  final TrytonScreen screen;
  final String title;

  /// Called when the user clicks "Close" – removes this tab from AppShell.
  final Future<void> Function()? onClose;

  const ListViewScreen({
    super.key,
    required this.screen,
    required this.title,
    this.onClose,
  });

  @override
  ConsumerState<ListViewScreen> createState() => _ListViewScreenState();
}

class _ListViewScreenState extends ConsumerState<ListViewScreen> {
  static const _displayStep = 100;

  ScreenView? _view;

  /// The parsed tree view (`keyword_open`).
  TreeViewDefinition? _tree;
  TrytonToolbar _toolbar = const TrytonToolbar();

  bool _loading = false;

  /// A record is being opened (form view and record are loaded): shown
  /// as progress bar, further opens are ignored.
  bool _opening = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _table = TreeViewController();

  /// Text of the context form not yet written (on focus loss).
  final Map<String, dynamic> _ctxPending = {};

  TrytonScreen get _screen => widget.screen;
  String get _model => _screen.model.name;
  List<TreeRow> get _rows => _table.rows;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _screen.removeListener(_onScreenChanged);
    _screen.contextScreen?.removeListener(_onScreenChanged);
    super.dispose();
  }

  void _onScreenChanged() {
    if (mounted) setState(() {});
  }

  /// End of the shown rows: the next search page.
  void _searchMore() {
    final screen = _screen;
    if (!screen.hasMore || _loading) return;
    _run(() async {
      setState(() => _loading = true);
      try {
        await screen.searchMore();
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  // ─── Screen ──────────────────────────────────────────────────────────────

  void _init() {
    final screen = _screen;
    screen.addListener(_onScreenChanged);
    screen.contextScreen?.addListener(_onScreenChanged);
    // Search text of the screen (normalized, or the action's search_value).
    _searchCtrl.text = screen.searchText;
    // „Search“ of the form (spec 10.3): focus into the search entry
    if (screen.searchFocusRequested) {
      screen.searchFocusRequested = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
    if (screen.domainParser == null && screen.group.parent == null) {
      // The list was opened after the form: parser for the search bar.
      screen.parserContext =
          ref.read(modelServiceProvider).metadata?.parserContext ?? const {};
      screen
          .loadDomainParser()
          .then((_) {
            if (mounted) setState(() {});
          })
          .catchError((Object _) {});
    }
    final view = screen.currentView;
    if (view != null && view.viewType == 'tree') {
      _view = view;
      _tree = TreeXmlParser()
          .parse(view.definition.arch, view.definition.rawFields);
    }
    _loadToolbar(ref.read(modelServiceProvider));
  }

  /// Rows are edited inline (`editable="1"`, screen not readonly).
  bool get _editableView =>
      (_view?.editable ?? false) && (_tree?.editable ?? false);

  Future<void> _loadToolbar(ModelService svc) async {
    try {
      final t = await svc.viewToolbarGet(_model);
      if (mounted) setState(() => _toolbar = t);
    } catch (_) {
      // Toolbar is optional – ignore errors
    }
  }

  /// Runs [action]; errors of the data layer were shown by its handler,
  /// others are shown here.
  Future<bool> _run(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } on HandledRpcError {
      return false;
    } catch (e) {
      if (mounted) await errorHandlerOf(context, ref).show(e);
      return false;
    }
  }

  /// Searches again (search text, tab, context form) from the first rows.

  /// Searches again (search text, tab, context form) from the first rows.
  Future<void> _search() => _run(() async {
        final screen = _screen;
        _table.reset();
        setState(() => _loading = true);
        try {
          await screen.searchFilter(_searchCtrl.text.trim());
          // The text normalized by the DomainParser (spec 8.3).
          _searchCtrl.text = screen.searchText;
        } finally {
          if (mounted) setState(() => _loading = false);
        }
      });

  /// Model with history (MODELHISTORY): menu "Revisions…".
  bool get _hasHistory =>
      ref.read(modelServiceProvider).metadata?.hasHistory(_model) ?? false;

  /// Revisions of the selected records (spec 11.7, Python
  /// `Form.sig_revision`): the group gets `_datetime` (+1 ms) and the
  /// search runs again – read only in the revision.
  Future<void> _revisions() async {
    final choice = await chooseRevision(context, _screen,
        [for (final r in _screen.selectedRecords) if (r.id >= 0) r.id]);
    if (choice == null || !mounted) return;
    _screen.group.revision = choice is DateTime
        ? choice.add(const Duration(milliseconds: 1))
        : null;
    await _search();
  }

  /// CSV import (spec 11.8); afterwards the list is searched again.
  Future<void> _importCsv() async {
    final count = await showCsvImport(context,
        model: _model, importContext: _screen.context, name: widget.title);
    if ((count ?? 0) > 0 && mounted) await _search();
  }

  // Dropdown buttons opened by the record menu and its shortcuts.
  final _attachKey = GlobalKey();
  final _actionKey = GlobalKey();
  final _relateKey = GlobalKey();
  final _printKey = GlobalKey();
  final _emailKey = GlobalKey();

  /// Previous/next row becomes the selection (Python `display_prev/next`
  /// of a list).
  void _moveSelection({required bool next}) {
    final rows = [for (final row in _rows) row.record];
    if (rows.isEmpty) return;
    final current = _screen.selectedRecords.isEmpty
        ? -1
        : rows.indexOf(_screen.selectedRecords.first);
    final index = current < 0
        ? (next ? 0 : rows.length - 1)
        : (current + (next ? 1 : -1)).clamp(0, rows.length - 1);
    _table.select([rows[index]]);
  }

  /// Logs / notes of the selected record (spec 11.5, 11.6).
  Future<void> _resourceDialog({required bool notes}) async {
    final selected = _screen.selectedRecords;
    final r = await resourceOf(selected.length == 1 ? selected.first : null);
    if (r == null || !mounted) return;
    try {
      notes ? await showNotes(context, r) : await showLogs(context, ref, r);
    } on HandledRpcError {
      // shown
    }
  }

  /// The entries of the record menu and their shortcuts with the
  /// activation of the toolbar buttons (spec 10.3).
  RecordActions _recordActions() {
    final selected = _screen.selectedRecords;
    final hasSelection = selected.isNotEmpty;
    final single = selected.length == 1 && selected.first.id >= 0;
    VoidCallback? menu(GlobalKey key, bool active) =>
        active ? () => pressButtonOf(key) : null;
    return {
      RecordAction.switchView: hasSelection ? _switchToForm : null,
      RecordAction.previous:
          _rows.isEmpty ? null : () => _moveSelection(next: false),
      RecordAction.next: _rows.isEmpty ? null : () => _moveSelection(next: true),
      RecordAction.search: _searchFocus.requestFocus,
      RecordAction.newRecord: _screen.canCreate ? _newRecord : null,
      RecordAction.save: _screen.modified() ? _saveList : null,
      RecordAction.reload: _search,
      RecordAction.copy:
          hasSelection && _screen.canCreate ? _copySelected : null,
      RecordAction.delete:
          hasSelection && _screen.canDelete ? _deleteSelected : null,
      RecordAction.logs: single ? () => _resourceDialog(notes: false) : null,
      if (_hasHistory) RecordAction.revision: hasSelection ? _revisions : null,
      RecordAction.attach: menu(_attachKey, single),
      RecordAction.note: single ? () => _resourceDialog(notes: true) : null,
      RecordAction.action:
          menu(_actionKey, hasSelection && _toolbar.actions.isNotEmpty),
      RecordAction.relate:
          menu(_relateKey, hasSelection && _toolbar.relate.isNotEmpty),
      RecordAction.print: menu(_printKey,
          hasSelection && _toolbar.print.isNotEmpty || _toolbar.exports.isNotEmpty),
      RecordAction.email:
          menu(_emailKey, hasSelection && _toolbar.emails.isNotEmpty),
      RecordAction.export: () => showCsvExport(context,
          screen: _screen,
          name: widget.title,
          listed: [for (final row in _rows) row.record]),
      RecordAction.import: _screen.canCreate ? _importCsv : null,
      RecordAction.close: () => widget.onClose?.call(),
    };
  }


  // ─── Actions ─────────────────────────────────────────────────────────────

  List<int> get _selectedIds => [
        for (final r in _screen.selectedRecords)
          if (r.id >= 0) r.id
      ];

  /// New record: the screen switches to the form (the list is not
  /// creatable) and adds it at `new_position` (spec 8.5).
  Future<void> _newRecord() => _run(() async {
        if (!await _table.leaveRow(null)) return;
        final record = await _screen.newRecord();
        // editable list: the new row at new_position is edited
        if (record != null && mounted && _editableView) {
          _table.edit(record);
        }
      });

  /// Row activation (SAO `default_row_activate`): with `keyword_open` the
  /// `tree_open` action of the record, otherwise the form of the record
  /// (same group and record).
  Future<void> _openRecord(Record record) => _whileOpening(() async {
        final screen = _screen;
        _table.select([record]);
        if ((_tree?.keywordOpen ?? false) && record.id >= 0) {
          // Keyword action of the record (one runs, several are offered).
          await ref.read(actionServiceProvider).execKeyword(
              'tree_open',
              {
                'model': _model,
                'id': record.id,
                'ids': [record.id]
              },
              context: screen.localContext,
              ui: DialogActionUi(context));
          return;
        }
        if (screen.modified()) return;
        screen.currentRecord = record;
        await screen.switchView(viewType: 'form');
      });

  /// Runs [action] (opening a record) once at a time with progress bar.
  Future<void> _whileOpening(Future<void> Function() action) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await _run(action);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// Saves the edited row / the group (SAO `save_current` of a tree).
  Future<void> _saveList() => _run(() async {
        await _table.flush();
        await _screen.saveCurrent();
        if (mounted) setState(() {});
      });

  /// Switch: the form of the first selected record (spec 8.2).
  Future<void> _switchToForm() => _whileOpening(() => _run(() async {
        final screen = _screen;
        if (!await _table.leaveRow(null)) return;
        _table.saveTreeState();
        final selected = screen.selectedRecords;
        screen.currentRecord = selected.isEmpty ? null : selected.first;
        await screen.switchView();
      }));

  Future<void> _deleteSelected() async {
    final screen = _screen;
    if (screen.selectedRecords.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.deleteRecords),
        content:
            Text('Really delete ${screen.selectedRecords.length} record(s)?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      final root = screen.group.parent == null;
      await screen.remove(delete: root, forceRemove: root);
    });
  }

  Future<void> _copySelected() async {
    final screen = _screen;
    final ok = await _run(() async {
      final ids = await screen.copy();
      _table.select([for (final id in ids) ?screen.group.get(id)]);
    });
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.recordCreated)));
    }
  }


  // ─── Context form ────────────────────────────────────────────────────────

  /// A value of the context form goes to its record; then search again.
  Future<void> _writeContext(String name, dynamic value) async {
    final record = _screen.contextScreen?.currentRecord;
    if (record == null) return;
    await _run(() => setRecordWidgetValue(record, name, value));
    await _search();
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final selectedIds = _selectedIds;
    final hasSelection = selectedIds.isNotEmpty;
    final singleSelection = selectedIds.length == 1;

    final actions = _recordActions();
    return RecordShortcuts(
      actions: actions,
      child: Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        scrolledUnderElevation: 0,
        // record menu at the title (spec 10.3)
        title: RecordTitleMenu(
          actions: actions,
          title: Text(_screen.group.revision == null
              ? widget.title
              : '${widget.title} @ ${revisionText(_screen.group.revision!)}'),
        ),
        actions: [
          // ── Navigation ────────────────────────────────────────────────
          // Switch: like SAO's tryton-switch – jump to form view
          IconButton(
            icon: TrytonIcon(
              iconName: 'tryton-switch',
              size: 20,
              color: hasSelection
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).disabledColor,
              fallback: Icons.compare_arrows,
            ),
            tooltip: context.l10n.switchToForm,
            onPressed: hasSelection ? _switchToForm : null,
          ),

          // ── CRUD ──────────────────────────────────────────────────────
          // Rights and revision view (spec 10.3, MODELACCESS)
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l.createNew,
            onPressed: _screen.canCreate ? _newRecord : null,
          ),
          // Save: changes of editable rows and of drag and drop
          IconButton(
            key: const ValueKey('list-save'),
            icon: const Icon(Icons.save),
            tooltip: l.save,
            onPressed: _screen.modified() ? _saveList : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l.reload,
            onPressed: _search,
          ),
          IconButton(
            icon: Icon(Icons.copy_outlined,
                color: hasSelection && _screen.canCreate
                    ? null
                    : Theme.of(context).disabledColor),
            tooltip: l.duplicate,
            onPressed: hasSelection && _screen.canCreate ? _copySelected : null,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                color: hasSelection && _screen.canDelete
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).disabledColor),
            tooltip: l.delete,
            onPressed: hasSelection && _screen.canDelete ? _deleteSelected : null,
          ),

          // ── Attachment (requires selection) ───────────────────────────
          _AttachmentButton(
            key: _attachKey,
            record: singleSelection ? _screen.selectedRecords.first : null,
          ),

          // ── Action / Relate / Print / Email (require selection) ───────
          ToolbarDropdownButton(
            key: _actionKey,
            screen: _screen,
            icon: Icons.rocket_launch_outlined,
            tooltip: l.launchActions,
            items: _toolbar.actions,
            model: _model,
            selectedIds: selectedIds,
            enabled: hasSelection,
          ),
          ToolbarDropdownButton(
            key: _relateKey,
            screen: _screen,
            icon: Icons.link,
            tooltip: l.relatedRecords,
            items: _toolbar.relate,
            model: _model,
            selectedIds: selectedIds,
            enabled: hasSelection,
          ),
          ToolbarDropdownButton(
            key: _printKey,
            screen: _screen,
            icon: Icons.print_outlined,
            tooltip: l.reports,
            items: _toolbar.print,
            model: _model,
            selectedIds: selectedIds,
            enabled: hasSelection,
            exports: _toolbar.exports,
            onExport: (export) => runPredefinedExport(context, _screen, export,
                listed: [for (final row in _rows) row.record]),
          ),
          ToolbarDropdownButton(
            key: _emailKey,
            screen: _screen,
            icon: Icons.email_outlined,
            tooltip: l.email,
            items: _toolbar.emails,
            model: _model,
            selectedIds: selectedIds,
            enabled: hasSelection,
          ),

          // ── Close ─────────────────────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: context.l10n.close,
            onPressed: () => widget.onClose?.call(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(),
    ), // Scaffold
    ); // RecordShortcuts
  }

  Widget _buildBody() {
    final screen = _screen;
    final searchBar = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SearchBox(
        screen: _screen,
        controller: _searchCtrl,
        focusNode: _searchFocus,
        onSearch: _search,
      ),
    );

    // Layout: [context form] → search bar → tabs → table → status
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?_buildContextForm(),
        searchBar,
        if (screen.tabDomain.isNotEmpty) _buildTabBar(screen),
        Expanded(child: _buildListBody()),
        _buildStatus(screen),
      ],
    );
  }

  /// Form of the context model (SAO `context_screen` above the search).
  Widget? _buildContextForm() {
    final cs = _screen.contextScreen;
    final view = cs?.currentView;
    final record = cs?.currentRecord;
    if (cs == null || view?.formRoot == null || record == null) return null;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: RecordForm(
          key: ObjectKey(record),
          model: cs.model.name,
          root: view!.formRoot!,
          viewDef: view.definition,
          record: record,
          onTextChanged: (name, value) => _ctxPending[name] = value,
          onBlur: (name) {
            if (_ctxPending.containsKey(name)) {
              _writeContext(name, _ctxPending.remove(name));
            }
          },
          onChangedImmediate: _writeContext,
          isReadOnly: false,
        ),
      ),
    );
  }

  /// Tab domains above the list with counter (`99+`, tooltip `1000+`).
  Widget _buildTabBar(TrytonScreen screen) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
      child: Row(
        children: [
          for (int i = 0; i < screen.tabDomain.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: _buildTabLabel(screen, i),
                selected: screen.tabIndex == i,
                onSelected: (_) {
                  if (screen.tabIndex == i) return;
                  _run(() async {
                    _table.reset();
                    setState(() => _loading = true);
                    try {
                      await screen.setTab(i);
                    } finally {
                      if (mounted) setState(() => _loading = false);
                    }
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabLabel(TrytonScreen screen, int i) {
    final tab = screen.tabDomain[i];
    final count = screen.tabCounters[i];
    if (!tab.count || count == null) return Text(tab.name);
    final label = count > 99 ? '99+' : '$count';
    return Tooltip(
      message: count >= 1000 ? '1000+' : '$count',
      child: Text('${tab.name} ($label)'),
    );
  }

  /// `position/count` of the screen (spec 8.3).
  Widget _buildStatus(TrytonScreen screen) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      alignment: Alignment.centerRight,
      child: Text(screen.statusText,
          style: TextStyle(
              fontSize: 11, color: Theme.of(context).colorScheme.outline)),
    );
  }


  Widget _buildListBody() {
    final view = _view;
    if (_screen.group.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_screen.group.isEmpty && !_editableView || view == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 8),
            Text(context.l10n.noRecordsFound),
            const SizedBox(height: 16),
            if (_screen.canCreate)
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: Text(context.l10n.createNew),
                onPressed: _newRecord,
              ),
          ]),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: TreeView(
            screen: _screen,
            view: view,
            controller: _table,
            displayStep: _displayStep,
            onActivate: _openRecord,
            onSelectionChanged: () => setState(() {}),
            onEndReached: _searchMore,
          ),
        ),
        if (_loading || _opening) const LinearProgressIndicator(),
      ],
    );
  }
}

// ─── Attachment button ────────────────────────────────────────────────────────

/// Attachments of the selected record (spec 11.4): counter of
/// `resources`, the dropdown of [AttachmentMenuButton].
class _AttachmentButton extends StatefulWidget {
  final Record? record;
  const _AttachmentButton({super.key, this.record});

  @override
  State<_AttachmentButton> createState() => _AttachmentButtonState();
}

class _AttachmentButtonState extends State<_AttachmentButton> {
  int _count = 0;
  ResourceRef? _resource;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_AttachmentButton old) {
    super.didUpdateWidget(old);
    if (!identical(old.record, widget.record)) _load();
  }

  Future<void> _load({bool reload = false}) async {
    final record = widget.record;
    final resource = await resourceOf(record);
    var count = 0;
    if (record != null && record.id >= 0) {
      try {
        final r = await record.getResources(reload: reload);
        count = (r?['attachment_count'] as num?)?.toInt() ?? 0;
      } catch (_) {}
    }
    if (!mounted || !identical(record, widget.record)) return;
    setState(() {
      _resource = resource;
      _count = count;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.record == null) return const SizedBox.shrink();
    return AttachmentMenuButton(
      resource: _resource,
      count: _count,
      onChanged: () => _load(reload: true),
    );
  }
}
