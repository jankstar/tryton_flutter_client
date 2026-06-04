import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xml/xml.dart';

import '../auth/auth_provider.dart';
import '../model/field_definition.dart';
import '../model/model_service.dart';
import '../model/record.dart';
import '../model/toolbar_data.dart';
import '../shell/app_shell.dart';
import '../shell/tab_manager.dart';
import '../../core/icons/tryton_icon.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/pyson/pyson_evaluator.dart';
import '../../core/serialization/tryton_serializer.dart';
import '../../core/xml/form_xml_parser.dart';
import '../../core/xml/view_definition.dart';
import '../../shared/utils/m2o_name_cache.dart' as m2o;
import '../../shared/utils/number_format_utils.dart';
import '../../shared/utils/symbol_cache.dart' as sym_cache;
import '../../shared/widgets/field_widget.dart';
import '../../shared/widgets/toolbar_dropdown_button.dart';
import 'navigation_context.dart';

/// Displays records of a Tryton model as a scrollable table
/// with a complete toolbar (New, Edit, Delete, Copy,
/// Actions, Reports, Relations, Attachments).
class ListViewScreen extends ConsumerStatefulWidget {
  final String model;
  final String title;
  final List<String> displayFields;
  /// Domain filter from the menu action (pyson_domain evaluated).
  final List<dynamic> initialDomain;
  /// Model for the context form (ir.action.act_window.context_model).
  final String? contextModel;
  /// PYSON domain string combined with context form values (context_domain).
  final String? contextDomain;
  /// `ir.action.act_window` ID — used to load domain tabs.
  final int? actionId;
  /// Called when the user clicks "Close" – removes this tab from AppShell.
  final VoidCallback? onClose;

  const ListViewScreen({
    super.key,
    required this.model,
    required this.title,
    this.displayFields = const [],
    this.initialDomain = const [],
    this.contextModel,
    this.contextDomain,
    this.actionId,
    this.onClose,
  });

  @override
  ConsumerState<ListViewScreen> createState() => _ListViewScreenState();
}

// Re-export the shared cache reference for use in _formatValue below.
final _m2oNameCache = m2o.m2oNameCache;

// ─── Tree row data model ──────────────────────────────────────────────────────

class _TreeRow {
  final TrytonRecord record;
  final int depth;
  bool hasChildren;
  bool isExpanded = false;
  bool isLoadingChildren = false;

  _TreeRow({
    required this.record,
    required this.depth,
    required this.hasChildren,
  });
}

// ─── State ────────────────────────────────────────────────────────────────────

class _ListViewScreenState extends ConsumerState<ListViewScreen> {
  // Flat record list (non-hierarchical)
  List<TrytonRecord> _records = [];
  // Tree rows (hierarchical) – contains visible rows with depth
  List<_TreeRow> _treeRows = [];

  Map<String, FieldDefinition> _fields = {};
  List<String> _columns = [];
  Map<String, String> _columnLabels = {};
  TrytonToolbar _toolbar = const TrytonToolbar();

  // Hierarchy fields from field_childs
  String? _fieldChilds;   // Field name of the children (e.g. "children")
  String? _parentField;   // Field name of the parent entry (e.g. "parent")
  bool get _isHierarchical =>
      _fieldChilds != null && _fieldChilds!.isNotEmpty;

  /// PYSON visual expression from <tree visual="...">.
  String? _treeVisual;
  /// Parsed tree columns (with sum/expand/treeInvisible meta).
  List<TreeColumn> _treeColumns = [];

  bool _loading = false;
  String? _error;
  int _offset = 0;
  static const _limit = 50;
  bool _hasMore = true;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  final Set<int> _selected = {};
  final _scrollController = ScrollController();
  final _hScrollController = ScrollController();

  // ─── Domain tabs (ir.action.act_window.domain) ───────────────────────────
  List<TabDomain> _tabDomains = [];
  int _activeTabIndex = -1; // -1 = no tab selected
  final Map<int, int?> _tabCounts = {}; // null = loading, int = loaded

  // ─── Context form state (context_model / context_domain) ─────────────────
  FormRoot? _ctxFormRoot;
  ViewDefinition? _ctxViewDef;
  /// Current values of the context form (used to evaluate context_domain).
  Map<String, dynamic> _ctxValues = {};
  bool _ctxLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadContextModel().then((_) => _load());
    if (widget.actionId != null) _loadTabDomains();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _hScrollController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loading &&
        _hasMore) {
      _loadMore();
    }
  }

  // ─── Context model / context form ────────────────────────────────────────

  /// Loads the context model's form view and default values.
  /// Like SAO: creates a context_screen in form mode and calls new_().
  Future<void> _loadContextModel() async {
    final cm = widget.contextModel;
    if (cm == null || cm.isEmpty) return;
    try {
      final svc = ref.read(modelServiceProvider);
      final viewDef = await svc.fieldsViewGet(cm, viewType: 'form');
      final formRoot = FormXmlParser().parse(viewDef.arch);
      final defaults = await svc.defaultGet(cm,
          viewDef.fields.keys.toList());
      if (mounted) {
        setState(() {
          _ctxViewDef = viewDef;
          _ctxFormRoot = formRoot;
          _ctxValues = Map<String, dynamic>.from(defaults);
          _ctxLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _ctxLoaded = true);
    }
  }

  /// Evaluates context_domain with current context form values and returns
  /// the additional domain to AND with the search domain.
  ///
  /// Before evaluation:
  /// - Many2One values [id, name] → id (integer), as SAO's get_on_change_value
  /// - Empty values (null/false/'') → kept as-is for PYSON; stripped after
  ///
  /// After evaluation:
  /// - Conditions with empty/falsy values are removed so an empty context
  ///   field does NOT filter the list (like clearing a selection returns all).
  List<dynamic> _buildContextDomain() {
    final cd = widget.contextDomain;
    if (cd == null || cd.isEmpty || cd == '[]') return const [];
    try {
      final session = ref.read(sessionProvider);
      // Normalise context values like SAO's get_on_change_value():
      // Many2One [id, name] → id; empty string → null (so Eval returns null)
      final normalised = _normaliseCtxValues(_ctxValues);
      final ctx = <String, dynamic>{
        ...session.context,
        ...normalised,
      };
      final evaluated = evaluateActionDomain(cd, ctx);
      return _stripEmptyConditions(evaluated);
    } catch (_) {
      return const [];
    }
  }

  /// Converts context-form values to the format PYSON expects:
  /// - Many2One [id, name] → id (int), matching SAO's get_on_change_value()
  /// - Empty string '' → null (falsy, will be stripped from domain)
  Map<String, dynamic> _normaliseCtxValues(Map<String, dynamic> values) {
    final result = <String, dynamic>{};
    for (final e in values.entries) {
      final v = e.value;
      if (v is List && v.isNotEmpty && v[0] is int) {
        // Many2One [id, rec_name] → just the id
        result[e.key] = v[0] as int;
      } else if (v is String && v.isEmpty) {
        // Empty selection → null so _stripEmptyConditions removes it
        result[e.key] = null;
      } else {
        result[e.key] = v;
      }
    }
    return result;
  }

  /// Returns true for values that represent "nothing selected" in a context form.
  static bool _isEmptyValue(dynamic value) =>
      value == null ||
      value == false ||
      (value is String && value.isEmpty) ||
      (value is List && value.isEmpty);

  /// Recursively removes domain conditions whose RHS value is empty/falsy,
  /// because these represent unset context-form fields and must not filter.
  List<dynamic> _stripEmptyConditions(List<dynamic> domain) {
    if (domain.isEmpty) return domain;

    // Single condition: ['field', 'op', value]
    if (domain.length == 3 && domain[0] is String && domain[1] is String) {
      return _isEmptyValue(domain[2]) ? const [] : domain;
    }

    // Composite: ['AND'/'OR', ...] or implicit AND [cond1, cond2, ...]
    final isOr  = domain.isNotEmpty && domain[0] == 'OR';
    final isAnd = domain.isNotEmpty && domain[0] == 'AND';
    final start = (isOr || isAnd) ? 1 : 0;

    final filtered = <dynamic>[];
    for (int i = start; i < domain.length; i++) {
      final item = domain[i];
      if (item is List) {
        final stripped = _stripEmptyConditions(item.cast<dynamic>());
        if (stripped.isNotEmpty) filtered.add(stripped);
      } else {
        filtered.add(item);
      }
    }

    if (filtered.isEmpty) return const [];
    if (isOr)  return ['OR',  ...filtered];
    if (isAnd) return ['AND', ...filtered];
    return filtered;
  }

  // ─── Domain tab helpers ──────────────────────────────────────────────────

  List<dynamic> get _activeTabDomain {
    if (_activeTabIndex < 0 || _activeTabIndex >= _tabDomains.length) {
      return const [];
    }
    return _tabDomains[_activeTabIndex].domain;
  }

  /// Loads `ir.action.act_window.domain` entries for the action, evaluates
  /// their PYSON domain strings, and triggers count loading.
  Future<void> _loadTabDomains() async {
    final id = widget.actionId;
    if (id == null) return;
    try {
      final svc = ref.read(modelServiceProvider);
      final session = ref.read(sessionProvider);
      final rows = await svc.searchRead(
        'ir.action.act_window.domain',
        domain: [
          ['act_window', '=', id],
          ['active', '=', true],
        ],
        fields: ['name', 'domain', 'count', 'sequence'],
        limit: null,
        order: [['sequence', 'ASC']],
      );
      final evalCtx = <String, dynamic>{
        ...session.context,
        'active_model': widget.model,
        'active_id': null,
        'active_ids': <int>[],
      };
      final tabs = rows
          .map((r) => TabDomain(
                id: r.id,
                name: r['name']?.toString() ?? '',
                domain: evaluateActionDomain(
                    r['domain']?.toString(), evalCtx),
                count: r['count'] as bool? ?? false,
              ))
          .where((t) => t.name.isNotEmpty)
          .toList();
      if (mounted) {
        setState(() {
          _tabDomains = tabs;
          if (tabs.isNotEmpty) _activeTabIndex = 0;
        });
        if (tabs.isNotEmpty) {
          _load(reset: true);
        } else {
          _loadTabCounts();
        }
      }
    } catch (_) {}
  }

  /// Asynchronously refreshes the record count for every tab with count=true.
  /// Mirrors SAO's count_tab_domain(current=false).
  Future<void> _loadTabCounts() async {
    if (_tabDomains.isEmpty) return;
    final svc = ref.read(modelServiceProvider);
    final searchDomain = _searchQuery.isEmpty
        ? <dynamic>[]
        : [['rec_name', 'ilike', '%$_searchQuery%']];
    final ctxDomain = _buildContextDomain();
    final base = _buildCombinedDomain(
      _buildCombinedDomain(widget.initialDomain, ctxDomain),
      searchDomain,
    );
    for (int i = 0; i < _tabDomains.length; i++) {
      final tab = _tabDomains[i];
      if (!tab.count) continue;
      if (mounted) setState(() => _tabCounts[i] = null);
      try {
        final domain = _buildCombinedDomain(base, tab.domain);
        final count = await svc.searchCount(widget.model, domain: domain);
        if (mounted) setState(() => _tabCounts[i] = count);
      } catch (_) {
        if (mounted) setState(() => _tabCounts[i] = 0);
      }
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _offset = 0;
        _records = [];
        _hasMore = true;
        _selected.clear();
      }
    });
    try {
      final svc = ref.read(modelServiceProvider);
      if (_fields.isEmpty) {
        await _loadViewDefinition(svc);
        _loadToolbar(svc);
      }
      final searchDomain = _searchQuery.isEmpty
          ? <dynamic>[]
          : [['rec_name', 'ilike', '%$_searchQuery%']];

      if (_isHierarchical) {
        await _loadHierarchical(svc, searchDomain, reset: reset);
      } else {
        await _loadFlat(svc, searchDomain, reset: reset);
      }
      if (_tabDomains.isNotEmpty) _loadTabCounts();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  /// Loads the tree view definition from the server and sets columns + labels.
  /// Falls back to fieldsGet if no tree view is available.
  Future<void> _loadViewDefinition(ModelService svc) async {
    if (widget.displayFields.isNotEmpty) {
      _fields = await svc.fieldsGet(widget.model,
          fields: widget.displayFields);
      _columns = widget.displayFields;
      _columnLabels = {for (final k in _columns) k: _fields[k]?.label ?? k};
      return;
    }

    // ── Step 1: Load tree view definition ──────────────────────────────────
    ViewDefinition? viewDef;
    try {
      viewDef = await svc.fieldsViewGet(widget.model, viewType: 'tree');
      _fields = viewDef.fields;

      // field_childs is in the ir.ui.view record; extract if present.
      if (viewDef.fieldChilds != null && viewDef.fieldChilds!.isNotEmpty) {
        _fieldChilds = viewDef.fieldChilds;
      }

      // Parse columns from arch XML.
      final doc = XmlDocument.parse(viewDef.arch);
      final root = doc.rootElement;

      final cols = <String>[];
      final labels = <String, String>{};
      final parsedColumns = <TreeColumn>[];
      for (final child in root.childElements) {
        if (child.name.local != 'field') continue;
        final name = child.getAttribute('name') ?? '';
        if (name.isEmpty) continue;
        final label = child.getAttribute('string') ??
            viewDef.fields[name]?.label ??
            name;
        final invisible = child.getAttribute('tree_invisible');
        parsedColumns.add(TreeColumn(
          name: name,
          label: label,
          widget: child.getAttribute('widget'),
          treeInvisible: invisible == '1' || invisible == 'true',
          sum: child.getAttribute('sum'),
          expand: child.getAttribute('expand') == '1',
        ));
        if (invisible != '1' && invisible != 'true') {
          cols.add(name);
          labels[name] = label;
        }
      }

      if (cols.isNotEmpty) {
        _columns = cols;
        _columnLabels = labels;
        _treeColumns = parsedColumns;
        _treeVisual = root.getAttribute('visual');
      }
    } catch (e) {
    }

    // ── Step 2: field_childs fallback – query ir.ui.view directly ──────────
    // fields_view_get may load a view with higher priority that has no
    // field_childs set. We scan ALL tree views for this model and take the
    // first one that has field_childs defined.
    if (_fieldChilds == null) {
      try {
        final viewRows = await svc.searchRead(
          'ir.ui.view',
          domain: [
            ['model', '=', widget.model],
            ['type', '=', 'tree'],
          ],
          fields: ['field_childs', 'priority'],
          limit: null,
          order: [['priority', 'ASC']],
        );
        for (final row in viewRows) {
          final fc = row['field_childs'];
          if (fc is String && fc.isNotEmpty) {
            _fieldChilds = fc;
            break;
          }
        }
      } catch (e) {
      }
    }

    // ── Step 3: Resolve parent field for root filter / expand ───────────────
    if (_fieldChilds != null) {
      _parentField = _fields[_fieldChilds!]?.relationField;
      if (_parentField == null) {
        try {
          final fd = await svc.fieldsGet(widget.model,
              fields: [_fieldChilds!]);
          _parentField = fd[_fieldChilds!]?.relationField;
        } catch (_) {}
      }
    }

    // ── Step 4: Fallback columns if still empty ─────────────────────────────
    if (_columns.isEmpty) {
      if (_fields.isEmpty) {
        _fields = await svc.fieldsGet(widget.model);
      }
      _columns = _visibleColumns(_fields);
      _columnLabels = {for (final k in _columns) k: _fields[k]?.label ?? k};
    }
  }

  Future<void> _loadToolbar(ModelService svc) async {
    try {
      final t = await svc.viewToolbarGet(widget.model);
      if (mounted) setState(() => _toolbar = t);
    } catch (_) {
      // Toolbar is optional – ignore errors
    }
  }

  Future<void> _loadMore() => _load();

  // ─── Load methods ────────────────────────────────────────────────────────

  Future<void> _loadFlat(
    ModelService svc,
    List<dynamic> searchDomain, {
    bool reset = false,
  }) async {
    final ctxDomain = _buildContextDomain();
    final domain = _buildCombinedDomain(
      _buildCombinedDomain(
        _buildCombinedDomain(widget.initialDomain, ctxDomain),
        _activeTabDomain,
      ),
      searchDomain,
    );
    final records = await svc.searchRead(
      widget.model,
      domain: domain,
      fields: ['rec_name', '_write', '_delete', ..._columns],
      offset: _offset,
      limit: _limit,
    );
    await _resolveM2ONames(svc, records);
    setState(() {
      _records = reset ? records : [..._records, ...records];
      _offset += records.length;
      _hasMore = records.length == _limit;
    });
  }

  Future<void> _loadHierarchical(
    ModelService svc,
    List<dynamic> searchDomain, {
    bool reset = false,
  }) async {
    // Add root filter (parent = null) ONLY if initialDomain
    // does not yet contain a filter on the parent field.
    // Use Dart null → JSON null → Python None.
    // Tryton rejects Python False (JSON false) in domain values:
    //   assert value is not False
    final rootFilter =
        (_parentField != null && !_domainFiltersField(widget.initialDomain, _parentField!))
            ? [[_parentField!, '=', null]]   // null, NOT false!
            : <dynamic>[];

    final ctxDomain = _buildContextDomain();
    final domain = _buildCombinedDomain(
      _buildCombinedDomain(
        _buildCombinedDomain(
          _buildCombinedDomain(widget.initialDomain, ctxDomain),
          _activeTabDomain,
        ),
        rootFilter,
      ),
      searchDomain,
    );

    final fieldList = ['rec_name', '_write', '_delete', ..._columns];

    final records = await svc.searchRead(
      widget.model,
      domain: domain,
      fields: fieldList,
      limit: null,
    );

    await _resolveM2ONames(svc, records);

    // Batch-check which root records have children via a single extra query.
    final withChildren = await _batchHasChildren(svc, records);

    final rows = records.map((r) => _TreeRow(
          record: r,
          depth: 0,
          hasChildren: withChildren.contains(r.id),
        )).toList();

    setState(() {
      _treeRows = reset ? rows : [..._treeRows, ...rows];
      _hasMore = false;
    });
  }

  /// Determines which records from [rows] have at least one child.
  /// Uses read() to read the _fieldChilds One2Many field directly.
  /// read() reliably returns actual ID lists — unlike search_read which
  /// may return Python False for empty One2Many fields.
  Future<Set<int>> _batchHasChildren(
      ModelService svc, List<TrytonRecord> rows) async {
    if (_fieldChilds == null || rows.isEmpty) {
      return {};
    }
    final ids = rows.map((r) => r.id).where((id) => id > 0).toList();
    if (ids.isEmpty) return {};
    try {
      final data = await svc.read(widget.model, ids, [_fieldChilds!]);
      final withChildren = <int>{};
      for (final r in data) {
        final v = r[_fieldChilds!];
        if (v is List && v.isNotEmpty) withChildren.add(r.id);
      }
      return withChildren;
    } catch (e) {
      // Fallback: searchRead-based query if _parentField is available.
      if (_parentField == null) return {};
      try {
        final childRecords = await svc.searchRead(
          widget.model,
          domain: [[_parentField!, 'in', ids]],
          fields: [_parentField!],
          limit: null,
        );
        final parentIds = <int>{};
        for (final r in childRecords) {
          final v = r[_parentField!];
          int? pid;
          if (v is List && v.isNotEmpty) pid = (v[0] as num?)?.toInt();
          else if (v is int) pid = v;
          if (pid != null) parentIds.add(pid);
        }
        return parentIds;
      } catch (e2) {
        return {};
      }
    }
  }

  Future<void> _expandRow(int index) async {
    final row = _treeRows[index];
    if (!row.hasChildren || row.isExpanded || row.isLoadingChildren) return;

    setState(() => row.isLoadingChildren = true);

    try {
      final svc = ref.read(modelServiceProvider);
      final fieldList = ['rec_name', '_write', '_delete', ..._columns];
      List<TrytonRecord> children;

      if (_parentField != null) {
        // Primary: domain-based load (respects action domain and ordering).
        final baseActionDomain =
            _domainWithoutField(widget.initialDomain, _parentField!);
        final childDomain = _buildCombinedDomain(
            baseActionDomain, [[_parentField!, '=', row.record.id]]);
        children = await svc.searchRead(
          widget.model,
          domain: childDomain,
          fields: fieldList,
          limit: null,
        );
      } else if (_fieldChilds != null) {
        // Fallback: read child IDs via One2Many field, then read records.
        final parentData =
            await svc.read(widget.model, [row.record.id], [_fieldChilds!]);
        if (parentData.isEmpty) {
          setState(() {
            row.isLoadingChildren = false;
            row.hasChildren = false;
          });
          return;
        }
        final childIds = (parentData.first[_fieldChilds!] as List?)
                ?.whereType<int>()
                .toList() ??
            [];
        if (childIds.isEmpty) {
          setState(() {
            row.isLoadingChildren = false;
            row.hasChildren = false;
          });
          return;
        }
        children = await svc.read(widget.model, childIds, fieldList);
      } else {
        setState(() => row.isLoadingChildren = false);
        return;
      }

      await _resolveM2ONames(svc, children);

      // Batch-check which child records themselves have children.
      final withChildren = await _batchHasChildren(svc, children);

      final childRows = children
          .map((r) => _TreeRow(
                record: r,
                depth: row.depth + 1,
                hasChildren: withChildren.contains(r.id),
              ))
          .toList();

      setState(() {
        row.isExpanded = true;
        row.isLoadingChildren = false;
        if (children.isEmpty) row.hasChildren = false;
        _treeRows.insertAll(index + 1, childRows);
      });
    } catch (e) {
      setState(() => row.isLoadingChildren = false);
    }
  }

  void _collapseRow(int index) {
    final row = _treeRows[index];
    if (!row.isExpanded) return;

    // Remove all child rows (deeper levels)
    int end = index + 1;
    while (end < _treeRows.length && _treeRows[end].depth > row.depth) {
      end++;
    }
    setState(() {
      row.isExpanded = false;
      _treeRows.removeRange(index + 1, end);
    });
  }

  /// Checks whether a domain already contains a condition for [field].
  static bool _domainFiltersField(List<dynamic> domain, String field) {
    for (final item in domain) {
      if (item is List && item.isNotEmpty && item[0] == field) return true;
    }
    return false;
  }

  /// Removes all conditions for [field] from a domain.
  /// Needed when loading child records: the action domain may already contain
  /// [parent = null], which must be replaced by [parent = id].
  static List<dynamic> _domainWithoutField(List<dynamic> domain, String field) {
    return domain.where((item) {
      if (item is List && item.isNotEmpty && item[0] == field) return false;
      return true;
    }).toList();
  }

  /// Combines action domain with search domain into an AND domain.
  /// Tryton domain syntax: both lists are merged into a new list.
  static List<dynamic> _buildCombinedDomain(
    List<dynamic> actionDomain,
    List<dynamic> searchDomain,
  ) {
    if (actionDomain.isEmpty) return searchDomain;
    if (searchDomain.isEmpty) return actionDomain;
    // AND join: both domains as elements in a new list
    return [...actionDomain, ...searchDomain];
  }

  /// Resolves Many2One IDs into display names.
  /// Strategy: check companion keys first, then batch RPC per model.
  Future<void> _resolveM2ONames(
    ModelService svc,
    List<TrytonRecord> records,
  ) => m2o.resolveM2ONames(svc, records, _columns, _fields);

  // ─── Actions ─────────────────────────────────────────────────────────────

  Future<void> _newRecord() async {
    await pushFormScreen(
      context,
      model: widget.model,
      recordId: -1,
      title: widget.title,
      screenDomain: widget.initialDomain,
    );
    if (mounted) _load(reset: true);
  }

  Future<void> _openRecord(int id) async {
    final allIds = _isHierarchical
        ? _treeRows.map((r) => r.record.id).toList()
        : _records.map((r) => r.id).toList();
    final idx = allIds.indexOf(id);
    ref.read(navContextProvider.notifier).state = RecordNavContext(
      model: widget.model,
      title: widget.title,
      recordIds: allIds,
      currentIndex: idx < 0 ? 0 : idx,
    );
    await pushFormScreen(
      context,
      model: widget.model,
      recordId: id,
      title: widget.title,
      screenDomain: widget.initialDomain,
    );
    if (mounted) _load(reset: true);
  }

  Future<void> _switchToForm() async {
    if (_selected.isEmpty) return;
    final allIds = _isHierarchical
        ? _treeRows.map((r) => r.record.id).toList()
        : _records.map((r) => r.id).toList();
    final orderedSelected = allIds.where(_selected.contains).toList();
    final firstId =
        orderedSelected.isNotEmpty ? orderedSelected.first : _selected.first;
    final navIds = orderedSelected.length > 1 ? orderedSelected : allIds;
    final idx = navIds.indexOf(firstId);
    ref.read(navContextProvider.notifier).state = RecordNavContext(
      model: widget.model,
      title: widget.title,
      recordIds: navIds,
      currentIndex: idx < 0 ? 0 : idx,
    );
    await pushFormScreen(
      context,
      model: widget.model,
      recordId: firstId,
      title: widget.title,
      screenDomain: widget.initialDomain,
    );
    if (mounted) _load(reset: true);
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.deleteRecords),
        content: Text('Really delete ${_selected.length} record(s)?'),
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
    if (confirmed != true) return;
    try {
      final svc = ref.read(modelServiceProvider);
      await svc.delete(widget.model, _selected.toList());
      _load(reset: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Future<void> _copySelected() async {
    if (_selected.isEmpty) return;
    try {
      final svc = ref.read(modelServiceProvider);
      await svc.copy(widget.model, _selected.toList());
      _load(reset: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.recordCreated)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selected.length == _records.length) {
        _selected.clear();
      } else {
        _selected.addAll(_records.map((r) => r.id));
      }
    });
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final hasSelection = _selected.isNotEmpty;
    final singleSelection = _selected.length == 1;
    final selectedList = _selected.toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        scrolledUnderElevation: 0,
        title: Text(widget.title),
        actions: [
          // ── Navigation ────────────────────────────────────────────────
          // Switch: like SAO's tryton-switch – jump to form view
          // Uses the actual SAO icon loaded from ir.ui.icon cache
          // Switch: active for any selection (≥1).
          // Opens the first selected record; Prev/Next navigates through
          // the selected set (or all records if only 1 is selected).
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
            onPressed: hasSelection
                ? () => _switchToForm()
                : null,
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
            onPressed: () => _load(reset: true),
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
            model: widget.model,
            selectedId: singleSelection ? _selected.first : null,
          ),

          // ── Action / Relate / Print / Email (require selection) ───────
          ToolbarDropdownButton(
            icon: Icons.rocket_launch_outlined,
            tooltip: l.launchActions,
            items: _toolbar.actions,
            model: widget.model,
            selectedIds: selectedList,
            enabled: hasSelection,
          ),
          ToolbarDropdownButton(
            icon: Icons.link,
            tooltip: l.relatedRecords,
            items: _toolbar.relate,
            model: widget.model,
            selectedIds: selectedList,
            enabled: hasSelection,
          ),
          ToolbarDropdownButton(
            icon: Icons.print_outlined,
            tooltip: l.reports,
            items: _toolbar.print,
            model: widget.model,
            selectedIds: selectedList,
            enabled: hasSelection,
          ),
          ToolbarDropdownButton(
            icon: Icons.email_outlined,
            tooltip: l.email,
            items: _toolbar.emails,
            model: widget.model,
            selectedIds: selectedList,
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
    final isEmpty = _isHierarchical ? _treeRows.isEmpty : _records.isEmpty;
    final searchBar = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: _SearchBar(
        controller: _searchCtrl,
        hint: context.l10n.search,
        onSearch: (q) {
          setState(() => _searchQuery = q);
          _load(reset: true);
        },
      ),
    );

    // Layout: [context form] → search bar → table
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Context model form (only when context_model is set)
        if (_ctxLoaded &&
            widget.contextModel != null &&
            _ctxFormRoot != null &&
            _ctxViewDef != null)
          _ContextForm(
            formRoot: _ctxFormRoot!,
            viewDef: _ctxViewDef!,
            values: _ctxValues,
            onChanged: (name, value) {
              setState(() => _ctxValues = {..._ctxValues, name: value});
              _load(reset: true);
            },
          ),
        // 2. Search bar (always visible)
        searchBar,
        // 3. Domain tabs (when action has ir.action.act_window.domain entries)
        if (_tabDomains.isNotEmpty) _buildTabBar(),
        // 4. Table / list
        Expanded(child: _buildListBody(isEmpty)),
      ],
    );
  }

  /// Horizontal scrollable row of filter chips, one per ir.action.act_window.domain entry.
  /// Mirrors SAO's Bootstrap nav-tabs above the list.
  Widget _buildTabBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
      child: Row(
        children: [
          for (int i = 0; i < _tabDomains.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: _buildTabLabel(i),
                selected: _activeTabIndex == i,
                onSelected: (_) {
                  final next = _activeTabIndex == i ? -1 : i;
                  setState(() {
                    _activeTabIndex = next;
                    _tabCounts.clear();
                  });
                  _load(reset: true);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabLabel(int i) {
    final tab = _tabDomains[i];
    if (!tab.count) return Text(tab.name);
    if (!_tabCounts.containsKey(i)) return Text(tab.name);
    final c = _tabCounts[i];
    if (c == null) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Text(tab.name),
        const SizedBox(width: 6),
        const SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      ]);
    }
    return Text('${tab.name} ($c)');
  }

  Widget _buildListBody(bool isEmpty) {
    if (_error != null) {
      // Scrollbar prevents overflow with long error text
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: () => _load(reset: true),
              child: Text(context.l10n.retry)),
        ]),
      );
    }

    if (isEmpty && _loading) return const Center(child: CircularProgressIndicator());

    if (isEmpty) {
      // No mainAxisSize.min inside Center – use direct positioning instead
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

    // Normal state: Expanded fills all available space
    return Column(
      children: [
        Expanded(
          child: _isHierarchical ? _buildTreeBody() : _buildTableBody(),
        ),
        if (_loading) const LinearProgressIndicator(),
      ],
    );
  }

  // ─── Flat table view ─────────────────────────────────────────────────────

  Widget _buildTableBody() {
    final allSelected = _selected.length == _records.length && _records.isNotEmpty;
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
                  columns: [
                    DataColumn(
                      label: Checkbox(
                        tristate: true,
                        value: allSelected ? true : (_selected.isEmpty ? false : null),
                        onChanged: (_) => _toggleSelectAll(),
                      ),
                    ),
                    ..._buildColumns(),
                  ],
                  rows: _buildRows(),
                ),
              ),
            ),
          ),
        ),
        ..._buildSumRow(),
      ],
    );
  }

  /// Builds a sum footer row for numeric columns that have sum="..." defined.
  List<Widget> _buildSumRow() {
    final sumCols = _treeColumns.where((c) => c.sum != null && c.sum!.isNotEmpty).toList();
    if (sumCols.isEmpty || _records.isEmpty) return [];

    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();

    return [
      Container(
        color: cs.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          // Checkbox column placeholder
          const SizedBox(width: 48),
          ..._columns.map((col) {
            final tc = _treeColumns.firstWhere((c) => c.name == col,
                orElse: () => TreeColumn(name: col, label: col));
            final fd = _fields[col];
            if (tc.sum == null || tc.sum!.isEmpty) {
              return const Expanded(child: SizedBox.shrink());
            }
            // Sum numeric values
            double total = 0;
            for (final r in _records) {
              final v = r[col];
              if (v is num) total += v.toDouble();
              else if (v is TrytonDecimal) total += v.toDouble();
            }
            final formatted = formatNumericValue(total,
                digits: fd?.digits, locale: locale);
            return Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(tc.sum!, style: TextStyle(fontSize: 10, color: cs.outline)),
                  Text(formatted,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }),
        ]),
      ),
    ];
  }

  // ─── Hierarchical tree view ───────────────────────────────────────────────

  /// Header row with column labels for the hierarchical tree.
  Widget _buildTreeHeader() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(children: [
        // ① Checkbox space (like in the row: 24px, not indented)
        const SizedBox(width: 24),
        // ② No indentation space in the header
        // ③ Expand button space (24px) + gap
        const SizedBox(width: 28),
        ..._columns.map((col) {
          final label = _columnLabels[col] ?? _fields[col]?.label ?? col;
          return Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 12)),
          );
        }),
      ]),
    );
  }

  Widget _buildTreeBody() {
    return ListView.builder(
      controller: _scrollController,
      // +1 for the header as the first item → no extra Column child needed
      itemCount: _treeRows.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) return _buildTreeHeader();
        return _buildTreeRow(ctx, i - 1);
      },
    );
  }

  /// Evaluates the tree's visual PYSON expression for a record row.
  /// Returns one of: 'success', 'warning', 'danger', or '' (no colour).
  String _evalVisual(TrytonRecord record) {
    if (_treeVisual == null || _treeVisual!.isEmpty) return '';
    try {
      // visual is a Python-ternary string like "'warning' if Eval('late') else ''"
      // Parse it as JSON to get the PYSON dict, then evaluate.
      final decoded = jsonDecode(_treeVisual!);
      final result = PYSONEvaluator(record.values).eval(decoded);
      return result?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  Color? _visualRowColor(BuildContext ctx, String visual, bool isSelected) {
    if (isSelected) {
      return Theme.of(ctx).colorScheme.primaryContainer.withAlpha(80);
    }
    switch (visual) {
      case 'success': return Colors.green.withAlpha(30);
      case 'warning': return Colors.orange.withAlpha(40);
      case 'danger':  return Theme.of(ctx).colorScheme.errorContainer.withAlpha(60);
      default: return null;
    }
  }

  Widget _buildTreeRow(BuildContext ctx, int index) {
    final row = _treeRows[index];
    final record = row.record;
    final isSelected = _selected.contains(record.id);
    final indent = row.depth * 20.0;
    final primary = Theme.of(ctx).colorScheme.primary;
    final visual = _evalVisual(record);

    return InkWell(
      onTap: () => _openRecord(record.id),
      child: Container(
        color: _visualRowColor(ctx, visual, isSelected),
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
        child: Row(
          children: [
            // ① Selection checkbox – always far left, never indented (like SAO)
            SizedBox(
              width: 24,
              child: Checkbox(
                value: isSelected,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (_) {
                  setState(() {
                    if (isSelected) {
                      _selected.remove(record.id);
                    } else {
                      _selected.add(record.id);
                    }
                  });
                },
              ),
            ),

            // ② Indentation per depth level
            SizedBox(width: indent),

            // ③ Expand/collapse button (like SAO: tryton-arrow-right/down)
            SizedBox(
              width: 24,
              child: row.isLoadingChildren
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : row.hasChildren
                      ? IconButton(
                          icon: Icon(
                            row.isExpanded
                                ? Icons.arrow_drop_down
                                : Icons.arrow_right,
                            color: primary,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 24, minHeight: 24),
                          onPressed: () {
                            if (row.isExpanded) {
                              _collapseRow(index);
                            } else {
                              _expandRow(index);
                            }
                          },
                        )
                      : const SizedBox(width: 24),
            ),

            const SizedBox(width: 4),

            // Data columns
            ..._columns.map((col) {
              final fd = _fields[col];
              return Expanded(
                child: _isNumeric(fd)
                    ? _NumericCell(
                        value: record[col],
                        field: fd!,
                        record: record,
                      )
                    : Text(
                        _formatValue(record[col], fd, record, col),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
              );
            }),
          ],
        ),
      ),
    );
  }

  List<DataColumn> _buildColumns() {
    return _columns.map((col) {
      // Server-defined label takes precedence over field name
      final label = _columnLabels[col] ?? _fields[col]?.label ?? col;
      return DataColumn(label: Text(label));
    }).toList();
  }

  List<DataRow> _buildRows() {
    return _records.map((record) {
      final isSelected = _selected.contains(record.id);
      final visual = _evalVisual(record);
      return DataRow(
        selected: isSelected,
        color: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Theme.of(context).colorScheme.primaryContainer.withAlpha(80);
          }
          return _visualRowColor(context, visual, false);
        }),
        cells: [
          DataCell(
            Checkbox(
              value: isSelected,
              onChanged: (_) {
                setState(() {
                  if (isSelected) {
                    _selected.remove(record.id);
                  } else {
                    _selected.add(record.id);
                  }
                });
              },
            ),
          ),
          ..._columns.map((col) {
            final fd = _fields[col];
            return DataCell(
              _isNumeric(fd)
                  ? _NumericCell(
                      value: record[col],
                      field: fd!,
                      record: record,
                    )
                  : Text(_formatValue(record[col], fd, record, col)),
              onTap: () => _openRecord(record.id),
            );
          }),
        ],
      );
    }).toList();
  }

  String _formatValue(
    dynamic value,
    FieldDefinition? field,
    TrytonRecord record,
    String colName,
  ) {
    if (value == null || value == false) return '';
    if (field?.type == 'boolean') return (value as bool) ? context.l10n.boolYes : context.l10n.boolNo;

    if (field?.type == 'many2one' || _isM2OPair(value)) {
      // [id, rec_name] pair — works even when field is null
      if (value is List && value.length > 1 && value[1] is String &&
          (value[1] as String).isNotEmpty) {
        return value[1] as String;
      }

      // Companion key 'col.rec_name'
      final companion = record['$colName.rec_name'];
      if (companion is String && companion.isNotEmpty) return companion;

      final id = _safeId(value);
      if (id == null || id <= 0) return '';

      // Cache from batch-resolve — guard against stale non-string entries.
      final relModel = field?.relation;
      if (relModel != null && relModel.isNotEmpty) {
        final cached = _m2oNameCache['$relModel,$id'];
        if (cached != null && cached.isNotEmpty &&
            !cached.startsWith('{') && !cached.startsWith('[')) {
          return cached;
        }
      }

      return '#$id';
    }

    // reference field: value is [model_name, rec_name] — show rec_name only.
    // Also catches untyped reference pairs when fd is null.
    if (field?.type == 'reference' || _isReferencePair(value)) {
      if (value is List && value.length >= 2) {
        final recName = value[1];
        if (recName is String && recName.isNotEmpty) return recName;
      }
      return '';
    }

    if (field?.type == 'selection' && field!.selection != null) {
      // Guard first: a List/Map can never be a valid selection key.
      if (value is List || value is Map) return '';
      final match = field.selection!
          .where((e) => e[0].toString() == value.toString())
          .firstOrNull;
      return match?[1]?.toString() ?? value.toString();
    }
    // Prevent raw List/Map from leaking as toString()
    if (value is List || value is Map) return '';
    return value.toString();
  }

  static bool _isM2OPair(dynamic val) =>
      val is List && val.length == 2 && val[0] is int && val[1] is String;

  /// True if [val] looks like a Tryton reference [model_name, rec_name] pair.
  /// Tryton model names always contain a dot ('product.product', 'res.user').
  static bool _isReferencePair(dynamic val) =>
      val is List &&
      val.length == 2 &&
      val[0] is String &&
      (val[0] as String).contains('.') &&
      (val[1] is String || val[1] == false || val[1] == null);

  static int? _safeId(dynamic val) {
    if (val is int) return val;
    if (val is List && val.isNotEmpty && val[0] is num) {
      return (val[0] as num).toInt();
    }
    return null;
  }

  static bool _isNumeric(FieldDefinition? fd) =>
      fd?.type == 'float' || fd?.type == 'numeric' || fd?.type == 'integer';

  List<String> _visibleColumns(Map<String, FieldDefinition> fields) {
    return fields.entries
        .where((e) =>
            !e.value.invisible &&
            e.value.type != 'one2many' &&
            e.value.type != 'many2many')
        .take(6)
        .map((e) => e.key)
        .toList();
  }
}

// ─── Numeric tree cell with locale formatting and currency symbol ─────────────

class _NumericCell extends ConsumerStatefulWidget {
  final dynamic value;
  final FieldDefinition field;
  final TrytonRecord record;
  const _NumericCell({
    required this.value,
    required this.field,
    required this.record,
  });
  @override
  ConsumerState<_NumericCell> createState() => _NumericCellState();
}

class _NumericCellState extends ConsumerState<_NumericCell> {
  String _symbol = '';
  double _position = 1.0;

  @override
  void initState() {
    super.initState();
    _loadSymbol();
  }

  @override
  void didUpdateWidget(_NumericCell old) {
    super.didUpdateWidget(old);
    if (_currencyId(old) != _currencyId(widget)) _loadSymbol();
  }

  int? _currencyId(_NumericCell w) {
    final sf = w.field.symbol;
    if (sf == null) return null;
    final v = w.record[sf];
    if (v is List && v.isNotEmpty) return (v[0] as num?)?.toInt();
    if (v is int) return v;
    return null;
  }

  Future<void> _loadSymbol() async {
    final sf = widget.field.symbol;
    if (sf == null) return;
    final id = _currencyId(widget);
    if (id == null || id <= 0) return;
    // Relation comes from the view definition – look it up via the record model.
    // We infer res.currency as default (covers 95% of cases).
    // A more complete solution would pass the relation from the tree column definition.
    const relation = 'res.currency';
    final svc = ref.read(modelServiceProvider);
    final (sym, pos) = await sym_cache.resolveSymbol(svc, relation, id);
    if (sym.isNotEmpty && mounted) {
      setState(() { _symbol = sym; _position = pos; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final isInt = widget.field.type == 'integer';
    final formatted = formatNumericValue(
      widget.value,
      digits: widget.field.digits,
      locale: locale,
      isInteger: isInt,
    );
    final hasPrefix = _symbol.isNotEmpty && _position < 0.5;
    final hasSuffix = _symbol.isNotEmpty && _position >= 0.5;
    final text = hasPrefix
        ? '$_symbol $formatted'
        : hasSuffix
            ? '$formatted $_symbol'
            : formatted;
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13),
      textAlign: TextAlign.end,
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

// ─── Context form (context_model filter panel) ────────────────────────────────

/// Renders the context model form above the list view.
/// Mirrors SAO's `context_screen` prepended to `screen_container.filter_box`.
/// When any field changes, `onChanged` is called and the list reloads.
class _ContextForm extends StatelessWidget {
  final FormRoot formRoot;
  final ViewDefinition viewDef;
  final Map<String, dynamic> values;
  final void Function(String name, dynamic value) onChanged;

  const _ContextForm({
    required this.formRoot,
    required this.viewDef,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _ContextFormGrid(
          formRoot: formRoot,
          viewDef: viewDef,
          values: values,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Grid renderer for the context form — handles col/colspan/newlines/labels
/// identically to the main form renderer.
class _ContextFormGrid extends StatelessWidget {
  final FormRoot formRoot;
  final ViewDefinition viewDef;
  final Map<String, dynamic> values;
  final void Function(String, dynamic) onChanged;

  const _ContextFormGrid({
    required this.formRoot,
    required this.viewDef,
    required this.values,
    required this.onChanged,
  });

  int get _totalCol => formRoot.col < 1 ? 4 : formRoot.col;

  @override
  Widget build(BuildContext context) {
    return _renderNodes(context, formRoot.children, _totalCol);
  }

  Widget _renderNodes(
      BuildContext context, List<FormNode> nodes, int totalCol) {
    // Pre-scan: map field name → label colspan (skipped labels donate colspan)
    final labelColspanMap = <String, int>{};
    for (final n in nodes) {
      if (n is LabelNode && n.fieldName != null) {
        labelColspanMap[n.fieldName!] = n.colspan;
      }
    }

    final rows = <Widget>[];
    final currentRow = <_CtxCell>[];
    int usedCols = 0;

    void flushRow() {
      if (currentRow.isEmpty) return;
      rows.add(_buildCtxRow(currentRow, totalCol));
      currentRow.clear();
      usedCols = 0;
    }

    for (final node in nodes) {
      if (node is LabelNode && node.fieldName != null) continue; // absorbed
      if (node is NewlineNode) { flushRow(); continue; }

      // Only FieldNodes in context forms
      if (node is! FieldNode) continue;
      final fd = viewDef.fields[node.name];
      if (fd == null) continue;

      int colspan = node.colspan.clamp(1, totalCol);
      colspan = (colspan + (labelColspanMap[node.name] ?? 0)).clamp(1, totalCol);

      if (usedCols + colspan > totalCol) flushRow();

      final fieldName = node.name;
      currentRow.add(_CtxCell(
        colspan: colspan,
        child: FieldWidget(
          field: fd,
          value: values[fieldName],
          readOnly: false,
          recordValues: values,
          onChanged: (v) => onChanged(fieldName, v),
          // Clear sets value to null → PYSON Eval returns null → condition stripped
          onClear: () => onChanged(fieldName, null),
        ),
      ));
      usedCols += colspan;
      if (usedCols >= totalCol) flushRow();
    }
    flushRow();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _buildCtxRow(List<_CtxCell> cells, int totalCol) {
    if (cells.isEmpty) return const SizedBox.shrink();
    final usedCols = cells.fold(0, (s, c) => s + c.colspan);

    if (cells.length == 1 && usedCols >= totalCol) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: cells.first.child,
      );
    }

    final children = <Widget>[
      for (final c in cells)
        Expanded(
          flex: c.colspan,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: c.child,
          ),
        ),
      if (usedCols < totalCol) Spacer(flex: totalCol - usedCols),
    ];

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

class _CtxCell {
  final int colspan;
  final Widget child;
  const _CtxCell({required this.colspan, required this.child});
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
