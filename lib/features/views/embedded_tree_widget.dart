import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart';
import '../../core/rpc/error_processing.dart';
import '../../core/screen/screen.dart';
import '../../core/xml/form_xml_parser.dart';
import '../../core/xml/view_definition.dart';
import '../../shared/errors/error_dialogs.dart';
import '../auth/user_preferences_provider.dart';
import '../model/field_definition.dart';
import '../model/field_support.dart';
import '../model/model_service.dart';
import 'form_dialog.dart';
import 'record_form.dart';
import 'record_widget_values.dart';
import 'search_dialog.dart';
import 'record_cells.dart';

/// Views of x2many relations (`fields_view_get`), loaded once per
/// relation and view type (values, not futures: a cached future would be
/// bound to the zone that created it).
final _viewCache = <String, ViewDefinition>{};

Future<ViewDefinition> _view(ModelService svc, String model, String type,
    [int? viewId]) async {
  final key = '$model|$type|${viewId ?? ''}';
  final cached = _viewCache[key];
  if (cached != null) return cached;
  return _viewCache[key] =
      await svc.fieldsViewGet(model, viewType: type, viewId: viewId);
}

/// Clears the cached x2many views (e.g. after logout).
void clearEmbeddedViewCache() => _viewCache.clear();

/// One2Many/Many2Many field of a form (spec 9.2.7): the child group of
/// [parent] as a table or, with `form` in `mode` (Python `Screen(mode=…)`,
/// default `tree,form`), as an inline form of one record with Previous/
/// Next; the first entry of `mode` is shown first, „Switch“ changes the
/// view. `view_ids` belong to the views of `mode` by position.
///
/// * New: `default_get` in a new child record, added to the group (the
///   parent field points to the parent), opened in the sub-form.
/// * Open/Edit: the sub-form works on the record of the group.
/// * Delete (one2many) / Remove (many2many): only marked, Undelete undoes.
///
/// Nothing is saved here: the parent writes the children with its x2many
/// commands (`add`, `create`, `write`, `remove`, `delete`).
class EmbeddedTreeWidget extends ConsumerStatefulWidget {
  final Record parent;
  final FieldDefinition fieldDef;

  /// The `<field>` of the form (attributes `view_ids`, `add_remove`,
  /// `size`, `delete`, `create`).
  final FieldNode? node;

  /// `readonly` of the x2many field (its states): New, Delete, Add, Remove
  /// are disabled (Python `One2Many._readonly`).
  final bool readOnly;

  /// The parent record/group is read-only: the records themselves cannot
  /// be edited (Python: the child screen's `readonly` = the parent group's).
  /// The inline form and the popup follow this, not [readOnly] – their
  /// fields are editable by their own states.
  final bool parentReadOnly;

  /// Breadcrumb of the popups.
  final List<String> breadcrumb;

  const EmbeddedTreeWidget({
    super.key,
    required this.parent,
    required this.fieldDef,
    this.node,
    this.readOnly = false,
    bool? parentReadOnly,
    this.breadcrumb = const [],
  }) : parentReadOnly = parentReadOnly ?? readOnly;

  @override
  ConsumerState<EmbeddedTreeWidget> createState() => _EmbeddedTreeWidgetState();
}

class _EmbeddedTreeWidgetState extends ConsumerState<EmbeddedTreeWidget> {
  TreeViewDefinition? _treeDef;
  ViewDefinition? _treeView;

  final Set<Record> _selected = {};

  /// A popup is open.
  bool _popup = false;

  /// Records whose row values are being loaded.
  final Set<Record> _loading = {};

  final _hScrollController = ScrollController();

  /// Inline form view (`form` in `mode`).
  ViewDefinition? _formView;
  FormRoot? _formRoot;

  /// The inline form is shown (else the table).
  bool _formMode = false;

  /// Record of the inline form.
  Record? _current;

  /// Text typed in the inline form, written on focus loss.
  final Map<String, dynamic> _pending = {};

  /// Keyboard focus of the table (Enter opens the selected record).
  final _tableFocus = FocusNode();
  bool _loadingView = false;
  String? _error;

  String get _relModel => widget.fieldDef.relation ?? '';
  bool get _isMany2Many => widget.fieldDef.type == 'many2many';

  RecordGroup? get _group {
    final value = widget.parent.fieldGetClient(widget.fieldDef.name);
    return value is RecordGroup ? value : null;
  }

  @override
  void initState() {
    super.initState();
    _formMode = _mode.isNotEmpty && _mode.first == 'form';
    _loadView();
    _loadAccess();
  }

  /// Views of the widget (`mode`, default `tree,form`).
  List<String> get _mode => widget.node?.mode ?? const ['tree', 'form'];

  bool get _hasTree => _mode.contains('tree');
  bool get _hasForm => _mode.contains('form');

  /// View id of [type]: the `view_ids` entry at its position in `mode`.
  int? _viewIdFor(String type) {
    final i = _mode.indexOf(type);
    final ids = _viewIds;
    return i >= 0 && i < ids.length ? ids[i] : null;
  }

  /// Access rights of the relation if not known yet.
  Future<void> _loadAccess() async {
    final session = widget.parent.model.session;
    if (_relModel.isEmpty || session.accessOf?.call(_relModel) != null) return;
    try {
      await session.loadAccess?.call([_relModel]);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hScrollController.dispose();
    _tableFocus.dispose();
    super.dispose();
  }

  // ─── Loading ──────────────────────────────────────────────────────────────

  Future<void> _loadView() async {
    if (_relModel.isEmpty) return;
    setState(() {
      _loadingView = true;
      _error = null;
    });
    try {
      final svc = ref.read(modelServiceProvider);
      if (_formMode || !_hasTree) await _loadFormView();
      if (!_hasTree) return;
      final view = await _view(svc, _relModel, 'tree', _viewIdFor('tree'));
      final treeDef = TreeXmlParser().parse(
        view.arch,
        view.fields.map(
          (k, v) => MapEntry(k, <String, dynamic>{'string': v.label, 'type': v.type, 'selection': v.selection}),
        ),
      );
      if (!mounted) return;
      setState(() {
        _treeView = view;
        _treeDef = TreeViewDefinition(
          columns: treeDef.columns,
          fields: view.fields,
          editable: treeDef.editable,
          visual: treeDef.visual,
        );
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loadingView = false);
    }
  }

  /// Loads the inline form view (of `view_ids`, else the default form).
  Future<void> _loadFormView() async {
    if (_formView != null) return;
    final svc = ref.read(modelServiceProvider);
    final id = _viewIdFor('form');
    final preload = _field.description['views'];
    final view = id == null && preload is Map && preload['form'] is Map
        ? ViewDefinition.fromJson(
            Map<String, dynamic>.from(preload['form'] as Map))
        : await _view(svc, _relModel, 'form', id);
    final root = FormXmlParser().parse(view.arch, fields: view.rawFields);
    if (!mounted) return;
    setState(() {
      _formView = view;
      _formRoot = root;
    });
  }

  /// The fields of [view] in the child model (the group's model is new
  /// after each reload of the parent).
  void _ensureFields(RecordGroup group, ViewDefinition? view) {
    if (view == null) return;
    if (view.rawFields.keys.every(group.model.fields.containsKey)) return;
    group.model.addFields(view.rawFields);
  }

  /// Loads the row values of [record] (eager: the neighbours of the group
  /// come in the same `read`), without error dialog.
  void _ensureLoaded(Record record, String field) {
    if (record.isLoaded(field) || _loading.contains(record)) return;
    _loading.add(record);
    record
        .load(field, processException: false)
        .catchError((Object _) {})
        .whenComplete(() {
      _loading.remove(record);
      if (mounted) setState(() {});
    });
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on HandledRpcError {
      // shown by the form's error handler
    } catch (e) {
      if (mounted) await errorHandlerOf(context, ref).show(e);
    }
    if (mounted) setState(() {});
  }

  Field get _field => widget.parent.model.fields[widget.fieldDef.name]!;

  /// Attribute of the view, else of the field description.
  dynamic _attr(String name) =>
      widget.node?.attributes[name] ?? _field.description[name];

  bool _flag(String name) {
    final value = _attr(name);
    if (value == null) return true;
    if (value is bool) return value;
    return (int.tryParse('$value') ?? 1) != 0;
  }

  /// `add_remove` evaluated with the parent (null = not set).
  dynamic get _addRemove {
    final raw = _attr('add_remove');
    if (raw == null || raw == '' || raw == false) return null;
    final value = widget.parent.exprEval(raw);
    return value == null || value == false ? null : value;
  }

  /// Access rights of the relation (SAO `get_access` of the widget).
  ModelAccess get _access =>
      _group?.model.access ??
      TrytonModel(_relModel, session: widget.parent.model.session).access;

  bool get _canAdd =>
      (_isMany2Many || _addRemove != null) && _access.write && _access.read;
  bool get _canDelete =>
      !_isMany2Many && _flag('delete') && _access.delete;
  bool get _canRemove =>
      (_isMany2Many || _addRemove != null) && _access.write && _access.read;
  bool get _canCreate => _flag('create') && _access.create;
  bool get _canOpen => _access.read;

  /// `size` reached: New/Add disabled (spec 9.2.7).
  bool get _sizeLimitReached {
    final size = widget.parent.exprEval(_attr('size'));
    if (size is! num || size < 0) return false;
    return _field.getEval(widget.parent).length >= size;
  }

  /// Remaining records for "… and New" (−1 unlimited).
  int get _remaining {
    final size = widget.parent.exprEval(_attr('size'));
    if (size is! num || size < 0) return -1;
    return (size - _field.getEval(widget.parent).length).toInt();
  }

  List<int?> get _viewIds => [
        for (final part in '${_attr('view_ids') ?? ''}'.split(','))
          if (part.trim().isNotEmpty) int.tryParse(part.trim())
      ];

  /// Form view of the relation as preload (from the field description or
  /// the session-wide view cache).
  Future<Map<String, Map<String, dynamic>>> _formPreload() async {
    final views = _field.description['views'];
    if (views is Map && views['form'] is Map) {
      return {'form': Map<String, dynamic>.from(views['form'] as Map)};
    }
    final formId = _viewIdFor('form');
    if (formId != null) return const {};
    final view = await _view(ref.read(modelServiceProvider), _relModel, 'form');
    return {
      'form': {
        'type': view.type,
        'view_id': view.viewId,
        'arch': view.arch,
        'fields': view.rawFields,
        'field_childs': view.fieldChilds,
      }
    };
  }

  /// A form screen on the child group (popups stay in the group).
  Future<TrytonScreen> _childScreen(RecordGroup group) async {
    final formId = _viewIdFor('form');
    final screen = TrytonScreen.forGroup(
      ScreenAttributes(
        _relModel,
        mode: const ['form'],
        viewIds: formId == null ? const [] : [formId],
        viewsPreload: await _formPreload(),
        readonly: widget.parentReadOnly,
      ),
      group,
    );
    screen.onViewAdded = (v) => markUnsupportedFields(screen.model, v);
    return screen;
  }

  Future<void> _popupRun(Future<void> Function() action) async {
    if (_popup) return;
    _popup = true;
    try {
      await _run(action);
    } finally {
      _popup = false;
    }
  }

  /// Open: form popup on the record of the child group (spec 11.1).
  Future<void> _openRecord(Record record) => _popupRun(() async {
        final group = _group;
        if (group == null) return;
        final screen = await _childScreen(group);
        try {
          await screen.switchView();
          screen.currentRecord = record;
          if (!mounted) return;
          await showFormDialog(context, screen,
              x2many: true,
              removeOnDelete: _isMany2Many,
              title: widget.fieldDef.label,
              breadcrumb: widget.breadcrumb);
        } finally {
          screen.dispose();
        }
      });

  /// New: form popup with a new record in the child group ("Add and New"
  /// up to the `size` limit).
  Future<void> _newRecord() => _popupRun(() async {
        final group = _group;
        if (group == null || _sizeLimitReached) return;
        final screen = await _childScreen(group);
        try {
          if (!mounted) return;
          await showFormDialog(context, screen,
              newRecord: true,
              many: _remaining,
              x2many: true,
              removeOnDelete: _isMany2Many,
              title: widget.fieldDef.label,
              breadcrumb: widget.breadcrumb);
        } finally {
          screen.dispose();
        }
      });

  /// Add (many2many / `add_remove`): search dialog with multiple
  /// selection, domain `add_remove` AND field domain without the records
  /// already contained; the chosen records are loaded as added.
  Future<void> _addRecords() => _popupRun(() async {
        final group = _group;
        if (group == null || _sizeLimitReached) return;
        final parent = widget.parent;
        var domain = <dynamic>[_field.getDomain(parent)];
        final addRemove = _addRemove;
        if (addRemove is List && addRemove.isNotEmpty) domain.add(addRemove);
        final existing = [
          for (final id in _field.getEval(parent) as List)
            if (id is int && id >= 0) id
        ];
        if (existing.isNotEmpty) {
          domain = [
            domain,
            ['id', 'not in', existing]
          ];
        }
        final result = await showSearchDialog(
          context,
          model: _relModel,
          session: group.model.session,
          domain: domain,
          searchContext: _field.getSearchContext(parent),
          order: _asList(_field.description['order']),
          viewIds: [?_viewIdFor('tree')],
          multi: true,
          allowNew: _canCreate,
          title: widget.fieldDef.label,
          okLabel: context.l10n.add,
        );
        if (result.isEmpty) return;
        group.load([for (final r in result) r.id], modified: true);
      });

  static List<dynamic>? _asList(dynamic value) => value is List ? value : null;

  /// Delete (one2many) or remove the link – both only marked.
  void _markSelected({required bool remove}) {
    final group = _group;
    if (group == null) return;
    for (final r in _selected.toList()) {
      group.remove(r, remove: remove);
      if (!group.contains(r)) _selected.remove(r);
    }
    setState(() {});
  }

  void _unmarkSelected() {
    final group = _group;
    if (group == null) return;
    for (final r in _selected) {
      if (r.deleted || r.removed) group.unremove(r);
    }
    setState(() {});
  }

  /// Keys of the table (desktop, Python `One2Many.on_keypress`): Enter/F2
  /// open, F3 new, F4 switch, Delete deletes (with `add_remove` or for
  /// many2many: removes; Ctrl+Delete always deletes), Insert undeletes.
  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final hasSelection = _selected.isNotEmpty;
    final editable = !widget.readOnly;
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.f2) &&
        hasSelection &&
        _canOpen) {
      _openRecord(_selected.first);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f3 &&
        editable &&
        _canCreate &&
        !_sizeLimitReached) {
      _newRecord();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f4) {
      _switch();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete &&
        editable &&
        hasSelection) {
      final ctrl = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      final remove = _isMany2Many || (!ctrl && _addRemove != null);
      if (remove ? _canRemove : _canDelete) {
        _markSelected(remove: remove);
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.insert && editable && hasSelection) {
      _unmarkSelected();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ─── Inline form (mode with `form`) ──────────────────────────────────────

  /// Switch (spec 9.2.7, Python `screen.switch_view`): table ↔ inline
  /// form of the selected record. Without `form` in `mode` the selected
  /// record opens in the form popup.
  Future<void> _switch() async {
    final group = _group;
    if (group == null) return;
    if (_formMode) {
      await _flushInline();
      if (!_hasTree) return;
      final current = _current;
      setState(() {
        _formMode = false;
        _selected.clear();
        if (current != null && group.contains(current)) _selected.add(current);
      });
      return;
    }
    if (!_hasForm) {
      if (_selected.isNotEmpty) await _openRecord(_selected.first);
      return;
    }
    await _run(_loadFormView);
    if (!mounted || _formRoot == null) return;
    setState(() {
      _formMode = true;
      _current = _selected.isNotEmpty
          ? _selected.first
          : (group.isEmpty ? null : group.first);
    });
  }

  /// Writes the text typed in the inline form (before navigation).
  Future<void> _flushInline() async {
    final record = _current;
    final pending = Map<String, dynamic>.from(_pending);
    _pending.clear();
    if (record == null) return;
    for (final MapEntry(key: name, value: value) in pending.entries) {
      await _run(() => setRecordWidgetValue(record, name, value));
    }
  }

  void _write(String name, dynamic value) {
    final record = _current;
    if (record == null) return;
    _run(() => setRecordWidgetValue(record, name, value));
  }

  Future<void> _move(int delta) async {
    final group = _group;
    final current = _current;
    if (group == null || current == null) return;
    await _flushInline();
    final records = group.toList();
    final i = records.indexOf(current) + delta;
    if (i < 0 || i >= records.length) return;
    setState(() => _current = records[i]);
  }

  /// New in the inline form: a record with defaults added to the group
  /// (Python `screen.new()` in a form view).
  Future<void> _newInline() => _run(() async {
        final group = _group;
        if (group == null || _sizeLimitReached) return;
        await _flushInline();
        final record = await group.newRecordWithDefaults();
        group.add(record);
        _current = record;
      });

  /// Values of the inline record (all fields of the form view).
  final Set<Record> _formLoaded = {};
  void _ensureFormLoaded(Record record) {
    if (record.id < 0 || _formLoaded.contains(record)) return;
    _formLoaded.add(record);
    record.load('*', processException: false).catchError((Object _) {}).whenComplete(() {
      if (mounted) setState(() {});
    });
  }

  Widget _buildForm(RecordGroup group) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final records = group.toList();
    var current = _current;
    if (current == null || !group.contains(current)) {
      current = _current = records.isEmpty ? null : records.first;
    }
    final index = current == null ? -1 : records.indexOf(current);
    if (current != null) _ensureFormLoaded(current);
    final marked = current != null && (current.deleted || current.removed);
    final limitReached = _sizeLimitReached;
    Widget btn(IconData icon, String tip, VoidCallback? onPressed,
            {Key? key, Color? color}) =>
        _TBtn(key: key, icon: icon, tip: tip, onPressed: onPressed, color: color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              if (_hasTree)
                btn(Icons.compare_arrows, l.switchView, _switch,
                    key: const ValueKey('x2m-switch')),
              btn(Icons.chevron_left, l.previousRecord,
                  index > 0 ? () => _move(-1) : null,
                  key: const ValueKey('x2m-previous')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                    records.isEmpty ? '0 / 0' : '${index + 1} / ${records.length}',
                    key: const ValueKey('x2m-position'),
                    style: TextStyle(fontSize: 12, color: cs.outline)),
              ),
              btn(Icons.chevron_right, l.nextRecord,
                  index >= 0 && index < records.length - 1 ? () => _move(1) : null,
                  key: const ValueKey('x2m-next')),
              if (!widget.readOnly) ...[
                if (_canCreate)
                  btn(Icons.add, l.createNew, limitReached ? null : _newInline,
                      key: const ValueKey('x2m-new')),
                if (_canAdd)
                  btn(Icons.playlist_add, l.add, limitReached ? null : _addRecords,
                      key: const ValueKey('x2m-add')),
                if (current != null && marked)
                  btn(Icons.undo, l.undelete, () {
                    group.unremove(current!);
                    setState(() {});
                  }, color: Colors.green),
                if (current != null && !marked && _canRemove)
                  btn(Icons.link_off, l.remove, () {
                    group.remove(current!, remove: true);
                    setState(() {});
                  }, key: const ValueKey('x2m-remove'), color: cs.error),
                if (current != null && !marked && _canDelete)
                  btn(Icons.delete_outline, l.delete, () {
                    group.remove(current!, remove: false);
                    setState(() {});
                  }, key: const ValueKey('x2m-delete'), color: cs.error),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 4),
        if (current == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(l.noEntries,
                style: TextStyle(color: cs.outline, fontSize: 13)),
          )
        else ...[
          if (marked)
            Text(l.delete, style: TextStyle(color: cs.error, fontSize: 12)),
          RecordForm(
            key: ObjectKey(current),
            model: _relModel,
            root: _formRoot!,
            viewDef: _formView!,
            record: current,
            excludeField: widget.fieldDef.relationField,
            onTextChanged: (name, value) => _pending[name] = value,
            onBlur: (name) {
              if (_pending.containsKey(name)) _write(name, _pending.remove(name));
            },
            onChangedImmediate: _write,
            // fields by their own states (Python child screen)
            isReadOnly: widget.parentReadOnly || marked,
            breadcrumb: [...widget.breadcrumb, widget.fieldDef.label],
          ),
        ],
      ],
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loadingView) {
      return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_error != null) {
      return Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12));
    }
    final group = _group;
    if (group == null) return const SizedBox.shrink();
    if (_formMode && _formRoot != null) {
      _ensureFields(group, _formView);
      return _buildForm(group);
    }
    if (_treeDef == null) return const SizedBox.shrink();
    _ensureFields(group, _treeView);

    // The parent was reloaded: its group (and records) are new.
    _selected.removeWhere((r) => !group.contains(r));

    return _buildTable(group);
  }

  Widget _buildTable(RecordGroup group) {
    final l = context.l10n;
    final primary = Theme.of(context).colorScheme.primary;
    final errorColor = Theme.of(context).colorScheme.error;
    final records = group.toList();
    final columns = _treeDef!.columns
        .where((c) => !c.treeInvisible && !c.isButton)
        .toList();
    final hasSelection = _selected.isNotEmpty;
    bool isMarked(Record r) => r.deleted || r.removed;
    final selectedAreMarked = hasSelection && _selected.every(isMarked);
    final selectedHaveMarked = _selected.any(isMarked);
    final markedCount = group.recordDeleted.length + group.recordRemoved.length;
    final limitReached = _sizeLimitReached;
    final touch = isTouchPlatform(context);
    // Row values: one eager load reads the neighbours too.
    if (columns.isNotEmpty) {
      for (final r in records) {
        if (r.id >= 0 && !r.isLoaded(columns.first.name)) {
          _ensureLoaded(r, columns.first.name);
          break;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Toolbar ───────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              // ── Buttons (scrollable so narrow layouts don't overflow) ─────
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      IconButton(
                        icon: TrytonIcon(
                          iconName: 'tryton-switch',
                          size: 16,
                          color: hasSelection ? primary : Theme.of(context).disabledColor,
                          fallback: Icons.compare_arrows,
                        ),
                        tooltip: l.openInForm,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: (_hasForm ? records.isNotEmpty : hasSelection) && _canOpen
                            ? _switch
                            : null,
                      ),
                      if (!widget.readOnly) ...[
                        if (_canCreate)
                          _TBtn(
                            key: const ValueKey('x2m-new'),
                            icon: Icons.add,
                            tip: l.createNew,
                            onPressed: limitReached ? null : _newRecord,
                          ),
                        if (_canAdd)
                          _TBtn(
                            key: const ValueKey('x2m-add'),
                            icon: Icons.playlist_add,
                            tip: l.add,
                            onPressed: limitReached ? null : _addRecords,
                          ),
                        _TBtn(
                          icon: Icons.undo,
                          tip: l.undelete,
                          color: selectedHaveMarked ? Colors.green : null,
                          onPressed: selectedHaveMarked ? _unmarkSelected : null,
                        ),
                        if (_canRemove)
                          _TBtn(
                            key: const ValueKey('x2m-remove'),
                            icon: Icons.link_off,
                            tip: l.remove,
                            color: hasSelection && !selectedAreMarked ? errorColor : null,
                            onPressed: hasSelection && !selectedAreMarked
                                ? () => _markSelected(remove: true)
                                : null,
                          ),
                        if (_canDelete)
                          _TBtn(
                            key: const ValueKey('x2m-delete'),
                            icon: Icons.delete_outline,
                            tip: l.delete,
                            color: hasSelection && !selectedAreMarked ? errorColor : null,
                            onPressed: hasSelection && !selectedAreMarked
                                ? () => _markSelected(remove: false)
                                : null,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              // ── Counts (pinned right) ─────────────────────────────────────
              if (markedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text('$markedCount ×', style: TextStyle(fontSize: 11, color: errorColor)),
                ),
              if (records.isNotEmpty)
                Text('${records.length}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // ── Table ─────────────────────────────────────────────────────────
        if (records.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(l.noEntries, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13)),
          )
        else
          Focus(
            focusNode: _tableFocus,
            onKeyEvent: (node, event) => _onKey(event),
            child: Scrollbar(
            controller: _hScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _hScrollController,
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 12,
                headingRowHeight: 34,
                dataRowMinHeight: 30,
                dataRowMaxHeight: 44,
                headingRowColor: WidgetStateProperty.all(
                  Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(120),
                ),
                columns: [
                  DataColumn(
                    label: Checkbox(
                      tristate: true,
                      value: _selected.length == records.length
                          ? true
                          : _selected.isEmpty
                          ? false
                          : null,
                      onChanged: (_) {
                        setState(() {
                          if (_selected.length == records.length) {
                            _selected.clear();
                          } else {
                            _selected.addAll(records);
                          }
                        });
                      },
                    ),
                  ),
                  ...columns.map(
                    (c) => DataColumn(
                      label: Text(c.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ),
                ],
                rows: records.map((record) {
                  final isSelected = _selected.contains(record);
                  final isDeleted = isMarked(record);
                  final visual = recordVisual(record, _treeDef?.visual);

                  return DataRow(
                    selected: isSelected,
                    color: WidgetStateProperty.resolveWith((states) {
                      if (isDeleted) return errorColor.withAlpha(20);
                      if (states.contains(WidgetState.selected)) return primary.withAlpha(40);
                      switch (visual) {
                        case 'success':
                          return Colors.green.withAlpha(30);
                        case 'warning':
                          return Colors.orange.withAlpha(40);
                        case 'danger':
                          return errorColor.withAlpha(40);
                        default:
                          return null;
                      }
                    }),
                    cells: [
                      DataCell(
                        Checkbox(
                          value: isSelected,
                          onChanged: (_) {
                            setState(() {
                              if (isSelected) {
                                _selected.remove(record);
                              } else {
                                _selected.add(record);
                              }
                            });
                          },
                        ),
                      ),
                      ...columns.map((col) {
                        final fd = _treeDef!.fields[col.name];
                        final cellStyle = TextStyle(
                          fontSize: 12,
                          decoration: isDeleted ? TextDecoration.lineThrough : null,
                          decorationColor: isDeleted ? errorColor : null,
                          color: isDeleted ? errorColor.withAlpha(160) : null,
                        );
                        return DataCell(
                          isNumericField(fd)
                              ? RecordNumericCell.of(record, col.name, fd!, style: cellStyle)
                              : RecordTextCell(record, col.name, fd, style: cellStyle),
                          // SAO: a click selects, a double click opens;
                          // touch: tapping opens, a long press selects.
                          onTap: touch
                              ? (isDeleted || !_canOpen ? null : () => _openRecord(record))
                              : () {
                                  _tableFocus.requestFocus();
                                  setState(() => _selected
                                    ..clear()
                                    ..add(record));
                                },
                          onDoubleTap: touch || isDeleted || !_canOpen
                              ? null
                              : () => _openRecord(record),
                          onLongPress: touch
                              ? () => setState(() {
                                    if (!_selected.remove(record)) _selected.add(record);
                                  })
                              : null,
                        );
                      }),
                    ],
                  );
                }).toList()
                  // sum="1" columns: „selected / all“ (spec 9.3.4)
                  ..addAll([
                    if (columns.any((c) => c.sum))
                      DataRow(
                        key: const ValueKey('x2m-sum-row'),
                        color: WidgetStateProperty.all(Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withAlpha(120)),
                        cells: [
                          const DataCell(SizedBox.shrink()),
                          for (final c in columns)
                            DataCell(c.sum
                                ? Text(
                                    recordSumText(group, c.name, _selected,
                                        locale: Localizations.localeOf(context)
                                            .toLanguageTag(),
                                        numberLocale:
                                            ref.watch(numberLocaleProvider)),
                                    key: ValueKey('x2m-sum-${c.key}'),
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(
                                        fontSize: 11, fontWeight: FontWeight.w600))
                                : const SizedBox.shrink()),
                        ],
                      ),
                  ]),
              ),
            ),
          ), // Scrollbar
          ), // Focus
      ],
    );
  }

}

// ─── Compact toolbar button ───────────────────────────────────────────────────

class _TBtn extends StatelessWidget {
  final IconData icon;
  final String tip;
  final Color? color;
  final VoidCallback? onPressed;
  const _TBtn({super.key, required this.icon, required this.tip, this.color, this.onPressed});

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon, size: 16, color: color),
    tooltip: tip,
    onPressed: onPressed,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
  );
}
