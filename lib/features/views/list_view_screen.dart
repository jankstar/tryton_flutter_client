import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart' hide TextField;
import '../../core/rpc/error_processing.dart';
import '../../core/screen/calendar.dart';
import '../../core/screen/screen.dart';
import '../../core/xml/form_xml_parser.dart';
import '../../core/xml/view_definition.dart';
import '../../shared/dialogs/tryton_dialogs.dart';
import '../../shared/errors/error_dialogs.dart';
import '../../shared/widgets/toolbar_dropdown_button.dart';
import '../model/model_service.dart';
import '../model/toolbar_data.dart';
import '../actions/action_service.dart';
import 'csv_dialogs.dart';
import 'record_menu.dart';
import 'resource_dialogs.dart';
import 'search_box.dart';
import 'list_form_view.dart';
import 'record_form.dart';
import 'record_widget_values.dart';
import 'tree_view.dart';
import 'calendar_view.dart';
import 'graph_view.dart';
import 'email_dialog.dart';
import '../shell/tab_manager.dart';
import '../actions/url_opener.dart';

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

  /// The view shows cards (`list-form`, spec 9.4) instead of a table.
  bool get _listForm => _view?.viewType == 'list-form';

  /// Graph or calendar instead of a table (spec 9.5, 9.6).
  bool get _chart => _view?.graph != null || _view?.calendar != null;

  /// The records listed (rows of the table, cards of a list-form).
  List<Record> get _listed => _listForm
      ? _screen.group.toList()
      : [for (final row in _rows) row.record];

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Tab of this list and its notifier: closing the tab asks to save the
  /// edited rows first (spec 10.4).
  String? _tabId;
  TabsNotifier? _tabs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabId = TabScope.of(context);
    if (tabId != _tabId) {
      if (_tabId != null) _tabs?.removeCloseGuard(_tabId!, _confirmSave);
      _tabId = tabId;
      _tabs = ref.read(tabsProvider.notifier);
      if (tabId != null) _tabs!.addCloseGuard(tabId, _confirmSave);
    }
  }

  @override
  void dispose() {
    if (_tabId != null) _tabs?.removeCloseGuard(_tabId!, _confirmSave);
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
    } else if (view != null &&
        (view.viewType == 'list-form' ||
            view.viewType == 'graph' ||
            view.viewType == 'calendar')) {
      _view = view;
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

  /// Save prompt (spec 10.4, Python `modified_save`) of an editable list
  /// with changes: Yes saves (stays on an error), No discards by searching
  /// again, Cancel stops; true = go on.
  Future<bool> _confirmSave() async {
    final question = context.l10n.recordModified;
    await _table.flush();
    if (!mounted || !_screen.modified()) return true;
    final choice = await showSur3(context, question);
    switch (choice) {
      case Sur3Choice.yes:
        await _saveList();
        return !_screen.modified();
      case Sur3Choice.no:
        await _search();
        return true;
      case Sur3Choice.cancel:
        return false;
    }
  }

  /// Reload (spec 10.3): save prompt, then the search again.
  Future<void> _reload() async {
    if (await _confirmSave()) await _search();
  }

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
    final rows = _listed;
    if (rows.isEmpty) return;
    final current = _screen.selectedRecords.isEmpty
        ? -1
        : rows.indexOf(_screen.selectedRecords.first);
    final index = current < 0
        ? (next ? 0 : rows.length - 1)
        : (current + (next ? 1 : -1)).clamp(0, rows.length - 1);
    _selectRecords([rows[index]]);
  }

  /// Selects [records] in the table or among the cards.
  void _selectRecords(List<Record> records) {
    if (!_listForm) return _table.select(records);
    setState(() {
      _screen.selectedRecords = records;
      _screen.currentRecord = records.firstOrNull;
    });
  }

  /// Email of the selected record (spec 11.10); a modified list is saved
  /// first (save prompt).
  Future<void> _email() async {
    final selected = _screen.selectedRecords;
    if (selected.length != 1) return;
    if (!await _confirmSave()) return;
    final record = selected.first;
    // (after a reload the record of the old search is gone)
    if (!mounted || record.destroyed || !_screen.group.contains(record)) return;
    await showEmailFlow(context,
        record: record, toolbar: _toolbar, title: widget.title);
  }

  /// Class buttons of the list for the selected records with [keyword]
  /// (default `action`) – the toolbar menus (Python `Screen.get_buttons`).
  List<ButtonNode> _keywordButtons(String keyword) => [
        for (final b in _screen.getButtons())
          if ((b.keyword ?? 'action') == keyword) b
      ];

  /// A button of the menus on the selected records (save prompt first).
  Future<void> _runButton(ButtonNode button) async {
    if (!await _confirmSave()) return;
    await _run(() => _screen.button(button));
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
          _listed.isEmpty ? null : () => _moveSelection(next: false),
      RecordAction.next:
          _listed.isEmpty ? null : () => _moveSelection(next: true),
      RecordAction.search: _listForm ? null : _searchFocus.requestFocus,
      RecordAction.newRecord: _screen.canCreate ? _newRecord : null,
      RecordAction.save: _screen.modified() ? _saveList : null,
      RecordAction.reload: _reload,
      RecordAction.copy:
          hasSelection && _screen.canCreate ? _copySelected : null,
      RecordAction.delete:
          hasSelection && _screen.canDelete ? _deleteSelected : null,
      RecordAction.logs: single ? () => _resourceDialog(notes: false) : null,
      if (_hasHistory) RecordAction.revision: hasSelection ? _revisions : null,
      RecordAction.attach: menu(_attachKey, single),
      RecordAction.note: single ? () => _resourceDialog(notes: true) : null,
      RecordAction.action: menu(_actionKey,
          hasSelection && (_toolbar.actions.isNotEmpty || _keywordButtons('action').isNotEmpty)),
      RecordAction.relate: menu(_relateKey,
          hasSelection && (_toolbar.relate.isNotEmpty || _keywordButtons('relate').isNotEmpty)),
      RecordAction.print: menu(
          _printKey,
          hasSelection &&
                  (_toolbar.print.isNotEmpty || _keywordButtons('print').isNotEmpty) ||
              _toolbar.exports.isNotEmpty),
      RecordAction.email: single ? _email : null,
      RecordAction.export: () => showCsvExport(context,
          screen: _screen,
          name: widget.title,
          listed: _listed),
      RecordAction.import: _screen.canCreate ? _importCsv : null,
      RecordAction.copyUrl: () =>
          copyScreenUrl(context, ref, _screen, widget.title),
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
        // editable list: the new row at new_position is edited; a
        // list-form selects the new card
        if (record != null && mounted && _editableView) {
          _table.edit(record);
        } else if (record != null && mounted && _listForm) {
          _selectRecords([record]);
        }
      });

  /// Row activation (SAO `default_row_activate`): with `keyword_open` the
  /// `tree_open` action of the record, otherwise the form of the record
  /// (same group and record).
  Future<void> _openRecord(Record record) => _whileOpening(() async {
        final screen = _screen;
        _selectRecords([record]);
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
        if (!await _confirmSave()) return;
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
        if (!await _confirmSave()) return;
        if (!await _table.leaveRow(null)) return;
        _table.saveTreeState();
        final selected = screen.selectedRecords;
        screen.currentRecord = selected.isEmpty ? null : selected.first;
        await screen.switchView();
      }));

  Future<void> _deleteSelected() async {
    final screen = _screen;
    if (screen.selectedRecords.isEmpty) return;
    final l = context.l10n;
    final confirmed = await showSur(
        context, l.reallyDeleteRecords(screen.selectedRecords.length),
        title: l.deleteRecords, okLabel: l.delete, destructive: true);
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
      _selectRecords([for (final id in ids) ?screen.group.get(id)]);
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
      // the toolbar follows the width of the tab (SAO hidden-xs/-sm)
      child: LayoutBuilder(builder: (context, box) => Scaffold(
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
          ...adaptiveToolbar(box.maxWidth, [
          // ── Navigation ────────────────────────────────────────────────
          // Switch: like SAO's tryton-switch – jump to form view
          ToolbarSlot(0, IconButton(
            icon: TrytonIcon(
              iconName: 'tryton-switch',
              size: 20,
              color: hasSelection || _chart
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).disabledColor,
              fallback: Icons.compare_arrows,
            ),
            tooltip: context.l10n.switchToForm,
            onPressed: hasSelection || _chart ? _switchToForm : null,
          )),

          // ── CRUD ──────────────────────────────────────────────────────
          // Rights and revision view (spec 10.3, MODELACCESS)
          ToolbarSlot(0, IconButton(
            icon: const Icon(Icons.add),
            tooltip: l.createNew,
            onPressed: _screen.canCreate ? _newRecord : null,
          )),
          // Save: changes of editable rows and of drag and drop
          ToolbarSlot(0, IconButton(
            key: const ValueKey('list-save'),
            icon: const Icon(Icons.save),
            tooltip: l.save,
            onPressed: _screen.modified() ? _saveList : null,
          )),
          ToolbarSlot(0, IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l.reload,
            onPressed: _reload,
          )),
          ToolbarSlot(3, IconButton(
            icon: Icon(Icons.copy_outlined,
                color: hasSelection && _screen.canCreate
                    ? null
                    : Theme.of(context).disabledColor),
            tooltip: l.duplicate,
            onPressed: hasSelection && _screen.canCreate ? _copySelected : null,
          )),
          ToolbarSlot(1, IconButton(
            icon: Icon(Icons.delete_outline,
                color: hasSelection && _screen.canDelete
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).disabledColor),
            tooltip: l.delete,
            onPressed: hasSelection && _screen.canDelete ? _deleteSelected : null,
          )),

          // ── Attachment (requires selection) ───────────────────────────
          ToolbarSlot(1, _ResourceButtons(
            attachKey: _attachKey,
            record: singleSelection ? _screen.selectedRecords.first : null,
            onNote: actions[RecordAction.note] == null
                ? null
                : () => _resourceDialog(notes: true),
          ), slots: 2),

          // ── Action / Relate / Print / Email (require selection) ───────
          ToolbarSlot(2, ToolbarDropdownButton(
            key: _actionKey,
            screen: _screen,
            icon: Icons.rocket_launch_outlined,
            tooltip: l.launchActions,
            items: _toolbar.actions,
            model: _model,
            selectedIds: selectedIds,
            enabled: hasSelection,
            beforeExecute: _confirmSave,
            buttons: _keywordButtons('action'),
            onButton: _runButton,
          )),
          ToolbarSlot(2, ToolbarDropdownButton(
            key: _relateKey,
            screen: _screen,
            icon: Icons.link,
            tooltip: l.relatedRecords,
            items: _toolbar.relate,
            model: _model,
            selectedIds: selectedIds,
            enabled: hasSelection,
            beforeExecute: _confirmSave,
            buttons: _keywordButtons('relate'),
            onButton: _runButton,
          )),
          ToolbarSlot(2, ToolbarDropdownButton(
            key: _printKey,
            screen: _screen,
            icon: Icons.print_outlined,
            tooltip: l.reports,
            items: _toolbar.print,
            model: _model,
            selectedIds: selectedIds,
            enabled: hasSelection,
            beforeExecute: _confirmSave,
            buttons: _keywordButtons('print'),
            onButton: _runButton,
            exports: _toolbar.exports,
            onExport: (export) => runPredefinedExport(context, _screen, export,
                listed: _listed),
          )),
          ToolbarSlot(2, IconButton(
            key: _emailKey,
            icon: const Icon(Icons.email_outlined),
            tooltip: l.email,
            onPressed: actions[RecordAction.email],
          )),

          // ── Close ─────────────────────────────────────────────────────
          ToolbarSlot(0, IconButton(
            icon: const Icon(Icons.close),
            tooltip: context.l10n.close,
            onPressed: () => widget.onClose?.call(),
          )),
          ]),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(),
    )), // Scaffold
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

    // Layout: [context form] → search bar → tabs → table → status; a
    // list-form is not searchable (Python `search_active`)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?_buildContextForm(),
        if (!_listForm) searchBar,
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
    // graph and calendar show their axes/days also without records
    if (view?.graph != null || view?.calendar != null) {
      return Column(children: [
        Expanded(child: _buildChartBody(view!)),
        if (_loading || _opening) const LinearProgressIndicator(),
      ]);
    }
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
          child: _listForm
              ? ListFormView(
                  screen: _screen,
                  view: view,
                  displayStep: _displayStep,
                  onActivate: _openRecord,
                  onSelectionChanged: () => setState(() {}),
                  onEndReached: _searchMore,
                )
              : TreeView(
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

// ─── Graph and calendar (spec 9.5, 9.6) ──────────────────────────────────────

extension on _ListViewScreenState {
  Widget _buildChartBody(ScreenView view) {
    final graph = view.graph;
    if (graph != null) {
      return GraphView(
        key: ObjectKey(view),
        screen: _screen,
        definition: graph,
        onOpen: _graphOpen,
      );
    }
    final calendar = view.calendar!;
    final canCreate = calendar.editable && _screen.model.access.create;
    return CalendarView(
      key: ObjectKey(view),
      calendar: calendar,
      events: calendar.events(
          [for (final r in _screen.group) if (_calendarLoaded(calendar, r)) r],
          canWrite: _screen.model.access.write && !_screen.screenReadonly),
      onPeriodChanged: () {
        if (calendar.updateDomain()) _search();
      },
      onOpen: (record) => _whileOpening(() => _run(() async {
            _screen.currentRecord = record;
            await _screen.switchView(viewType: 'form');
          })),
      onNew: canCreate
          ? () {
              _screen.currentRecord = null;
              _newRecord();
            }
          : null,
      onMove: (event, start, end) => _run(() async {
        await calendar.move(event.record, start, end);
        await event.record.save();
        calendar.select(start);
      }),
    );
  }

  /// The fields of the calendar are loaded for [record] (else loaded in
  /// the background, the event appears afterwards).
  bool _calendarLoaded(CalendarState calendar, Record record) {
    if (record.isLoaded(calendar.dtstart)) return true;
    record
        .load(calendar.dtstart, processException: false)
        .then((_) => _onScreenChanged())
        .catchError((Object _) {});
    return false;
  }

  /// Keyword `graph_open` with the ids of a point (Python
  /// `action_keyword`; the context without active_id(s)).
  Future<void> _graphOpen(List<int> ids) => _run(() async {
        final context = {..._screen.localContext}
          ..remove('active_id')
          ..remove('active_ids');
        await ref.read(actionServiceProvider).execKeyword(
            'graph_open',
            {'model': _model, 'id': ids.first, 'ids': ids},
            context: context,
            warning: false,
            ui: DialogActionUi(this.context));
      });
}

// ─── Attachment and note buttons ─────────────────────────────────────────────

/// Attachments and notes of the selected record (spec 10.3, 11.4, 11.5):
/// the badges from `resources`, the attachment dropdown of
/// [AttachmentMenuButton] and the notes dialog.
class _ResourceButtons extends StatefulWidget {
  final Record? record;
  final GlobalKey attachKey;
  final Future<void> Function()? onNote;
  const _ResourceButtons(
      {required this.record, required this.attachKey, this.onNote});

  @override
  State<_ResourceButtons> createState() => _ResourceButtonsState();
}

class _ResourceButtonsState extends State<_ResourceButtons> {
  Map<String, dynamic>? _resources;
  ResourceRef? _resource;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ResourceButtons old) {
    super.didUpdateWidget(old);
    if (!identical(old.record, widget.record)) _load();
  }

  Future<void> _load({bool reload = false}) async {
    final record = widget.record;
    final resource = await resourceOf(record);
    Map<String, dynamic>? resources;
    if (record != null && record.id >= 0) {
      try {
        resources = await record.getResources(reload: reload);
      } catch (_) {}
    }
    if (!mounted || !identical(record, widget.record)) return;
    setState(() {
      _resource = resource;
      _resources = resources;
    });
  }

  int _count(String key) => (_resources?[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final onNote = widget.onNote;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      AttachmentMenuButton(
        key: widget.attachKey,
        resource: widget.record == null ? null : _resource,
        count: _count('attachment_count'),
        onChanged: () => _load(reload: true),
      ),
      NoteIconButton(
        total: _count('note_count'),
        unread: _count('note_unread'),
        onPressed: onNote == null
            ? null
            : () async {
                await onNote();
                await _load(reload: true);
              },
      ),
    ]);
  }
}
