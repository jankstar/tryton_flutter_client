import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/domain/domain_inversion.dart';
import '../../core/domain/domain_parser.dart' show convertValue;
import '../../core/icons/tryton_icon.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart' hide TextField;
import '../../core/pyson/pyson_evaluator.dart';
import '../../core/rpc/error_processing.dart';
import '../../core/rpc/rpc_cache.dart';
import '../../core/screen/screen.dart';
import '../../core/serialization/tryton_serializer.dart';
import '../../core/xml/form_xml_parser.dart';
import '../../core/xml/view_definition.dart';
import '../../shared/errors/error_dialogs.dart';
import '../../shared/utils/csv_format.dart';
import '../../shared/utils/number_format_utils.dart';
import '../auth/auth_provider.dart';
import '../auth/user_preferences_provider.dart';
import '../model/field_definition.dart';
import '../model/model_service.dart';
import 'record_cells.dart';
import 'record_form.dart';
import 'record_link.dart' show parseHexColor;
import 'record_widget_values.dart';
import 'tree_context_menu.dart';
import '../../shared/dialogs/tryton_dialogs.dart';

/// A visible row: record and depth (tree views).
typedef TreeRow = ({Record record, int depth});

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

/// Access of a host to its [TreeView] (selection, edited row, tree
/// state).
class TreeViewController {
  _TreeViewState? _state;

  /// The visible rows (with the children of expanded records).
  List<TreeRow> get rows => _state?._rows ?? const [];

  /// Rows are edited inline (`editable`, screen not readonly).
  bool get editable => _state?._editableView ?? false;

  /// Selects [records] (the first one becomes the current record).
  void select(Iterable<Record> records) => _state?._select(records);

  /// Selects [record] and edits its first editable cell (new lines of an
  /// editable list).
  void edit(Record record) => _state?._edit(record);

  /// Before a new search: no selection, nothing expanded, first rows.
  void reset() => _state?._reset();

  /// `ir.ui.view_tree_state.set` (before a search, switch or close).
  void saveTreeState() => _state?._saveTreeState();

  /// Writes the text typed in the edited row.
  Future<void> flush() async {
    final state = _state;
    final record = state?.widget.screen.currentRecord;
    if (state != null && record != null) await state._flushPending(record);
  }

  /// Leaves the edited row towards [next] (validation; a root list saves
  /// the record). False keeps the row.
  Future<bool> leaveRow(Record? next) async =>
      await _state?._leaveRow(next) ?? true;

  /// „Copy selected rows“ (tab-separated text).
  Future<void> copyRows() async => _state?._copy();

  /// „Paste rows“ of an editable list from the clipboard.
  Future<void> pasteRows() async => _state?._paste();
}

/// The tree view of a [TrytonScreen] (spec 9.3) – the same component for
/// the main list of a tab and the x2many list of a form (spec 9.2.7):
/// columns (`tree_invisible`, optional, `exclude_field`, unique by the
/// domain), widths (resize, `set_width`, reset), header menu, rows flat
/// or as a tree (`field_childs`, `tree_state`), selection, inline editing
/// (`editable`), drag and drop by `sequence`, sum row, button columns and
/// footer buttons, `visual`, sorting (root: new search; child: local).
///
/// Rows are loaded lazily with `Record.load` (neighbours in one `read`)
/// and rendered in steps of [displayStep]; at the end [onEndReached]
/// appends the next page of a root list.
class TreeView extends ConsumerStatefulWidget {
  final TrytonScreen screen;

  /// The tree view of [screen] shown.
  final ScreenView view;
  final TreeViewController? controller;

  /// Row activation (double click / Enter; tap on touch platforms).
  final void Function(Record record) onActivate;
  final VoidCallback? onSelectionChanged;

  /// All group records are shown (next search page).
  final VoidCallback? onEndReached;

  /// Inside a form: as high as the rows, at most [maxHeight].
  final bool shrinkWrap;
  final double? maxHeight;

  /// Prefix of the keys of the table (`list`, `x2m`).
  final String keyPrefix;

  /// Number of rows rendered at once (Python `display_size`).
  final int displayStep;

  const TreeView({
    super.key,
    required this.screen,
    required this.view,
    required this.onActivate,
    this.controller,
    this.onSelectionChanged,
    this.onEndReached,
    this.shrinkWrap = false,
    this.maxHeight,
    this.keyPrefix = 'list',
    this.displayStep = 100,
  });

  @override
  ConsumerState<TreeView> createState() => _TreeViewState();
}

class _TreeViewState extends ConsumerState<TreeView> {
  /// The parsed tree view (root attributes, columns, footer buttons).
  late TreeViewDefinition _tree;

  /// All columns of the view (one per occurrence); [_columns] are the
  /// visible ones.
  List<TreeColumn> _allColumns = const [];

  /// Widths changed by the user (column key → px).
  final Map<String, double> _resized = {};

  /// After „Reset column widths“ the view's widths are ignored.
  bool _widthsReset = false;

  /// Text typed in the editable row, written on focus loss.
  final Map<String, dynamic> _pending = {};

  /// RPC cache (cleared after storing the tree state / resetting widths).
  RpcCache? _rpcCache;
  bool _treeStateLoaded = false;

  final _scrollController = ScrollController();
  final _hScrollController = ScrollController();

  /// Keyboard focus of the list (Enter opens the selected record).
  final _listFocus = FocusNode();

  /// Number of group records shown (grows while scrolling).
  late int _visible = widget.displayStep;
  final Set<Record> _selected = {};

  /// Expanded records of a tree view.
  final Set<Record> _expanded = {};

  /// Records whose row values are being loaded.
  final Set<Record> _rowLoading = {};

  /// Local order of a child list (Python: client side sort): field and
  /// `ASC`/`DESC`.
  (String, String)? _localOrder;

  /// Context menu (spec 9.3.4): its entries, opened at the pointer.
  final _contextMenu = MenuController();
  final _anchorKey = GlobalKey();
  List<Widget> _contextEntries = const [];

  /// Column of the last click (start column of „Paste rows“) and pointer
  /// of the last press (position of the menu on a long press).
  TreeColumn? _cursorColumn;
  Offset? _lastPointer;

  TrytonScreen get _screen => widget.screen;
  ScreenView get _view => widget.view;
  String get _model => _screen.model.name;
  Map<String, FieldDefinition> get _fields => _view.definition.fields;
  String? get _fieldChilds => _view.fieldChilds;
  bool get _isHierarchical => _fieldChilds != null;
  bool get _isRoot => _screen.group.parent == null;

  /// Key of an element of the table (`sum-…`; `x2m-sum-…` in a form).
  String _key(String name) =>
      widget.keyPrefix == 'list' ? name : '${widget.keyPrefix}-$name';

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _scrollController.addListener(_onScroll);
    _parse();
    _screen.addListener(_onScreenChanged);
    // The current record (e.g. from the form) is the selection; the
    // screen is not notified while the host builds.
    final current = _screen.currentRecord;
    final initial = current != null ? [current] : _screen.selectedRecords;
    _selected.addAll(initial);
    _screen.selectedRecords = [
      for (final r in _rows.map((row) => row.record))
        if (_selected.contains(r)) r
    ];
    if (!identical(current, _screen.selectedRecords.firstOrNull)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setSelected({..._selected});
      });
    }
    _rpcCache = ref.read(rpcClientProvider).cache;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTreeState());
  }

  void _parse() {
    _tree = TreeXmlParser()
        .parse(_view.definition.arch, _view.definition.rawFields);
    _allColumns = _tree.columns;
  }

  @override
  void didUpdateWidget(TreeView old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      if (identical(old.controller?._state, this)) old.controller?._state = null;
      widget.controller?._state = this;
    }
    if (!identical(old.screen, widget.screen)) {
      old.screen.removeListener(_onScreenChanged);
      widget.screen.addListener(_onScreenChanged);
      _reset();
    }
    if (!identical(old.view, widget.view)) _parse();
  }

  @override
  void dispose() {
    _saveTreeState();
    if (identical(widget.controller?._state, this)) widget.controller?._state = null;
    _screen.removeListener(_onScreenChanged);
    _scrollController.dispose();
    _hScrollController.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  void _onScreenChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels < pos.maxScrollExtent - 200) return;
    if (_visible < _screen.group.length) {
      setState(() => _visible += widget.displayStep);
    } else {
      widget.onEndReached?.call();
    }
  }

  void _reset() {
    _saveTreeState();
    setState(() {
      _visible = widget.displayStep;
      _selected.clear();
      _expanded.clear();
    });
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
    final optional = _treeColumnOptional[_view.viewId] ?? const {};
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
    final viewId = _view.viewId;
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

  bool get _hasTreeState => _tree.treeState && _isRoot;

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
        if (record != null && mounted) _select([record]);
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

  /// Text of [c] in the row of [r] as shown (numbers with the locale).
  String _cellText(Record r, TreeColumn c) {
    final fd = _fields[c.name];
    if (isNumericField(fd)) {
      final field = r.model.fields[c.name];
      return formatNumericValue(field?.get(r),
          digits: field is FloatField ? field.digits(r, factor: c.factor) : fd!.digits,
          locale: Localizations.localeOf(context).toLanguageTag(),
          numberLocale: ref.read(numberLocaleProvider),
          isInteger: fd!.type == 'integer',
          factor: c.factor,
          grouping: c.grouping);
    }
    return recordCellText(r, c.name, fd,
        dateFormat: ref.read(dateFormatProvider),
        localeTag: Localizations.localeOf(context).toLanguageTag(),
        widget: c.widget);
  }

  /// Copy (Python `on_copy`): the [columns] (default all visible field
  /// columns) of the selected rows as tab-separated text, one line per
  /// row (`csv` with tab).
  Future<void> _copy({List<TreeColumn>? columns}) async {
    final selected = _screen.selectedRecords;
    if (selected.isEmpty) return;
    final shown = columns ?? _fieldColumns;
    final lines = [
      for (final r in selected)
        csvRow([for (final c in shown) _cellText(r, c)], delimiter: '\t')
    ];
    final data = selected.length > 1 ? lines.map((l) => '$l\n').join() : lines.single;
    await Clipboard.setData(ClipboardData(text: data));
  }

  /// „Paste rows“ (Python `on_paste`, editable lists): the tab-separated
  /// lines of the clipboard from the current record on (new records at
  /// the end, one `default_get`), the values from the start column on
  /// ([from], else the last clicked column). Texts are converted like
  /// search values (DomainParser `convert_value` with the locale of the
  /// preferences), many2one/reference by a `rec_name` search that must
  /// find exactly one record. An invalid row stops; a root list saves
  /// each row, a child list keeps them in its group.
  Future<void> _paste([TreeColumn? from]) async {
    if (!_editableView) return;
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.isEmpty || !mounted) return;
    final lines = parseCsv(text, delimiter: '\t');
    var columns = _fieldColumns;
    final start = from ?? _cursorColumn;
    if (start != null && columns.contains(start)) {
      columns = columns.sublist(columns.indexOf(start));
    }
    final group = _screen.group;
    var record = _screen.currentRecord;
    var idx = record != null && group.contains(record)
        ? group.toList().indexOf(record)
        : group.length;
    Map<String, dynamic>? defaults;
    await _run(() async {
      for (final line in lines) {
        if (line.isEmpty) continue;
        if (idx >= group.length) {
          final created = group.newRecord();
          if (defaults == null) {
            defaults = await created.defaultGet();
          } else {
            await created.setDefault(defaults!);
          }
          group.add(created);
        }
        final current = record = group.elementAt(idx);
        for (var i = 0; i < columns.length && i < line.length; i++) {
          final value = line[i];
          if (_cellText(current, columns[i]) == value) continue;
          await _setFromText(current, columns[i], value);
          if (value.isNotEmpty && _cellText(current, columns[i]).isEmpty) {
            // a value could not be set: the next line gets a new record
            idx = group.length - 1;
            break;
          }
        }
        await current.idle;
        if (!current.validate()) break;
        if (_isRoot && !await current.save()) break;
        idx++;
      }
    });
    if (mounted && record != null) _select([record!]);
  }

  /// Sets [text] as value of [c] (Python `value_from_text` /
  /// `search_remote`).
  Future<void> _setFromText(Record record, TreeColumn c, String text) async {
    final field = record.model.fields[c.name];
    final type = _fields[c.name]?.type;
    if (field == null || type == null || field.description['readonly'] == true) {
      return;
    }
    if (field is Many2OneField || field is ReferenceField) {
      String? relation = field.description['relation'] as String?;
      if (field is ReferenceField) {
        final value = field.get(record);
        relation = value is String && value.contains(',')
            ? value.split(',').first
            : null;
      }
      if (text.isEmpty || relation == null) {
        await setRecordWidgetValue(record, c.name, null);
        return;
      }
      final domain = field.getDomain(record);
      final found = await record.model.related(relation).execute('search_read', [
        [
          if (domain.isNotEmpty) domain,
          ['rec_name', 'ilike', '%$text%'],
        ],
        0,
        2,
        null,
        ['rec_name'],
      ], context: field.getSearchContext(record), processException: false);
      final hit = found is List && found.length == 1 && found.single is Map
          ? found.single as Map
          : null;
      final id = hit?['id'];
      final value = id is int ? [id, '${hit!['rec_name'] ?? ''}'] : null;
      if (field is ReferenceField) {
        await setRecordWidgetValue(
            record, c.name, value == null ? null : [relation, value]);
      } else {
        await setRecordWidgetValue(record, c.name, value);
      }
      return;
    }
    final dynamic value = switch (type) {
      'char' || 'text' || 'one2many' || 'many2many' || 'binary' => text,
      _ => convertValue({...field.description, 'type': type}, text,
          ref.read(modelServiceProvider).metadata?.parserContext),
    };
    if (type == 'one2many' || type == 'many2many' || type == 'binary') return;
    await setRecordWidgetValue(record, c.name, value);
  }

  /// A parent of [record] is modified: no record actions (Python `pop`).
  bool _parentModified(Record record) {
    var parent = record.group.parent;
    while (parent != null) {
      if (parent.modified) return true;
      parent = parent.group.parent;
    }
    return false;
  }

  /// Context menu of the row of [record] at [global] (spec 9.3.4, Python
  /// `__button_press`): copy cell/row resp. column/rows, paste rows in
  /// editable lists, the record's functions (logs, attachments, notes,
  /// actions, relate, report, print, e-mail) unless a parent is modified,
  /// and per visible many2one/reference column a submenu for the linked
  /// record.
  Future<void> _openContextMenu(
      Record record, TreeColumn? column, Offset global) async {
    if (!_selected.contains(record)) _select([record]);
    final l = context.l10n;
    final selected = _screen.selectedRecords;
    final field = column != null && !column.isButton ? column : null;
    Widget item(String key, String label, VoidCallback? onPressed) =>
        MenuItemButton(key: ValueKey(key), onPressed: onPressed, child: Text(label));
    final entries = <Widget>[
      if (selected.length == 1) ...[
        item('ctx-copy', l.ctxCopy, field == null ? null : () => _copy(columns: [field])),
        item('ctx-copy-row', l.ctxCopyRow, _copy),
      ] else if (selected.length > 1) ...[
        if (field != null)
          item('ctx-copy-column', l.ctxCopyColumn, () => _copy(columns: [field])),
        item('ctx-copy-rows', l.ctxCopyRows, _copy),
      ],
      if (_editableView) item('ctx-paste', l.ctxPasteRows, () => _paste(field)),
    ];
    void addAll(List<Widget> more) {
      if (more.isEmpty) return;
      if (entries.isNotEmpty) entries.add(const Divider(height: 1));
      entries.addAll(more);
    }

    if (selected.length == 1) {
      if (!_parentModified(record) && record.id >= 0) {
        String name;
        try {
          name = await record.recName();
        } catch (_) {
          name = '${record.id}';
        }
        if (!mounted) return;
        addAll(await recordMenuEntries(context, ref, (
          model: _model,
          id: record.id,
          recName: name,
          context: record.getContext(),
        )));
      }
      for (final c in _columns) {
        if (c.isButton || !mounted) continue;
        final f = record.model.fields[c.name];
        String? model;
        int? id;
        if (f is Many2OneField) {
          model = f.description['relation'] as String?;
          final value = f.get(record);
          id = value is int ? value : null;
        } else if (f is ReferenceField) {
          final value = f.get(record);
          if (value is String && value.contains(',')) {
            model = value.split(',').first;
            id = int.tryParse(value.split(',').last);
          }
        }
        if (f == null || model == null || id == null || id < 0) continue;
        addAll(await recordMenuEntries(
          context,
          ref,
          (
            model: model,
            id: id,
            recName: _cellText(record, c),
            context: f.getContext(record),
          ),
          title: c.label,
          viewIds: [
            for (final part in '${c.attrs['view_ids'] ?? ''}'.split(','))
              if (part.trim().isNotEmpty) int.tryParse(part.trim())
          ],
          key: ValueKey('ctx-column-${c.key}'),
        ));
      }
    }
    if (!mounted || entries.isEmpty) return;
    setState(() => _contextEntries = entries);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
      if (!mounted || box == null) return;
      _contextMenu.open(position: box.globalToLocal(global));
    });
  }

  // ─── Editable list (spec 9.3.4) ──────────────────────────────────────────

  /// Rows are edited inline (`editable="1"`, screen not readonly).
  bool get _editableView =>
      _view.editable && _view.viewType == 'tree' && _tree.editable;

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
        setState(() {});
        await showWarning(context, previous.invalidMessage(texts));
      }
      return false;
    }
    if (_isRoot && (previous.modified || previous.id < 0)) {
      var saved = false;
      await _run(() async => saved = await previous.save());
      if (!saved) return false;
    } else if (!_isRoot && _screen.preValidate) {
      // a child row with `pre_validate` (Python `_row_selected`)
      var valid = false;
      await _run(() async {
        await previous.preValidate();
        valid = true;
      });
      if (!valid) return false;
    }
    return true;
  }

  // ─── Drag and drop (sequence) ────────────────────────────────────────────

  /// Rows can be reordered: `sequence` set, flat list, no local order,
  /// sequence field writable for all records (Python `drag_data_received`).
  bool get _reorderable {
    final sequence = _tree.sequence;
    if (sequence == null ||
        _isHierarchical ||
        _localOrder != null ||
        _screen.group.readonly) {
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
        _select([record]);
        await group.setSequence(
            field: _tree.sequence!, position: _screen.newPosition);
        if (mounted) setState(() {});
      });

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

  // ─── Selection ───────────────────────────────────────────────────────────

  void _setSelected(Iterable<Record> records) {
    records = records.toList();
    final previous = _screen.currentRecord;
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
    // another cursor row: no cell is edited (until a click or a key)
    if (!identical(previous, screen.currentRecord)) _editKey = null;
  }

  /// Selects [record] and edits its first editable column (a new line).
  void _edit(Record record) {
    _select([record]);
    if (!_editableView) return;
    setState(() => _editKey = _editableColumns(record).firstOrNull?.key);
  }

  void _select(Iterable<Record> records) {
    setState(() => _setSelected(records));
    widget.onSelectionChanged?.call();
  }

  /// Touch devices: tapping opens, a long press selects; otherwise a click
  /// selects and a double click / Enter opens (like SAO).
  bool get _touch => isTouchPlatform(context);

  void _toggleSelected(Record record) {
    final selected = {..._selected};
    if (!selected.remove(record)) selected.add(record);
    _select(selected);
  }

  void _toggleSelectAll(List<TreeRow> rows) {
    if (_selected.length == rows.length) {
      _select(const []);
    } else {
      _select(rows.map((r) => r.record));
    }
  }

  /// Loads the row values of [record] (and its neighbours) once.
  void _ensureLoaded(Record record) {
    final first = _allColumns.where((c) => !c.isButton).firstOrNull;
    final name = first?.name ?? 'rec_name';
    if (record.destroyed ||
        record.id < 0 ||
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

  /// Visible rows: the first [_visible] records of the group (in the
  /// local order of a child list), in a tree with the children of the
  /// expanded records.
  List<TreeRow> get _rows {
    final rows = <TreeRow>[];
    void add(Iterable<Record> records, int depth) {
      for (final r in records) {
        rows.add((record: r, depth: depth));
        final children = _childrenOf(r);
        if (_expanded.contains(r) && children != null) {
          add(children, depth + 1);
        }
      }
    }

    add(_ordered(_screen.group.take(_visible)), 0);
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

  // ─── Sorting (spec 9.3.4) ────────────────────────────────────────────────

  /// Whether the list can be sorted by [column] (Python: no `sequence`,
  /// no `field_childs`, sortable field); a child list only when the
  /// column's values of all records are loaded.
  bool _sortable(TreeColumn column) {
    if (column.isButton || _tree.sequence != null || _isHierarchical) {
      return false;
    }
    final desc = _screen.model.fields[column.name]?.description;
    if (desc == null || desc['sortable'] == false) return false;
    if (_isRoot) return true;
    return _screen.group.every((r) => r.id < 0 || r.isLoaded(column.name));
  }

  String? _sortDirection(TreeColumn c) {
    if (c.isButton) return null;
    if (_isRoot) return _screen.sortDirection(c.name);
    final order = _localOrder;
    return order != null && order.$1 == c.name ? order.$2 : null;
  }

  /// Root list: new search with the order (ASC → DESC → default); child
  /// list: the rows sorted on the client by the shown values.
  Future<void> _sortBy(String name) async {
    if (_isRoot) {
      await _run(() async {
        setState(() => _visible = widget.displayStep);
        await _screen.sortBy(name);
      });
      return;
    }
    setState(() {
      final order = _localOrder;
      _localOrder = order == null || order.$1 != name
          ? (name, 'ASC')
          : (order.$2 == 'ASC' ? (name, 'DESC') : null);
    });
  }

  Iterable<Record> _ordered(Iterable<Record> records) {
    final order = _localOrder;
    if (order == null) return records;
    final column = _allColumns.firstWhere((c) => c.name == order.$1);
    final field = _screen.model.fields[order.$1];
    Comparable? keyOf(Record r) {
      final value = field?.get(r);
      if (value == null || value == false) return null;
      if (value is num || value is String || value is DateTime) {
        return value as Comparable;
      }
      if (value is TrytonDecimal) return value.toDouble();
      if (value is TrytonDate) return value.toDateTime();
      return _cellText(r, column).toLowerCase();
    }

    final sorted = records.toList()
      ..sort((a, b) {
        final ka = keyOf(a), kb = keyOf(b);
        final c = ka == null
            ? (kb == null ? 0 : -1)
            : (kb == null ? 1 : Comparable.compare(ka, kb));
        return order.$2 == 'ASC' ? c : -c;
      });
    return sorted;
  }

  // ─── Build (spec 9.3) ────────────────────────────────────────────────────

  static const _selectionWidth = 40.0;
  static const _handleWidth = 28.0;
  static const _menuWidth = 36.0;
  static const _rowHeight = 31.0;
  static const _headerHeight = 34.0;

  /// Height of the sum row (two lines „selected / all“).
  static const _sumHeight = 44.0;

  /// Compact selection checkboxes (smaller rows).
  static const _compact = VisualDensity(horizontal: -2, vertical: -4);

  @override
  Widget build(BuildContext context) {
    // The group was replaced or records were removed.
    _selected.removeWhere((r) => r.destroyed || !_screen.selectedRecords.contains(r));
    final rows = _rows;
    Widget gridOf(double fill) => Focus(
      focusNode: _listFocus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final selected = _screen.selectedRecords;
        // Ctrl/Cmd+C: copy the selected rows (tab-separated)
        final keyboard = HardwareKeyboard.instance;
        if (event.logicalKey == LogicalKeyboardKey.keyC &&
            (keyboard.isControlPressed || keyboard.isMetaPressed) &&
            selected.isNotEmpty) {
          _copy();
          return KeyEventResult.handled;
        }
        // Ctrl/Cmd+V: paste rows (editable lists)
        if (event.logicalKey == LogicalKeyboardKey.keyV &&
            (keyboard.isControlPressed || keyboard.isMetaPressed) &&
            _editableView) {
          _paste();
          return KeyEventResult.handled;
        }
        // Enter opens the selected record (SAO row activation).
        if ((event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
            selected.isNotEmpty) {
          widget.onActivate(selected.first);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MenuAnchor(
        key: _anchorKey,
        controller: _contextMenu,
        menuChildren: _contextEntries,
        child: _buildGrid(rows, fill: fill),
      ),
    );
    final footer = _buildFooterButtons();
    if (widget.shrinkWrap) {
      // inside a form: as high as the rows; with a minimum height (the
      // list takes the remaining height, yexpand) more rows are shown
      return LayoutBuilder(
        builder: (context, constraints) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            gridOf(constraints.minHeight.isFinite ? constraints.minHeight : 0),
            ?footer,
          ],
        ),
      );
    }
    return Column(children: [Expanded(child: gridOf(0)), ?footer]);
  }

  /// The table: header, rows (flat, tree or reorderable), sum row, all
  /// columns at their width (expanding ones share the free space).
  /// [fill]: height the table may take in a form (0: up to ten rows).
  Widget _buildGrid(List<TreeRow> rows, {double fill = 0}) {
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
      final shrink = widget.shrinkWrap;
      final body = reorderable
          ? ReorderableListView.builder(
              scrollController: _scrollController,
              buildDefaultDragHandles: false,
              shrinkWrap: shrink,
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
              shrinkWrap: shrink,
              itemCount: rows.length,
              itemBuilder: (context, i) =>
                  _buildRow(rows[i], i, columns, widths, key: ObjectKey(rows[i].record)),
            );
      final sum = _buildSumRow(columns, widths, reorderable);
      final table = SizedBox(
        width: width,
        child: Column(
          mainAxisSize: shrink ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(rows, columns, widths, reorderable),
            if (shrink)
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: math.max(widget.maxHeight ?? _rowHeight * 10,
                        fill - _headerHeight - (sum == null ? 0 : _sumHeight))),
                child: body,
              )
            else
              Expanded(child: body),
            ?sum,
          ],
        ),
      );
      return Scrollbar(
        controller: _hScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _hScrollController,
          scrollDirection: Axis.horizontal,
          child: table,
        ),
      );
    });
  }

  Widget _buildHeader(List<TreeRow> rows, List<TreeColumn> columns,
      Map<String, double> widths, bool reorderable) {
    final cs = Theme.of(context).colorScheme;
    final allSelected = _selected.length == rows.length && rows.isNotEmpty;
    return Container(
      color: cs.surfaceContainerHighest,
      height: _headerHeight,
      child: Row(children: [
        SizedBox(
          width: _selectionWidth,
          child: Checkbox(
            tristate: true,
            visualDensity: _compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            value: allSelected ? true : (_selected.isEmpty ? false : null),
            onChanged: (_) => _toggleSelectAll(rows),
          ),
        ),
        if (reorderable) const SizedBox(width: _handleWidth),
        for (final c in columns)
          SizedBox(
            width: widths[c.key],
            child: _HeaderCell(
              key: ValueKey(_key('header-${c.key}')),
              label: c.label,
              help: c.help,
              numeric: isNumericField(_fields[c.name]),
              required: _editableView &&
                  _screen.model.fields[c.name]?.description['required'] == true,
              sortDirection: _sortDirection(c),
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
    final optional = _treeColumnOptional[_view.viewId] ?? const {};
    final names = <String, String>{};
    for (final c in _allColumns) {
      if (c.optional != null && !c.isButton) {
        names[c.name] = names.containsKey(c.name)
            ? '${names[c.name]} / ${c.label}'
            : c.label;
      }
    }
    return PopupMenuButton<String>(
      key: ValueKey('${widget.keyPrefix}-column-menu'),
      icon: const Icon(Icons.view_column_outlined, size: 18),
      tooltip: l.columns,
      padding: EdgeInsets.zero,
      onSelected: (v) {
        if (v == '__reset') {
          _resetWidths();
        } else if (v == '__copy') {
          _copy();
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

  Widget _buildRow(TreeRow row, int index, List<TreeColumn> columns,
      Map<String, double> widths,
      {required Key key, bool reorderable = false}) {
    final record = row.record;
    _ensureLoaded(record);
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selected.contains(record);
    final marked = record.deleted || record.removed;
    final visual = recordVisual(record, _tree.visual);
    // the row of the cursor (current record of an editable list)
    final editingRow = _editableView &&
        identical(_screen.currentRecord, record) &&
        !record.readonly &&
        !marked;
    final firstField = columns.where((c) => !c.isButton).firstOrNull;
    final children = _childrenOf(record);
    final hasChildren = _isHierarchical &&
        (children == null ? record.id >= 0 : children.isNotEmpty);
    final expanded = _expanded.contains(record);

    Widget cell(TreeColumn c) {
      // only the cell of the cursor is edited (Python `set_cursor(path,
      // column, start_editing)`), the others show their value
      final editing = editingRow && c.key == _editKey && _cellEditable(record, c);
      Widget content = _cellContent(record, c, editing, marked);
      if (_isHierarchical && identical(c, firstField)) {
        content = Row(children: [
          SizedBox(width: row.depth * 20.0),
          SizedBox(
            width: 24,
            child: hasChildren
                ? IconButton(
                    key: ValueKey(_key('expand-${record.id}')),
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
      final box = SizedBox(
        width: widths[c.key],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: content,
        ),
      );
      if (editing) {
        // the edited cell has no InkWell (its double tap would hold the
        // clicks into the input); its keys move the cursor
        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) => _onEditorKey(record, c, event),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTapDown: (d) =>
                _openContextMenu(record, c, d.globalPosition),
            child: box,
          ),
        );
      }
      return InkWell(
        onTapDown: (d) {
          _cursorColumn = c;
          _lastPointer = d.globalPosition;
        },
        onTap: () => _tapCell(record, c),
        onDoubleTap: _touch ? null : () => widget.onActivate(record),
        // touch: a long press selects the row and opens the context menu
        onLongPress: _touch
            ? () => _openContextMenu(record, c, _lastPointer ?? Offset.zero)
            : null,
        onSecondaryTapDown: (d) => _openContextMenu(record, c, d.globalPosition),
        child: box,
      );
    }

    return Material(
      key: key,
      color: marked
          ? cs.error.withAlpha(20)
          : isSelected
              ? cs.primaryContainer.withAlpha(80)
              : (_visualRowColor(context, visual) ?? Colors.transparent),
      child: Container(
        constraints: const BoxConstraints(minHeight: _rowHeight - 1),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant.withAlpha(80)))),
        child: Row(children: [
          // outside the InkWells of the cells: their double tap would
          // hold the click on the checkbox
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (d) =>
                _openContextMenu(record, null, d.globalPosition),
            child: SizedBox(
              width: _selectionWidth,
              child: Checkbox(
                visualDensity: _compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                value: isSelected,
                onChanged: (_) => _toggleSelected(record),
              ),
            ),
          ),
          if (reorderable)
            SizedBox(
              width: _handleWidth,
              child: ReorderableDragStartListener(
                key: ValueKey(_key('drag-${record.id}')),
                index: index,
                child: Icon(Icons.drag_indicator, size: 18, color: cs.outline),
              ),
            ),
          for (final c in columns) cell(c),
        ]),
      ),
    );
  }

  // ─── Cell editing (Python list_gtk/editabletree.py) ─────────────────────

  /// Key of the edited column of the cursor row (null: none).
  String? _editKey;

  /// [c] can be edited in the row of [record]: a field column, not
  /// readonly by the view or the field's states, not an x2many/binary.
  bool _cellEditable(Record record, TreeColumn c) {
    if (c.isButton || c.readonly == true) return false;
    final field = record.model.fields[c.name];
    final type = _fields[c.name]?.type;
    if (field == null ||
        type == null ||
        const {'one2many', 'many2many', 'binary'}.contains(type)) {
      return false;
    }
    field.setState(record);
    return !PYSONEvaluator.truthy(field.stateAttrs(record)['readonly']);
  }

  /// A click on a cell: the row becomes the cursor row (leaving the
  /// previous one validates/saves it); in an editable list the cell is
  /// edited. Touch without editable list: the row opens.
  Future<void> _tapCell(Record record, TreeColumn c) async {
    if (_touch && !_editableView) {
      widget.onActivate(record);
      return;
    }
    if (!identical(_screen.currentRecord, record)) {
      if (!await _leaveRow(record)) return;
    } else if (_editKey != null) {
      await _flushPending(record);
    }
    if (!mounted) return;
    if (!_editableView) _listFocus.requestFocus();
    _select([record]);
    if (_editableView) {
      setState(() => _editKey = _cellEditable(record, c) ? c.key : null);
    }
  }

  /// The editable columns of the row of [record] in their order.
  List<TreeColumn> _editableColumns(Record record) =>
      [for (final c in _columns) if (_cellEditable(record, c)) c];

  /// Keys of the edited cell (Python `EditableTreeView.on_keypressed`):
  /// Tab/Shift+Tab next/previous editable column (cyclic in the row),
  /// Up/Down the same column in the previous/next row, Enter the next row
  /// (a new line after the last one with `new_position` at the end),
  /// Escape stops editing.
  KeyEventResult _onEditorKey(Record record, TreeColumn c, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (key == LogicalKeyboardKey.tab) {
      _moveEditColumn(record, c, shift ? -1 : 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _flushPending(record).then((_) {
        if (mounted) setState(() => _editKey = null);
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      _moveEditRow(record, c, key == LogicalKeyboardKey.arrowUp ? -1 : 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _moveEditRow(record, null, _screen.newPosition == 0 ? -1 : 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _moveEditColumn(Record record, TreeColumn c, int delta) async {
    final columns = _editableColumns(record);
    if (columns.isEmpty) return;
    final i = columns.indexWhere((e) => e.key == c.key);
    final next = columns[(i + delta) % columns.length];
    await _flushPending(record);
    if (mounted) setState(() => _editKey = next.key);
  }

  /// The row [delta] away becomes the cursor row (validated and – in a
  /// root list – saved first); beyond the last (first) row a new line is
  /// created when new records go there (Python `_key_down`/`_key_up`).
  /// [column] null: the first editable column of the new row.
  Future<void> _moveEditRow(Record record, TreeColumn? column, int delta) async {
    final rows = [for (final r in _rows) r.record];
    final i = rows.indexOf(record);
    if (i < 0) return;
    final j = i + delta;
    Record? target;
    if (j >= 0 && j < rows.length) {
      target = rows[j];
      if (!await _leaveRow(target)) return;
    } else {
      final atEnd = j >= rows.length && _screen.newPosition == -1;
      final atStart = j < 0 && _screen.newPosition == 0;
      if ((atEnd || atStart) && _view.creatable && !_screen.group.readonly) {
        if (!await _leaveRow(null)) return;
        await _run(() async => target = await _screen.newRecord());
      } else {
        target = rows[j % rows.length];
        if (!await _leaveRow(target)) return;
      }
    }
    final next = target;
    if (next == null || !mounted) return;
    _select([next]);
    final editable = _editableColumns(next);
    setState(() => _editKey = column != null && editable.any((e) => e.key == column.key)
        ? column.key
        : editable.firstOrNull?.key);
  }

  /// A cell (spec 9.3.3): button, editor of the edited row, or the value
  /// with prefixes/suffixes and the column's `visual`; rows marked for
  /// deletion/removal struck through.
  Widget _cellContent(Record record, TreeColumn c, bool editing, bool marked) {
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
    final cs = Theme.of(context).colorScheme;
    final visual = recordVisual(record, c.visual is String ? c.visual as String : null);
    final color = marked
        ? cs.error.withAlpha(160)
        : switch (visual) {
            'success' => Colors.green.shade700,
            'warning' => Colors.orange.shade800,
            'danger' => cs.error,
            'muted' => cs.outline,
            _ => null,
          };
    final textStyle = TextStyle(
      fontSize: 13,
      color: color,
      decoration: marked ? TextDecoration.lineThrough : null,
      decorationColor: marked ? cs.error : null,
    );
    Widget value;
    switch (c.widget ?? fd?.type) {
      case 'boolean':
        value = Icon(
            field?.get(record) == true ? Icons.check_box : Icons.check_box_outline_blank,
            size: 18,
            color: cs.outline);
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
        key: ValueKey(_key('edit-${record.id}-${c.key}')),
        model: _model,
        // the edited cell gets the focus (`cursor`)
        root: FormRoot(col: 1, attrs: {'cursor': c.name}, children: [
          FieldNode(
            name: c.name,
            attrs: c.attrs,
            widget: c.widget,
            readonly: c.readonly,
          ),
        ]),
        viewDef: _view.definition,
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
        _select([record]);
        await _screen.button(node);
      });

  /// Sum row (Python `update_with_selection`): „selected / all“ of the
  /// loaded records per `sum` column, `-` while not all are loaded.
  Widget? _buildSumRow(
      List<TreeColumn> columns, Map<String, double> widths, bool reorderable) {
    if (!columns.any((c) => c.sum) || _screen.group.isEmpty) return null;
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('${widget.keyPrefix}-sum-row'),
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
                        key: ValueKey(_key('sum-${c.key}')),
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  )
                : null,
          ),
      ]),
    );
  }

  /// Digits of a sum column still loading (`get_digits`, e.g. of the
  /// currency): the sum is formatted once they are there (Python
  /// `field.digits(record)` per record).
  final Set<String> _sumDigitsLoading = {};

  String _sumText(TreeColumn c) {
    final field = _screen.model.fields[c.name];
    if (field is FloatField) {
      for (final r in _screen.group) {
        if (r.id < 0 || !r.isLoaded(c.name) || !field.digitsPending(r)) continue;
        if (_sumDigitsLoading.add(c.key)) {
          field.loadDigits(r).whenComplete(() {
            _sumDigitsLoading.remove(c.key);
            if (mounted) setState(() {});
          });
        }
        return '-';
      }
    }
    return recordSumText(_screen.group, c.name, _screen.selectedRecords,
        locale: Localizations.localeOf(context).toLanguageTag(),
        numberLocale: ref.watch(numberLocaleProvider));
  }

  /// `<button multiple="1">`: buttons for the selected records.
  Widget? _buildFooterButtons() {
    final buttons = _tree.buttons;
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
              key: ValueKey(_key('multi-button-${b.name}')),
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
