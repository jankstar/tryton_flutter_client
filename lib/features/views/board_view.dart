import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart';
import '../../core/pyson/pyson_evaluator.dart';
import '../../core/rpc/error_processing.dart';
import '../../core/screen/screen.dart';
import '../../core/xml/form_xml_parser.dart';
import '../../core/xml/view_definition.dart';
import '../../shared/errors/error_dialogs.dart';
import '../actions/action_service.dart';
import '../model/field_support.dart';
import '../model/model_rpc.dart';
import '../model/model_service.dart';
import 'fill_column.dart';
import 'form_dialog.dart';
import 'form_grid.dart';
import 'list_form_view.dart';
import 'record_form.dart';
import 'screen_widget.dart';
import 'tree_view.dart';

/// One `<action>` of a board (spec 9.7, Python `view_board.Action`): the
/// act_window of [name] (`ir.action.act_window.get`) shown in its own
/// [screen]. The domain is PYSON evaluated with `_actions` – the active
/// records of the other actions of the board (master/detail).
class BoardAction {
  final ActionNode node;

  /// Values of the act_window (`get_action_value`).
  final Map<String, dynamic> action;
  final TrytonScreen screen;

  /// Environment of the PYSON domain (session context, `_user`, the
  /// action's context).
  final Map<String, dynamic> _env;

  BoardAction(this.node, this.action, this.screen, this._env);

  /// Key in `_actions` (the `name` of the `<action>` node).
  String get name => node.name;

  /// Title of the frame: the node's `string`, else the action's name.
  String get title => node.string ?? '${action['name'] ?? ''}';

  /// `active_id`/`active_ids` of this action for the others.
  Map<String, dynamic> get active {
    final current = screen.currentRecord;
    return {
      'active_id': current?.id,
      'active_ids': current == null
          ? <int>[]
          : [for (final r in screen.selectedRecords) r.id],
    };
  }

  /// The domain of the action with the active records of [actions].
  List<dynamic> domainFor(Iterable<BoardAction> actions) {
    final env = <String, dynamic>{
      ..._env,
      '_actions': {for (final a in actions) a.name: a.active},
    };
    final raw = action['pyson_domain'];
    final decoded = raw is String && raw.isNotEmpty ? jsonDecode(raw) : raw;
    final domain = decoded == null ? null : PYSONEvaluator(env).eval(decoded);
    return domain is List ? domain : const [];
  }
}

/// A board tab (spec 9.7, 10.2; Python `Board`): the arch of
/// `ir.ui.view.view_get(view_id)` with root `<board col>`, laid out like a
/// form (group, notebook, hpaned/vpaned, label, separator, newline), with
/// one screen per `<action>`. A selection in one action updates the
/// domains of the others.
class BoardView extends ConsumerStatefulWidget {
  /// Attributes of the board action: `view_ids` (the board view) and the
  /// context.
  final ScreenAttributes attributes;
  final String title;
  final Future<void> Function()? onClose;

  const BoardView({
    super.key,
    required this.attributes,
    required this.title,
    this.onClose,
  });

  @override
  ConsumerState<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends ConsumerState<BoardView> {
  FormRoot? _root;
  final Map<ActionNode, BoardAction> _actions = {};
  final Map<ActionNode, Object> _actionErrors = {};
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final a in _actions.values) {
      a.screen.dispose();
    }
    super.dispose();
  }

  ModelService get _svc => ref.read(modelServiceProvider);

  Future<void> _load() async {
    try {
      final viewId = widget.attributes.viewIds.firstOrNull;
      final view = await _svc.execute<Map<String, dynamic>>(
          'ir.ui.view', 'view_get', [viewId],
          context: widget.attributes.context);
      final root = FormXmlParser().parse('${view['arch']}');
      final nodes = _actionNodes(root.children).toList();
      final loaded = await Future.wait(nodes.map(_createAction));
      if (!mounted) {
        for (final a in loaded) {
          a?.screen.dispose();
        }
        return;
      }
      setState(() {
        _root = root;
        for (final (i, node) in nodes.indexed) {
          final action = loaded[i];
          if (action != null) _actions[node] = action;
        }
      });
      // the domains with the (still empty) selections, then the searches
      // (Python `ViewBoard.active_changed(None)` + `reload`)
      for (final a in _actions.values) {
        a.screen.updateDomain(a.domainFor(_actions.values));
      }
      await _reload();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static Iterable<ActionNode> _actionNodes(List<FormNode> nodes) sync* {
    for (final node in nodes) {
      switch (node) {
        case ActionNode():
          yield node;
        case GroupNode():
          yield* _actionNodes(node.children);
        case NotebookNode():
          for (final page in node.pages) {
            yield* _actionNodes(page.children);
          }
        default:
          break;
      }
    }
  }

  /// The act_window of [node] and its screen (Python `Action.__init__`).
  Future<BoardAction?> _createAction(ActionNode node) async {
    try {
      final action = await _svc.execute<Map<String, dynamic>>(
          'ir.action.act_window', 'get', [node.name],
          context: widget.attributes.context);
      final actions = ref.read(actionServiceProvider);
      final attributes = ScreenAttributes.fromActWindow(
        action,
        sessionContext: actions.sessionContext(),
        userId: actions.userId(),
        context: widget.attributes.context,
      );
      final env = <String, dynamic>{
        ...actions.sessionContext(),
        '_user': actions.userId(),
        ...attributes.context,
      };
      env['context'] = env;
      final screen = _newScreen(attributes);
      final loadAccess = screen.model.session.loadAccess;
      await loadAccess?.call([screen.model.name]);
      await screen.switchView();
      await loadAccess?.call(relationModels(screen.model));
      return BoardAction(node, action, screen, env);
    } catch (e) {
      _actionErrors[node] = e;
      return null;
    }
  }

  TrytonScreen _newScreen(ScreenAttributes attributes) {
    final screen = TrytonScreen(attributes,
        session: modelSessionFor(_svc, processor: errorHandlerOf(context, ref)));
    screen
      ..onViewAdded = ((v) => markUnsupportedFields(screen.model, v))
      ..onAction = (action, data, context) => ref
          .read(actionServiceProvider)
          .execute(action,
              data: data,
              context: context,
              keyword: true,
              ui: DialogActionUi(this.context),
              screen: screen);
    return screen;
  }

  /// Searches all actions again (Python `ViewBoard.reload`).
  Future<void> _reload() async {
    await Future.wait([for (final a in _actions.values) _display(a)]);
  }

  /// Searches [action] again with its search text (Python
  /// `Action.display`).
  Future<void> _display(BoardAction action) async {
    try {
      await action.screen.searchFilter(action.screen.searchText);
    } on HandledRpcError {
      // shown
    } catch (e) {
      if (mounted) await errorHandlerOf(context, ref).show(e);
    }
  }

  /// The selection of [source] changed: the other actions update their
  /// domain and search again when it changed (Python `active_changed`).
  void _activeChanged(BoardAction source) {
    for (final a in _actions.values) {
      if (identical(a, source)) continue;
      if (a.screen.updateDomain(a.domainFor(_actions.values))) _display(a);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final root = _root;
    Widget body;
    if (_loading && root == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null || root == null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text('${_error ?? ''}', textAlign: TextAlign.center),
          ]),
        ),
      );
    } else {
      // one scroll area; the actions share the height of the tab
      body = LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: math.max(0, constraints.maxHeight - 16)),
            child: _layout(root.children, root.col),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHighest,
        scrolledUnderElevation: 0,
        title: Text(widget.title),
        actions: [
          IconButton(
            key: const ValueKey('board-reload'),
            icon: const Icon(Icons.refresh),
            tooltip: context.l10n.reload,
            onPressed: _actions.isEmpty ? null : _reload,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: context.l10n.close,
            onPressed: () => widget.onClose?.call(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: body,
    );
  }

  // ─── Layout (like the form, spec 9.2.2) ──────────────────────────────────

  /// [nodes] contain an action (the cell takes the remaining height).
  static bool _fills(FormNode node) => switch (node) {
        ActionNode() => node.yexpand ?? true,
        GroupNode() => node.children.any(_fills),
        NotebookNode() => node.pages.any((p) => p.children.any(_fills)),
        _ => false,
      };

  /// The grid of [nodes] in [col] columns (`col ≤ 0`: side by side).
  Widget _layout(List<FormNode> nodes, int col) {
    if (col <= 0) {
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final node in nodes)
          if (_cell(node) case final Widget child) child,
      ]);
    }
    final cells = <FormGridCell>[];
    var row = 0, used = 0;
    for (final node in nodes) {
      if (node is NewlineNode) {
        if (used > 0) row++;
        used = 0;
        continue;
      }
      final child = _cell(node);
      if (child == null) continue;
      final full = node is NotebookNode || node is SeparatorNode;
      final colspan = math.min(
          switch (node) {
            ActionNode() => node.colspan,
            GroupNode() => node.colspan,
            LabelNode() => node.colspan,
            _ => col,
          },
          col);
      if (full || used + colspan > col) {
        if (used > 0) row++;
        used = 0;
      }
      cells.add(FormGridCell(
        row: row,
        column: full ? 0 : used,
        colspan: full ? col : colspan,
        full: full,
        expand: node.xexpand ?? node is! LabelNode,
        xalign: node.xalign ?? (node is LabelNode ? 1.0 : null),
        fill: _fills(node),
        child: Padding(padding: const EdgeInsets.all(4), child: child),
      ));
      if (full) {
        row++;
      } else {
        used += colspan;
      }
    }
    return FormGrid(columns: col, children: cells);
  }

  Widget? _cell(FormNode node) => switch (node) {
        ActionNode() => _actionView(node),
        GroupNode() => node.string == null || node.string!.isEmpty
            ? _layout(node.children, node.col)
            : InputDecorator(
                decoration: InputDecoration(
                  labelText: node.string,
                  border: const OutlineInputBorder(),
                ),
                child: _layout(node.children, node.col),
              ),
        NotebookNode() => _BoardNotebook(
            pages: node.pages,
            page: (page) => _layout(page.children, page.col)),
        LabelNode() => Text(node.string ?? ''),
        SeparatorNode() => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (node.string != null && node.string!.isNotEmpty)
                Text(node.string!,
                    style: Theme.of(context).textTheme.titleSmall),
              const Divider(),
            ],
          ),
        _ => null,
      };

  Widget _actionView(ActionNode node) {
    final action = _actions[node];
    if (action == null) {
      final error = _actionErrors[node];
      return SizedBox(
        height: 120,
        child: Center(
            child: error == null
                ? const CircularProgressIndicator()
                : Text('$error', textAlign: TextAlign.center)),
      );
    }
    return _BoardActionView(
      key: ObjectKey(action),
      action: action,
      onSelectionChanged: () => _activeChanged(action),
      onReload: () => _display(action),
    );
  }
}

/// The frame of a board action: title, Switch and Reload, the current
/// view of its screen; at least the node's `height` (default 300 px),
/// more when the board has room.
class _BoardActionView extends ConsumerStatefulWidget {
  final BoardAction action;
  final VoidCallback onSelectionChanged;
  final Future<void> Function() onReload;

  const _BoardActionView({
    super.key,
    required this.action,
    required this.onSelectionChanged,
    required this.onReload,
  });

  @override
  ConsumerState<_BoardActionView> createState() => _BoardActionViewState();
}

class _BoardActionViewState extends ConsumerState<_BoardActionView> {
  TrytonScreen get _screen => widget.action.screen;

  @override
  void initState() {
    super.initState();
    _screen.addListener(_onScreenChanged);
  }

  @override
  void dispose() {
    _screen.removeListener(_onScreenChanged);
    super.dispose();
  }

  void _onScreenChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on HandledRpcError {
      // shown
    } catch (e) {
      if (mounted) await errorHandlerOf(context, ref).show(e);
    }
  }

  /// Row activation (Python `Action.row_activate`): `tree_open` with
  /// `keyword_open`, otherwise the record in a form dialog.
  Future<void> _activate(Record record) => _run(() async {
        final screen = _screen;
        screen
          ..selectedRecords = [record]
          ..currentRecord = record;
        final view = screen.currentView;
        if (view?.viewType == 'tree' &&
            (int.tryParse(view?.attributes['keyword_open'] ?? '') ?? 0) != 0) {
          await ref.read(actionServiceProvider).execKeyword(
              'tree_open',
              {
                'model': screen.model.name,
                'id': record.id,
                'ids': [for (final r in screen.selectedRecords) r.id],
              },
              context: {...screen.group.context},
              warning: false,
              ui: DialogActionUi(context));
          return;
        }
        final previous = view?.viewType;
        await showFormDialog(context, screen, title: widget.action.title);
        if (previous != null && screen.currentView?.viewType != previous) {
          await screen.switchView(viewType: previous);
        }
      });

  Future<void> _switch() => _run(() async {
        final screen = _screen;
        if (screen.currentRecord == null && screen.selectedRecords.isNotEmpty) {
          screen.currentRecord = screen.selectedRecords.first;
        }
        await screen.switchView();
      });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final node = widget.action.node;
    final minHeight = (node.height ?? 300).toDouble();
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: math.max(minHeight, constraints.minHeight),
        child: Card(
          key: ValueKey('board-action-${node.name}'),
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: cs.surfaceContainerHighest,
                padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      widget.action.title,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: cs.primary),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('board-switch-${node.name}'),
                    icon: TrytonIcon(
                        iconName: 'tryton-switch',
                        size: 18,
                        fallback: Icons.compare_arrows),
                    tooltip: context.l10n.switchView,
                    onPressed: _screen.numberOfViews > 1 ? _switch : null,
                  ),
                  IconButton(
                    key: ValueKey('board-reload-${node.name}'),
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: context.l10n.reload,
                    onPressed: widget.onReload,
                  ),
                ]),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final screen = _screen;
    final view = screen.currentView;
    if (view == null) return const SizedBox.shrink();
    void selectionChanged() {
      setState(() {});
      widget.onSelectionChanged();
    }

    switch (view.viewType) {
      case 'tree':
        return TreeView(
          key: ObjectKey(view),
          screen: screen,
          view: view,
          onActivate: _activate,
          onSelectionChanged: selectionChanged,
          onEndReached: () => _run(screen.searchMore),
        );
      case 'list-form':
        return ListFormView(
          key: ObjectKey(view),
          screen: screen,
          view: view,
          onActivate: _activate,
          onSelectionChanged: selectionChanged,
          onEndReached: () => _run(screen.searchMore),
        );
      default:
        // a form shows the current record (read only; editing in the
        // dialog of the row activation)
        final record = screen.currentRecord;
        final root = view.formRoot;
        if (record == null || root == null) return const SizedBox.shrink();
        return SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: RecordForm(
            key: ObjectKey(record),
            model: screen.model.name,
            root: root,
            viewDef: view.definition,
            record: record,
            onTextChanged: (_, _) {},
            onBlur: (_) {},
            onChangedImmediate: (_, _) {},
            isReadOnly: true,
          ),
        );
    }
  }
}

/// Tabs of a board notebook and the selected page (which takes the
/// remaining height).
class _BoardNotebook extends StatefulWidget {
  final List<PageNode> pages;
  final Widget Function(PageNode page) page;

  const _BoardNotebook({required this.pages, required this.page});

  @override
  State<_BoardNotebook> createState() => _BoardNotebookState();
}

class _BoardNotebookState extends State<_BoardNotebook> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = widget.pages;
    if (pages.isEmpty) return const SizedBox.shrink();
    final index = _index.clamp(0, pages.length - 1);
    return FillColumn(children: [
      DefaultTabController(
        length: pages.length,
        initialIndex: index,
        child: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          onTap: (i) => setState(() => _index = i),
          tabs: [for (final p in pages) Tab(text: p.string)],
        ),
      ),
      FillChild(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: KeyedSubtree(
              key: ValueKey(index), child: widget.page(pages[index])),
        ),
      ),
    ]);
  }
}
