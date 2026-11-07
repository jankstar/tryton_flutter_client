import 'package:flutter/material.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart';
import '../../core/pyson/pyson_evaluator.dart';
import '../../core/xml/view_definition.dart';
import '../../shared/widgets/field_widget.dart';
import '../model/field_definition.dart';
import 'embedded_tree_widget.dart';
import 'record_field_widgets.dart';
import 'record_link.dart';
import 'record_many2one.dart';
import 'record_widget_values.dart';

/// Form layout of one [Record] (spec 9.2): fields, labels, groups,
/// notebooks and buttons of a form view. States come from the record
/// (`field.setState/stateAttrs`), values are read with `get/getClient`;
/// changes are handed to the callbacks (the owner writes them with
/// `setClient`). Used by the form screen and the x2many sub-form.

class RecordForm extends StatefulWidget {
  final String model;
  final FormRoot root;
  final ViewDefinition viewDef;

  /// The record shown; states come from `field.setState/stateAttrs`.
  final Record record;
  final void Function(String, dynamic) onTextChanged;
  final void Function(String) onBlur;
  final void Function(String, dynamic) onChangedImmediate;

  final bool isReadOnly;

  /// Breadcrumb of the popups opened from this form.
  final List<String> breadcrumb;

  /// Field not shown (the parent field of an x2many sub-form, spec 9.2.1
  /// `exclude_field`).
  final String? excludeField;
  /// Called when the user activates a <button> in the form.
  final Future<void> Function(ButtonNode)? onButton;

  const RecordForm({
    super.key,
    required this.model,
    required this.root,
    required this.viewDef,
    required this.record,
    required this.onTextChanged,
    required this.onBlur,
    required this.onChangedImmediate,
    required this.isReadOnly,
    this.onButton,
    this.breadcrumb = const [],
    this.excludeField,
  });

  @override
  State<RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<RecordForm> {
  /// Values in FieldWidget format, computed once per build.
  late Map<String, dynamic> _values;

  Record get _record => widget.record;

  @override
  Widget build(BuildContext context) {
    _values = recordWidgetValues(_record);
    return _renderNodes(widget.root.children, _safeCol(widget.root.col));
  }

  /// `states` of the field evaluated into its state attributes (SAO
  /// `set_state` in `display`).
  Map<String, dynamic> _stateAttrs(Field field) {
    field.setState(_record);
    return field.stateAttrs(_record);
  }

  /// invisible/readonly of a button or page from its PYSON `states`.
  ({bool invisible, bool readonly}) _nodeStates(Map<String, dynamic>? states) {
    if (states == null || states.isEmpty) {
      return (invisible: false, readonly: false);
    }
    final evaluated = _record.exprEval(states);
    final map = evaluated is Map ? evaluated : const {};
    return (
      invisible: PYSONEvaluator.truthy(map['invisible']),
      readonly: PYSONEvaluator.truthy(map['readonly']),
    );
  }


  /// Columns of a container: ≤ 0 = horizontal box (spec 9.2.2).
  static int _safeCol(int col) => col;

  /// Lays out [nodes] in a grid of [col] columns (spec 9.2.2, GTK
  /// `Container.add`): cells are placed row by row at fixed column
  /// positions; `colspan` at most [col]; a cell that does not fit starts
  /// a new row. `col ≤ 0` puts all cells in one row (horizontal box),
  /// `col = 1` one below the other. Cells keep their position when they
  /// are invisible; columns without a visible cell collapse.
  Widget _renderNodes(List<FormNode> nodes, int col) {
    final hbox = col <= 0;
    // Labels with fieldName are skipped. Their column width is transferred to
    // the immediately following Field-Node with the same name, so that no
    // gaps appear in the grid and the field uses the full available space.
    // (The field already shows its name as a floating label internally.)
    final labelColspanMap = <String, int>{};
    for (final n in nodes) {
      if (n is LabelNode && n.fieldName != null) {
        labelColspanMap[n.fieldName!] = n.colspan;
      }
    }

    // Rows of cells (List<_Cell>) or full-width widgets (notebook,
    // separator).
    final rows = <Object>[];
    var currentRow = <_Cell>[];
    var used = 0;

    void flushRow() {
      if (currentRow.isEmpty) return;
      rows.add(currentRow);
      currentRow = <_Cell>[];
      used = 0;
    }

    for (final node in nodes) {
      // LabelNode with field name → skip (field shows label internally)
      // (`string=""` shows the field value instead, spec 9.2.1.)
      if (node is LabelNode &&
          node.fieldName != null &&
          node.string != '' &&
          _hasField(nodes, node.fieldName!)) {
        continue;
      }

      if (node is NewlineNode) {
        if (!hbox) flushRow();
        continue;
      }
      if (!hbox && (node is NotebookNode || node is SeparatorNode)) {
        // Full width (notebooks default to colspan 4, separators to col).
        final cell = _cellOf(node, col);
        if (cell == null) continue;
        flushRow();
        rows.add(cell.visible ? cell.child : const SizedBox.shrink());
        continue;
      }

      final cell = _cellOf(node, hbox ? 1 : col,
          extraColspan: node is FieldNode ? labelColspanMap[node.name] ?? 0 : 0);
      if (cell == null) continue;
      if (hbox) {
        currentRow.add(cell.at(currentRow.length, 1));
        continue;
      }
      if (used + cell.colspan > col) flushRow();
      currentRow.add(cell.at(used, cell.colspan));
      used += cell.colspan;
    }
    flushRow();

    return _Grid(
      rows: rows,
      cols: hbox ? rows.whereType<List<_Cell>>().fold(1, (m, r) => r.length > m ? r.length : m) : col,
      hbox: hbox,
    );
  }

  /// [nodes] (or their groups) contain a `<field>` named [name].
  static bool _hasField(List<FormNode> nodes, String name) => nodes.any((n) =>
      (n is FieldNode && n.name == name) ||
      (n is GroupNode && _hasField(n.children, name)));

  /// The cell of [node] in a container of [col] columns (null: no cell).
  _Cell? _cellOf(FormNode node, int col, {int extraColspan = 0}) {
    final maxCol = col < 1 ? 1 : col;
    var colspan = switch (node) {
      FieldNode() => node.colspan,
      LabelNode() => node.colspan,
      GroupNode() => node.colspan,
      ButtonNode() => node.colspan,
      LinkNode() => node.colspan,
      ImageNode() => node.colspan,
      SeparatorNode() => node.colspan,
      NotebookNode() => node.colspan,
      _ => 1,
    };
    colspan = (colspan + extraColspan).clamp(1, maxCol);
    if (node is FieldNode) {
      // one2many / many2many tables always need full width – force it even
      // when the XML omits an explicit colspan (Tryton forms always intend
      // this, but our parser defaults to 1).
      final fd = widget.viewDef.fields[node.name];
      if (fd != null && (fd.type == 'one2many' || fd.type == 'many2many')) {
        colspan = maxCol;
      }
    }
    // Invisible cells keep their position but are not built.
    final visible = !_isInvisible(node);
    final child = visible ? _buildNode(node) : const SizedBox.shrink();
    if (child == null) return null;
    // Labels and separator texts do not expand (xexpand 0), everything
    // else does (default xexpand = 1).
    final defaultExpand = node is! LabelNode;
    return _Cell(
      child: visible ? _sized(node, child) : const SizedBox.shrink(),
      colspan: colspan,
      visible: visible,
      expand: node.xexpand ?? defaultExpand,
      xalign: node.xalign ?? (node is LabelNode ? 1.0 : null),
    );
  }

  /// `width`/`height` of the node as size request (GTK
  /// `set_size_request`: a minimum, never more than the cell offers).
  Widget _sized(FormNode node, Widget child) {
    final w = node.width, h = node.height;
    if ((w == null || w <= 0) && (h == null || h <= 0)) return child;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: w != null && w > 0 ? w.toDouble() : 0,
        minHeight: h != null && h > 0 ? h.toDouble() : 0,
      ),
      child: child,
    );
  }

  /// The node is hidden by its `states` / field state (spec 9.2.3).
  bool _isInvisible(FormNode node) {
    switch (node) {
      case FieldNode():
        if (node.name == widget.excludeField) return true;
        final field = _record.model.fields[node.name];
        if (field == null) return false;
        return PYSONEvaluator.truthy(_stateAttrs(field)['invisible']);
      case LabelNode():
        if (_nodeStates(node.states).invisible) return true;
        final name = node.fieldName;
        final field = name == null ? null : _record.model.fields[name];
        return field != null &&
            PYSONEvaluator.truthy(_stateAttrs(field)['invisible']);
      case ButtonNode():
        return RecordButton.statesOf(node, _record).invisible;
      case PageNode():
        return node.invisibleStatic || _nodeStates(node.statesRaw ?? node.states).invisible;
      case GroupNode() || SeparatorNode() || LinkNode() || ImageNode() ||
            NotebookNode():
        return PYSONEvaluator.truthy(node.attrs['invisible']) ||
            _nodeStates(node.states).invisible;
      default:
        return false;
    }
  }

  Widget? _buildNode(FormNode node) {
    if (node is FieldNode) return _withHelp(node, _buildField(node));
    if (node is LabelNode) return _buildLabel(node);
    if (node is GroupNode) return _buildGroup(node);
    if (node is ButtonNode) return _buildButton(node);
    if (node is NotebookNode) return _buildNotebook(node);
    if (node is SeparatorNode) return _buildSeparator(node);
    if (node is LinkNode) {
      return RecordLink(
          key: ValueKey('link-${node.actionId}'), node: node, record: _record);
    }
    if (node is ImageNode) return RecordImage(node: node, record: _record);
    return null;
  }

  /// `help` of the field as tooltip (spec 9.2.3).
  Widget _withHelp(FieldNode node, Widget child) {
    final help = node.help;
    if (help == null) return child;
    return Tooltip(message: help, waitDuration: const Duration(milliseconds: 600), child: child);
  }

  Widget _buildField(FieldNode node) {
    final fd = widget.viewDef.fields[node.name];
    final field = _record.model.fields[node.name];
    if (fd == null || field == null) return _unknownField(node.name);

    final attrs = _stateAttrs(field);
    // Invisible fields are not rendered (no placeholder, no spacing)
    if (PYSONEvaluator.truthy(attrs['invisible'])) {
      return const SizedBox.shrink();
    }
    // readonly also covers domain_readonly (unique value of the domain)
    final readOnly =
        widget.isReadOnly || PYSONEvaluator.truthy(attrs['readonly']);
    final invalid = attrs['invalid'] != null && attrs['invalid'] != false;

    // One2Many / Many2Many → inline table
    if (fd.type == 'one2many' || fd.type == 'many2many') {
      return _buildX2ManyField(fd, field, readOnly, node);
    }

    // Many2One / One2One with widget="selection": dropdown (9.2.4)
    if ((fd.type == 'many2one' || fd.type == 'one2one') &&
        node.widget == 'selection') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: RecordSelectionMany2One(
          key: ValueKey('m2o-sel-${node.name}'),
          args: RecordFieldArgs(
            record: _record,
            node: node,
            fd: fd,
            readOnly: readOnly,
            required: PYSONEvaluator.truthy(attrs['required']),
            invalid: invalid,
            onText: (v) => widget.onChangedImmediate(node.name, v),
            onBlur: () {},
            onValue: (v) => widget.onChangedImmediate(node.name, v),
          ),
        ),
      );
    }

    // Many2One / One2One / Reference → widget on the record (9.2.6)
    if (fd.type == 'many2one' ||
        fd.type == 'one2one' ||
        fd.type == 'reference') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: RecordMany2One(
          record: _record,
          node: node,
          fieldDef: fd,
          readOnly: readOnly,
          required: PYSONEvaluator.truthy(attrs['required']),
          invalid: invalid,
          breadcrumb: widget.breadcrumb,
          onChanged: (value) => widget.onChangedImmediate(node.name, value),
        ),
      );
    }

    final args = RecordFieldArgs(
      record: _record,
      node: node,
      fd: fd,
      readOnly: readOnly,
      required: PYSONEvaluator.truthy(attrs['required']),
      invalid: invalid,
      autofocus: widget.root.cursor == node.name,
      onText: (v) => widget.onTextChanged(node.name, v),
      onBlur: () => widget.onBlur(node.name),
      onValue: (v) => widget.onChangedImmediate(node.name, v),
    );
    final special = _recordWidget(fd, node, args);
    if (special != null) {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8), child: special);
    }

    // Text-input fields: kept locally on keystroke, written to the record
    // (on_change) only on blur – like SAO's focus_out event.
    // Single-action fields (selection, date, many2one, boolean): written
    // immediately since there is no "typing" involved.
    final isTextInput = fd.type == 'char' || fd.type == 'text' ||
        fd.type == 'integer' || fd.type == 'float' || fd.type == 'numeric';

    final input = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: FieldWidget(
        field: fd,
        value: _values[node.name],
        readOnly: readOnly,
        isRequired: PYSONEvaluator.truthy(attrs['required']),
        invalid: invalid,
        recordValues: _values,
        // XML attr takes precedence; fall back to fields_get 'symbol'.
        symbolField: node.symbol ?? fd.symbol,
        // Resolve the relation model of the symbol field so _NumericField
        // can call get_symbol without hardcoding 'res.currency'.
        symbolRelation: _resolveSymbolRelation(node.symbol ?? fd.symbol),
        // widget= override from XML arch (e.g. "url", "email", "password").
        widgetOverride: node.widget,
        autofocus: widget.root.cursor == node.name,
        model: widget.model,
        onChanged: isTextInput
            ? (v) => widget.onTextChanged(node.name, v)
            : (v) => widget.onChangedImmediate(node.name, v),
        onBlur: isTextInput ? () => widget.onBlur(node.name) : null,
      ),
    );
    // Translation dialog of translatable char/text fields (spec 9.2.5).
    if (node.attrs['translate'] == true &&
        (fd.type == 'char' || fd.type == 'text') &&
        node.widget != 'password') {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: input),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: IconButton(
            key: ValueKey('translate-${node.name}'),
            icon: const Icon(Icons.translate, size: 18),
            tooltip: context.l10n.translate,
            onPressed: () => _translate(node, fd.type == 'text'),
          ),
        ),
      ]);
    }
    return input;
  }

  Future<void> _translate(FieldNode node, bool multiline) async {
    // pending text of the field first (Python `view.set_value`)
    widget.onBlur(node.name);
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    try {
      await showTranslateDialog(context, _record, node.name,
          multiline: multiline);
    } catch (_) {
      // errors were shown by the form's error handler
    }
    if (mounted) setState(() {});
  }

  /// Widgets on the record (spec 9.2.4) for numbers, date/time,
  /// timedelta, multiselection, dict and the char widgets color, pyson and
  /// html; null for the others (FieldWidget).
  Widget? _recordWidget(FieldDefinition fd, FieldNode node, RecordFieldArgs args) {
    final w = node.widget;
    if (w == 'progressbar') return null;
    switch (w) {
      case 'color':
        return RecordColorInput(args: args);
      case 'pyson':
        return RecordPysonInput(args: args);
      case 'html':
        return RecordHtmlButton(args: args);
    }
    switch (fd.type) {
      case 'integer' || 'float' || 'numeric':
        return RecordNumberInput(args: args);
      case 'date' || 'datetime' || 'timestamp' || 'time':
        return RecordDateInput(args: args);
      case 'timedelta':
        return RecordTimeDeltaInput(args: args);
      case 'multiselection':
        return RecordMultiSelection(args: args);
      case 'dict':
        return RecordDictField(args: args);
    }
    return null;
  }

  /// Returns the relation model name of a symbol field (e.g. 'res.currency').
  String? _resolveSymbolRelation(String? symbolFieldName) {
    if (symbolFieldName == null) return null;
    return widget.viewDef.fields[symbolFieldName]?.relation;
  }

  Widget _buildX2ManyField(
      FieldDefinition fd, Field field, bool readOnly, FieldNode node) {

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(fd.label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  )),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline.withAlpha(80)),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.all(8),
          // The child group of the record (spec 9.2.7); saved with the
          // parent through the x2many commands.
          child: EmbeddedTreeWidget(
            key: ValueKey('x2m_${fd.name}'),
            parent: _record,
            fieldDef: fd,
            node: node,
            readOnly: readOnly,
            // the records follow the parent record, not the field state
            parentReadOnly: widget.isReadOnly,
            breadcrumb: widget.breadcrumb,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildLabel(LabelNode node) {
    final name = node.fieldName;
    final field = name == null ? null : _record.model.fields[name];
    String text;
    if (node.string == '' && field != null) {
      // `string=""`: the value of the field (Python `Label.state_set`).
      final value = field.getClient(_record);
      text = value == null || value == false ? '' : '$value';
    } else if (node.string != null) {
      text = node.string!;
    } else if (name != null) {
      text = '${node.attrs['string'] ?? '${widget.viewDef.fields[name]?.label ?? name}:'}';
    } else {
      return const SizedBox.shrink();
    }
    // required/readonly style of the field (or of the label states)
    final states = _nodeStates(node.states);
    final fieldStates = field == null ? const {} : _stateAttrs(field);
    final required = PYSONEvaluator.truthy(fieldStates['required']);
    final cs = Theme.of(context).colorScheme;
    final xalign = node.xalign ?? 1.0;
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 4),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: states.readonly ? cs.outline : cs.onSurfaceVariant,
              fontWeight: required ? FontWeight.w600 : null,
            ),
        textAlign: xalign >= 0.75
            ? TextAlign.right
            : (xalign <= 0.25 ? TextAlign.left : TextAlign.center),
      ),
    );
  }

  Widget _buildSeparator(SeparatorNode node) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        if (node.string != null && node.string!.isNotEmpty) ...[
          // Flexible prevents overflow when the text is wider than available
          Flexible(
            child: Text(
              node.string!,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        const Expanded(child: Divider()),
      ]),
    );
  }

  /// `<group>`: frame with title, or expander with `expandable` (open at
  /// `1`); `states` (invisible) are evaluated by the cell.
  Widget _buildGroup(GroupNode node) {
    final inner = _renderNodes(node.children, _safeCol(node.col));
    if (node.expandable) {
      return _GroupExpander(
        key: ValueKey('group-${node.id ?? identityHashCode(node)}'),
        title: node.string ?? '',
        initiallyExpanded: node.expanded,
        child: inner,
      );
    }
    if (node.string != null && node.string!.isNotEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(node.string!,
                  style: Theme.of(context).textTheme.titleSmall),
              const Divider(),
              inner,
            ],
          ),
        ),
      );
    }
    return inner;
  }

  Widget _buildButton(ButtonNode node) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: RecordButton(
            node: node, record: _record, onPressed: widget.onButton),
      );

  Widget _buildNotebook(NotebookNode node) {
    // Filter pages based on their states/invisible conditions
    final visiblePages = node.pages.where((p) => !_isInvisible(p)).toList();
    if (visiblePages.isEmpty) return const SizedBox.shrink();

    return DefaultTabController(
      length: visiblePages.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final p in visiblePages)
                Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (p.icon != null) ...[
                      TrytonIcon(iconName: p.icon, size: 16),
                      const SizedBox(width: 6),
                    ],
                    Text(_pageLabel(p)),
                  ]),
                ),
            ],
          ),
          SizedBox(
            height: _estimateNotebookHeight(visiblePages),
            child: TabBarView(
              children: visiblePages.map((page) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 8),
                  child: _renderNodes(page.children, _safeCol(page.col)),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// Resolves the display label for a notebook page.
  ///
  /// Priority (like Tryton/SAO):
  /// 1. `string` attribute in the XML arch (already translated by server)
  /// 2. The `string` (label) of the field with the same name as `page.name`
  ///    (pages added via view inheritance often have only `name`, not `string`)
  /// 3. Capitalize the technical `name` as a last fallback
  String _pageLabel(PageNode page) {
    // If the page has an explicit string that looks like a real label, use it
    if (page.string.isNotEmpty &&
        (page.string.contains(' ') ||
            page.string != page.string.toLowerCase() ||
            page.name == null)) {
      return page.string;
    }

    // Look up the field whose name matches the page name → its translated label
    final name = page.name ?? page.string;
    final fieldLabel = widget.viewDef.fields[name]?.label;
    if (fieldLabel != null && fieldLabel.isNotEmpty) return fieldLabel;

    // Fallback: capitalize each word of the technical name
    if (name.isEmpty) return '';
    return name
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  // Estimates the minimum height of a notebook based on the number of fields
  double _estimateNotebookHeight(List<PageNode> pages) {
    final maxFields = pages.fold<int>(0, (max, page) {
      final count = page.children.whereType<FieldNode>().length;
      return count > max ? count : max;
    });
    final x2mCount = pages.fold<int>(0, (max, page) {
      final count = page.children.whereType<FieldNode>().where((f) {
        final fd = widget.viewDef.fields[f.name];
        return fd?.type == 'one2many' || fd?.type == 'many2many';
      }).length;
      return count > max ? count : max;
    });
    return (maxFields * 64.0 + x2mCount * 200.0 + 40).clamp(200, 800);
  }

  Widget _unknownField(String name) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text('[$name]', style: const TextStyle(color: Colors.grey, fontSize: 11)),
    );
  }

}

// ─── Sticky button footer ─────────────────────────────────────────────────────

/// Renders root-level form buttons in a fixed footer bar that stays visible
/// while the form content scrolls.
class FormButtonFooter extends StatelessWidget {
  final List<ButtonNode> nodes;
  /// The record whose values the button states use.
  final Record record;
  final Future<void> Function(ButtonNode)? onButton;

  const FormButtonFooter({
    super.key,
    required this.nodes,
    required this.record,
    this.onButton,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final buttons = [
      for (final node in nodes)
        if (!RecordButton.statesOf(node, record).invisible)
          RecordButton(node: node, record: record, onPressed: onButton),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: cs.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: buttons,
      ),
    );
  }
}

/// A `<button>` of a form (SAO `Sao.common.Button.set_state`): `states`
/// evaluated with the record (invisible, readonly, icon); class buttons
/// are disabled while a parent record is unsaved; with `rule` a badge
/// shows the number of clicks (tooltip with the users).
class RecordButton extends StatelessWidget {
  final ButtonNode node;
  final Record record;
  final Future<void> Function(ButtonNode)? onPressed;

  const RecordButton(
      {super.key, required this.node, required this.record, this.onPressed});

  static ({bool invisible, bool readonly, String? icon}) statesOf(
      ButtonNode node, Record record) {
    final evaluated = node.statesRaw == null
        ? const {}
        : record.exprEval(node.statesRaw);
    final states = evaluated is Map ? evaluated : const {};
    final icon = states['icon'];
    return (
      invisible: PYSONEvaluator.truthy(states['invisible']),
      readonly: PYSONEvaluator.truthy(states['readonly']),
      icon: icon is String && icon.isNotEmpty ? icon : node.icon,
    );
  }

  /// A parent record (of an x2many sub-form) is modified.
  static bool _parentModified(Record record) {
    var parent = record.group.parent;
    while (parent != null) {
      if (parent.modified) return true;
      parent = parent.group.parent;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final states = statesOf(node, record);
    if (states.invisible) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final disabled = states.readonly ||
        (!node.isInstance && _parentModified(record)) ||
        record.group.rootGroup.revision != null ||
        onPressed == null;
    final label = node.string ?? node.name;
    final Widget text = node.rule
        ? Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label),
            const SizedBox(width: 6),
            _ClickCounter(record: record, name: node.name),
          ])
        : Text(label);
    final iconName = states.icon;
    void press() => onPressed?.call(node);
    return iconName != null && iconName.isNotEmpty
        ? OutlinedButton.icon(
            icon: TrytonIcon(
              iconName: iconName,
              size: 16,
              color: disabled ? cs.onSurface.withAlpha(97) : cs.primary,
              fallback: Icons.play_circle_outline,
            ),
            label: text,
            onPressed: disabled ? null : press,
          )
        : OutlinedButton(
            onPressed: disabled ? null : press,
            child: text,
          );
  }
}

/// Number of clicks of a button with rules (`ir.model.button.click`
/// `get_click`), tooltip "By: users".
class _ClickCounter extends StatelessWidget {
  final Record record;
  final String name;
  const _ClickCounter({required this.record, required this.name});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: record.getButtonClicks(name).catchError((Object _) => null),
      builder: (context, snapshot) {
        final clicks = snapshot.data;
        final users = clicks is Map
            ? [for (final u in clicks.values) '$u']
            : const <String>[];
        if (users.isEmpty) return const SizedBox.shrink();
        return Tooltip(
          message: context.l10n.buttonClickedBy(users.join(', ')),
          child: Badge(label: Text('${users.length}')),
        );
      },
    );
  }
}

// ─── Grid cell / row ──────────────────────────────────────────────────────────

class _Cell {
  final Widget child;
  final int colspan;

  /// First column of the cell (set when it is placed).
  final int column;
  final bool visible;

  /// `xexpand`: the cell's columns grow (else they take the cell's width).
  final bool expand;
  final double? xalign;
  const _Cell({
    required this.child,
    required this.colspan,
    this.column = 0,
    this.visible = true,
    this.expand = true,
    this.xalign,
  });

  _Cell at(int column, int colspan) => _Cell(
      child: child,
      colspan: colspan,
      column: column,
      visible: visible,
      expand: expand,
      xalign: xalign);
}

/// Grid of a container (spec 9.2.2): rows of cells at fixed columns or
/// full-width widgets. Columns with a visible expanding cell share the
/// width; columns without a visible cell collapse; other columns take
/// their cells' width. On narrow screens (or when the columns would get
/// too narrow) the cells are laid out in one column, the labels above the
/// fields (GTK `client.modepda`, SAO responsive).
class _Grid extends StatelessWidget {
  final List<Object> rows;
  final int cols;
  final bool hbox;

  /// Screen width below which forms use one column.
  static const double narrowWidth = 600;

  /// Minimum width per column before a container wraps.
  static const double _minColWidth = 160.0;

  const _Grid({required this.rows, required this.cols, this.hbox = false});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.maybeSizeOf(context)?.width ?? double.infinity;
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = screenWidth < narrowWidth ||
          (cols > 1 && constraints.maxWidth / _usedCols < _minColWidth);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows)
            if (row is List<_Cell>)
              narrow ? _column(row) : _row(row)
            else
              row as Widget,
        ],
      );
    });
  }

  /// Columns actually used (unused trailing columns collapse, e.g.
  /// `<form col="10">` with groups of colspan 1 in wizards).
  int get _usedCols {
    var used = 1;
    for (final row in rows) {
      if (row is List<_Cell> && row.isNotEmpty) {
        final end = row.last.column + row.last.colspan;
        if (end > used) used = end;
      }
    }
    return used.clamp(1, cols < 1 ? 1 : cols);
  }

  /// Per column: has a visible cell / has a visible expanding cell.
  ({List<bool> visible, List<bool> expand}) _columns() {
    final n = _usedCols;
    final visible = List.filled(n, false);
    final expand = List.filled(n, false);
    for (final row in rows) {
      if (row is! List<_Cell>) continue;
      for (final cell in row) {
        if (!cell.visible) continue;
        for (var c = cell.column; c < cell.column + cell.colspan && c < n; c++) {
          visible[c] = true;
          if (cell.expand) expand[c] = true;
        }
      }
    }
    return (visible: visible, expand: expand);
  }

  Widget _row(List<_Cell> cells) {
    if (cells.every((c) => !c.visible)) return const SizedBox.shrink();
    final columns = _columns();
    final n = columns.visible.length;
    int weight(int from, int to) {
      var w = 0;
      for (var c = from; c < to && c < n; c++) {
        if (columns.expand[c]) w++;
      }
      return w;
    }

    final children = <Widget>[];
    var next = 0;
    void gap(int to) {
      final w = weight(next, to);
      if (w > 0) children.add(Spacer(flex: w));
    }

    for (final cell in cells) {
      gap(cell.column);
      final end = cell.column + cell.colspan;
      final w = weight(cell.column, end);
      final content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: cell.child,
      );
      if (w > 0) {
        // A non-expanding cell in expanding columns keeps its alignment.
        children.add(Expanded(
          flex: w,
          child: cell.expand || cell.xalign == null
              ? content
              : Align(alignment: Alignment(cell.xalign! * 2 - 1, -1), child: content),
        ));
      } else if (cell.visible) {
        // Own width, but never wider than the row (text inputs).
        children.add(Flexible(child: content));
      }
      next = end;
    }
    gap(n);
    if (hbox && children.isNotEmpty && !children.any((c) => c is Expanded || c is Spacer)) {
      children.add(const Spacer());
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  /// One cell per line (narrow screens); labels left aligned above.
  Widget _column(List<_Cell> cells) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final cell in cells)
            if (cell.visible)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: cell.expand
                    ? cell.child
                    : Align(alignment: AlignmentDirectional.centerStart, child: cell.child),
              ),
        ],
      );
}

/// `<group expandable="0|1">` as expander (SAO/GTK `Expander`).
class _GroupExpander extends StatefulWidget {
  final String title;
  final bool initiallyExpanded;
  final Widget child;
  const _GroupExpander(
      {super.key,
      required this.title,
      required this.initiallyExpanded,
      required this.child});

  @override
  State<_GroupExpander> createState() => _GroupExpanderState();
}

class _GroupExpanderState extends State<_GroupExpander> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(_expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 20, color: cs.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(widget.title,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
              ),
            ]),
          ),
        ),
        if (_expanded) widget.child,
      ],
    );
  }
}
