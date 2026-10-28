import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart' hide TextField;
import '../../core/rpc/error_processing.dart';
import '../../core/screen/screen.dart';
import '../../core/serialization/tryton_serializer.dart';
import '../../core/xml/form_xml_parser.dart';
import '../../core/xml/view_definition.dart';
import '../../shared/errors/error_dialogs.dart';
import '../../shared/utils/number_format_utils.dart';
import '../../shared/widgets/toolbar_dropdown_button.dart';
import '../model/field_definition.dart';
import '../model/model_service.dart';
import '../model/toolbar_data.dart';
import '../actions/action_service.dart';
import '../shell/tab_manager.dart';
import 'record_cells.dart';
import 'record_form.dart';
import 'record_widget_values.dart';

/// List of a [TrytonScreen] (spec 8, 9.3): the records of the screen's
/// group as a table (or a tree with `field_childs`) with search, tab
/// domains, context form, column sorting and the toolbar (New, Delete,
/// Copy, Actions, Reports, Relations, Attachments).
///
/// Rows are loaded lazily with `Record.load` (neighbours in one `read`);
/// the table shows the group in steps of [_displayStep] rows and appends
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

/// A visible row: record and depth (tree views).
typedef _Row = ({Record record, int depth});

class _ListViewScreenState extends ConsumerState<ListViewScreen> {
  static const _displayStep = 100;

  ScreenView? _view;
  List<TreeColumn> _columns = const [];
  TrytonToolbar _toolbar = const TrytonToolbar();

  bool _loading = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final _scrollController = ScrollController();
  final _hScrollController = ScrollController();

  /// Number of group records shown (grows while scrolling).
  int _visible = _displayStep;
  final Set<Record> _selected = {};

  /// Expanded records of a tree view.
  final Set<Record> _expanded = {};

  /// Records whose row values are being loaded.
  final Set<Record> _rowLoading = {};

  /// Text of the context form not yet written (on focus loss).
  final Map<String, dynamic> _ctxPending = {};

  TrytonScreen get _screen => widget.screen;
  String get _model => _screen.model.name;
  Map<String, FieldDefinition> get _fields => _view?.definition.fields ?? const {};
  String? get _fieldChilds => _view?.fieldChilds;
  bool get _isHierarchical => _fieldChilds != null;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _hScrollController.dispose();
    _searchCtrl.dispose();
    _screen.removeListener(_onScreenChanged);
    _screen.contextScreen?.removeListener(_onScreenChanged);
    super.dispose();
  }

  void _onScreenChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    final screen = _screen;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels < pos.maxScrollExtent - 200) return;
    if (_visible < screen.group.length) {
      setState(() => _visible += _displayStep);
    } else if (screen.hasMore && !_loading) {
      _run(() async {
        setState(() => _loading = true);
        try {
          await screen.searchMore();
        } finally {
          if (mounted) setState(() => _loading = false);
        }
      });
    }
  }

  // ─── Screen ──────────────────────────────────────────────────────────────

  void _init() {
    final screen = _screen;
    screen.addListener(_onScreenChanged);
    screen.contextScreen?.addListener(_onScreenChanged);
    // The current record (e.g. from the form) is the selection.
    final current = screen.currentRecord;
    _setSelected(current != null ? [current] : screen.selectedRecords);
    final view = screen.currentView;
    if (view != null && view.viewType == 'tree') {
      _view = view;
      _columns = [
        for (final c in TreeXmlParser()
            .parse(view.definition.arch, view.definition.rawFields)
            .columns)
          if (!c.treeInvisible) c
      ];
    }
    _loadToolbar(ref.read(modelServiceProvider));
  }

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
  Future<void> _search() => _run(() async {
        final screen = _screen;
        setState(() {
          _loading = true;
          _visible = _displayStep;
          _selected.clear();
          _expanded.clear();
        });
        try {
          await screen.searchFilter(_searchCtrl.text.trim());
        } finally {
          if (mounted) setState(() => _loading = false);
        }
      });

  void _setSelected(Iterable<Record> records) {
    _selected
      ..clear()
      ..addAll(records);
    final screen = _screen;
    screen.selectedRecords = [
      for (final r in _rows.map((row) => row.record))
        if (_selected.contains(r)) r
    ];
    screen.currentRecord =
        screen.selectedRecords.isEmpty ? null : screen.selectedRecords.first;
  }

  void _toggleSelected(Record record) {
    final selected = {..._selected};
    if (!selected.remove(record)) selected.add(record);
    _setSelected(selected);
  }

  /// Loads the row values of [record] (and its neighbours) once.
  void _ensureLoaded(Record record) {
    final name = _columns.isNotEmpty ? _columns.first.name : 'rec_name';
    if (record.destroyed ||
        !record.model.fields.containsKey(name) ||
        record.isLoaded(name) ||
        _rowLoading.contains(record)) {
      return;
    }
    _rowLoading.add(record);
    record.load(name, processException: false).catchError((Object _) {}).whenComplete(() {
      _rowLoading.remove(record);
      if (mounted) setState(() {});
    });
  }

  /// Visible rows: the first [_visible] records of the group, in a tree
  /// with the children of the expanded records.
  List<_Row> get _rows {
    final screen = _screen;
    final rows = <_Row>[];
    void add(Iterable<Record> records, int depth) {
      for (final r in records) {
        rows.add((record: r, depth: depth));
        final children = _childrenOf(r);
        if (_expanded.contains(r) && children != null) {
          add(children, depth + 1);
        }
      }
    }

    add(screen.group.take(_visible), 0);
    return rows;
  }

  RecordGroup? _childrenOf(Record record) {
    final fc = _fieldChilds;
    if (fc == null || !record.isLoaded(fc)) return null;
    final value = record.fieldGetClient(fc);
    return value is RecordGroup ? value : null;
  }

  Future<void> _toggleExpanded(Record record) async {
    if (_expanded.remove(record)) {
      setState(() {});
      return;
    }
    await _run(() async {
      await record.load(_fieldChilds!);
      if (mounted) setState(() => _expanded.add(record));
    });
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  List<int> get _selectedIds => [
        for (final r in _screen.selectedRecords)
          if (r.id >= 0) r.id
      ];

  /// New record: the screen switches to the form (the list is not
  /// creatable) and adds it at `new_position` (spec 8.5).
  Future<void> _newRecord() => _run(() async {
        await _screen.newRecord();
      });

  /// Row activation (SAO `default_row_activate`): with `keyword_open` the
  /// `tree_open` action of the record, otherwise the form of the record
  /// (same group and record).
  Future<void> _openRecord(Record record) => _run(() async {
        final screen = _screen;
        _setSelected([record]);
        if (_view?.attributes['keyword_open'] == '1' && record.id >= 0) {
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

  /// Switch: the form of the first selected record (spec 8.2).
  Future<void> _switchToForm() => _run(() async {
        final screen = _screen;
        final selected = screen.selectedRecords;
        screen.currentRecord = selected.isEmpty ? null : selected.first;
        await screen.switchView();
      });

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
      _selected.retainWhere((r) => !r.destroyed);
    });
  }

  Future<void> _copySelected() async {
    final screen = _screen;
    final ok = await _run(() async {
      final ids = await screen.copy();
      _setSelected([for (final id in ids) ?screen.group.get(id)]);
    });
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.recordCreated)));
    }
  }

  void _toggleSelectAll(List<_Row> rows) {
    setState(() {
      if (_selected.length == rows.length) {
        _setSelected(const []);
      } else {
        _setSelected(rows.map((r) => r.record));
      }
    });
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        scrolledUnderElevation: 0,
        title: Text(widget.title),
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
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l.createNew,
            onPressed: _newRecord,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l.reload,
            onPressed: _search,
          ),
          IconButton(
            icon: Icon(Icons.copy_outlined,
                color: hasSelection ? null : Theme.of(context).disabledColor),
            tooltip: l.duplicate,
            onPressed: hasSelection ? _copySelected : null,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                color: hasSelection
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).disabledColor),
            tooltip: l.delete,
            onPressed: hasSelection ? _deleteSelected : null,
          ),

          // ── Attachment (requires selection) ───────────────────────────
          _AttachmentButton(
            model: _model,
            selectedId: singleSelection ? selectedIds.first : null,
          ),

          // ── Action / Relate / Print / Email (require selection) ───────
          ToolbarDropdownButton(
            icon: Icons.rocket_launch_outlined,
            tooltip: l.launchActions,
            items: _toolbar.actions,
            model: _model,
            selectedIds: selectedIds,
            enabled: hasSelection,
          ),
          ToolbarDropdownButton(
            icon: Icons.link,
            tooltip: l.relatedRecords,
            items: _toolbar.relate,
            model: _model,
            selectedIds: selectedIds,
            enabled: hasSelection,
          ),
          ToolbarDropdownButton(
            icon: Icons.print_outlined,
            tooltip: l.reports,
            items: _toolbar.print,
            model: _model,
            selectedIds: selectedIds,
            enabled: hasSelection,
          ),
          ToolbarDropdownButton(
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
    );
  }

  Widget _buildBody() {
    final screen = _screen;
    final rows = _rows;
    final searchBar = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: _SearchBar(
        controller: _searchCtrl,
        hint: context.l10n.search,
        onSearch: (_) => _search(),
      ),
    );

    // Layout: [context form] → search bar → tabs → table → status
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?_buildContextForm(),
        searchBar,
        if (screen.tabDomain.isNotEmpty) _buildTabBar(screen),
        Expanded(child: _buildListBody(rows)),
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
                    setState(() {
                      _loading = true;
                      _visible = _displayStep;
                      _selected.clear();
                      _expanded.clear();
                    });
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

  Widget _buildListBody(List<_Row> rows) {
    if (rows.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 8),
            Text(context.l10n.noRecordsFound),
            const SizedBox(height: 16),
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
          child: _isHierarchical ? _buildTreeBody(rows) : _buildTableBody(rows),
        ),
        if (_loading) const LinearProgressIndicator(),
      ],
    );
  }

  // ─── Flat table view ─────────────────────────────────────────────────────

  /// Whether the list can be sorted by [column] (root lists, sortable
  /// fields).
  bool _sortable(TreeColumn column) {
    final screen = _screen;
    if (screen.group.parent != null) return false;
    final desc = screen.model.fields[column.name]?.description;
    return desc != null && desc['sortable'] != false;
  }

  Widget _buildTableBody(List<_Row> rows) {
    final screen = _screen;
    final allSelected = _selected.length == rows.length && rows.isNotEmpty;
    final sortIndex =
        _columns.indexWhere((c) => screen.sortDirection(c.name) != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.vertical,
            child: Scrollbar(
              controller: _hScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _hScrollController,
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  sortColumnIndex: sortIndex < 0 ? null : sortIndex + 1,
                  sortAscending: sortIndex < 0 ||
                      screen.sortDirection(_columns[sortIndex].name) == 'ASC',
                  columns: [
                    DataColumn(
                      label: Checkbox(
                        tristate: true,
                        value: allSelected
                            ? true
                            : (_selected.isEmpty ? false : null),
                        onChanged: (_) => _toggleSelectAll(rows),
                      ),
                    ),
                    for (final col in _columns)
                      DataColumn(
                        label: Text(col.label),
                        numeric: isNumericField(_fields[col.name]),
                        onSort: _sortable(col)
                            ? (_, _) => _sortBy(col.name)
                            : null,
                      ),
                  ],
                  rows: [for (final row in rows) _buildRow(row.record)],
                ),
              ),
            ),
          ),
        ),
        ?_buildSumRow(),
      ],
    );
  }

  Future<void> _sortBy(String name) => _run(() async {
        setState(() {
          _loading = true;
          _visible = _displayStep;
        });
        try {
          await _screen.sortBy(name);
        } finally {
          if (mounted) setState(() => _loading = false);
        }
      });

  DataRow _buildRow(Record record) {
    _ensureLoaded(record);
    final isSelected = _selected.contains(record);
    final visual = recordVisual(record, _view?.attributes['visual']);
    return DataRow(
      selected: isSelected,
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Theme.of(context).colorScheme.primaryContainer.withAlpha(80);
        }
        return _visualRowColor(context, visual);
      }),
      cells: [
        DataCell(
          Checkbox(
            value: isSelected,
            onChanged: (_) => setState(() => _toggleSelected(record)),
          ),
        ),
        for (final col in _columns)
          DataCell(
            _cell(record, col.name, const TextStyle(fontSize: 13)),
            onTap: () => setState(() => _setSelected([record])),
            onDoubleTap: () => _openRecord(record),
          ),
      ],
    );
  }

  Widget _cell(Record record, String name, TextStyle style) {
    final fd = _fields[name];
    if (!record.isLoaded(name) && record.id >= 0) return const Text('');
    return isNumericField(fd)
        ? RecordNumericCell.of(record, name, fd!, style: style)
        : Text(recordCellText(record, name, fd),
            overflow: TextOverflow.ellipsis, style: style);
  }

  /// Sum footer for the columns with `sum` (loaded records).
  Widget? _buildSumRow() {
    final screen = _screen;
    final sumCols = _columns.where((c) => c.sum != null && c.sum!.isNotEmpty);
    if (sumCols.isEmpty || screen.group.isEmpty) return null;

    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Container(
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(children: [
        // Checkbox column placeholder
        const SizedBox(width: 48),
        for (final col in _columns)
          if (col.sum == null || col.sum!.isEmpty)
            const Expanded(child: SizedBox.shrink())
          else
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(col.sum!,
                      style: TextStyle(fontSize: 10, color: cs.outline)),
                  Text(
                      formatNumericValue(_sum(screen.group, col.name),
                          digits: _fields[col.name]?.digits, locale: locale),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
      ]),
    );
  }

  static double _sum(RecordGroup group, String name) {
    var total = 0.0;
    for (final r in group) {
      if (!r.isLoaded(name)) continue;
      final v = r.model.fields[name]?.get(r);
      if (v is num) {
        total += v.toDouble();
      } else if (v is TrytonDecimal) {
        total += v.toDouble();
      }
    }
    return total;
  }

  Color? _visualRowColor(BuildContext ctx, String visual) {
    switch (visual) {
      case 'success':
        return Colors.green.withAlpha(30);
      case 'warning':
        return Colors.orange.withAlpha(40);
      case 'danger':
        return Theme.of(ctx).colorScheme.errorContainer.withAlpha(60);
      default:
        return null;
    }
  }

  // ─── Hierarchical tree view ───────────────────────────────────────────────

  /// Header row with column labels for the hierarchical tree.
  Widget _buildTreeHeader() {
    final screen = _screen;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(children: [
        // Checkbox + expander space
        const SizedBox(width: 52),
        for (final col in _columns)
          Expanded(
            child: InkWell(
              onTap: _sortable(col) ? () => _sortBy(col.name) : null,
              child: Row(children: [
                Flexible(
                  child: Text(col.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                if (screen.sortDirection(col.name) case final dir?)
                  Icon(dir == 'ASC' ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 14),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _buildTreeBody(List<_Row> rows) {
    return ListView.builder(
      controller: _scrollController,
      // +1 for the header as the first item → no extra Column child needed
      itemCount: rows.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) return _buildTreeHeader();
        return _buildTreeRow(ctx, rows[i - 1]);
      },
    );
  }

  Widget _buildTreeRow(BuildContext ctx, _Row row) {
    final record = row.record;
    _ensureLoaded(record);
    final isSelected = _selected.contains(record);
    final primary = Theme.of(ctx).colorScheme.primary;
    final visual = recordVisual(record, _view?.attributes['visual']);
    final children = _childrenOf(record);
    final hasChildren = children != null && children.isNotEmpty;
    final expanded = _expanded.contains(record);

    return InkWell(
      onTap: () => setState(() => _setSelected([record])),
      onDoubleTap: () => _openRecord(record),
      child: Container(
        color: isSelected
            ? Theme.of(ctx).colorScheme.primaryContainer.withAlpha(80)
            : _visualRowColor(ctx, visual),
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
        child: Row(
          children: [
            // ① Selection checkbox – always far left, never indented (like SAO)
            SizedBox(
              width: 24,
              child: Checkbox(
                value: isSelected,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (_) => setState(() => _toggleSelected(record)),
              ),
            ),
            // ② Indentation per depth level
            SizedBox(width: row.depth * 20.0),
            // ③ Expand/collapse button (like SAO: tryton-arrow-right/down)
            SizedBox(
              width: 24,
              child: hasChildren
                  ? IconButton(
                      icon: Icon(
                        expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                        color: primary,
                      ),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 24, minHeight: 24),
                      onPressed: () => _toggleExpanded(record),
                    )
                  : null,
            ),
            const SizedBox(width: 4),
            for (final col in _columns)
              Expanded(
                child: _cell(record, col.name, const TextStyle(fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Attachment button ────────────────────────────────────────────────────────

class _AttachmentButton extends ConsumerStatefulWidget {
  final String model;
  final int? selectedId;

  const _AttachmentButton({required this.model, this.selectedId});

  @override
  ConsumerState<_AttachmentButton> createState() => _AttachmentButtonState();
}

class _AttachmentButtonState extends ConsumerState<_AttachmentButton> {
  int _count = 0;

  @override
  void didUpdateWidget(_AttachmentButton old) {
    super.didUpdateWidget(old);
    if (old.selectedId != widget.selectedId) _loadCount();
  }

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final id = widget.selectedId;
    if (id == null) {
      setState(() => _count = 0);
      return;
    }
    try {
      final svc = ref.read(modelServiceProvider);
      final c = await svc.attachmentCount(widget.model, id);
      if (mounted) setState(() => _count = c);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedId == null) return const SizedBox.shrink();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.attach_file),
          tooltip: 'Attachments ($_count)',
          onPressed: () => _openAttachments(context),
        ),
        if (_count > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                _count > 99 ? '99+' : '$_count',
                style: const TextStyle(color: Colors.white, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  void _openAttachments(BuildContext context) {
    final id = widget.selectedId;
    if (id == null) return;
    ref.read(tabsProvider.notifier).openTab(
      title: 'Attachments',
      model: 'ir.attachment',
      initialDomain: [['resource', '=', '${widget.model},$id']],
    );
  }
}

// ─── Search bar with explicit search button ───────────────────────────────────

/// Like the SAO search bar: the request is only sent when the user
/// explicitly clicks the search button or presses Enter – not on every
/// keystroke.
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final void Function(String query) onSearch;

  const _SearchBar({
    required this.controller,
    required this.hint,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 20),
        // Search button on the right – like SAO's explicit search trigger
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Clear button (only shown when text is present)
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (ctx, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      tooltip: context.l10n.clearSearch,
                      onPressed: () {
                        controller.clear();
                        onSearch('');
                      },
                    ),
            ),
            // Explicit search button
            IconButton(
              icon: Icon(Icons.search, color: primary),
              tooltip: context.l10n.search,
              onPressed: () => onSearch(controller.text.trim()),
            ),
          ],
        ),
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      // Enter key also triggers search (like SAO)
      onSubmitted: (q) => onSearch(q.trim()),
      textInputAction: TextInputAction.search,
    );
  }
}
