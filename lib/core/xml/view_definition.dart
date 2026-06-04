import '../../features/model/field_definition.dart';

// ─── ViewDefinition ───────────────────────────────────────────────────────────

class ViewDefinition {
  final String arch;
  final Map<String, FieldDefinition> fields;
  final int? viewId;
  final String type; // 'form' | 'tree' | 'graph' | ...
  /// Field name of the child records (One2Many). Only for hierarchical trees.
  /// SAO: `field_childs` in the `fields_view_get` response.
  final String? fieldChilds;

  const ViewDefinition({required this.arch, required this.fields, this.viewId, required this.type, this.fieldChilds});

  factory ViewDefinition.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'] as Map<String, dynamic>? ?? {};
    final fields = rawFields.map((k, v) => MapEntry(k, FieldDefinition.fromJson(k, v as Map<String, dynamic>)));
    return ViewDefinition(
      arch: json['arch'] as String? ?? '<form/>',
      fields: fields,
      viewId: json['view_id'] as int?,
      type: json['type'] as String? ?? 'form',
      // field_childs is a field name (String) or false/null (no tree).
      // Tryton returns Python False as JSON false → do not cast to String?!
      fieldChilds: json['field_childs'] is String && (json['field_childs'] as String).isNotEmpty
          ? json['field_childs'] as String
          : null,
    );
  }
}

// ─── FormNode hierarchy ───────────────────────────────────────────────────────

sealed class FormNode {
  const FormNode();
}

class FormRoot extends FormNode {
  final int col;
  final List<FormNode> children;
  const FormRoot({this.col = 4, required this.children});
}

class FieldNode extends FormNode {
  final String name;
  final int colspan;
  final String? widget;
  final bool? readonly;
  final bool? required;
  final bool? invisible;
  final String? string; // Label override
  /// Name of the sibling field that holds the currency/unit reference.
  // ignore: unintended_html_in_doc_comment
  /// SAO: `symbol` XML attribute on <field>. E.g. symbol="currency" means
  /// the record has a `currency` Many2One whose rec_name provides the symbol.
  final String? symbol;
  const FieldNode({
    required this.name,
    this.colspan = 1,
    this.widget,
    this.readonly,
    this.required,
    this.invisible,
    this.string,
    this.symbol,
  });
}

class LabelNode extends FormNode {
  final String? fieldName;
  final String? string;
  final int colspan;
  const LabelNode({this.fieldName, this.string, this.colspan = 1});
}

class SeparatorNode extends FormNode {
  final String? string;
  final int colspan;
  const SeparatorNode({this.string, this.colspan = 4});
}

class NewlineNode extends FormNode {
  const NewlineNode();
}

class GroupNode extends FormNode {
  final int col;
  final String? string;
  final int colspan;
  final bool expandable;
  final List<FormNode> children;
  const GroupNode({this.col = 4, this.string, this.colspan = 1, this.expandable = false, required this.children});
}

class NotebookNode extends FormNode {
  final int colspan;
  final List<PageNode> pages;
  const NotebookNode({this.colspan = 4, required this.pages});
}

class PageNode extends FormNode {
  final String string;
  final String? name;
  final List<FormNode> children;

  /// Static invisible flag from `invisible="1"` XML attribute.
  final bool invisibleStatic;

  /// Raw PYSON states dict from `states="..."` XML attribute.
  /// Evaluated at render time against the current field values.
  final Map<String, dynamic>? statesRaw;

  const PageNode({
    required this.string,
    this.name,
    required this.children,
    this.invisibleStatic = false,
    this.statesRaw,
  });
}

class ButtonNode extends FormNode {
  final String name;
  final String? string;
  final int colspan;
  final String? icon;
  final String? states;

  /// Decoded PYSON states map – ready for PYSONEvaluator.
  final Map<String, dynamic>? statesRaw;

  /// Confirmation text shown before executing the button action.
  final String? confirm;
  const ButtonNode({
    required this.name,
    this.string,
    this.colspan = 1,
    this.icon,
    this.states,
    this.statesRaw,
    this.confirm,
  });
}

// ─── TreeColumn (for tree views) ──────────────────────────────────────────────

class TreeViewDefinition {
  final List<TreeColumn> columns;
  final Map<String, FieldDefinition> fields;
  final bool editable;

  /// PYSON expression for row color: evaluates to 'success', 'warning', 'danger' or ''.
  final String? visual;

  const TreeViewDefinition({required this.columns, required this.fields, this.editable = false, this.visual});
}

class TreeColumn {
  final String name;
  final String label;
  final int width; // 0 = flexible
  final String? widget;

  /// If true, column is hidden by default (tree_invisible="1").
  final bool treeInvisible;

  /// Label for the sum footer row (sum="Total").
  final String? sum;

  /// If true, column expands to fill available space.
  final bool expand;
  const TreeColumn({
    required this.name,
    required this.label,
    this.width = 0,
    this.widget,
    this.treeInvisible = false,
    this.sum,
    this.expand = false,
  });
}
