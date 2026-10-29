import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart' hide TextField;
import '../../core/rpc/error_processing.dart';
import '../../core/screen/screen.dart';
import '../../core/xml/view_definition.dart';
import '../../l10n/app_localizations.dart';
import '../model/field_definition.dart';
import '../model/field_support.dart';
import '../model/model_service.dart';
import '../shell/tab_manager.dart';
import 'form_dialog.dart';
import 'search_dialog.dart';

/// Many2One / One2One / Reference widget on the data layer (spec 9.2.6,
/// SAO `Sao.View.Form.Many2One`):
///
/// * typing runs `model.<rel>.autocomplete(text, domain, limit, order)`
///   with the field's domain, search context and search order; entries
///   with `id = null` create a record („"…" anlegen…“, only with create
///   right); the list ends with "Search…" and "Create…";
/// * text changed without choice → on focus loss/Enter the search dialog
///   with the text (one hit is taken directly); cancel clears the text;
/// * buttons: Open (form popup, then rec_name read again; Ctrl/Cmd+click
///   opens a tab) and Clear, without value Search;
/// * keys: F2 open/search, F3 new with `rec_name` = text;
/// * attributes: `create`, `completion="0"`, `view_ids` (the first tree
///   view is dropped for the form), `views` as preload,
///   `relation_field` as `exclude_field`.
///
/// Reference fields get a model selection in front.
class RecordMany2One extends ConsumerStatefulWidget {
  final Record record;
  final FieldNode node;
  final FieldDefinition fieldDef;
  final bool readOnly;
  final bool required;
  final bool invalid;

  /// Sets the value (`[id, rec_name]`, reference `[model, [id, name]]`, or
  /// null) through the owner (`setClient`).
  final void Function(dynamic value) onChanged;

  /// Breadcrumb of the popups (e.g. the form title).
  final List<String> breadcrumb;

  const RecordMany2One({
    super.key,
    required this.record,
    required this.node,
    required this.fieldDef,
    required this.readOnly,
    required this.onChanged,
    this.required = false,
    this.invalid = false,
    this.breadcrumb = const [],
  });

  @override
  ConsumerState<RecordMany2One> createState() => _RecordMany2OneState();
}

class _RecordMany2OneState extends ConsumerState<RecordMany2One> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  /// Autocomplete entries `{id, name, defaults}`.
  List<Map<String, dynamic>> _completion = const [];
  bool _showCompletion = false;

  /// The text differs from the value (typed, not yet chosen).
  bool _typed = false;

  /// A popup is open (no second one, no activation on focus loss).
  bool _popup = false;

  /// Models of a reference field (`[value, label]`).
  List<List<dynamic>>? _models;

  Record get _record => widget.record;
  String get _name => widget.node.name;
  Field get _field => _record.model.fields[_name]!;
  bool get _isReference => widget.fieldDef.type == 'reference';

  /// Attribute of the view, else of the field description (SAO
  /// `field_attrs`).
  dynamic _attr(String name) =>
      widget.node.attributes[name] ?? _field.description[name];

  bool _flag(String name, {bool defaultValue = true}) {
    final value = _attr(name);
    if (value == null) return defaultValue;
    if (value is bool) return value;
    return (int.tryParse('$value') ?? 1) != 0;
  }

  bool get _completionEnabled => _flag('completion');

  /// `create` attribute and create right of the relation.
  bool get _createAccess =>
      _flag('create') && (_relationModel?.access.create ?? false);

  bool get _readAccess => _relationModel?.access.read ?? false;

  // ── Value ─────────────────────────────────────────────────────────────────

  /// Relation model (reference: the chosen model).
  String? get _relation {
    if (_isReference) {
      final value = _record.values[_name];
      final model = value is List && value.isNotEmpty ? value[0] : null;
      return model is String && model.isNotEmpty ? model : null;
    }
    return widget.fieldDef.relation;
  }

  TrytonModel? get _relationModel {
    final relation = _relation;
    return relation == null
        ? null
        : TrytonModel(relation, session: _record.model.session);
  }

  /// Id of the value (null = none).
  int? get _id {
    if (_isReference) {
      final value = _record.values[_name];
      final id = value is List && value.length > 1 ? value[1] : null;
      return id is int && id >= 0 ? id : null;
    }
    final id = _field.get(_record);
    return id is int ? id : null;
  }

  bool get _hasTarget => _id != null;

  String get _recName {
    final client = _field.getClient(_record);
    if (_isReference) {
      return client is List && client.length > 1 ? '${client[1]}' : '';
    }
    return '${client ?? ''}';
  }

  /// Value for [onChanged] from [id]/[name].
  dynamic _valueOf(int? id, String name) {
    if (_isReference) {
      final model = _relation;
      if (model == null) return null;
      return [model, id == null ? null : [id, name]];
    }
    return id == null ? null : [id, name];
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _ctrl.text = _recName;
    _focus.addListener(_onFocus);
    if (_isReference) _loadModels();
  }

  @override
  void didUpdateWidget(RecordMany2One old) {
    super.didUpdateWidget(old);
    if (!_typed && _ctrl.text != _recName) _ctrl.text = _recName;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus) return;
    // Delay so a tap on a completion entry fires first.
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted || _focus.hasFocus) return;
      setState(() => _showCompletion = false);
      if (_typed && !_popup) _activate();
    });
  }

  Future<void> _loadModels() async {
    var options = widget.fieldDef.selection;
    final method = widget.fieldDef.selectionFunction;
    if (options == null && method != null) {
      try {
        options = await ref
            .read(modelServiceProvider)
            .getSelectionOptions(_record.model.name, method);
      } catch (_) {
        options = const [];
      }
    }
    if (mounted) setState(() => _models = options ?? const []);
  }

  // ── Completion ────────────────────────────────────────────────────────────

  void _onTyped(String text) {
    _typed = true;
    // Typing over a chosen value removes it (SAO key_press).
    if (_hasTarget && text != _recName) widget.onChanged(_valueOf(null, ''));
    _debounce?.cancel();
    if (!_completionEnabled || text.isEmpty) {
      setState(() => _showCompletion = false);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _complete(text));
  }

  /// `autocomplete(text, domain, limit, order)` with the search context
  /// (SAO `update_completion`).
  Future<void> _complete(String text) async {
    final model = _relationModel;
    if (model == null) return;
    try {
      final result = await model.execute('autocomplete', [
        text,
        _field.getDomain(_record),
        _record.model.session.limit,
        _field.getSearchOrder(_record),
      ],
          context: {
            ..._record.model.sessionContext(),
            ..._field.getSearchContext(_record),
          },
          processException: false);
      if (!mounted || _ctrl.text != text) return;
      final create = _createAccess;
      setState(() {
        _completion = [
          for (final v in (result as List? ?? const []))
            if (v is Map && (v['id'] != null || create))
              Map<String, dynamic>.from(v)
        ];
        _showCompletion = true;
      });
    } catch (_) {
      // like SAO: completion errors are only logged
    }
  }

  void _choose(Map<String, dynamic> entry) {
    setState(() => _showCompletion = false);
    final id = entry['id'];
    if (id is int) {
      _typed = false;
      final name = '${entry['name'] ?? ''}';
      _ctrl.text = name;
      widget.onChanged(_valueOf(id, name));
    } else {
      final defaults = entry['defaults'];
      _new(defaults is Map ? defaults.cast<String, dynamic>() : null);
    }
  }

  // ── Popups ────────────────────────────────────────────────────────────────

  List<int?> _viewIds({bool form = false}) {
    final raw = _attr('view_ids');
    final ids = [
      for (final part in '${raw ?? ''}'.split(','))
        if (part.trim().isNotEmpty) int.tryParse(part.trim())
    ];
    // The first (tree) view is not used when only the form is shown.
    if (form && ids.isNotEmpty) ids.removeAt(0);
    return ids;
  }

  Map<String, Map<String, dynamic>> get _viewsPreload {
    final views = _field.description['views'];
    return views is Map
        ? {
            for (final MapEntry(:key, :value) in views.entries)
              if (value is Map) '$key': Map<String, dynamic>.from(value)
          }
        : const {};
  }

  String? get _excludeField {
    final value = _attr('relation_field');
    return value is String && value.isNotEmpty ? value : null;
  }

  String get _title => widget.node.string ?? widget.fieldDef.label;

  /// Form screen of the relation (SAO `get_screen`).
  TrytonScreen _screen({bool search = false}) {
    final screen = TrytonScreen(
      ScreenAttributes(
        _relation!,
        mode: const ['form'],
        viewIds: _viewIds(form: true),
        viewsPreload: _viewsPreload,
        domain: _field.getDomain(_record),
        context: search
            ? _field.getSearchContext(_record)
            : _field.getContext(_record),
        readonly: widget.readOnly,
        excludeField: _excludeField,
      ),
      session: _record.model.session,
    );
    screen.onViewAdded = (v) => markUnsupportedFields(screen.model, v);
    return screen;
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_popup) return;
    _popup = true;
    try {
      await action();
    } on HandledRpcError {
      // shown
    } finally {
      _popup = false;
      if (mounted) setState(() {});
    }
  }

  /// Search dialog with the typed text (SAO `activate`): a choice sets
  /// the value, cancel clears the text.
  Future<void> _activate() => _guard(() async {
        if (_relation == null || !_readAccess || _hasTarget) {
          _typed = false;
          return;
        }
        final text = _ctrl.text;
        if (widget.readOnly || (text.isEmpty && !widget.required)) {
          _typed = false;
          return;
        }
        await _search(text);
      });

  Future<void> _search(String text) async {
    final result = await showSearchDialog(
      context,
      model: _relation!,
      session: _record.model.session,
      domain: _field.getDomain(_record),
      searchContext: _field.getSearchContext(_record),
      order: _asList(_field.getSearchOrder(_record)),
      viewIds: _viewIds(),
      viewsPreload: _viewsPreload,
      allowNew: _createAccess,
      searchText: text,
      title: _title,
      excludeField: _excludeField,
    );
    _typed = false;
    if (!mounted) return;
    if (result.isNotEmpty) {
      _ctrl.text = result.first.name;
      widget.onChanged(_valueOf(result.first.id, result.first.name));
    } else {
      _ctrl.text = '';
      if (_hasTarget) widget.onChanged(_valueOf(null, ''));
    }
  }

  static List<dynamic>? _asList(dynamic value) => value is List ? value : null;

  /// Open (form popup, saves itself; then rec_name read again) or, without
  /// value, Search (SAO `edit`). [newTab]: the record in a new tab.
  Future<void> _edit({bool newTab = false}) => _guard(() async {
        if (_relation == null || !_readAccess) return;
        final id = _id;
        if (id == null) {
          if (!widget.readOnly) await _search(_ctrl.text);
          return;
        }
        if (newTab) {
          ref.read(tabsProvider.notifier).openTab(
                title: _title,
                attributes: ScreenAttributes(
                  _relation!,
                  mode: const ['form'],
                  viewIds: _viewIds(form: true),
                  context: _field.getContext(_record),
                  resId: id,
                ),
              );
          return;
        }
        final screen = _screen();
        try {
          screen.load([id]);
          screen.currentRecord = screen.group.get(id);
          final ok = await showFormDialog(context, screen,
              saveCurrent: true,
              title: _title,
              breadcrumb: widget.breadcrumb);
          final record = screen.currentRecord;
          if (ok && record != null && mounted) {
            final name = await record.recName();
            _ctrl.text = name;
            widget.onChanged(_valueOf(record.id, name));
          }
        } finally {
          screen.dispose();
        }
      });

  /// New record in a form popup (saves itself) with `rec_name` = text
  /// (SAO `new_`).
  Future<void> _new([Map<String, dynamic>? defaults]) => _guard(() async {
        if (_relation == null || !_createAccess || widget.readOnly) return;
        final screen = _screen(search: true);
        try {
          final ok = await showFormDialog(context, screen,
              newRecord: true,
              defaults: {...?defaults, 'rec_name': _ctrl.text},
              saveCurrent: true,
              title: _title,
              breadcrumb: widget.breadcrumb);
          final record = screen.currentRecord;
          _typed = false;
          if (ok && record != null && record.id >= 0 && mounted) {
            final name = await record.recName();
            _ctrl.text = name;
            widget.onChanged(_valueOf(record.id, name));
          }
        } finally {
          screen.dispose();
        }
      });

  void _clear() {
    _typed = false;
    _ctrl.text = '';
    widget.onChanged(_valueOf(null, ''));
    _focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.f3 &&
        !widget.readOnly &&
        _createAccess) {
      _new();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f2 && _readAccess) {
      _edit();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _showCompletion) {
      setState(() => _showCompletion = false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final label = widget.required ? '$_title *' : _title;
    final field = Focus(
      onKeyEvent: _onKey,
      child: TextField(
        key: ValueKey('m2o-$_name'),
        controller: _ctrl,
        focusNode: _focus,
        readOnly: widget.readOnly || _relation == null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: Tooltip(
            message: _relation ?? '',
            child: const Icon(Icons.account_tree_outlined, size: 16),
          ),
          suffixIcon: _buttons(l),
          errorText: widget.invalid ? '' : null,
          errorStyle:
              widget.invalid ? const TextStyle(height: 0, fontSize: 0) : null,
        ),
        onChanged: _onTyped,
        onSubmitted: (_) {
          if (_typed) _activate();
        },
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isReference) ...[
          _modelSelector(),
          const SizedBox(height: 4),
        ],
        field,
        if (_showCompletion) _completionList(l),
      ],
    );
  }

  Widget? _buttons(AppLocalizations l) {
    final buttons = <Widget>[];
    Widget button(IconData icon, String tip, VoidCallback onPressed,
            {Key? key}) =>
        IconButton(
          key: key,
          icon: Icon(icon, size: 16),
          tooltip: tip,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        );
    if (_hasTarget && _readAccess) {
      buttons.add(button(Icons.open_in_new, l.openRecord, () {
        final keys = HardwareKeyboard.instance;
        _edit(newTab: keys.isControlPressed || keys.isMetaPressed);
      }, key: ValueKey('m2o-open-$_name')));
    }
    if (!widget.readOnly && _relation != null) {
      if (_hasTarget) {
        buttons.add(button(Icons.clear, l.clearField, _clear,
            key: ValueKey('m2o-clear-$_name')));
      } else if (_readAccess) {
        buttons.add(button(Icons.search, l.searchRecord, () => _edit(),
            key: ValueKey('m2o-search-$_name')));
      }
    }
    return buttons.isEmpty
        ? null
        : Row(mainAxisSize: MainAxisSize.min, children: buttons);
  }

  Widget _completionList(AppLocalizations l) {
    final entries = <(String, VoidCallback)>[
      for (final e in _completion)
        (
          e['id'] == null
              ? l.createNamed('${e['name'] ?? ''}')
              : '${e['name'] ?? ''}',
          () => _choose(e)
        ),
      if (_readAccess)
        (l.searchMenu, () {
          setState(() => _showCompletion = false);
          _edit();
        }),
      if (_createAccess && !widget.readOnly)
        (l.createMenu, () {
          setState(() => _showCompletion = false);
          _new();
        }),
    ];
    return Material(
      elevation: 4,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: [
            for (final (text, onTap) in entries)
              InkWell(
                onTap: onTap,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(text, style: const TextStyle(fontSize: 13)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Model of a reference field (allowed models from the domains).
  Widget _modelSelector() {
    final allowed = (_field as ReferenceField).getModels(_record);
    final models = [
      for (final m in _models ?? const <List<dynamic>>[])
        if (m.isNotEmpty &&
            m[0] != null &&
            '${m[0]}'.isNotEmpty &&
            (allowed.isEmpty || allowed.contains(m[0])))
          m
    ];
    final current = _relation;
    return DropdownButtonFormField<String>(
      key: ValueKey('ref-model-$_name'),
      initialValue: models.any((m) => m[0] == current) ? current : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: _title,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final m in models)
          DropdownMenuItem(
              value: '${m[0]}',
              child: Text('${m.length > 1 ? m[1] : m[0]}',
                  overflow: TextOverflow.ellipsis)),
      ],
      onChanged: widget.readOnly
          ? null
          : (model) {
              _typed = false;
              _ctrl.text = '';
              widget.onChanged(model == null ? null : [model, null]);
            },
    );
  }
}
