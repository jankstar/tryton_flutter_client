import 'package:flutter/material.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart';
import '../../core/pyson/pyson_evaluator.dart';
import '../../core/xml/view_definition.dart';
import '../../shared/widgets/field_widget.dart';
import '../model/field_definition.dart';
import 'embedded_tree_widget.dart';
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


  // Tryton can use col="-1" or col="0" for flexible layouts.
  // We normalise to at least 1 (default: 4).
  static int _safeCol(int col) => col < 1 ? 4 : col;

  Widget _renderNodes(List<FormNode> nodes, int totalCol) {
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

    final rows = <Widget>[];
    final currentRow = <_Cell>[];
    int currentColUsed = 0;

    void flushRow() {
      if (currentRow.isEmpty) return;
      rows.add(_GridRow(cells: List.from(currentRow), totalCols: totalCol));
      currentRow.clear();
      currentColUsed = 0;
    }

    for (final node in nodes) {
      // LabelNode with field name → skip (field shows label internally)
      if (node is LabelNode && node.fieldName != null) continue;

      if (node is NewlineNode) {
        flushRow();
        continue;
      }
      if (node is NotebookNode) {
        flushRow();
        rows.add(_buildNotebook(node));
        continue;
      }
      if (node is SeparatorNode) {
        flushRow();
        rows.add(_buildSeparator(node));
        continue;
      }

      final w = _buildNode(node, totalCol);
      if (w == null) continue;

      // Field colspan + absorbed label colspan
      int colspan = _getColspan(node, totalCol);
      if (node is FieldNode) {
        final extra = labelColspanMap[node.name] ?? 0;
        colspan = (colspan + extra).clamp(1, totalCol);
        // one2many / many2many tables always need full width – force it even
        // when the XML omits an explicit colspan (Tryton forms always intend
        // this, but our parser defaults to 1).
        final fd = widget.viewDef.fields[node.name];
        if (fd != null && (fd.type == 'one2many' || fd.type == 'many2many')) {
          colspan = totalCol;
        }
      }

      if (currentColUsed + colspan > totalCol) flushRow();
      currentRow.add(_Cell(child: w, colspan: colspan));
      currentColUsed += colspan;

      if (colspan >= totalCol) flushRow();
    }
    flushRow();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget? _buildNode(FormNode node, int totalCol) {
    if (node is FieldNode) return _buildField(node);
    if (node is LabelNode) return _buildLabel(node);
    if (node is GroupNode) return _buildGroup(node);
    if (node is ButtonNode) return _buildButton(node);
    return null;
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
      return _buildX2ManyField(fd, field, readOnly);
    }

    // Text-input fields: kept locally on keystroke, written to the record
    // (on_change) only on blur – like SAO's focus_out event.
    // Single-action fields (selection, date, many2one, boolean): written
    // immediately since there is no "typing" involved.
    final isTextInput = fd.type == 'char' || fd.type == 'text' ||
        fd.type == 'integer' || fd.type == 'float' || fd.type == 'numeric';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: FieldWidget(
        field: fd,
        value: _values[node.name],
        readOnly: readOnly,
        isRequired: PYSONEvaluator.truthy(attrs['required']),
        invalid: invalid,
        recordValues: _values,
        searchDomain: field is Many2OneField ? field.getDomain(_record) : null,
        // XML attr takes precedence; fall back to fields_get 'symbol'.
        symbolField: node.symbol ?? fd.symbol,
        // Resolve the relation model of the symbol field so _NumericField
        // can call get_symbol without hardcoding 'res.currency'.
        symbolRelation: _resolveSymbolRelation(node.symbol ?? fd.symbol),
        // widget= override from XML arch (e.g. "url", "email", "password").
        widgetOverride: node.widget,
        model: widget.model,
        onChanged: isTextInput
            ? (v) => widget.onTextChanged(node.name, v)
            : (v) => widget.onChangedImmediate(node.name, v),
        onBlur: isTextInput ? () => widget.onBlur(node.name) : null,
      ),
    );
  }

  /// Returns the relation model name of a symbol field (e.g. 'res.currency').
  String? _resolveSymbolRelation(String? symbolFieldName) {
    if (symbolFieldName == null) return null;
    return widget.viewDef.fields[symbolFieldName]?.relation;
  }

  Widget _buildX2ManyField(FieldDefinition fd, Field field, bool readOnly) {

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
            readOnly: readOnly,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildLabel(LabelNode node) {
    // Hide label for a field if the field itself is invisible
    if (node.fieldName != null) {
      final field = _record.model.fields[node.fieldName!];
      if (field != null &&
          PYSONEvaluator.truthy(_stateAttrs(field)['invisible'])) {
        return const SizedBox.shrink();
      }
    }

    String text;
    if (node.string != null) {
      text = node.string!;
    } else if (node.fieldName != null) {
      text = widget.viewDef.fields[node.fieldName!]?.label ?? node.fieldName!;
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 4),
      child: Text(
        '$text:',
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
        textAlign: TextAlign.right,
      ),
    );
  }

  Widget _buildSeparator(SeparatorNode node) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        if (node.string != null) ...[
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

  Widget _buildGroup(GroupNode node) {
    final inner = _renderNodes(node.children, _safeCol(node.col));
    if (node.string != null) {
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
    final visiblePages = node.pages.where(_isPageVisible).toList();
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
            tabs: visiblePages.map((p) => Tab(text: _pageLabel(p))).toList(),
          ),
          SizedBox(
            height: _estimateNotebookHeight(visiblePages),
            child: TabBarView(
              children: visiblePages.map((page) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 8),
                  child: _renderNodes(page.children, _safeCol(widget.root.col)),
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

  /// Returns true when the page should be shown.
  /// Evaluates static `invisible` attribute and PYSON `states` against
  /// the current field values – same logic as SAO's page visibility check.
  bool _isPageVisible(PageNode page) {
    // Static invisible="1" → always hidden
    if (page.invisibleStatic) return false;

    // PYSON states evaluation
    if (_nodeStates(page.statesRaw).invisible) return false;

    return true;
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

  int _getColspan(FormNode node, int totalCol) {
    final maxCol = _safeCol(totalCol); // Prevents clamp(1, 0) or clamp(1, -1)
    if (node is FieldNode) return node.colspan.clamp(1, maxCol);
    if (node is LabelNode) return node.colspan.clamp(1, maxCol);
    if (node is GroupNode) return node.colspan.clamp(1, maxCol);
    if (node is ButtonNode) return node.colspan.clamp(1, maxCol);
    return 1;
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
  const _Cell({required this.child, required this.colspan});
}

class _GridRow extends StatelessWidget {
  final List<_Cell> cells;
  final int totalCols;

  /// Minimum pixel width per base column. When the available width divided by
  /// totalCols falls below this value, the effective column count is reduced
  /// so that fields wrap to the next line instead of becoming too narrow.
  static const double _minColWidth = 160.0;

  const _GridRow({required this.cells, required this.totalCols});

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        // How many base columns fit at the minimum width?
        final effectiveCols =
            (available / _minColWidth).floor().clamp(1, totalCols);

        if (effectiveCols >= totalCols) {
          return _buildRow(cells, totalCols);
        }
        // Re-layout: scale each colspan to the reduced column count and wrap.
        return _buildWrapped(cells, totalCols, effectiveCols);
      },
    );
  }

  Widget _buildRow(List<_Cell> rowCells, int cols) {
    if (rowCells.isEmpty) return const SizedBox.shrink();
    final usedCols = rowCells.fold(0, (s, c) => s + c.colspan);

    if (rowCells.length == 1 && usedCols >= cols) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: rowCells.first.child,
      );
    }

    final children = <Widget>[];
    for (final cell in rowCells) {
      children.add(Expanded(
        flex: cell.colspan,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: cell.child,
        ),
      ));
    }
    final remaining = cols - usedCols;
    if (remaining > 0) children.add(Spacer(flex: remaining));
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _buildWrapped(
      List<_Cell> allCells, int origCols, int effectiveCols) {
    final rows = <Widget>[];
    final curRow = <_Cell>[];
    int curUsed = 0;

    void flush() {
      if (curRow.isEmpty) return;
      rows.add(_buildRow(List.from(curRow), effectiveCols));
      curRow.clear();
      curUsed = 0;
    }

    for (final cell in allCells) {
      // Scale colspan proportionally; always at least 1, at most effectiveCols.
      final scaled =
          ((cell.colspan * effectiveCols) / origCols).ceil().clamp(1, effectiveCols);
      if (curUsed + scaled > effectiveCols) flush();
      curRow.add(_Cell(child: cell.child, colspan: scaled));
      curUsed += scaled;
      if (curUsed >= effectiveCols) flush();
    }
    flush();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}
