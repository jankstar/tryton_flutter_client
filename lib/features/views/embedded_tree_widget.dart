import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart' hide TextField;
import '../../core/rpc/error_processing.dart';
import '../../core/screen/screen.dart';
import '../../core/xml/form_xml_parser.dart';
import '../../core/xml/view_definition.dart';
import '../../shared/errors/error_dialogs.dart';
import '../model/field_definition.dart';
import '../model/field_support.dart';
import '../model/model_service.dart';
import 'fill_column.dart';
import 'form_dialog.dart';
import 'record_form.dart';
import 'record_widget_values.dart';
import 'search_dialog.dart';
import 'tree_view.dart';
import 'wizard_widget.dart' show wizardInvalidTexts;
import '../../shared/dialogs/tryton_dialogs.dart';

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
  ViewDefinition? _treeView;

  /// Screen of the table on the child group with the tree view (the
  /// table is a [TreeView] like the main list, spec 9.2.7).
  TrytonScreen? _treeScreen;
  ScreenView? _treeScreenView;
  final _table = TreeViewController();

  /// The selected records of the table.
  List<Record> get _selected => _treeScreen?.selectedRecords ?? const [];

  /// A popup is open.
  bool _popup = false;


  /// Inline form view (`form` in `mode`).
  ViewDefinition? _formView;
  FormRoot? _formRoot;

  /// The inline form is shown (else the table).
  bool _formMode = false;

  /// Record of the inline form.
  Record? _current;

  /// Text typed in the inline form, written on focus loss.
  final Map<String, dynamic> _pending = {};

  bool _loadingView = false;
  String? _error;

  String get _relModel => widget.fieldDef.relation ?? '';
  /// The many2many widget (Python chooses the widget, not the field type:
  /// a many2many shown with `widget="one2many"` – e.g. the bank accounts
  /// of a party – gets New/Edit/Delete/Undelete like a one2many).
  bool get _isMany2Many =>
      (widget.node?.widget ?? widget.fieldDef.type) == 'many2many';

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
    _treeScreen?.dispose();
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
      if (!mounted) return;
      setState(() => _treeView = view);
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
  /// after each reload of the parent), marked as fields of the view: a
  /// record loads with `load('*')` only the fields of its views (Python
  /// `screen.add_view`), e.g. the function fields of the inline form.
  void _ensureFields(RecordGroup group, ViewDefinition? view) {
    if (view == null) return;
    final key = view.viewId ?? view.type;
    final fields = group.model.fields;
    if (view.rawFields.keys
        .every((name) => fields[name]?.views.contains(key) ?? false)) {
      return;
    }
    group.model.addFields(view.rawFields);
    for (final name in view.rawFields.keys) {
      fields[name]!.views.add(key);
    }
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

  bool get _canDelete =>
      !_isMany2Many && _flag('delete') && _access.delete;
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
    screen
      ..onViewAdded = ((v) => markUnsupportedFields(screen.model, v))
      ..preValidate = _preValidate;
    return screen;
  }

  /// `pre_validate` of the field (Python `screen.pre_validate`).
  bool get _preValidate {
    final value = _attr('pre_validate');
    return value == true || (int.tryParse('$value') ?? 0) != 0;
  }

  /// The record of the inline form is valid (Python `One2Many._validate`:
  /// the fields of the view, with `pre_validate` the server's check).
  Future<bool> _validateInline() async {
    final record = _current;
    if (record == null || record.destroyed) return true;
    final view = _formView;
    if (!record.validate(fields: view?.rawFields.keys)) {
      setState(() {});
      if (mounted) {
        await showWarning(
            context, record.invalidMessage(wizardInvalidTexts(context)));
      }
      return false;
    }
    if (!_preValidate) return true;
    try {
      await record.preValidate();
      return true;
    } on HandledRpcError {
      return false;
    } catch (e) {
      if (mounted) await errorHandlerOf(context, ref).show(e);
      return false;
    }
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

  /// New: in an editable table a new row (spec 9.2.7), else the form
  /// popup with a new record in the child group ("Add and New" up to the
  /// `size` limit).
  Future<void> _newRecord([Map<String, dynamic>? defaults]) =>
      _popupRun(() async {
        final group = _group;
        if (group == null || _sizeLimitReached) return;
        // add_remove: the text of the search entry (Python `_sig_new`)
        final text = _addText?.text.trim() ?? '';
        if (_addRemove != null && text.isNotEmpty) {
          defaults = {...?defaults, 'rec_name': text};
          _addText?.clear();
        }
        // `product`: a record per combination (Python `_new_product`)
        if (_attr('product') case final String product
            when product.trim().isNotEmpty) {
          await _newProduct(product, defaults);
          return;
        }
        final tree = _treeScreen;
        if (!_formMode && tree != null && _table.editable) {
          if (!await _table.leaveRow(null)) return;
          final record = await group.newRecordWithDefaults(defaults: defaults);
          group.add(record, position: tree.newPosition);
          if (mounted) _table.edit(record);
          return;
        }
        final screen = await _childScreen(group);
        try {
          if (!mounted) return;
          await showFormDialog(context, screen,
              newRecord: true,
              defaults: defaults,
              many: _remaining,
              x2many: true,
              removeOnDelete: _isMany2Many,
              title: widget.fieldDef.label,
              breadcrumb: widget.breadcrumb);
        } finally {
          screen.dispose();
        }
      });

  /// `product="f1,f2"` (Python `One2Many._new_product`): one search dialog
  /// per field (multiple choice, from the last field on) with the field's
  /// domain, context and order on a record with the defaults; then one new
  /// record per combination of the chosen values, all with the same
  /// defaults; `sequence` renumbers them.
  Future<void> _newProduct(String product, Map<String, dynamic>? defaults) async {
    final group = _group;
    if (group == null) return;
    final names = [
      for (final n in product.split(',')) if (n.trim().isNotEmpty) n.trim()
    ];
    // (the first record is not added: only its domains and defaults count)
    final first = group.newRecord();
    final values = await first.defaultGet(defaults);
    final chosen = <String, List<SearchResult>>{};
    for (final name in names.reversed) {
      final field = group.model.fields[name];
      final relation = field?.description['relation'];
      if (field == null || relation is! String || !mounted) continue;
      final result = await showSearchDialog(
        context,
        model: relation,
        session: group.model.session,
        domain: field.getDomain(first),
        searchContext: field.getSearchContext(first),
        order: _asList(field.getSearchOrder(first)),
        multi: true,
        title: widget.fieldDef.label,
      );
      if (result.isNotEmpty) chosen[name] = result;
    }
    if (chosen.isEmpty) return;
    var combinations = <Map<String, dynamic>>[{}];
    for (final MapEntry(key: name, value: results) in chosen.entries) {
      combinations = [
        for (final c in combinations)
          for (final r in results)
            {
              ...c,
              name: r.id,
              '$name.': {'rec_name': r.name},
            }
      ];
    }
    for (final combination in combinations) {
      final record = group.newRecord();
      group.add(record);
      await record.setDefault({...values, ...combination});
    }
    final sequence = _treeScreen?.currentView?.attributes['sequence'];
    if (sequence != null && sequence.isNotEmpty) {
      await group.setSequence(
          field: sequence, position: _treeScreen?.newPosition ?? -1);
    }
  }

  /// Domain of „Add“: `add_remove` AND field domain without the records
  /// already contained.
  List<dynamic> get _addDomain {
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
    return domain;
  }

  /// Add (many2many / `add_remove`): search dialog with multiple
  /// selection on [_addDomain] (with the [text] of the entry); the chosen
  /// records are loaded as added.
  Future<void> _addRecords([String text = '']) => _popupRun(() async {
        final group = _group;
        if (group == null || _sizeLimitReached) return;
        final result = await showSearchDialog(
          context,
          model: _relModel,
          session: group.model.session,
          domain: _addDomain,
          searchContext: _field.getSearchContext(widget.parent),
          // Python `get_search_order` (the field's `order` sorts the
          // relation table of a many2many, e.g. `account.owners_sequence`)
          order: _asList(_field.getSearchOrder(widget.parent)),
          viewIds: [?_viewIdFor('tree')],
          multi: true,
          allowNew: _canCreate,
          searchText: text.isEmpty ? null : text,
          title: widget.fieldDef.label,
          okLabel: context.l10n.add,
        );
        _addText?.clear();
        if (result.isEmpty) return;
        group.load([for (final r in result) r.id], modified: true);
      });

  /// Text of the `add_remove` entry (set by its Autocomplete).
  TextEditingController? _addText;

  /// Completion of the `add_remove` entry (Python `update_completion`):
  /// `autocomplete(text, domain, limit, order)` of the relation.
  Future<Iterable<Map<String, dynamic>>> _completeAdd(String text) async {
    final group = _group;
    if (group == null || text.isEmpty) return const [];
    try {
      final result = await group.model.execute('autocomplete', [
        text,
        _addDomain,
        group.model.session.limit,
        _field.getSearchOrder(widget.parent),
      ], context: _field.getSearchContext(widget.parent), processException: false);
      // Many2Many: also the „Create …“ entries (id null) with create
      // right (Python `get_completion(create=…)`)
      final create = _isMany2Many && _canCreate;
      return [
        for (final v in result as List? ?? const [])
          if (v is Map && (v['id'] is int || create)) Map<String, dynamic>.from(v)
      ];
    } catch (_) {
      return const [];
    }
  }

  /// The search entry (spec 9.2.7; one2many with `add_remove`, always for
  /// many2many): completion → the record is added (a „Create …“ entry
  /// opens a new record with its defaults); Enter → the search dialog
  /// with the text. Active like „Add“.
  Widget _buildAddEntry({required bool enabled, double width = 180}) => SizedBox(
        width: width,
        height: 32,
        child: Autocomplete<Map<String, dynamic>>(
          displayStringForOption: (o) => '${o['name'] ?? ''}',
          optionsBuilder: (value) =>
              enabled ? _completeAdd(value.text) : const <Map<String, dynamic>>[],
          onSelected: (o) {
            final group = _group;
            if (group == null || _sizeLimitReached) return;
            _addText?.clear();
            final id = o['id'];
            if (id is int) {
              group.load([id], modified: true);
              setState(() {});
            } else {
              final defaults = o['defaults'];
              _newRecord(defaults is Map ? defaults.cast<String, dynamic>() : null);
            }
          },
          fieldViewBuilder: (context, controller, focus, _) {
            _addText = controller;
            return TextField(
              key: const ValueKey('x2m-add-entry'),
              controller: controller,
              focusNode: focus,
              enabled: enabled,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: context.l10n.search,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (text) {
                if (text.trim().isNotEmpty) _addRecords(text.trim());
              },
            );
          },
        ),
      );

  static List<dynamic>? _asList(dynamic value) => value is List ? value : null;

  /// The records the buttons act on: the record of the inline form,
  /// else the selection of the table.
  List<Record> get _actionRecords => _formMode ? [?_current] : _selected;

  /// Delete (one2many) or remove the link – both only marked.
  void _markSelected({required bool remove}) {
    final group = _group;
    if (group == null) return;
    final records = _actionRecords.toList();
    for (final r in records) {
      group.remove(r, remove: remove);
    }
    if (!_formMode) {
      _table.select([for (final r in records) if (group.contains(r)) r]);
    }
    setState(() {});
  }

  void _unmarkSelected() {
    final group = _group;
    if (group == null) return;
    for (final r in _actionRecords) {
      if (r.deleted || r.removed) group.unremove(r);
    }
    setState(() {});
  }

  // ─── Toolbar (spec 9.2.7 „Kopfzeile im Detail“) ──────────────────────────

  /// Readonly (spec 9.2.7): the field (static or `states`), the parent
  /// record or a revision; switch, navigation and Edit (view only) stay.
  bool get _readonly =>
      widget.readOnly ||
      widget.parentReadOnly ||
      widget.parent.group.rootGroup.revision != null;

  /// Records in the shown order (table) or the group's (inline form).
  List<Record> get _navRecords {
    final rows = _table.rows;
    if (_formMode || rows.isEmpty) return _group?.toList() ?? const [];
    return [for (final r in rows) if (r.depth == 0) r.record];
  }

  /// Position of the current record (1-based; null without, Python
  /// `record_message`).
  int? get _position {
    final record = _formMode ? _current : _selected.firstOrNull;
    if (record == null) return null;
    final i = _navRecords.indexOf(record);
    return i < 0 ? null : i + 1;
  }

  /// Activation of the buttons (Python `_set_button_sensitive` of
  /// `One2Many` / `Many2Many`).
  ({
    bool switchView,
    bool previous,
    bool next,
    bool add,
    bool remove,
    bool create,
    bool open,
    bool delete,
    bool undelete,
  }) get _enabled {
    final readonly = _readonly;
    final limit = _sizeLimitReached;
    final position = _position;
    final length = _navRecords.length;
    final records = _actionRecords;
    final removable = records.any((r) => !r.deleted && !r.removed);
    final unremovable = records.any((r) => r.deleted || r.removed);
    if (_isMany2Many) {
      return (
        switchView: false,
        previous: false,
        next: false,
        add: !readonly && !limit,
        remove: !readonly && removable && position != null,
        create: !readonly && _canCreate && !limit,
        open: position != null && _canOpen,
        delete: false,
        undelete: !readonly && !limit && unremovable && position != null,
      );
    }
    final rights = _access.write && _access.read;
    return (
      switchView: (position != null || _formMode) && _hasTree && _hasForm,
      previous: length > 0 && (position == null || position > 1),
      next: length > 0 && (position == null || position < length),
      add: !readonly && !limit && rights,
      remove: !readonly && position != null && rights,
      create: !readonly && _canCreate && !limit,
      open: position != null && _canOpen && _hasForm,
      delete: !readonly &&
          _canDelete &&
          removable &&
          records.every((r) => r.deletable) &&
          position != null,
      undelete: !readonly && !limit && unremovable && position != null,
    );
  }

  /// Previous/next record (Python `screen.display_prev/next`): in the
  /// inline form the shown record, in the table the selection follows.
  Future<void> _navigate(int delta) async {
    if (_formMode) {
      if (_current == null) {
        final records = _navRecords;
        if (records.isNotEmpty) {
          setState(() => _current = delta > 0 ? records.first : records.last);
        }
        return;
      }
      await _move(delta);
      return;
    }
    final records = _navRecords;
    if (records.isEmpty) return;
    final position = _position;
    final index = position == null
        ? (delta > 0 ? 0 : records.length - 1)
        : (position - 1 + delta).clamp(0, records.length - 1);
    final target = records[index];
    if (!await _table.leaveRow(target) || !mounted) return;
    _table.select([target]);
  }

  /// The header of the widget (Python `One2Many`/`Many2Many`): all
  /// buttons always shown, disabled when not allowed; on narrow screens
  /// the rare ones (switch, add, remove, undelete) in a „More“ menu.
  Widget _buildToolbar(RecordGroup group) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final enabled = _enabled;
    final records = _actionRecords;
    final position = _position;
    final selected = records.length;
    final positionText =
        '${position ?? '_'}${selected > 1 ? '#$selected' : ''}/${_navRecords.length}';
    final first = records.firstOrNull;
    final searchEntry = _isMany2Many || _addRemove != null;

    // (key, icon, tooltip, action, rare)
    final items = <(String, IconData, String, VoidCallback?, bool)>[
      if (!_isMany2Many) ...[
        ('switch', Icons.compare_arrows, l.x2mSwitch,
            enabled.switchView ? _switch : null, true),
        ('previous', Icons.chevron_left, l.x2mPrevious,
            enabled.previous ? () => _navigate(-1) : null, false),
        ('position', Icons.tag, positionText, null, false),
        ('next', Icons.chevron_right, l.x2mNext,
            enabled.next ? () => _navigate(1) : null, false),
      ],
      if (searchEntry) ...[
        ('add', Icons.playlist_add, l.x2mAdd,
            enabled.add ? _addRecords : null, true),
        if (_isMany2Many) ('position', Icons.tag, positionText, null, false),
        ('remove', Icons.link_off, l.x2mRemove,
            enabled.remove ? () => _markSelected(remove: true) : null, true),
      ],
      if (!_isMany2Many) ...[
        ('new', Icons.add, l.x2mCreate,
            enabled.create ? (_formMode ? _newInline : _newRecord) : null, false),
        ('open', Icons.edit_outlined, l.x2mEdit,
            enabled.open && first != null ? () => _openRecord(first) : null, false),
        ('delete', Icons.delete_outline, l.x2mDelete,
            enabled.delete ? () => _markSelected(remove: false) : null, false),
      ],
      ('undelete', Icons.restore_from_trash_outlined,
          _isMany2Many ? l.x2mRestore : l.x2mUndelete,
          enabled.undelete ? _unmarkSelected : null, true),
    ];

    Widget button((String, IconData, String, VoidCallback?, bool) item) {
      final (name, icon, tip, onPressed, _) = item;
      if (name == 'position') {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(tip,
              key: const ValueKey('x2m-position'),
              style: TextStyle(fontSize: 12, color: cs.outline)),
        );
      }
      final color = onPressed == null
          ? null
          : switch (name) {
              'delete' || 'remove' => cs.error,
              'undelete' => Colors.green.shade700,
              _ => null,
            };
      return _TBtn(
          key: ValueKey('x2m-$name'),
          icon: icon,
          tip: tip,
          color: color,
          onPressed: onPressed);
    }

    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 560;
      final shown = [for (final i in items) if (!narrow || !i.$5) i];
      final more = [for (final i in items) if (narrow && i.$5) i];
      return Container(
        key: const ValueKey('x2m-toolbar'),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          // the title (Python: label of the field)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(widget.fieldDef.label,
                  key: const ValueKey('x2m-title'),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: cs.primary,
                      )),
            ),
          ),
          // the controls never overflow (scroll on very narrow screens)
          Flexible(
            flex: 4,
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (searchEntry)
                    _buildAddEntry(enabled: enabled.add, width: narrow ? 120 : 180),
                  for (final item in shown) button(item),
                ]),
              ),
            ),
          ),
          if (more.isNotEmpty)
            PopupMenuButton<VoidCallback>(
              key: const ValueKey('x2m-more'),
              icon: const Icon(Icons.more_vert, size: 16),
              tooltip: l.x2mMore,
              padding: EdgeInsets.zero,
              onSelected: (action) => action(),
              itemBuilder: (_) => [
                for (final (name, icon, tip, onPressed, _) in more)
                  PopupMenuItem<VoidCallback>(
                    key: ValueKey('x2m-more-$name'),
                    value: onPressed,
                    enabled: onPressed != null,
                    child: ListTile(
                      dense: true,
                      leading: Icon(icon, size: 18),
                      title: Text(tip),
                    ),
                  ),
              ],
            ),
        ]),
      );
    });
  }

  /// Keys of the table (desktop, Python `One2Many.on_keypress`): Enter/F2
  /// open, F3 new, F4 switch, Delete deletes (with `add_remove` or for
  /// many2many: removes; Ctrl+Delete always deletes), Insert undeletes.
  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final enabled = _enabled;
    final first = _actionRecords.firstOrNull;
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.f2) &&
        first != null &&
        _canOpen) {
      _openRecord(first);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f3 && enabled.create) {
      _newRecord();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f4 && enabled.switchView) {
      _switch();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      final ctrl = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      final remove = _isMany2Many || (!ctrl && _addRemove != null);
      if (remove ? enabled.remove : enabled.delete) {
        _markSelected(remove: remove);
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.insert && enabled.undelete) {
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
      if (!_hasTree || !await _validateInline()) return;
      final current = _current;
      setState(() {
        _formMode = false;
        // the table shows the record of the form selected
        final screen = _treeScreen;
        if (screen != null) {
          screen.selectedRecords =
              current != null && group.contains(current) ? [current] : const [];
        }
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
    if (!await _validateInline()) return;
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
        if (!await _validateInline()) return;
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
    if (current != null) _ensureFormLoaded(current);
    final marked = current != null && (current.deleted || current.removed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(group),
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
    final view = _treeView;
    if (view == null) return const SizedBox.shrink();
    _ensureFields(group, view);
    return _buildTable(group, _screenFor(group, view));
  }

  /// The table's screen on [group]; a new one when the parent was
  /// reloaded (its group and records are new).
  TrytonScreen _screenFor(RecordGroup group, ViewDefinition view) {
    final current = _treeScreen;
    if (current != null && identical(current.group, group)) return current;
    final screen = TrytonScreen.forGroup(
      ScreenAttributes(
        _relModel,
        mode: const ['tree'],
        viewIds: [?_viewIdFor('tree')],
        readonly: widget.parentReadOnly,
        excludeField: widget.fieldDef.relationField,
      ),
      group,
    );
    screen
      ..onViewAdded = ((v) => markUnsupportedFields(screen.model, v))
      ..invalidTexts = (() => wizardInvalidTexts(context))
      ..preValidate = _preValidate;
    _treeScreenView = screen.currentView = screen.addView(view);
    if (current != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
    }
    return _treeScreen = screen;
  }

  Widget _buildTable(RecordGroup group, TrytonScreen screen) {
    final l = context.l10n;
    final records = group.toList();
    bool isMarked(Record r) => r.deleted || r.removed;
    final height = widget.node?.height;

    // the table takes the height given to the field (yexpand, 9.2.2)
    return FillColumn(
      children: [
        _buildToolbar(group),
        const SizedBox(height: 4),

        // ── Table: the tree view of the child screen (spec 9.3) ──────────
        if (records.isEmpty && !_editableTree)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(l.noEntries, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13)),
          )
        else
          FillChild(child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (node, event) => _onKey(event),
            child: TreeView(
              screen: screen,
              view: _treeScreenView!,
              controller: _table,
              keyPrefix: 'x2m',
              shrinkWrap: true,
              maxHeight: height != null && height > 0 ? height.toDouble() : null,
              onActivate: (record) {
                if (!isMarked(record) && _canOpen) _openRecord(record);
              },
              onSelectionChanged: () => setState(() {}),
            ),
          )),
      ],
    );
  }

  /// The tree view is editable (`editable`, parent not readonly).
  bool get _editableTree => _treeScreenView?.editable ?? false;
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
