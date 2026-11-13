import 'package:flutter/material.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart';
import '../../core/pyson/pyson_evaluator.dart';
import '../../core/xml/view_definition.dart';
import '../../shared/widgets/field_widget.dart';
import '../../shared/widgets/shrink_to_fit.dart';
import '../model/field_definition.dart';
import 'embedded_tree_widget.dart';
import 'fill_column.dart';
import 'form_edit_scope.dart';
import 'form_grid.dart';
import 'record_binary_widgets.dart';
import 'record_field_widgets.dart';
import 'record_richtext.dart';
import 'record_link.dart';
import 'record_many2one.dart';
import 'record_widget_values.dart';
import 'form_label_style.dart';

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

  /// Fields whose typed text differs from the record, reported to the
  /// [FormEditScope] (Python `widget.modified`).
  final Set<String> _edited = {};
  void Function(Object key, bool modified)? _report;

  @override
  void didUpdateWidget(RecordForm old) {
    super.didUpdateWidget(old);
    // the text typed belonged to the record shown before
    if (!identical(old.record, widget.record)) _clearEdits();
  }

  @override
  void dispose() {
    _clearEdits();
    super.dispose();
  }

  void _clearEdits() {
    for (final name in _edited) {
      _report?.call((this, name), false);
    }
    _edited.clear();
  }

  /// A keystroke in the text input of [name]: kept by the host until
  /// focus loss; Save is enabled at once when the text differs from the
  /// record (Python `send_modified`).
  void _typed(String name, dynamic value) {
    widget.onTextChanged(name, value);
    final modified = !_sameValue(value, _record.fieldGetClient(name));
    if (modified ? _edited.add(name) : _edited.remove(name)) {
      _report?.call((this, name), modified);
    }
  }

  /// Focus loss of the text input of [name]: the host writes the value.
  void _left(String name) {
    widget.onBlur(name);
    if (_edited.remove(name)) {
      _report?.call((this, name), false);
    }
  }

  static bool _sameValue(dynamic a, dynamic b) {
    bool empty(dynamic v) => v == null || v == '';
    if (empty(a) || empty(b)) return empty(a) && empty(b);
    if (a == b) return true;
    if (a is num && b is num) return a == b;
    return a.toString() == b.toString();
  }

  @override
  Widget build(BuildContext context) {
    _report = FormEditScope.of(context);
    _values = recordWidgetValues(_record);
    final side = _sideLabels;
    return Theme(
      data: compactFormTheme(Theme.of(context)),
      child: FormLabelScope(
        side: side,
        underline: true,
        child: _renderNodes(widget.root.children, _safeCol(widget.root.col)),
      ),
    );
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
  /// Fields with a `<label>` anywhere in the form (the label may stand in
  /// another container than its field).
  late final Set<String> _labelledFields = _labelsOf(widget.root.children);

  static Set<String> _labelsOf(List<FormNode> nodes) => {
        for (final node in nodes)
          ...switch (node) {
            LabelNode(:final fieldName?) => {fieldName},
            GroupNode() => _labelsOf(node.children),
            NotebookNode() => _labelsOf(node.pages),
            PageNode() => _labelsOf(node.children),
            _ => const <String>{},
          },
      };

  /// On wide windows the labels stand in their own cells before the
  /// fields (GTK/SAO, spec 9.2.2); narrow ones float in the field.
  bool get _sideLabels =>
      MediaQuery.sizeOf(context).width >= _Grid.narrowWidth;

  Widget _renderNodes(List<FormNode> nodes, int col) {
    final hbox = col <= 0;
    final side = _sideLabels;
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

    // Rows of cells; a notebook or separator is a full-width row.
    final rows = <List<_Cell>>[];
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
      if (!side &&
          node is LabelNode &&
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
        // (a notebook takes the remaining height, yexpand default 1)
        rows.add([cell.at(0, col, full: true)]);
        continue;
      }

      final cell = _cellOf(node, hbox ? 1 : col,
          extraColspan: node is FieldNode && !side
              ? labelColspanMap[node.name] ?? 0
              : 0,
          hbox: hbox,
          labelled: node is FieldNode && _labelledFields.contains(node.name));
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
      cols: hbox ? rows.fold(1, (m, r) => r.length > m ? r.length : m) : col,
      hbox: hbox,
    );
  }

  /// [nodes] (or their groups) contain a `<field>` named [name].
  static bool _hasField(List<FormNode> nodes, String name) => nodes.any((n) =>
      (n is FieldNode && n.name == name) ||
      (n is GroupNode && _hasField(n.children, name)));

  /// The cell of [node] in a container of [col] columns (null: no cell).
  /// [labelled]: a `<label>` of the field stands in the same container.
  _Cell? _cellOf(FormNode node, int col, {int extraColspan = 0,
    bool hbox = false, bool labelled = false}) {
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
    // Invisible cells keep their position but are not built.
    final visible = !_isInvisible(node);
    var child = visible ? _buildNode(node) : const SizedBox.shrink();
    if (child == null) return null;
    // a field without label cell keeps its label in the field (wide
    // windows; nothing is lost when the XML has no `<label>`)
    if (node is FieldNode && !labelled && _sideLabels) {
      child = FormLabelScope(side: false, underline: true, child: child);
    }
    // In a horizontal box an input gets a natural width instead of the
    // whole line (spec 9.2.2); checkboxes keep their own width.
    if (hbox && visible && node is FieldNode) {
      final maxWidth = _hboxWidth(node);
      if (maxWidth != null) {
        child = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        );
      }
    }
    // Natural width per widget (spec 9.2.2): numbers, dates, booleans
    // and char with `size` do not fill their cell; the grid gives the
    // cells of a column the same width (amounts stay one below the other).
    double? naturalWidth;
    if (!hbox && visible && node is FieldNode) {
      final type = widget.viewDef.fields[node.name]?.type;
      if (type == 'boolean') {
        child = Align(
          alignment: AlignmentDirectional.centerStart,
          child: child,
        );
      } else {
        naturalWidth =
            _naturalWidth(node, labelInField: !(labelled && _sideLabels));
      }
    }
    // Labels and separator texts do not expand (xexpand 0), everything
    // else does (default xexpand = 1).
    final defaultExpand = node is! LabelNode;
    // yexpand (spec 9.2.2): notebooks and x2many lists take the
    // remaining height of the form
    var fill = false;
    if (node is NotebookNode) fill = node.yexpand ?? true;
    if (node is FieldNode) {
      final type = widget.viewDef.fields[node.name]?.type;
      // an x2many shown first as form (e.g. the addresses of the party)
      // keeps its natural height, like SAO
      fill =
          (type == 'one2many' || type == 'many2many') &&
          node.mode.firstOrNull != 'form' &&
          (node.yexpand ?? true);
    }
    return _Cell(
      child: visible ? _sized(node, child) : const SizedBox.shrink(),
      colspan: colspan,
      visible: visible,
      expand: node.xexpand ?? defaultExpand,
      xalign: node.xalign ?? (node is LabelNode ? 1.0 : null),
      fill: fill,
      naturalWidth: naturalWidth,
      labelFor: node is LabelNode ? node.fieldName : null,
      field: node is FieldNode ? node.name : null,
      shrinks: hbox && node is FieldNode && _hboxWidth(node) != null,
      // GTK: the size request of labels, buttons and groups is met first
      need: node is LabelNode || node is ButtonNode
          ? FormGridNeed.natural
          : node is GroupNode
              ? FormGridNeed.content
              // a field of natural width (date, number) keeps it: a long
              // label beside it must not squeeze it
              : node is FieldNode && naturalWidth != null
                  ? FormGridNeed.natural
              : node is FieldNode &&
                      const {'many2one', 'one2one', 'reference'}.contains(
                          widget.viewDef.fields[node.name]?.type) &&
                      node.widget != 'selection'
                  ? FormGridNeed.relation
              : node is FieldNode &&
                      naturalWidth == null &&
                      !const {'one2many', 'many2many'}.contains(
                          node.widget ?? widget.viewDef.fields[node.name]?.type)
                  ? FormGridNeed.input
                  : FormGridNeed.none,
    );
  }

  /// Natural width of the input of [node] in a horizontal box (null:
  /// its own width, e.g. a checkbox): numbers 120, others 220 px, never
  /// narrower than the floating label; lists and texts the whole line.
  double? _hboxWidth(FieldNode node) {
    final fd = widget.viewDef.fields[node.name];
    if (fd == null) return 220;
    final type = node.widget ?? fd.type;
    if (type == 'boolean') return null;
    // lists and multi-line texts fill the box (GTK `expand`)
    if (const {'one2many', 'many2many', 'text', 'richtext'}.contains(fd.type) ||
        const {'text', 'richtext'}.contains(type)) {
      return double.infinity;
    }
    final label = fd.label.length * 8.5 + 40;
    final width =
        const {'integer', 'float', 'numeric', 'timedelta'}.contains(type)
        ? 120.0
        : 220.0;
    return width > label ? width : label;
  }

  /// Natural width of the input of [node] in a grid cell (null: fills
  /// the cell), spec 9.2.2 „Natürliche Breite je Widget“: numbers 8
  /// characters, dates their format, char with `size` min(120, size)
  /// characters; never narrower than the floating label.
  /// [labelInField]: the floating label is in the field, so the field is
  /// not narrower than its label.
  double? _naturalWidth(FieldNode node, {bool labelInField = true}) {
    final fd = widget.viewDef.fields[node.name];
    if (fd == null) return null;
    const charWidth = 8.5, padding = 40.0;
    final type = node.widget ?? fd.type;
    double? width;
    if (const {'integer', 'float', 'numeric', 'timedelta'}.contains(type)) {
      width = 8 * charWidth + padding + 20; // + symbol
    } else if (type == 'date') {
      width = 10 * charWidth + padding + 40; // + calendar button
    } else if (type == 'datetime') {
      width = 19 * charWidth + padding + 40;
    } else if (type == 'time') {
      width = 8 * charWidth + padding + 40;
    } else if (type == 'char' &&
        (widget.viewDef.rawFields[node.name] as Map?)?['size'] is int) {
      final size = (widget.viewDef.rawFields[node.name] as Map)['size'] as int;
      width = (size < 120 ? size : 120) * charWidth + padding;
    }
    if (width == null) return null;
    if (!labelInField) return width;
    final label = fd.label.length * charWidth + padding;
    return width > label ? width : label;
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
        // the label of the excluded parent field (x2many form) too
        if (name != null && name == widget.excludeField) return true;
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
        padding: const EdgeInsets.symmetric(vertical: _fieldGap),
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
        padding: const EdgeInsets.symmetric(vertical: _fieldGap),
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
      onText: (v) => _typed(node.name, v),
      onBlur: () => _left(node.name),
      onValue: (v) => widget.onChangedImmediate(node.name, v),
    );
    var special = _recordWidget(fd, node, args);
    if (special != null) {
      // scrolling lists, the PDF preview and the rich text editor have no
      // intrinsic sizes (a group's minimum asks them; they expand anyway)
      if (const {'image', 'document', 'richtext'}.contains(node.widget) ||
          fd.type == 'multiselection') {
        special = GridIntrinsicBarrier(child: special);
      }
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: _fieldGap), child: special);
    }

    // Text-input fields: kept locally on keystroke, written to the record
    // (on_change) only on blur – like SAO's focus_out event.
    // Single-action fields (selection, date, many2one, boolean): written
    // immediately since there is no "typing" involved.
    final isTextInput = fd.type == 'char' || fd.type == 'text' ||
        fd.type == 'integer' || fd.type == 'float' || fd.type == 'numeric';

    // (FieldWidget has its own _fieldGap above and below)

    final Widget input = FieldWidget(
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
            ? (v) => _typed(node.name, v)
            : (v) => widget.onChangedImmediate(node.name, v),
        onBlur: isTextInput ? () => _left(node.name) : null,
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
    _left(node.name);
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
      case 'image':
        return RecordImageField(args: args);
      case 'document':
        return RecordDocumentField(args: args);
      case 'richtext':
        return RecordRichTextField(args: args);
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
      case 'binary':
        return RecordBinaryField(args: args);
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
    // the title is part of the widget's header (Python One2Many); the
    // list gets the height given to the field (yexpand)

    return FillColumn(
      children: [
        const SizedBox(height: 8),
        FillChild(
          child:
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline.withAlpha(80)),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.all(8),
          // The child group of the record (spec 9.2.7); saved with the
          // parent through the x2many commands.
          // a list needs no minimum width in the grid (and its
          // LayoutBuilder has no intrinsic sizes)
          child: GridIntrinsicBarrier(child: EmbeddedTreeWidget(
            key: ValueKey('x2m_${fd.name}'),
            parent: _record,
            fieldDef: fd,
            node: node,
            readOnly: readOnly,
            // the records follow the parent record, not the field state
            parentReadOnly: widget.isReadOnly,
            breadcrumb: widget.breadcrumb,
            )),
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
    // labels before the fields: as high as the text of an input
    final side = _sideLabels && name != null;
    return Padding(
      padding: EdgeInsets.only(top: side ? 13 : 8, right: 4),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
        style: (side
                ? Theme.of(context).textTheme.bodyMedium
                : Theme.of(context).textTheme.bodySmall)
            ?.copyWith(
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

  /// Notebook: tabs and the selected page in its natural height (spec
  /// 9.2.2: no own scroll area and no fixed height, nothing cut off – the
  /// form scrolls as a whole).

  Widget _buildNotebook(NotebookNode node) {
    // Filter pages based on their states/invisible conditions
    final visiblePages = node.pages.where((p) => !_isInvisible(p)).toList();
    if (visiblePages.isEmpty) return const SizedBox.shrink();

    return _NotebookView(
      pages: visiblePages,
      tab:(p) =>
                Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (p.icon != null) ...[
                      TrytonIcon(iconName: p.icon, size: 16),
                      const SizedBox(width: 6),
                    ],
                    Text(_pageLabel(p)),
                  ]),
                ),
      page: (p
          ) => _renderNodes(p.children, _safeCol(p.col)
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

  Widget _unknownField(String name) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text('[$name]', style: const TextStyle(color: Colors.grey, fontSize: 11)),
    );
  }

}

// ─── Button footer ────────────────────────────────────────────────────────────

/// The buttons of a form in a fixed footer below the scroll area (always
/// visible, also while scrolling): the buttons of the form's top level
/// and of its top-level groups that hold only buttons (e.g. the workflow
/// group of an invoice), see [FormButtonFooter.split]. One line per
/// button text, the footer wraps into several lines when needed.
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

  /// The footer buttons of [root] and the root without them.
  static ({List<ButtonNode> buttons, FormRoot content}) split(FormRoot root) {
    bool onlyButtons(FormNode node) =>
        node is GroupNode &&
        node.children.isNotEmpty &&
        node.children.every((c) => c is ButtonNode || onlyButtons(c));
    Iterable<ButtonNode> buttonsOf(FormNode node) sync* {
      if (node is ButtonNode) yield node;
      if (node is GroupNode) {
        for (final c in node.children) {
          yield* buttonsOf(c);
        }
      }
    }

    final buttons = <ButtonNode>[];
    final rest = <FormNode>[];
    for (final node in root.children) {
      if (node is ButtonNode || onlyButtons(node)) {
        buttons.addAll(buttonsOf(node));
      } else {
        rest.add(node);
      }
    }
    if (buttons.isEmpty) return (buttons: buttons, content: root);
    return (
      buttons: buttons,
      content: FormRoot(col: root.col, children: rest, attrs: root.attrs),
    );
  }

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
      key: const ValueKey('form-button-footer'),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: cs.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      // many buttons on a narrow window wrap into lines: at most about a
      // third of the window high, then scrolling (no overflow of the form)
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height / 3),
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: buttons,
          ),
        ),
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
    // one line, never wrapped (shortened when there is no room)
    final caption = Text(
      label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
    final Widget text = node.rule
        ? Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: caption),
            const SizedBox(width: 6),
            _ClickCounter(record: record, name: node.name),
          ])
        : caption;
    final iconName = states.icon;
    void press() => onPressed?.call(node);
    // a grid column narrower than the button (resizing): scaled down
    // instead of overflowing
    return ShrinkToFit(child: iconName != null && iconName.isNotEmpty
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
          ));
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

  /// `yexpand` of a notebook or a list: takes the remaining height.
  final bool fill;

  /// Natural width of the input (null: fills the cell), spec 9.2.2.
  final double? naturalWidth;

  /// A full-width row (notebook, separator).
  final bool full;

  /// The field a label cell belongs to / the field of a field cell (a
  /// label stays beside its field in a horizontal box).
  final String? labelFor;
  final String? field;

  /// In a horizontal box the input may shrink to the line (not a
  /// checkbox).
  final bool shrinks;

  /// The width the cell needs in the grid (labels, buttons: natural;
  /// groups: their content).
  final FormGridNeed need;

  const _Cell({
    required this.child,
    required this.colspan,
    this.column = 0,
    this.visible = true,
    this.expand = true,
    this.xalign,
    this.fill = false,
    this.naturalWidth,
    this.full = false,
    this.labelFor,
    this.field,
    this.shrinks = false,
    this.need = FormGridNeed.none,
  });

  _Cell at(int column, int colspan, {bool full = false}) => _Cell(
      child: child,
      colspan: colspan,
      column: column,
      visible: visible,
      expand: expand,
      xalign: xalign,
      fill: fill,
      naturalWidth: naturalWidth,
      full: full,
      labelFor: labelFor,
      field: field,
      shrinks: shrinks,
      need: need);
}

/// Grid of a container (spec 9.2.2): rows of cells at fixed columns or
/// full-width rows, laid out by [FormGrid] (column widths the same in all
/// rows). Only in a narrow window (< [narrowWidth]) the cells are laid out
/// in one column (GTK `client.modepda`, SAO responsive).
class _Grid extends StatelessWidget {
  final List<List<_Cell>> rows;
  final int cols;
  final bool hbox;

  /// Screen width below which forms use one column.
  static const double narrowWidth = 600;

  const _Grid({required this.rows, required this.cols, this.hbox = false});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.maybeSizeOf(context)?.width ?? double.infinity;
    // one column only by the width of the window, never by the width of a
    // single container (spec 9.2.2)
    final narrow = screenWidth < narrowWidth;
    if (hbox) return _box(narrow);
    if (narrow) {
      // rows in their natural height; the yexpand rows (notebook, list)
      // share a remaining height
      return FillColumn(children: [
        for (final row in rows)
          if (row.length == 1 && row.single.full)
            _fullRow(row.single)
          else
            _column(row),
      ]);
    }
    final naturalWidths = _naturalWidths();
    return FormGrid(
      columns: _usedCols,
      children: [
        for (final (i, row) in rows.indexed)
          for (final cell in row)
            if (cell.visible)
              FormGridCell(
                row: i,
                column: cell.column,
                colspan: cell.colspan,
                expand: cell.expand,
                xalign: cell.xalign,
                fill: cell.fill,
                full: cell.full,
                need: cell.need,
                child: cell.full
                    ? cell.child
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _natural(cell, naturalWidths, cell.child),
                      ),
              ),
      ],
    );
  }

  /// A horizontal box (`col ≤ 0`): natural widths, not stretched; a box
  /// holding only a list (e.g. a notebook page `col="-1"` with one
  /// x2many) passes the remaining height on to it (yexpand).
  Widget _box(bool narrow) {
    final visible = [
      for (final row in rows)
        for (final c in row)
          if (c.visible) c,
    ];
    if (visible.length == 1 && visible.single.fill) {
      return FillColumn(children: [
        FillChild(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: visible.single.child,
          ),
        ),
      ]);
    }
    return Column(
      crossAxisAlignment:
          narrow ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          if (row.length == 1 && row.single.full)
            row.single.visible ? row.single.child : const SizedBox.shrink()
          else
            _line(row),
      ],
    );
  }

  /// A full-width row in the narrow layout (a notebook takes the
  /// remaining height).
  Widget _fullRow(_Cell cell) {
    if (!cell.visible) return const SizedBox.shrink();
    return cell.fill ? FillChild(child: cell.child) : cell.child;
  }

  /// The widest natural width per first column: inputs of a column get
  /// the same width, so amounts stand one below the other.
  Map<int, double> _naturalWidths() {
    final widths = <int, double>{};
    for (final row in rows) {
      for (final cell in row) {
        final w = cell.naturalWidth;
        if (w == null || !cell.visible) continue;
        final current = widths[cell.column];
        if (current == null || w > current) widths[cell.column] = w;
      }
    }
    return widths;
  }

  /// The input of [cell] in its natural width ([widths]: per column).
  Widget _natural(_Cell cell, Map<int, double> widths, Widget child) {
    if (cell.naturalWidth == null) return child;
    final width = widths[cell.column] ?? cell.naturalWidth!;
    // a fixed width (the column limits it) – also as intrinsic width, a
    // parent grid sizes a group with it (FormGridNeed.content); the Align
    // keeps the child's width (widthFactor), else the grid would measure
    // the whole offered width as natural width of the column
    return Align(
      alignment: AlignmentDirectional.topStart,
      widthFactor: 1,
      child: SizedBox(width: width, child: child),
    );
  }

  /// Columns actually used (unused trailing columns collapse, e.g.
  /// `<form col="10">` with groups of colspan 1 in wizards).
  int get _usedCols {
    var used = 1;
    for (final row in rows) {
      if (row.isEmpty || row.last.full) continue;
      final end = row.last.column + row.last.colspan;
      if (end > used) used = end;
    }
    return used.clamp(1, cols < 1 ? 1 : cols);
  }

  /// A horizontal box (`col ≤ 0`, spec 9.2.2): the cells side by side in
  /// their natural width, wrapping only when the line is full – also in
  /// the narrow layout.
  Widget _line(List<_Cell> cells) {
    // a label and its field stay together when the line wraps
    final children = <Widget>[];
    final visible = [for (final c in cells) if (c.visible) c];
    for (var i = 0; i < visible.length; i++) {
      final cell = visible[i];
      final next = i + 1 < visible.length ? visible[i + 1] : null;
      if (cell.labelFor != null && next != null && next.field == cell.labelFor) {
        // (the field takes at most the rest of the line)
        children.add(Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(child: cell.child),
            if (next.shrinks) Flexible(child: next.child) else next.child,
          ],
        ));
        i++;
      } else {
        children.add(cell.child);
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }

  /// One cell per line (narrow screens); labels left aligned above.
  Widget _column(List<_Cell> cells) {
    final naturalWidths = _naturalWidths();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final cell in cells)
          if (cell.visible)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _natural(
                  cell,
                  naturalWidths,
                  cell.expand
                      ? cell.child
                      : Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: cell.child)),
            ),
      ],
    );
  }
}

/// Tabs of a notebook and the selected page in its natural height.
class _NotebookView extends StatefulWidget {
  final List<PageNode> pages;
  final Widget Function(PageNode page) tab;
  final Widget Function(PageNode page) page;

  const _NotebookView({
    required this.pages,
    required this.tab,
    required this.page,
  });

  @override
  State<_NotebookView> createState() => _NotebookViewState();
}

class _NotebookViewState extends State<_NotebookView>
    with TickerProviderStateMixin {
  late TabController _controller = _create(0);

  TabController _create(int index) => TabController(
    length: widget.pages.length,
    initialIndex: index.clamp(0, widget.pages.length - 1),
    vsync: this,
  )..addListener(_onTab);

  void _onTab() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(_NotebookView old) {
    super.didUpdateWidget(old);
    // pages shown/hidden by their states: keep the selected index
    if (old.pages.length != widget.pages.length) {
      final index = _controller.index;
      _controller.dispose();
      _controller = _create(index);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = _controller.index;
    // the page gets the remaining height of the notebook (yexpand)
    return FillColumn(
      children: [
        const SizedBox(height: 8),
        TabBar(
          controller: _controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final p in widget.pages) widget.tab(p)],
        ),
        FillChild(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: KeyedSubtree(
              key: ValueKey('page-$index'),
              child: widget.page(widget.pages[index]),
            ),
          ),
        ),
      ],
    );
  }
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

/// Theme of forms: 14 pt text and labels, dense inputs with less padding
/// (compact like the reference clients).
/// Space above and below every field of a form: the same for all widget
/// kinds, so the inputs of a row line up (FieldWidget's own padding).
const double _fieldGap = 4;

ThemeData compactFormTheme(ThemeData theme) {
  final text = theme.textTheme;
  return theme.copyWith(
    textTheme: text.copyWith(
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 14),
      titleMedium: text.titleMedium?.copyWith(fontSize: 14),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 13),
    ),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      // the buttons of many2one fields without the 48 px tap target (one
      // height for all single-line inputs)
      prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    ),
    // checkboxes 40 px like the inputs (no 48 px tap target)
    checkboxTheme: theme.checkboxTheme
        .copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
  );
}
