import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../core/domain/domain_inversion.dart';
import '../../core/icons/tryton_icon.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart' hide TextField;
import '../../core/pyson/pyson_evaluator.dart';
import '../../core/rpc/rpc_cache.dart';
import '../../core/rpc/error_processing.dart';
import '../../core/screen/screen.dart';
import '../../core/serialization/tryton_serializer.dart';
import '../../core/xml/form_xml_parser.dart';
import '../../core/xml/view_definition.dart';
import '../../shared/errors/error_dialogs.dart';
import '../../shared/utils/number_format_utils.dart';
import '../../shared/widgets/toolbar_dropdown_button.dart';
import '../auth/auth_provider.dart';
import '../auth/user_preferences_provider.dart';
import '../model/field_definition.dart';
import '../model/model_service.dart';
import '../model/toolbar_data.dart';
import '../actions/action_service.dart';
import '../shell/tab_manager.dart';
import 'record_cells.dart';
import 'record_link.dart' show parseHexColor;
import 'search_box.dart';
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

/// Column widths per model and field (one entry per occurrence) set in
/// this session (Python `Screen.tree_column_width`); they win over the
/// `width` of the view.
final Map<String, Map<String, List<int?>>> _treeColumnWidth = {};

/// Hidden optional columns per view id (Python `tree_column_optional`).
final Map<int?, Map<String, bool>> _treeColumnOptional = {};

/// Clears the column widths/optional columns of the session (logout).
void clearListCaches() {
  _treeColumnWidth.clear();
  _treeColumnOptional.clear();
}

/// Default column widths per field type (Python `_set_column_width`).
const _defaultWidths = {
  'integer': 80.0,
  'selection': 90.0,
  'reference': 200.0,
  'one2many': 50.0,
  'many2many': 50.0,
  'boolean': 30.0,
  'binary': 200.0,
};

class _ListViewScreenState extends ConsumerState<ListViewScreen> {
  static const _displayStep = 100;

  ScreenView? _view;

  /// The parsed tree view (root attributes, columns, footer buttons).
  TreeViewDefinition? _tree;

  /// All columns of the view (one per occurrence); [_columns] are the
  /// visible ones.
  List<TreeColumn> _allColumns = const [];
  TrytonToolbar _toolbar = const TrytonToolbar();

  /// Widths changed by the user (column key → px).
  final Map<String, double> _resized = {};

  /// After „Reset column widths“ the view's widths are ignored.
  bool _widthsReset = false;

  /// Text typed in the editable row, written on focus loss.
  final Map<String, dynamic> _pending = {};

  /// RPC cache (cleared after storing the tree state / resetting widths).
  RpcCache? _rpcCache;
  bool _treeStateLoaded = false;

  bool _loading = false;

  /// A record is being opened (form view and record are loaded): shown
  /// as progress bar, further opens are ignored.
  bool _opening = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final _scrollController = ScrollController();
  final _hScrollController = ScrollController();

  /// Keyboard focus of the list (Enter opens the selected record).
  final _listFocus = FocusNode();

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
    _saveTreeState();
    _scrollController.dispose();
    _hScrollController.dispose();
    _listFocus.dispose();
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
    // Search text of the screen (normalized, or the action's search_value).
    _searchCtrl.text = screen.searchText;
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
    // The current record (e.g. from the form) is the selection.
    final current = screen.currentRecord;
    _setSelected(current != null ? [current] : screen.selectedRecords);
    final view = screen.currentView;
    if (view != null && view.viewType == 'tree') {
      _view = view;
      _tree = TreeXmlParser()
          .parse(view.definition.arch, view.definition.rawFields);
      _allColumns = _tree!.columns;
    }
    _rpcCache = ref.read(rpcClientProvider).cache;
    _loadToolbar(ref.read(modelServiceProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTreeState());
  }

  // ─── Columns (spec 9.3.2) ─────────────────────────────────────────────────

  /// Visible columns (Python `ViewTree.display`): not `tree_invisible`
  /// (PYSON with the screen context), optional ones as chosen, not the
  /// `exclude_field` and not a field with a unique value by the domain
  /// (except in hierarchical trees).
  List<TreeColumn> get _columns {
    final screen = _screen;
    final env = {...screen.context};
    env['context'] = {...env};
    final evaluator = PYSONEvaluator(env);
    final optional = _treeColumnOptional[_view?.viewId] ?? const {};
    var domain = <dynamic>[];
    try {
      domain = simplify([
        if (screen.domain.isNotEmpty) screen.domain,
        if (screen.tabIndex >= 0 && screen.tabIndex < screen.tabDomain.length &&
            screen.tabDomain[screen.tabIndex].domain.isNotEmpty)
          screen.tabDomain[screen.tabIndex].domain,
      ]);
    } catch (_) {}
    bool invisible(TreeColumn c) {
      try {
        return PYSONEvaluator.truthy(evaluator.eval(c.treeInvisibleExpr));
      } catch (_) {
        return false;
      }
    }

    return [
      for (final c in _allColumns)
        if (c.isButton)
          if (!invisible(c)) c else ...[]
        else if (!invisible(c) &&
            !(c.optional != null && (optional[c.name] ?? c.optional!)) &&
            c.name != screen.attributes.excludeField &&
            !_uniqueByDomain(c.name, domain))
          c
    ];
  }

  /// [name] has one value by [domain] (the column says nothing).
  bool _uniqueByDomain(String name, List<dynamic> domain) {
    if (domain.isEmpty || _isHierarchical) return false;
    final field = _screen.model.fields[name];
    if (field == null) return false;
    try {
      var inverted = domainInversion(domain, name);
      if (inverted is! bool) inverted = simplify(inverted);
      return uniqueValue(inverted, singleValue: field.singleValue).$1;
    } catch (_) {
      return false;
    }
  }

  /// Field columns of [_columns].
  List<TreeColumn> get _fieldColumns => [
        for (final c in _columns)
          if (!c.isButton) c
      ];

  /// Width of [c]: resized, else stored this session, else of the view,
  /// else by type (+20 with symbol).
  double _widthOf(TreeColumn c) {
    final resized = _resized[c.key];
    if (resized != null) return resized;
    if (!c.isButton) {
      final stored = _treeColumnWidth[_model]?[c.name];
      if (stored != null && c.occurrence < stored.length) {
        final w = stored[c.occurrence];
        if (w != null && w > 0) return w.toDouble();
      }
    }
    if (!_widthsReset && c.width > 0) return c.width.toDouble();
    return _computedWidth(c);
  }

  double _computedWidth(TreeColumn c) {
    if (c.isButton) return 80;
    final type = _fields[c.name]?.type;
    if (type == null) return 80;
    var w = _defaultWidths[type] ?? 100;
    if (c.symbol != null) w += 20;
    // headers of narrow types need some room for their label
    return w < 30 ? 30 : w;
  }

  /// `ir.ui.view_tree_width.set_width` with the changed widths (per
  /// occurrence; unchanged, hidden and expanding columns null, the last
  /// visible column null – Python `save_width`).
  Future<void> _saveWidths() async {
    final visible = _fieldColumns;
    final fields = <String, List<int?>>{};
    for (final c in _allColumns) {
      if (c.isButton) continue;
      final w = _resized[c.key];
      fields.putIfAbsent(c.name, () => []).add(
          w == null || !visible.contains(c) || c.expand > 0 ? null : w.round());
    }
    if (visible.isNotEmpty) {
      final last = visible.last;
      final list = fields[last.name]!;
      if (last.occurrence < list.length) list[last.occurrence] = null;
    }
    if (!fields.values.any((l) => l.any((w) => w != null))) return;
    final width = MediaQuery.sizeOf(context).width.round();
    _treeColumnWidth.putIfAbsent(_model, () => {}).addAll(fields);
    try {
      await _screen.model.related('ir.ui.view_tree_width').execute(
          'set_width', [_model, fields, width],
          processException: false);
    } catch (_) {}
  }

  /// „Reset column widths“ (`reset_width`).
  Future<void> _resetWidths() async {
    final width = MediaQuery.sizeOf(context).width.round();
    setState(() {
      _resized.clear();
      _widthsReset = true;
      _treeColumnWidth.remove(_model);
    });
    try {
      await _screen.model.related('ir.ui.view_tree_width').execute(
          'reset_width', [_model, width],
          processException: false);
    } catch (_) {}
    _rpcCache?.clear('model.$_model.fields_view_get');
  }

  /// Shows/hides the optional column [name] (`set_optional` with all
  /// optional fields of the view).
  Future<void> _toggleOptional(String name, bool visible) async {
    final viewId = _view?.viewId;
    final current = {..._treeColumnOptional[viewId] ?? const <String, bool>{}};
    for (final c in _allColumns) {
      if (c.optional != null && !c.isButton) {
        current.putIfAbsent(c.name, () => c.optional!);
      }
    }
    current[name] = !visible;
    setState(() => _treeColumnOptional[viewId] = current);
    if (viewId == null) return;
    try {
      await _screen.model.related('ir.ui.view_tree_optional').execute(
          'set_optional', [viewId, current],
          processException: false);
    } catch (_) {}
  }

  // ─── Tree state (spec 8.8) ───────────────────────────────────────────────

  bool get _hasTreeState =>
      (_tree?.treeState ?? false) && _screen.group.parent == null;

  String get _treeDomainJson =>
      jsonEncode(TrytonSerializer.encode(_screen.domain));

  /// `ir.ui.view_tree_state.get` → expanded and selected id paths.
  Future<void> _loadTreeState() async {
    if (_treeStateLoaded || !_hasTreeState || !mounted) return;
    _treeStateLoaded = true;
    try {
      final result = await _screen.model
          .related('ir.ui.view_tree_state')
          .execute('get', [_model, _treeDomainJson, _fieldChilds],
              processException: false);
      if (result is! List || result.length < 2) return;
      final expanded = jsonDecode('${result[0]}');
      final selected = jsonDecode('${result[1]}');
      if (_isHierarchical && expanded is List) {
        for (final path in expanded) {
          if (path is List) await _expandPath(path);
        }
      }
      if (selected is List && selected.isNotEmpty && selected.first is List) {
        final record = _recordAt(selected.first as List);
        if (record != null && mounted) setState(() => _setSelected([record]));
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  /// The record at the id [path] (root id, child id, …), loading children.
  Record? _recordAt(List path) {
    RecordGroup? group = _screen.group;
    Record? record;
    for (final id in path) {
      if (group == null || id is! int) return null;
      record = group.get(id);
      if (record == null) return null;
      group = _childrenOf(record);
    }
    return record;
  }

  Future<void> _expandPath(List path) async {
    RecordGroup group = _screen.group;
    for (final id in path) {
      if (id is! int) return;
      final record = group.get(id);
      if (record == null) return;
      await record.load(_fieldChilds!, processException: false);
      _expanded.add(record);
      final children = _childrenOf(record);
      if (children == null) return;
      group = children;
    }
  }

  /// Id path of [record] from the screen's group.
  List<int> _pathOf(Record record) {
    final path = [record.id];
    var current = record;
    while (!identical(current.group, _screen.group)) {
      final parent = current.group.parent;
      if (parent == null) break;
      current = parent;
      path.insert(0, current.id);
    }
    return path;
  }

  /// `ir.ui.view_tree_state.set` (on close, switch and new search).
  void _saveTreeState() {
    if (!_hasTreeState) return;
    final expanded = [
      for (final r in _expanded)
        if (!r.destroyed && r.id >= 0) _pathOf(r)
    ];
    final selected = [
      for (final r in _screen.selectedRecords)
        if (!r.destroyed && r.id >= 0) _pathOf(r)
    ];
    final cache = _rpcCache;
    _screen.model.related('ir.ui.view_tree_state').execute('set', [
      _model,
      _treeDomainJson,
      _fieldChilds,
      jsonEncode(expanded),
      jsonEncode(selected),
    ], processException: false).then((_) {
      cache?.clear('model.ir.ui.view_tree_state.get');
    }).catchError((Object _) {});
  }

  // ─── Copy (spec 9.3.4) ───────────────────────────────────────────────────

  /// „Copy selected rows“: tab-separated text of the visible field columns
  /// (Python `on_copy`).
  Future<void> _copyRows() async {
    final selected = _screen.selectedRecords;
    if (selected.isEmpty) return;
    final columns = _fieldColumns;
    final dateFormat = ref.read(dateFormatProvider);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final numberLocale = ref.read(numberLocaleProvider);
    String text(Record r, TreeColumn c) {
      final fd = _fields[c.name];
      if (isNumericField(fd)) {
        final field = r.model.fields[c.name];
        return formatNumericValue(field?.get(r),
            digits: field is FloatField ? field.digits(r, factor: c.factor) : fd!.digits,
            locale: locale,
            numberLocale: numberLocale,
            isInteger: fd!.type == 'integer',
            factor: c.factor,
            grouping: c.grouping);
      }
      return recordCellText(r, c.name, fd,
          dateFormat: dateFormat, localeTag: locale, widget: c.widget);
    }

    final lines = [
      for (final r in selected) [for (final c in columns) text(r, c)].join('\t')
    ];
    final data = selected.length > 1 ? lines.map((l) => '$l\n').join() : lines.single;
    await Clipboard.setData(ClipboardData(text: data));
  }

  // ─── Editable list (spec 9.3.4) ──────────────────────────────────────────

  /// Rows are edited inline (`editable="1"`, screen not readonly).
  bool get _editableView => _view?.editable == true && _view?.viewType == 'tree' && (_tree?.editable ?? false);

  /// Writes the text typed in the editable row of [record].
  Future<void> _flushPending(Record record) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    final pending = Map<String, dynamic>.from(_pending);
    _pending.clear();
    for (final MapEntry(key: name, value: value) in pending.entries) {
      await setRecordWidgetValue(record, name, value);
    }
    await record.idle;
  }

  Future<void> _writeEdited(Record record, String name, dynamic value) async {
    await _run(() => setRecordWidgetValue(record, name, value));
    if (mounted) setState(() {});
  }

  /// Leaving the edited row (Python `__select_changed`): the record is
  /// validated – an invalid row keeps the cursor; in a root list a
  /// modified record is saved.
  Future<bool> _leaveRow(Record? next) async {
    final previous = _screen.currentRecord;
    if (!_editableView ||
        previous == null ||
        identical(previous, next) ||
        previous.destroyed ||
        !_screen.group.contains(previous)) {
      return true;
    }
    await _flushPending(previous);
    final fields = [for (final c in _allColumns) if (!c.isButton) c.name];
    if (!previous.validate(fields: fields)) {
      if (mounted) {
        final texts = _screen.invalidTexts?.call() ?? const InvalidMessages();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(previous.invalidMessage(texts))));
        setState(() {});
      }
      return false;
    }
    // (Child lists – pre_validate – are the x2many widget's business.)
    if (_screen.group.parent == null &&
        (previous.modified || previous.id < 0)) {
      var saved = false;
      await _run(() async => saved = await previous.save());
      if (!saved) return false;
    }
    return true;
  }

  // ─── Drag and drop (sequence) ────────────────────────────────────────────

  /// Rows can be reordered: `sequence` set, flat list, sequence field
  /// writable for all records (Python `drag_data_received`).
  bool get _reorderable {
    final sequence = _tree?.sequence;
    if (sequence == null || _isHierarchical || _screen.group.readonly) {
      return false;
    }
    final field = _screen.model.fields[sequence];
    if (field == null) return false;
    for (final r in _screen.group) {
      field.setState(r);
      if (PYSONEvaluator.truthy(field.stateAttrs(r)['readonly'])) return false;
    }
    return true;
  }

  /// Moves the row [oldIndex] before [newIndex] and renumbers the sequence
  /// (`set_sequence` with `new_position`); saved like other changes.
  Future<void> _reorder(int oldIndex, int newIndex) => _run(() async {
        final group = _screen.group;
        if (oldIndex < 0 || oldIndex >= group.length) return;
        final record = group.elementAt(oldIndex);
        group.move(record, newIndex);
        _setSelected([record]);
        await group.setSequence(
            field: _tree!.sequence!, position: _screen.newPosition);
        if (mounted) setState(() {});
      });


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
        _saveTreeState();
        setState(() {
          _loading = true;
          _visible = _displayStep;
          _selected.clear();
          _expanded.clear();
        });
        try {
          await screen.searchFilter(_searchCtrl.text.trim());
          // The text normalized by the DomainParser (spec 8.3).
          _searchCtrl.text = screen.searchText;
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

  /// Touch devices: tapping opens, a long press selects; otherwise a click
  /// selects and a double click / Enter opens (like SAO).
  bool get _touch => isTouchPlatform(context);

  Future<void> _tapRow(Record record) async {
    if (_touch && !_editableView) {
      await _openRecord(record);
      return;
    }
    if (!await _leaveRow(record)) return;
    if (!mounted) return;
    if (!_editableView) _listFocus.requestFocus();
    setState(() => _setSelected([record]));
  }

  void _longPressRow(Record record) => setState(() => _toggleSelected(record));

  void _toggleSelected(Record record) {
    final selected = {..._selected};
    if (!selected.remove(record)) selected.add(record);
    _setSelected(selected);
  }

  /// Loads the row values of [record] (and its neighbours) once.
  void _ensureLoaded(Record record) {
    final first = _allColumns.where((c) => !c.isButton).firstOrNull;
    final name = first?.name ?? 'rec_name';
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
        if (!await _leaveRow(null)) return;
        final record = await _screen.newRecord();
        // editable list: the new row at new_position is edited
        if (record != null && mounted && _editableView) {
          setState(() => _setSelected([record]));
        }
      });

  /// Row activation (SAO `default_row_activate`): with `keyword_open` the
  /// `tree_open` action of the record, otherwise the form of the record
  /// (same group and record).
  Future<void> _openRecord(Record record) => _whileOpening(() async {
        final screen = _screen;
        _setSelected([record]);
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
        final current = _screen.currentRecord;
        if (current != null) await _flushPending(current);
        await _screen.saveCurrent();
        if (mounted) setState(() {});
      });

  /// Switch: the form of the first selected record (spec 8.2).
  Future<void> _switchToForm() => _whileOpening(() => _run(() async {
        final screen = _screen;
        if (!await _leaveRow(null)) return;
        _saveTreeState();
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
            model: _model,
            selectedId: singleSelection ? selectedIds.first : null,
          ),

          // ── Action / Relate / Print / Email (require selection) ───────
          ToolbarDropdownButton(
            screen: _screen,
            icon: Icons.rocket_launch_outlined,
            tooltip: l.launchActions,
            items: _toolbar.actions,
            model: _model,
            selectedIds: selectedIds,
            enabled: hasSelection,
          ),
          ToolbarDropdownButton(
            screen: _screen,
            icon: Icons.link,
            tooltip: l.relatedRecords,
            items: _toolbar.relate,
            model: _model,
            selectedIds: selectedIds,
            enabled: hasSelection,
          ),
          ToolbarDropdownButton(
            screen: _screen,
            icon: Icons.print_outlined,
            tooltip: l.reports,
            items: _toolbar.print,
            model: _model,
            selectedIds: selectedIds,
            enabled: hasSelection,
          ),
          ToolbarDropdownButton(
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
    );
  }

  Widget _buildBody() {
    final screen = _screen;
    final rows = _rows;
    final searchBar = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SearchBox(
        screen: _screen,
        controller: _searchCtrl,
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
          // Enter opens the selected record (SAO row activation).
          child: Focus(
            focusNode: _listFocus,
            onKeyEvent: (node, event) {
              final selected = _screen.selectedRecords;
              // Ctrl/Cmd+C: copy the selected rows (tab-separated)
              final keyboard = HardwareKeyboard.instance;
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.keyC &&
                  (keyboard.isControlPressed || keyboard.isMetaPressed) &&
                  selected.isNotEmpty) {
                _copyRows();
                return KeyEventResult.handled;
              }
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
                  selected.isNotEmpty) {
                _openRecord(selected.first);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: _buildGrid(rows),
          ),
        ),
        if (_loading || _opening) const LinearProgressIndicator(),
        ?_buildFooterButtons(),
      ],
    );
  }

  // ─── Table (spec 9.3) ───────────────────────────────────────────────────

  /// Whether the list can be sorted by [column] (Python: no `sequence`,
  /// no `field_childs`, sortable field; root lists).
  bool _sortable(TreeColumn column) {
    final screen = _screen;
    if (column.isButton || screen.group.parent != null) return false;
    if (_tree?.sequence != null || _isHierarchical) return false;
    final desc = screen.model.fields[column.name]?.description;
    return desc != null && desc['sortable'] != false;
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

  static const _selectionWidth = 40.0;
  static const _handleWidth = 28.0;
  static const _menuWidth = 36.0;

  /// The table: header, rows (flat, tree or reorderable), sum row, all
  /// columns at their width (expanding ones share the free space).
  Widget _buildGrid(List<_Row> rows) {
    final columns = _columns;
    final reorderable = _reorderable;
    return LayoutBuilder(builder: (context, constraints) {
      final widths = {for (final c in columns) c.key: _widthOf(c)};
      final lead = _selectionWidth + (reorderable ? _handleWidth : 0);
      var total = lead + _menuWidth + widths.values.fold(0.0, (a, b) => a + b);
      final free = constraints.maxWidth - total;
      final expanding = [for (final c in columns) if (c.expand > 0) c];
      if (free > 0 && expanding.isNotEmpty) {
        final weights = expanding.fold(0, (a, c) => a + c.expand);
        for (final c in expanding) {
          widths[c.key] = widths[c.key]! + free * c.expand / weights;
        }
        total = constraints.maxWidth;
      }
      final width = total < constraints.maxWidth ? constraints.maxWidth : total;
      final body = reorderable
          ? ReorderableListView.builder(
              scrollController: _scrollController,
              buildDefaultDragHandles: false,
              itemCount: rows.length,
              // newIndex counts without the moved row; group.move (Python)
              // counts with it
              onReorderItem: (oldIndex, newIndex) => _reorder(
                  oldIndex, newIndex > oldIndex ? newIndex + 1 : newIndex),
              itemBuilder: (context, i) => _buildRow(rows[i], i, columns, widths,
                  key: ObjectKey(rows[i].record), reorderable: true),
            )
          : ListView.builder(
              controller: _scrollController,
              itemCount: rows.length,
              itemBuilder: (context, i) =>
                  _buildRow(rows[i], i, columns, widths, key: ObjectKey(rows[i].record)),
            );
      return Scrollbar(
        controller: _hScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _hScrollController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(rows, columns, widths, reorderable),
                Expanded(child: body),
                ?_buildSumRow(columns, widths, reorderable),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildHeader(List<_Row> rows, List<TreeColumn> columns,
      Map<String, double> widths, bool reorderable) {
    final screen = _screen;
    final cs = Theme.of(context).colorScheme;
    final allSelected = _selected.length == rows.length && rows.isNotEmpty;
    return Container(
      color: cs.surfaceContainerHighest,
      height: 40,
      child: Row(children: [
        SizedBox(
          width: _selectionWidth,
          child: Checkbox(
            tristate: true,
            value: allSelected ? true : (_selected.isEmpty ? false : null),
            onChanged: (_) => _toggleSelectAll(rows),
          ),
        ),
        if (reorderable) const SizedBox(width: _handleWidth),
        for (final c in columns)
          SizedBox(
            width: widths[c.key],
            child: _HeaderCell(
              key: ValueKey('header-${c.key}'),
              label: c.label,
              help: c.help,
              numeric: isNumericField(_fields[c.name]),
              required: _editableView &&
                  _screen.model.fields[c.name]?.description['required'] == true,
              sortDirection: c.isButton ? null : screen.sortDirection(c.name),
              onSort: _sortable(c) ? () => _sortBy(c.name) : null,
              onResize: (dx) => setState(() {
                _resized[c.key] =
                    ((_resized[c.key] ?? widths[c.key]!) + dx).clamp(30.0, 2000.0);
              }),
              onResizeEnd: _saveWidths,
            ),
          ),
        SizedBox(width: _menuWidth, child: _buildColumnMenu()),
      ]),
    );
  }

  /// Menu of the header: optional columns, reset widths, copy rows.
  Widget _buildColumnMenu() {
    final l = context.l10n;
    final optional = _treeColumnOptional[_view?.viewId] ?? const {};
    final names = <String, String>{};
    for (final c in _allColumns) {
      if (c.optional != null && !c.isButton) {
        names[c.name] = names.containsKey(c.name)
            ? '${names[c.name]} / ${c.label}'
            : c.label;
      }
    }
    return PopupMenuButton<String>(
      key: const ValueKey('list-column-menu'),
      icon: const Icon(Icons.view_column_outlined, size: 18),
      tooltip: l.columns,
      padding: EdgeInsets.zero,
      onSelected: (v) {
        if (v == '__reset') {
          _resetWidths();
        } else if (v == '__copy') {
          _copyRows();
        } else {
          final hidden = optional[v] ??
              _allColumns.firstWhere((c) => c.name == v).optional!;
          _toggleOptional(v, hidden);
        }
      },
      itemBuilder: (context) => [
        for (final MapEntry(key: name, value: label) in names.entries)
          CheckedPopupMenuItem<String>(
            value: name,
            checked: !(optional[name] ??
                _allColumns.firstWhere((c) => c.name == name).optional!),
            child: Text(label),
          ),
        if (names.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem(value: '__reset', child: Text(l.resetColumnWidths)),
        PopupMenuItem(
          value: '__copy',
          enabled: _screen.selectedRecords.isNotEmpty,
          child: Text(l.copySelectedRows),
        ),
      ],
    );
  }

  Widget _buildRow(_Row row, int index, List<TreeColumn> columns,
      Map<String, double> widths,
      {required Key key, bool reorderable = false}) {
    final record = row.record;
    _ensureLoaded(record);
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selected.contains(record);
    final visual = recordVisual(record, _tree?.visual);
    final editing = _editableView &&
        identical(_screen.currentRecord, record) &&
        !record.readonly;
    final firstField = columns.where((c) => !c.isButton).firstOrNull;
    final children = _childrenOf(record);
    final hasChildren = _isHierarchical &&
        (children == null ? record.id >= 0 : children.isNotEmpty);
    final expanded = _expanded.contains(record);
    Widget cell(TreeColumn c) {
      Widget content = _cellContent(record, c, editing);
      if (_isHierarchical && identical(c, firstField)) {
        content = Row(children: [
          SizedBox(width: row.depth * 20.0),
          SizedBox(
            width: 24,
            child: hasChildren
                ? IconButton(
                    key: ValueKey('expand-${record.id}'),
                    icon: Icon(expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                        color: cs.primary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () => _toggleExpanded(record),
                  )
                : null,
          ),
          Expanded(child: content),
        ]);
      }
      return SizedBox(
        width: widths[c.key],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: content,
        ),
      );
    }

    return Material(
      key: key,
      color: isSelected
          ? cs.primaryContainer.withAlpha(80)
          : (_visualRowColor(context, visual) ?? Colors.transparent),
      child: InkWell(
        onTap: editing ? null : () => _tapRow(record),
        onDoubleTap: _touch || editing ? null : () => _openRecord(record),
        onLongPress: _touch && !editing ? () => _longPressRow(record) : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant.withAlpha(80)))),
          child: Row(children: [
            SizedBox(
              width: _selectionWidth,
              child: Checkbox(
                value: isSelected,
                onChanged: (_) => setState(() => _toggleSelected(record)),
              ),
            ),
            if (reorderable)
              SizedBox(
                width: _handleWidth,
                child: ReorderableDragStartListener(
                  key: ValueKey('drag-${record.id}'),
                  index: index,
                  child: Icon(Icons.drag_indicator, size: 18, color: cs.outline),
                ),
              ),
            for (final c in columns) cell(c),
          ]),
        ),
      ),
    );
  }

  /// A cell (spec 9.3.3): button, editor of the edited row, or the value
  /// with prefixes/suffixes and the column's `visual`.
  Widget _cellContent(Record record, TreeColumn c, bool editing) {
    const style = TextStyle(fontSize: 13);
    final button = c.button;
    if (button != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: RecordButton(
            node: button,
            record: record,
            onPressed: (node) => _rowButton(record, node)),
      );
    }
    final fd = _fields[c.name];
    final field = record.model.fields[c.name];
    if (editing && fd != null && field != null) {
      return _editor(record, c);
    }
    if (!record.isLoaded(c.name) && record.id >= 0) return const Text('');
    final visual = recordVisual(record, c.visual is String ? c.visual as String : null);
    final color = switch (visual) {
      'success' => Colors.green.shade700,
      'warning' => Colors.orange.shade800,
      'danger' => Theme.of(context).colorScheme.error,
      'muted' => Theme.of(context).colorScheme.outline,
      _ => null,
    };
    final textStyle = color == null ? style : style.copyWith(color: color);
    Widget value;
    switch (c.widget ?? fd?.type) {
      case 'boolean':
        value = Icon(
            field?.get(record) == true ? Icons.check_box : Icons.check_box_outline_blank,
            size: 18,
            color: Theme.of(context).colorScheme.outline);
      case 'progressbar':
        final v = field?.get(record);
        final p = v is num ? v.toDouble() : (v is TrytonDecimal ? v.toDouble() : 0.0);
        value = Row(children: [
          Expanded(child: LinearProgressIndicator(value: p.clamp(0.0, 1.0))),
          const SizedBox(width: 4),
          Text('${(p * 100).toStringAsFixed(0)} %', style: textStyle),
        ]);
      default:
        value = isNumericField(fd)
            ? RecordNumericCell.of(record, c.name, fd!,
                style: textStyle,
                factor: c.factor,
                grouping: c.grouping,
                symbol: c.symbol)
            : RecordTextCell(record, c.name, fd, style: textStyle, widget: c.widget);
    }
    final prefixes = [
      ..._linkPrefix(record, c),
      for (final a in c.prefixes) _affix(record, a),
      ..._referencePrefix(record, c),
    ];
    final suffixes = [for (final a in c.suffixes) _affix(record, a)];
    if (prefixes.isEmpty && suffixes.isEmpty) return value;
    return Row(children: [
      ...prefixes,
      Expanded(child: value),
      ...suffixes,
    ]);
  }

  /// Editor of the edited row: the form widget of the field (one-cell
  /// form on the record, on_change and states like in forms).
  Widget _editor(Record record, TreeColumn c) => RecordForm(
        key: ValueKey('edit-${record.id}-${c.key}'),
        model: _model,
        root: FormRoot(col: 1, children: [
          FieldNode(
            name: c.name,
            attrs: c.attrs,
            widget: c.widget,
            readonly: c.readonly,
          ),
        ]),
        viewDef: _view!.definition,
        record: record,
        onTextChanged: (name, value) => _pending[name] = value,
        onBlur: (name) {
          if (_pending.containsKey(name)) {
            _writeEdited(record, name, _pending.remove(name));
          }
        },
        onChangedImmediate: (name, value) => _writeEdited(record, name, value),
        isReadOnly: false,
      );

  /// url/email/callto/sip: a link icon before the value.
  List<Widget> _linkPrefix(Record record, TreeColumn c) {
    final scheme = c.widget;
    if (scheme == null || !const {'url', 'email', 'callto', 'sip'}.contains(scheme)) {
      return const [];
    }
    final value = record.model.fields[c.name]?.get(record);
    if (value is! String || value.isEmpty) return const [];
    final uri = switch (scheme) {
      'email' => Uri.tryParse('mailto:$value'),
      'callto' => Uri.tryParse('callto:$value'),
      'sip' => Uri.tryParse('sip:$value'),
      _ => Uri.tryParse(value.contains('://') ? value : 'http://$value'),
    };
    return [
      InkWell(
        onTap: uri == null ? null : () => launchUrl(uri),
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(scheme == 'email' ? Icons.email_outlined : Icons.open_in_new,
              size: 14, color: Theme.of(context).colorScheme.primary),
        ),
      ),
    ];
  }

  /// Reference: the model label before the rec_name (Python
  /// `_ReferenceSelection`).
  List<Widget> _referencePrefix(Record record, TreeColumn c) {
    final field = record.model.fields[c.name];
    if (field is! ReferenceField) return const [];
    final value = field.get(record);
    final model = value is String && value.contains(',')
        ? value.split(',').first
        : (value is List && value.isNotEmpty ? '${value.first}' : null);
    if (model == null || model.isEmpty) return const [];
    final selection = _fields[c.name]?.selection;
    final label = selection?.where((s) => '${s[0]}' == model).firstOrNull?[1] ??
        ref.read(modelServiceProvider).metadata?.nameOf(model) ??
        model;
    return [
      Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Text('$label:',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
      ),
    ];
  }

  /// `<prefix>`/`<suffix>`: icon (name or field value) or text.
  Widget _affix(Record record, Map<String, dynamic> attrs) {
    final string = attrs['string'];
    if (string is String && string.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(string, style: const TextStyle(fontSize: 12)),
      );
    }
    var icon = attrs['icon'];
    final field = icon is String ? record.model.fields[icon] : null;
    if (field != null) icon = field.get(record);
    if (icon is! String || icon.isEmpty) return const SizedBox.shrink();
    if (attrs['icon_type'] == 'url') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ClipOval(
            child: Image.network(icon, width: 18, height: 18,
                errorBuilder: (_, _, _) => const SizedBox(width: 18))),
      );
    }
    if (attrs['icon_type'] == 'color') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(width: 12, height: 12, color: parseHexColor(icon)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TrytonIcon(iconName: icon, size: 16),
    );
  }

  /// A button of a row: the row is selected, then the button runs.
  Future<void> _rowButton(Record record, ButtonNode node) => _run(() async {
        if (!await _leaveRow(record)) return;
        setState(() => _setSelected([record]));
        await _screen.button(node);
      });

  /// Sum row (Python `update_with_selection`): „selected / all“ of the
  /// loaded records per `sum` column, `-` while not all are loaded.
  Widget? _buildSumRow(
      List<TreeColumn> columns, Map<String, double> widths, bool reorderable) {
    if (!columns.any((c) => c.sum) || _screen.group.isEmpty) return null;
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('list-sum-row'),
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: _selectionWidth + (reorderable ? _handleWidth : 0)),
        for (final c in columns)
          SizedBox(
            width: widths[c.key],
            child: c.sum
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(_sumText(c),
                        key: ValueKey('sum-${c.key}'),
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  )
                : null,
          ),
      ]),
    );
  }

  String _sumText(TreeColumn c) => recordSumText(
      _screen.group, c.name, _screen.selectedRecords,
      locale: Localizations.localeOf(context).toLanguageTag(),
      numberLocale: ref.watch(numberLocaleProvider));

  /// `<button multiple="1">`: buttons for the selected records.
  Widget? _buildFooterButtons() {
    final buttons = _tree?.buttons ?? const [];
    if (buttons.isEmpty) return null;
    final selected = _screen.selectedRecords;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Wrap(spacing: 8, runSpacing: 4, children: [
        for (final b in buttons)
          if (selected.isEmpty ||
              !RecordButton.statesOf(b, selected.first).invisible)
            OutlinedButton(
              key: ValueKey('multi-button-${b.name}'),
              onPressed: selected.isEmpty ||
                      selected.any((r) => RecordButton.statesOf(b, r).readonly)
                  ? null
                  : () => _run(() => _screen.button(b)),
              child: Text(b.string ?? b.name),
            ),
      ]),
    );
  }

  Color? _visualRowColor(BuildContext ctx, String visual) {
    switch (visual) {
      case 'success':
        return Colors.green.withAlpha(30);
      case 'warning':
        return Colors.orange.withAlpha(40);
      case 'danger':
        return Theme.of(ctx).colorScheme.errorContainer.withAlpha(60);
      case 'muted':
        return Theme.of(ctx).colorScheme.surfaceContainerHigh;
      default:
        return null;
    }
  }
}

/// Header of a column: label (tooltip `help`), sort arrow, resize handle.
class _HeaderCell extends StatelessWidget {
  final String label;
  final String? help;
  final bool numeric;
  final bool required;
  final String? sortDirection;
  final VoidCallback? onSort;
  final void Function(double dx) onResize;
  final VoidCallback onResizeEnd;

  const _HeaderCell({
    super.key,
    required this.label,
    this.help,
    this.numeric = false,
    this.required = false,
    this.sortDirection,
    this.onSort,
    required this.onResize,
    required this.onResizeEnd,
  });

  @override
  Widget build(BuildContext context) {
    Widget text = Text(label,
        overflow: TextOverflow.ellipsis,
        textAlign: numeric ? TextAlign.end : TextAlign.start,
        style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            decoration: required ? TextDecoration.underline : null));
    if (help != null) text = Tooltip(message: help!, child: text);
    return Stack(children: [
      Positioned.fill(
        child: InkWell(
          onTap: onSort,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(children: [
              Expanded(child: text),
              if (sortDirection != null)
                Icon(sortDirection == 'ASC' ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 14),
            ]),
          ),
        ),
      ),
      // resize handle at the right edge
      Positioned(
        right: 0,
        top: 0,
        bottom: 0,
        width: 8,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => onResize(d.delta.dx),
            onHorizontalDragEnd: (_) => onResizeEnd(),
            child: Center(
              child: Container(
                  width: 1, color: Theme.of(context).colorScheme.outlineVariant),
            ),
          ),
        ),
      ),
    ]);
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
