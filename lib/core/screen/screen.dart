/// Screen of a model (spec 04-screen.md 8.1–8.5, 8.7): a [RecordGroup],
/// its views, the search and the current record.
///
/// Port of `Sao.Screen` (SAO screen.js), checked against the Python
/// client `tryton/gui/window/view_form/screen/screen.py` 8.0. Names follow
/// screen.js. No widgets: changes are announced through [TrytonScreen]
/// (a [ChangeNotifier]); the views are descriptions ([ScreenView]) the UI
/// renders.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:xml/xml.dart';

import '../domain/domain_inversion.dart' as inversion;
import '../model/model.dart';
import '../pyson/pyson_environment.dart';
import '../pyson/pyson_evaluator.dart';
import '../xml/form_xml_parser.dart';
import '../xml/view_definition.dart';

/// View types the client can show; others in `mode` are skipped.
const supportedViewTypes = {'tree', 'form'};

/// A tab of the screen container (`tab_domain`): name, domain and whether
/// the number of records is shown (spec 8.4).
class TabDomain {
  final String name;
  final List<dynamic> domain;
  final bool count;

  const TabDomain(this.name, this.domain, {this.count = false});
}

/// Attributes of a screen (spec 8.1, SAO `Sao.Screen(model, attributes)`).
class ScreenAttributes {
  final String model;

  /// View types in the order they are loaded (`['tree', 'form']`).
  final List<String> mode;

  /// View ids belonging to [mode] (same position; may be shorter).
  final List<int?> viewIds;

  /// Views delivered beforehand (key: view id or view type).
  final Map<String, Map<String, dynamic>> viewsPreload;

  final List<dynamic> domain;
  final Map<String, dynamic> context;
  final String? contextModel;

  /// PYSON domain evaluated with the screen context (string or decoded).
  final dynamic contextDomain;
  final List<TabDomain> tabDomain;

  /// Initial search domain.
  final List<dynamic>? searchValue;
  final List<dynamic>? order;

  /// Records per search; null = unlimited.
  final int? limit;
  final bool readonly;
  final String? excludeField;

  /// Record shown first (`res_id`).
  final int? resId;

  const ScreenAttributes(
    this.model, {
    this.mode = const ['tree', 'form'],
    this.viewIds = const [],
    this.viewsPreload = const {},
    this.domain = const [],
    this.context = const {},
    this.contextModel,
    this.contextDomain,
    this.tabDomain = const [],
    this.searchValue,
    this.order,
    this.limit = 1000,
    this.readonly = false,
    this.excludeField,
    this.resId,
  });

  /// Attributes of an `ir.action.act_window` (Python client
  /// `Action.exec_action`): `views` → [viewIds]/[mode], PYSON domain,
  /// context, order, search value and tab domains evaluated in the action
  /// environment ([data]: `model`, `id`, `ids` of the calling record).
  factory ScreenAttributes.fromActWindow(
    Map<String, dynamic> action, {
    Map<String, dynamic> sessionContext = const {},
    int? userId,
    Map<String, dynamic> data = const {},
    Map<String, dynamic> context = const {},
  }) {
    final views = action['views'];
    var viewIds = const <int?>[];
    List<String>? mode;
    if (views is List && views.isNotEmpty) {
      viewIds = [for (final v in views) (v as List)[0] as int?];
      mode = [for (final v in views) '${(v as List)[1]}'];
    } else if (action['view_id'] case [final int id, ...]) {
      viewIds = [id];
    } else if (action['view_id'] case final int id) {
      viewIds = [id];
    }
    final env = actionEnvironment(
      sessionContext: sessionContext,
      userId: userId,
      activeModel: data['model'] as String?,
      activeId: data['id'] as int?,
      activeIds: [
        for (final id in (data['ids'] as List? ?? const [])) id as int,
      ],
    );
    final actionContext = <String, dynamic>{
      ...context,
      ...?_asMap(_decode(action['pyson_context'], env)),
    };
    env.addAll(actionContext);
    env['context'] = env;
    final tabs = <TabDomain>[
      for (final d in (action['domains'] as List? ?? const []))
        if (d is List && d.length >= 2)
          TabDomain(
            '${d[0]}',
            _asList(_decode(d[1], env)) ?? const [],
            count: d.length > 2 && d[2] == true,
          ),
    ];
    final limit = action['limit'];
    final contextModel = action['context_model'];
    final contextDomain = action['context_domain'];
    final resId = action['res_id'] ?? data['res_id'];
    return ScreenAttributes(
      '${action['res_model'] ?? data['res_model']}',
      mode: mode ?? const ['tree', 'form'],
      viewIds: viewIds,
      domain: _asList(_decode(action['pyson_domain'] ?? '[]', env)) ?? const [],
      context: actionContext,
      contextModel: contextModel is String && contextModel.isNotEmpty
          ? contextModel
          : null,
      contextDomain: contextDomain is String && contextDomain.isNotEmpty
          ? contextDomain
          : null,
      tabDomain: tabs,
      searchValue: _asList(_decode(action['pyson_search_value'], env)),
      order: _asList(_decode(action['pyson_order'], env)),
      limit: limit is int ? limit : 1000,
      resId: resId is int ? resId : null,
    );
  }

  static dynamic _decode(dynamic value, Map<String, dynamic> env) {
    if (value is String) {
      if (value.isEmpty) return null;
      try {
        value = jsonDecode(value);
      } catch (_) {
        return null;
      }
    }
    return value == null ? null : PYSONEvaluator(env).eval(value);
  }

  static Map<String, dynamic>? _asMap(dynamic v) =>
      v is Map ? v.map((k, v) => MapEntry('$k', v)) : null;

  static List<dynamic>? _asList(dynamic v) => v is List ? v : null;
}

/// A view of a screen (SAO `Sao.View`): the `fields_view_get` result and
/// the attributes of the root element.
class ScreenView {
  final ViewDefinition definition;

  /// Attributes of the root element (`editable`, `creatable`,
  /// `keyword_open`, `visual`, …).
  final Map<String, String> attributes;

  /// Parsed form (form views only).
  final FormRoot? formRoot;

  final bool _screenReadonly;

  ScreenView._(
    this.definition,
    this.attributes,
    this.formRoot,
    this._screenReadonly,
  );

  factory ScreenView.parse(
    ViewDefinition definition, {
    bool screenReadonly = false,
  }) {
    final root = XmlDocument.parse(definition.arch).rootElement;
    return ScreenView._(
      definition,
      {for (final a in root.attributes) a.localName: a.value},
      definition.type == 'form' ? FormXmlParser().parse(definition.arch) : null,
      screenReadonly,
    );
  }

  int? get viewId => definition.viewId;
  String get viewType => definition.type;

  /// One2Many field of hierarchical trees (only from this view).
  String? get fieldChilds => definition.fieldChilds;

  /// Field names of this view.
  Iterable<String> get fields => definition.rawFields.keys;

  bool _flag(String name) => (int.tryParse(attributes[name] ?? '') ?? 0) != 0;

  /// Form: always; tree: `editable="1"` and screen not readonly.
  bool get editable =>
      viewType == 'form' || (_flag('editable') && !_screenReadonly);

  /// Whether records can be created in this view.
  bool get creatable {
    if (viewType == 'form') {
      return attributes['creatable'] == null || _flag('creatable');
    }
    if (!editable) return false;
    return attributes['creatable'] == null || _flag('creatable');
  }

  bool get searchable => viewType == 'tree';

  /// Buttons of the view (form: all `<button>` nodes, nested too).
  late final List<ButtonNode> buttons = [
    if (formRoot != null) ..._buttonsOf(formRoot!.children),
  ];

  static Iterable<ButtonNode> _buttonsOf(List<FormNode> nodes) sync* {
    for (final node in nodes) {
      switch (node) {
        case ButtonNode():
          yield node;
        case GroupNode():
          yield* _buttonsOf(node.children);
        case NotebookNode():
          yield* _buttonsOf(node.pages);
        case PageNode():
          yield* _buttonsOf(node.children);
        default:
          break;
      }
    }
  }

  @override
  String toString() => 'ScreenView($viewType, $viewId)';
}

/// Answer of [TrytonScreen.clientAction] for actions handled outside the
/// screen (`close`, `reload menu`, `reload context`).
typedef ScreenCallback = Future<void> Function();

/// Screen of a model (SAO `Sao.Screen`, spec 8).
class TrytonScreen extends ChangeNotifier {
  final ScreenAttributes attributes;
  final TrytonModel model;

  late RecordGroup group;

  final List<int?> _viewIds;
  final List<String> _viewToLoad;
  final List<ScreenView> views = [];
  ScreenView? currentView;

  /// Domain of the screen (`attributes.domain`).
  final List<dynamic> domain;
  final dynamic contextDomain;
  final int? limit;
  int offset = 0;

  /// Current order (null = server default) and the action's order.
  List<dynamic>? order;
  final List<dynamic>? defaultOrder;

  /// Number of records of the last search (capped at [countLimit]).
  int searchCount = 0;
  List<dynamic> _currentDomain = const [];

  /// Number of ids of the last `search` (for [hasNextPage]).
  int _lastSearchLength = 0;

  final bool screenReadonly;

  /// Screen of the `context_model` (form of the search context).
  final TrytonScreen? contextScreen;

  /// Text of the search entry (rec_name ilike until the DomainParser, C4).
  String searchText = '';

  /// Tab domains and the selected tab; [tabCounters] holds the counts of
  /// tabs with `count` (null = loading/unknown).
  final List<TabDomain> tabDomain;
  int tabIndex = 0;
  late final List<int?> tabCounters;

  /// `[width, height]` for `fields_view_get` (`screen_size`).
  List<int> Function()? screenSize;

  /// Called for each added view with its model (e.g. to mark fields
  /// without widget readonly).
  void Function(ScreenView view)? onViewAdded;

  /// Client actions handled outside (spec 8.7).
  ScreenCallback? onClose;
  ScreenCallback? onReloadMenu;
  ScreenCallback? onReloadContext;

  /// Buttons (spec 8.6): `confirm` question (true = go on), warning of
  /// a failed pre-validation (message, title), an action returned by a
  /// class button (run with keyword; data `model`, `id`, `ids`), texts of
  /// [Record.invalidMessage].
  Future<bool> Function(String text)? onConfirm;
  Future<void> Function(String message)? onPreValidationFailed;
  Future<void> Function(dynamic action, Map<String, dynamic> data,
      Map<String, dynamic> context)? onAction;
  InvalidMessages Function()? invalidTexts;

  /// Records selected in a list view (set by the view).
  List<Record> selectedRecords = const [];

  Record? _currentRecord;
  bool _disposed = false;

  TrytonScreen(this.attributes, {required ModelSession session})
    : model = TrytonModel(attributes.model, session: session),
      _viewIds = [...attributes.viewIds],
      _viewToLoad = [...attributes.mode],
      domain = attributes.domain,
      contextDomain = attributes.contextDomain,
      limit = attributes.limit,
      order = attributes.order,
      defaultOrder = attributes.order,
      screenReadonly = attributes.readonly,
      tabDomain = attributes.tabDomain,
      contextScreen = attributes.contextModel == null
          ? null
          : TrytonScreen(
              ScreenAttributes(
                attributes.contextModel!,
                mode: const ['form'],
                context: attributes.context,
              ),
              session: session,
            ) {
    tabCounters = List.filled(tabDomain.length, null);
    _setGroup(RecordGroup(model, context: attributes.context));
  }

  /// A screen on an existing [group] (x2many child group of a form): the
  /// records stay in that group (popups, spec 11.1). Modifications are
  /// announced by the root group, so the screen listens there.
  TrytonScreen.forGroup(this.attributes, RecordGroup group)
      : model = group.model,
        _viewIds = [...attributes.viewIds],
        _viewToLoad = [...attributes.mode],
        domain = attributes.domain,
        contextDomain = null,
        limit = null,
        order = null,
        defaultOrder = null,
        screenReadonly = attributes.readonly,
        tabDomain = const [],
        contextScreen = null {
    tabCounters = const [];
    this.group = group;
    _listened = group.rootGroup..addListener(_onGroupChanged);
  }

  /// Group whose notifications this screen follows (the root group of a
  /// child group).
  RecordGroup? _listened;

  @override
  void dispose() {
    _disposed = true;
    group.removeListener(_onGroupChanged);
    _listened?.removeListener(_onGroupChanged);
    contextScreen?.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _onGroupChanged() => _notify();

  // ── Group ─────────────────────────────────────────────────────────────────

  void _setGroup(RecordGroup newGroup) {
    newGroup.readonly = screenReadonly;
    newGroup.excludeField = attributes.excludeField;
    if (domain.isNotEmpty) newGroup.screenDomains.add(domain);
    newGroup.addListener(_onGroupChanged);
    group = newGroup;
    _currentRecord = null;
  }

  /// Replaces the group by an empty one with [context] (SAO `new_group`).
  void newGroup([Map<String, dynamic>? context]) {
    final old = group;
    old.removeListener(_onGroupChanged);
    final onNotify = old.onNotify;
    _setGroup(
      RecordGroup(model, context: context ?? old.localContext)
        ..onWrite = [...old.onWrite]
        ..onNotify = onNotify,
    );
  }

  /// Group context; with a context model also `context_model`.
  Map<String, dynamic> get context => {
    ...group.context,
    if (contextScreen != null) 'context_model': contextScreen!.model.name,
  };

  Map<String, dynamic> get localContext => {
    ...group.localContext,
    if (contextScreen != null) 'context_model': contextScreen!.model.name,
  };

  // ── Current record ────────────────────────────────────────────────────────

  Record? get currentRecord {
    final r = _currentRecord;
    if (r != null && r.destroyed) _currentRecord = null;
    return _currentRecord;
  }

  set currentRecord(Record? record) {
    _currentRecord = record;
    _notify();
  }

  /// Position of the current record (1-based incl. [offset]); 0 = none.
  int get position {
    final r = currentRecord;
    if (r == null) return 0;
    final i = group.indexOf(r);
    return i >= 0 ? i + offset + 1 : 0;
  }

  /// Records loaded so far incl. [offset] (SAO `group.length + offset`).
  int get loadedCount => group.length + offset;

  /// Count of `search_count` (`limit * 100 + offset`).
  int get countLimit => (limit ?? 0) * 100 + offset;

  /// Whether [searchCount] hit [countLimit] (status shows `+`).
  bool get countLimitReached =>
      limit != null && searchCount >= countLimit && countLimit > 0;

  /// Status text (spec 8.3, SAO `record_message`): `position@loaded/count`
  /// (`+` when the count limit is reached) or `position/loaded`; `_`
  /// without current record, `#n` with n selected records.
  String get statusText {
    var name = '_';
    if (position > 0) {
      name = '$position';
      if (selectedRecords.length > 1) name += '#${selectedRecords.length}';
    }
    final size = loadedCount;
    if (size < searchCount) {
      return '$name@$size/$searchCount${countLimitReached ? '+' : ''}';
    }
    return '$name/$size';
  }

  bool get readonly =>
      screenReadonly ||
      !(model.access.write || model.access.create) ||
      selectedRecords.any((r) => r.readonly);

  bool get deletable => selectedRecords.every((r) => r.deletable);

  // ── Views (8.2) ───────────────────────────────────────────────────────────

  int get numberOfViews => views.length + _viewToLoad.length;

  int get viewIndex => currentView == null ? -1 : views.indexOf(currentView!);

  /// Type of the view [switchView] would show next.
  String? get nextViewType {
    final all = [
      for (final v in views) v.viewType,
      ..._viewToLoad.where(supportedViewTypes.contains),
    ];
    if (all.isEmpty) return null;
    return all[(viewIndex + 1) % all.length];
  }

  Future<ScreenView?> _loadNextView() async {
    while (_viewToLoad.isNotEmpty) {
      final viewId = _viewIds.isNotEmpty ? _viewIds.removeAt(0) : null;
      final viewType = _viewToLoad.removeAt(0);
      if (!supportedViewTypes.contains(viewType)) continue;
      return addViewId(viewId, viewType);
    }
    return null;
  }

  /// Loads the view [viewId]/[viewType] (preloaded or `fields_view_get`
  /// with `screen_size` and `view_tree_width`) and adds it.
  Future<ScreenView> addViewId(int? viewId, String viewType) async {
    Map<String, dynamic>? view;
    if (viewId != null) {
      view = attributes.viewsPreload['$viewId'];
    } else {
      view = attributes.viewsPreload[viewType];
    }
    if (view == null) {
      final ctx = context;
      final size = screenSize?.call();
      if (size != null) ctx['screen_size'] = size;
      ctx['view_tree_width'] = true;
      final result = await model.execute('fields_view_get', [
        viewId,
        viewType,
      ], context: ctx);
      view = Map<String, dynamic>.from(result as Map);
    }
    return addView(ViewDefinition.fromJson(view));
  }

  /// Adds a loaded view: fields get `loading` (form lazy, else eager)
  /// and the view id (SAO `add_view`).
  ScreenView addView(ViewDefinition definition) {
    final loading = definition.type == 'form' ? 'lazy' : 'eager';
    final fields = <String, dynamic>{};
    for (final MapEntry(key: name, value: desc)
        in definition.rawFields.entries) {
      final d = Map<String, dynamic>.from(desc as Map);
      final existing = model.fields[name];
      d['loading'] = existing == null || loading == 'eager'
          ? loading
          : existing.description['loading'] ?? loading;
      fields[name] = d;
    }
    group.addFields(fields);
    for (final name in fields.keys) {
      model.fields[name]!.views.add(definition.viewId ?? definition.type);
    }
    final view = ScreenView.parse(definition, screenReadonly: screenReadonly);
    if (view.formRoot != null) _applyViewAttributes(view.formRoot!.children);
    views.add(view);
    onViewAdded?.call(view);
    return view;
  }

  /// readonly/required/invisible of the `<field>` nodes extend the field
  /// description (SAO `field_attrs`).
  void _applyViewAttributes(List<FormNode> nodes) {
    for (final node in nodes) {
      switch (node) {
        case FieldNode():
          final desc = model.fields[node.name]?.description;
          if (desc == null) continue;
          if (node.readonly != null) desc['readonly'] = node.readonly;
          if (node.required != null) desc['required'] = node.required;
          if (node.invisible != null) desc['invisible'] = node.invisible;
        case GroupNode():
          _applyViewAttributes(node.children);
        case NotebookNode():
          _applyViewAttributes(node.pages);
        case PageNode():
          _applyViewAttributes(node.children);
        default:
          break;
      }
    }
  }

  /// Switches to the next view matching [viewType]/[viewId]/[creatable]/
  /// [searchable] (cyclic, loading views as needed). An invalid record of
  /// an editable view blocks the switch (returns false).
  Future<bool> switchView({
    String? viewType,
    int? viewId,
    bool? creatable,
    bool? searchable,
  }) async {
    final current = currentView;
    if (current != null) {
      final record = currentRecord;
      if (record != null && !group.contains(record) && !_inChildGroup(record)) {
        _currentRecord = null;
      }
      if (currentRecord != null &&
          current.editable &&
          !currentRecord!.validate(fields: current.fields)) {
        _notify();
        return false;
      }
    }
    bool found() {
      final v = currentView;
      if (v == null) return false;
      return (viewType == null || v.viewType == viewType) &&
          (viewId == null || v.viewId == viewId) &&
          (creatable == null || v.creatable == creatable) &&
          (searchable == null || v.searchable == searchable);
    }

    final total = numberOfViews;
    for (var n = 0; n < total; n++) {
      if (_viewToLoad.isNotEmpty) {
        final loaded = await _loadNextView();
        if (loaded != null) currentView = loaded;
      } else if (viewId != null && !views.any((v) => v.viewId == viewId)) {
        currentView = await addViewId(viewId, viewType ?? 'form');
      } else if (views.isNotEmpty) {
        currentView = views[(viewIndex + 1) % views.length];
      }
      if (found()) break;
    }
    if (currentView?.viewType == 'form' &&
        currentRecord == null &&
        group.isNotEmpty) {
      _currentRecord = group.first;
    }
    await _loadCurrent();
    _notify();
    return true;
  }

  bool _inChildGroup(Record record) {
    var g = record.group;
    while (g.parent != null) {
      g = g.parent!.group;
    }
    return identical(g, group);
  }

  /// Loads all fields of the current record for a form view.
  Future<void> _loadCurrent() async {
    final record = currentRecord;
    if (record != null && currentView?.viewType == 'form') {
      await record.load('*');
    }
  }

  // ── Search (8.3) ──────────────────────────────────────────────────────────

  /// Search domain (SAO `search_domain`): search text (`rec_name ilike`,
  /// or [ScreenAttributes.searchValue] for the first search) or, for a
  /// child group, the ids of the group; AND screen domain, context domain
  /// and (with [withTab]) the selected tab domain.
  List<dynamic> searchDomain({String? text, bool withTab = true}) {
    List<dynamic> result;
    if (group.parent == null) {
      final search = text ?? searchText;
      if (search.isNotEmpty) {
        result = [
          ['rec_name', 'ilike', '%$search%'],
        ];
      } else {
        result = _initialSearchValue ?? const [];
      }
    } else {
      result = [
        [
          'id',
          'in',
          [for (final r in group) r.id],
        ],
      ];
    }
    if (result.isNotEmpty) {
      if (domain.isNotEmpty) result = ['AND', result, domain];
    } else {
      result = domain;
    }
    final cd = contextDomain;
    if (cd != null) {
      final env = context;
      env['context'] = env;
      dynamic decoded = cd;
      if (cd is String) decoded = jsonDecode(cd);
      result = ['AND', result, PYSONEvaluator(env).eval(decoded)];
    }
    if (withTab && tabIndex >= 0 && tabIndex < tabDomain.length) {
      final tab = tabDomain[tabIndex].domain;
      if (tab.isNotEmpty) result = ['AND', result, tab];
    }
    return result;
  }

  late List<dynamic>? _initialSearchValue = attributes.searchValue;

  /// Searches with [text] and loads the first page (SAO `search_filter`,
  /// spec 8.3). Returns false when the context form is invalid.
  Future<bool> searchFilter([String? text]) async {
    if (text != null) searchText = text;
    final cs = contextScreen;
    if (cs != null) {
      final record = cs.currentRecord;
      if (record != null && !record.validate()) {
        newGroup();
        _notify();
        return false;
      }
      final screenContext = {...?cs.currentRecord?.getOnChangeValue()}
        ..remove('id');
      newGroup({...group.localContext, ...screenContext});
    }
    final searchDomain = this.searchDomain();
    _initialSearchValue = null;
    final canonical = inversion.canonicalize(searchDomain);
    if (!inversion.domainEquals(canonical, _currentDomain)) {
      _currentDomain = canonical;
      offset = 0;
    }
    final ctx = context;
    var ids = await _search(searchDomain, ctx, offset);
    while (ids.isEmpty && offset > 0) {
      offset = math.max(offset - (limit ?? 0), 0);
      ids = await _search(searchDomain, ctx, offset);
    }
    _lastSearchLength = ids.length;
    await _updateCount(searchDomain, ctx, ids.length);
    clear();
    load(ids);
    unawaited(countTabDomain());
    return true;
  }

  Future<List<int>> _search(
    List<dynamic> domain,
    Map<String, dynamic> ctx,
    int offset,
  ) async => [
    for (final id
        in (await model.execute('search', [
                  domain,
                  offset,
                  limit,
                  order,
                ], context: ctx)
                as List? ??
            const []))
      id as int,
  ];

  Future<void> _updateCount(
    List<dynamic> domain,
    Map<String, dynamic> ctx,
    int found,
  ) async {
    if (limit != null && found == limit) {
      try {
        final count = await model.execute(
          'search_count',
          [domain, 0, countLimit],
          context: ctx,
          processException: false,
        );
        searchCount = count is int ? count : 0;
      } catch (_) {
        searchCount = 0;
      }
    } else {
      searchCount = offset + found;
    }
  }

  /// Whether a further page exists (SAO `but_next`).
  bool get hasNextPage =>
      limit != null &&
      _lastSearchLength == limit &&
      searchCount > limit! + offset;

  bool get hasPreviousPage => offset > 0;

  /// Previous / next page (SAO `search_prev/next`).
  Future<void> searchPrev() async {
    if (limit != null) offset = math.max(offset - limit!, 0);
    await searchFilter();
  }

  Future<void> searchNext() async {
    if (limit != null) offset += limit!;
    await searchFilter();
  }

  /// Whether [searchMore] can append records (endless scrolling).
  bool get hasMore =>
      limit != null &&
      group.parent == null &&
      _lastSearchLength == limit &&
      loadedCount < math.max(searchCount, loadedCount + 1);

  /// Appends the next [limit] records to the group (endless scrolling of
  /// the list instead of a page switch; [offset] stays).
  Future<void> searchMore() async {
    if (!hasMore) return;
    final searchDomain = this.searchDomain();
    final ids = await _search(searchDomain, context, loadedCount);
    _lastSearchLength = ids.length;
    if (searchCount < loadedCount + ids.length) {
      searchCount = loadedCount + ids.length;
    }
    load(ids, resetCurrent: false);
  }

  /// Counts of the tabs with `count` (`search_count` up to 1000).
  Future<void> countTabDomain({bool current = false}) async {
    if (tabDomain.isEmpty) return;
    final screenDomain = searchDomain(withTab: false);
    final ctx = context;
    await Future.wait([
      for (var i = 0; i < tabDomain.length; i++)
        if (tabDomain[i].count && (!current || i == tabIndex))
          () async {
            tabCounters[i] = null;
            try {
              final count = await model.execute(
                'search_count',
                [
                  ['AND', tabDomain[i].domain, screenDomain],
                  0,
                  1000,
                ],
                context: ctx,
                processException: false,
              );
              tabCounters[i] = count is int ? count : null;
            } catch (_) {
              tabCounters[i] = null;
            }
          }(),
    ]);
    _notify();
  }

  /// Selects tab [index] and searches again.
  Future<void> setTab(int index) async {
    tabIndex = index;
    offset = 0;
    await searchFilter();
  }

  /// Sorts by [field]: ASC → DESC → default order (root lists only).
  Future<void> sortBy(String field) async {
    if (group.parent != null) return;
    final current = order;
    String? direction;
    if (current != null &&
        current.length == 1 &&
        current.first is List &&
        (current.first as List).first == field) {
      direction = '${(current.first as List)[1]}';
    }
    if (direction == null) {
      order = [
        [field, 'ASC'],
      ];
    } else if (direction.startsWith('ASC')) {
      order = [
        [field, 'DESC'],
      ];
    } else {
      order = defaultOrder;
    }
    await searchFilter();
  }

  /// Sort direction of [field] in the current order (`ASC`/`DESC`/null).
  String? sortDirection(String field) {
    final current = order;
    if (current == null || current == defaultOrder) return null;
    for (final o in current) {
      if (o is List && o.first == field) {
        return '${o[1]}'.startsWith('DESC') ? 'DESC' : 'ASC';
      }
    }
    return null;
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  /// Adds placeholder records for [ids] (SAO `load`).
  void load(
    List<int> ids, {
    bool modified = false,
    int position = -1,
    bool resetCurrent = true,
  }) {
    group.load(ids, modified: modified, position: position);
    if (resetCurrent) _currentRecord = null;
    _notify();
  }

  void clear() {
    _currentRecord = null;
    group.clear();
    selectedRecords = const [];
  }

  // ── Navigation (8.5) ──────────────────────────────────────────────────────

  Record? _nextRecord() {
    final view = currentView;
    final record = currentRecord;
    if (view != null && record != null) {
      var g = record.group;
      var r = record;
      while (true) {
        final index = g.indexOf(r);
        if (index < g.length - 1) return g[index + 1];
        final p = g.parent;
        if (p != null && r.group.model.name == p.group.model.name) {
          r = p;
          g = p.group;
        } else {
          return r;
        }
      }
    }
    return group.isEmpty ? null : group.first;
  }

  Record? _previousRecord() {
    final view = currentView;
    final record = currentRecord;
    if (view != null && record != null) {
      var g = record.group;
      var r = record;
      while (true) {
        final index = g.indexOf(r);
        if (index > 0) return g[index - 1];
        final p = g.parent;
        if (p != null && r.group.model.name == p.group.model.name) {
          r = p;
          g = p.group;
        } else {
          return r;
        }
      }
    }
    return group.isEmpty ? null : group.first;
  }

  bool get hasNext {
    final next = _nextRecord();
    return next != null && !identical(next, currentRecord);
  }

  bool get hasPrevious {
    final previous = _previousRecord();
    return previous != null && !identical(previous, currentRecord);
  }

  Future<void> displayNext() async {
    _currentRecord = _nextRecord();
    await _loadCurrent();
    _notify();
  }

  Future<void> displayPrevious() async {
    _currentRecord = _previousRecord();
    await _loadCurrent();
    _notify();
  }

  // ── Record operations (8.5) ───────────────────────────────────────────────

  /// Position of new records (SAO `new_position`): `id DESC` → top,
  /// `id ASC` → bottom, else root top, child bottom.
  int get newPosition {
    final o = order ?? defaultOrder;
    if (o != null) {
      for (final item in o) {
        if (item is List && item.first == 'id' && item.length > 1) {
          final type = '${item[1]}';
          if (type.startsWith('DESC')) return 0;
          if (type.startsWith('ASC')) return -1;
        }
      }
    }
    return group.parent != null ? -1 : 0;
  }

  /// New record (SAO `new_`): switches to a creatable view first, adds the
  /// record with its defaults at [newPosition] in the group of the current
  /// record (tree) or the root group.
  Future<Record?> newRecord({
    bool defaults = true,
    Map<String, dynamic>? values,
  }) async {
    if (currentView != null && !currentView!.creatable) {
      if (!await switchView(viewType: 'form', creatable: true)) return null;
    }
    if (currentView == null || !currentView!.editable) return null;
    final target = currentRecord?.group ?? group;
    final record = target.newRecord();
    if (defaults) await record.defaultGet(values);
    target.add(record, position: _positionIn(target));
    _currentRecord = record;
    _notify();
    return record;
  }

  int _positionIn(RecordGroup target) {
    final position = newPosition;
    return position == -1 ? target.length : math.min(position, target.length);
  }

  /// Saves the current record (SAO `save_current`): a tree view saves the
  /// whole group, otherwise the record is validated first. Returns false
  /// when invalid or not saved.
  Future<bool> saveCurrent() async {
    var record = currentRecord;
    final view = currentView;
    if (record == null) {
      if (view?.viewType == 'tree' && group.isNotEmpty) {
        record = _currentRecord = group.first;
      } else {
        return true;
      }
    }
    final bool ok;
    if (view?.viewType == 'tree') {
      ok = await group.save();
    } else if (record.validate(fields: view?.fields)) {
      ok = await record.save();
    } else {
      _notify();
      return false;
    }
    _notify();
    return ok;
  }

  /// Discards the changes of the current record (SAO `cancel_current`); a
  /// new record is removed.
  Future<void> cancelCurrent() async {
    final record = currentRecord;
    if (record == null) return;
    record.cancel();
    if (record.id < 0) {
      await remove(records: [record]);
    } else {
      await record.load('*');
    }
    _notify();
  }

  /// Deletes ([delete]) or removes ([remove]) [records] (default:
  /// selection or current record) (SAO `remove`). Returns false when the
  /// user cancelled a conflict.
  Future<bool> remove({
    bool delete = false,
    bool remove = false,
    bool forceRemove = false,
    List<Record>? records,
  }) async {
    records ??= _selectedOrCurrent;
    if (records.isEmpty) return true;
    final current = currentRecord;
    if (delete && !await group.delete(records)) return false;
    for (final record in records) {
      record.group.remove(
        record,
        remove: remove,
        forceRemove: forceRemove,
        modified: false,
      );
    }
    records.first.group.recordModified();
    if (delete) {
      for (final record in records) {
        final g = record.group;
        if (g.parent != null) await g.parent!.save(forceReload: false);
        g.recordDeleted.remove(record);
        g.recordRemoved.remove(record);
      }
      _removeDestroyed(records);
    }
    _currentRecord = current != null && !current.destroyed ? current : null;
    selectedRecords = [
      for (final r in selectedRecords)
        if (!r.destroyed) r,
    ];
    if (delete &&
        _currentRecord == null &&
        currentView?.viewType == 'form' &&
        group.isNotEmpty) {
      _currentRecord = group.first;
      await _loadCurrent();
    }
    _notify();
    return true;
  }

  /// Deleted records leave their (root) group.
  void _removeDestroyed(List<Record> records) {
    for (final record in records) {
      if (record.destroyed && record.group.contains(record)) {
        record.group.remove(
          record,
          remove: false,
          forceRemove: true,
          modified: false,
        );
        record.group.recordDeleted.remove(record);
      }
    }
  }

  List<Record> get _selectedOrCurrent {
    if (currentView?.viewType == 'tree' && selectedRecords.isNotEmpty) {
      return [...selectedRecords];
    }
    final r = currentRecord;
    return r == null ? const [] : [r];
  }

  /// Restores removed/deleted (not yet saved) records (SAO `unremove`).
  void unremove() {
    for (final record in _selectedOrCurrent) {
      record.group.unremove(record);
    }
    _notify();
  }

  /// Copies the selected records (`copy(ids, {})`), loads the copies at
  /// [newPosition] and selects the first (SAO `copy`).
  Future<List<int>> copy() async {
    final ids = [
      for (final r in _selectedOrCurrent)
        if (r.id >= 0) r.id,
    ];
    if (ids.isEmpty) return const [];
    final result = await model.execute('copy', [
      ids,
      <String, dynamic>{},
    ], context: context);
    final newIds = [for (final id in (result as List? ?? const [])) id as int];
    group.load(newIds, position: _positionIn(group));
    if (newIds.isNotEmpty) {
      _currentRecord = group.get(newIds.first);
      await _loadCurrent();
    }
    _notify();
    return newIds;
  }

  /// Form: current record modified or new; list: any record (SAO
  /// `modified`).
  bool modified() {
    bool test(Record r) => r.modified || r.id < 0;
    if (currentView != null && currentView!.viewType != 'tree') {
      final r = currentRecord;
      return r != null && test(r);
    }
    return group.any(test);
  }

  /// Reloads [ids] (unchanged records are reset and loaded again), then
  /// on_write ids (SAO `reload`).
  Future<void> reload(List<int> ids, {bool written = false}) async {
    group.reload(ids);
    if (written) await group.written(ids);
    final p = group.parent;
    if (p != null) await p.rootParent.reload();
    await _loadCurrent();
    _notify();
  }

  /// Reloads the current list (search again) or the current record.
  Future<void> reloadCurrent() async {
    if (currentView?.searchable ?? false) {
      if (group.parent == null) await searchFilter();
      return;
    }
    final record = currentRecord;
    if (record == null) return;
    record.cancel();
    await record.load('*');
    _notify();
  }

  // ── Buttons (8.6) ─────────────────────────────────────────────────────────

  /// Records a button works on: the selection of a list, else the
  /// current record.
  List<Record> get _buttonRecords => _selectedOrCurrent;

  /// Class buttons of the current view usable for all selected records
  /// (not invisible/readonly; SAO `get_buttons`, toolbar menus).
  List<ButtonNode> getButtons() {
    final records = _buttonRecords;
    if (records.isEmpty || screenReadonly) return const [];
    return [
      for (final button in currentView?.buttons ?? const <ButtonNode>[])
        if (!button.isInstance &&
            records.every((r) {
              final states = r.exprEval(button.statesRaw ?? const {});
              return !(states is Map &&
                  (PYSONEvaluator.truthy(states['invisible']) ||
                      PYSONEvaluator.truthy(states['readonly'])));
            }))
          button
    ];
  }

  /// Runs [button] (SAO `screen.button`, spec 8.6):
  /// 1. selected records validated with `states.pre_validate`;
  /// 2. `confirm` question;
  /// 3. instance button: `model.X.<name>(values of change + id)`, the
  ///    changes applied with `set_on_change` (no save);
  /// 4. class button: save the current record, `model.X.<name>(ids)` with
  ///    `_timestamp` of the selected records; a string result is a client
  ///    action (after reload), an action runs with keyword (then reload),
  ///    otherwise and on error reload.
  Future<void> button(ButtonNode button) async {
    final current = currentRecord;
    if (current == null) return;
    final records = _buttonRecords;
    final fields = currentView?.fields;
    for (final record in records) {
      final states = record.exprEval(button.statesRaw ?? const {});
      final domain = states is Map ? states['pre_validate'] : null;
      if (!record.validate(
          fields: fields,
          preValidate: domain is List && domain.isNotEmpty ? domain : null)) {
        final texts = invalidTexts?.call() ?? const InvalidMessages();
        await onPreValidationFailed?.call(record.invalidMessage(texts));
        // Reset the valid state with the normal domain
        record.validate(fields: fields);
        _notify();
        return;
      }
    }
    final confirm = button.confirm;
    if (confirm != null && confirm.isNotEmpty) {
      if (!await (onConfirm?.call(confirm) ?? Future.value(true))) {
        _notify();
        return;
      }
    }
    if (button.isInstance) {
      final args = current.exprEval(button.change ?? const []);
      final values = current.getOnChangeArgs(
          [for (final a in (args is List ? args : const [])) '$a'])
        ..['id'] = current.id;
      final changes = await model
          .execute(button.name, [values], context: context);
      if (changes is Map) {
        await current.setOnChange(changes.cast<String, dynamic>());
      }
      current.setModified();
      _notify();
      return;
    }
    if (!await current.save(forceReload: false)) return;
    final ctx = context;
    final timestamps = <String, String?>{};
    final ids = <int>[];
    for (final record in records) {
      timestamps.addAll(record.getTimestamp());
      ids.add(record.id);
    }
    ctx['_timestamp'] = timestamps;
    final dynamic result;
    try {
      result = await model.execute(button.name, [ids], context: ctx);
    } catch (_) {
      await reload(ids, written: true);
      rethrow;
    }
    if (result is String) {
      await reload(ids, written: true);
      await clientAction(result);
    } else if (result != null && result != false) {
      try {
        await onAction?.call(result,
            {'model': model.name, 'id': current.id, 'ids': ids}, context);
      } finally {
        await reload(ids, written: true);
      }
    } else {
      await reload(ids, written: true);
    }
  }

  // ── Client actions (8.7) ──────────────────────────────────────────────────

  /// Runs a client action string of a button (spec 8.7) with the access
  /// checks of SAO `client_action`.
  Future<void> clientAction(String action) async {
    final access = model.access;
    switch (action) {
      case 'new':
        if (access.create) await newRecord();
      case 'delete':
        if (access.delete && (currentRecord?.deletable ?? true)) {
          final root = group.parent == null;
          await remove(delete: root, forceRemove: root);
        }
      case 'remove':
        if (access.write && access.read && group.parent != null) {
          await remove(remove: true);
        }
      case 'copy':
        if (access.create) await copy();
      case 'next':
        await displayNext();
      case 'previous':
        await displayPrevious();
      case 'close':
        await onClose?.call();
      case 'reload':
        if ((currentView?.searchable ?? false) && group.parent == null) {
          await searchFilter();
        }
      case 'reload menu':
        await onReloadContext?.call();
        await onReloadMenu?.call();
      case 'reload context':
        await onReloadContext?.call();
      default:
        if (action.startsWith('switch')) {
          final parts = action.split(' ');
          await switchView(
            viewType: parts.length > 1 ? parts[1] : null,
            viewId: parts.length > 2 ? int.tryParse(parts[2]) : null,
          );
        }
    }
  }

  @override
  String toString() => 'TrytonScreen(${model.name})';
}
