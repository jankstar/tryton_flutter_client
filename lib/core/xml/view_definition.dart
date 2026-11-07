import 'dart:convert';

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
  /// Field descriptions as sent by `fields_view_get` (for the data layer,
  /// `TrytonModel.addFields`).
  final Map<String, dynamic> rawFields;

  const ViewDefinition({required this.arch, required this.fields, this.viewId, required this.type, this.fieldChilds, this.rawFields = const {}});

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
      rawFields: rawFields,
    );
  }
}

// ─── FormNode hierarchy ───────────────────────────────────────────────────────

/// A node of a form view (spec 9.2.1).
sealed class FormNode {
  /// The XML attributes of the node, converted (spec 9.1: `readonly`,
  /// `homogeneous` → bool; `colspan`, `position`, `height`, `width`,
  /// `xexpand`, `yexpand`, `xfill`, `yfill`, `expand` → int; `xalign`,
  /// `yalign` → double) and, for nodes with a field `name`, completed with
  /// the field description (Python `XMLViewParser._node_attributes`).
  final Map<String, dynamic> attrs;
  const FormNode([this.attrs = const {}]);

  bool? _flag(String name) {
    final v = attrs[name];
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final i = int.tryParse('$v');
    return i == null ? '$v'.toLowerCase() == 'true' : i != 0;
  }

  double? _double(String name) {
    final v = attrs[name];
    return v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
  }

  int? _int(String name) {
    final v = attrs[name];
    return v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  }

  String? _string(String name) {
    final v = attrs[name];
    return v == null ? null : '$v';
  }

  // Layout (spec 9.2.2); null = default of the element.
  bool? get xexpand => _flag('xexpand');
  bool? get xfill => _flag('xfill');
  bool? get yexpand => _flag('yexpand');
  bool? get yfill => _flag('yfill');
  double? get xalign => _double('xalign');
  double? get yalign => _double('yalign');
  int? get height => _int('height');
  int? get width => _int('width');

  /// `id` of a group/page/link (link: the action id).
  String? get id => _string('id');

  /// Tooltip (`help`, of the field when not set).
  String? get help {
    final v = _string('help');
    return v == null || v.isEmpty || v == 'false' ? null : v;
  }

  /// Decoded PYSON `states` (`invisible`, `readonly`, …) or null.
  Map<String, dynamic>? get states {
    final v = attrs['states'];
    if (v is Map) return v.cast<String, dynamic>();
    if (v is String && v.isNotEmpty) {
      try {
        final d = jsonDecode(v);
        if (d is Map) return d.cast<String, dynamic>();
      } catch (_) {}
    }
    return null;
  }
}

class FormRoot extends FormNode {
  /// Columns; ≤ 0 = horizontal box (spec 9.2.2).
  final int col;
  final List<FormNode> children;
  const FormRoot({this.col = 4, required this.children, Map<String, dynamic> attrs = const {}})
      : super(attrs);

  /// Field with the initial focus.
  String? get cursor => _string('cursor');

  /// Method name of `group.on_write`.
  String? get onWrite => _string('on_write');

  /// Records can be created in this view (default true).
  bool get creatable => _flag('creatable') ?? true;

  /// `scan_code` (`one`, `submit`, `loop`) or null.
  String? get scanCode => _string('scan_code');
}

class FieldNode extends FormNode {
  final String name;
  final int colspan;

  /// `widget` of the XML, else the field type (spec 9.1).
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
    Map<String, dynamic> attrs = const {},
    this.colspan = 1,
    this.widget,
    this.readonly,
    this.required,
    this.invisible,
    this.string,
    this.symbol,
  }) : super(attrs);

  /// All attributes (alias of [attrs]; e.g. `view_ids`, `completion`,
  /// `create`, `delete`, `add_remove`, `size`, `mode`).
  Map<String, dynamic> get attributes => attrs;

  /// Views of an x2many field (`mode`, default `tree,form`).
  List<String> get mode => [
        for (final m in (_string('mode') ?? 'tree,form').split(','))
          if (m.trim().isNotEmpty) m.trim()
      ];

  /// `view_ids` (ids; unknown entries as null).
  List<int?> get viewIds => [
        for (final part in (_string('view_ids') ?? '').split(','))
          if (part.trim().isNotEmpty) int.tryParse(part.trim())
      ];

  /// Autocomplete of a many2one (`completion`, default on).
  bool get completion => _flag('completion') ?? true;

  /// `create` / `delete` of relation fields (null = not set).
  bool? get create => _flag('create');
  bool? get delete => _flag('delete');

  /// `product="f1,f2"` of x2many fields.
  List<String> get product => [
        for (final p in (_string('product') ?? '').split(','))
          if (p.trim().isNotEmpty) p.trim()
      ];

  bool get preValidate => _flag('pre_validate') ?? false;

  /// Field holding the file name of a binary field.
  String? get filename => _string('filename');
  bool get filenameVisible => _flag('filename_visible') ?? false;

  /// Spell checking language (PYSON) of text fields.
  dynamic get spell => attrs['spell'];

  /// Display factor of numbers (value × factor).
  num get factor => num.tryParse('${attrs['factor'] ?? 1}') ?? 1;

  /// Thousands grouping of numbers (default on).
  bool get grouping => _flag('grouping') ?? true;

  /// Time `format` (PYSON-encoded string) of date/time fields.
  dynamic get format => attrs['format'];

  /// Sub-view fields of an x2many read with the parent (`visible`).
  bool get visible => _flag('visible') ?? false;
}

class LabelNode extends FormNode {
  final String? fieldName;
  final String? string;
  final int colspan;
  const LabelNode({this.fieldName, this.string, this.colspan = 1, Map<String, dynamic> attrs = const {}})
      : super(attrs);
}

class SeparatorNode extends FormNode {
  final String? string;
  final String? name;
  final int colspan;
  const SeparatorNode({this.string, this.name, this.colspan = 4, Map<String, dynamic> attrs = const {}})
      : super(attrs);
}

class NewlineNode extends FormNode {
  const NewlineNode();
}

class GroupNode extends FormNode {
  /// Columns; ≤ 0 = horizontal box (spec 9.2.2).
  final int col;
  final String? string;
  final int colspan;

  /// `expandable` set: shown as expander ([expanded] = `1`).
  final bool expandable;
  final List<FormNode> children;
  const GroupNode({this.col = 4, this.string, this.colspan = 1, this.expandable = false, required this.children, Map<String, dynamic> attrs = const {}})
      : super(attrs);

  /// Expander initially open (`expandable="1"`).
  bool get expanded => _string('expandable') == '1';

  bool get homogeneous => _flag('homogeneous') ?? false;
}

class NotebookNode extends FormNode {
  final int colspan;
  final List<PageNode> pages;
  const NotebookNode({this.colspan = 4, required this.pages, Map<String, dynamic> attrs = const {}})
      : super(attrs);
}

class PageNode extends FormNode {
  final String string;
  final String? name;
  final List<FormNode> children;

  /// Columns of the page (default 4).
  final int col;

  /// Static invisible flag from `invisible="1"` XML attribute.
  final bool invisibleStatic;

  /// Raw PYSON states dict from `states="..."` XML attribute.
  /// Evaluated at render time against the current field values.
  final Map<String, dynamic>? statesRaw;

  const PageNode({
    required this.string,
    this.name,
    required this.children,
    this.col = 4,
    this.invisibleStatic = false,
    this.statesRaw,
    Map<String, dynamic> attrs = const {},
  }) : super(attrs);

  String? get icon => _string('icon');
}

/// `<link id="<action id>" icon="…" empty="hide"/>` (spec 9.2.1): a
/// button with the action name and counters.
class LinkNode extends FormNode {
  final int colspan;
  const LinkNode({this.colspan = 1, Map<String, dynamic> attrs = const {}}) : super(attrs);

  int? get actionId => _int('id');
  String? get icon => _string('icon');

  /// `empty="hide"`: hidden while all counters are 0.
  bool get hideEmpty => _string('empty') == 'hide';
}

/// `<image name="…" type="icon|url|color" size="48" border="…"/>`.
class ImageNode extends FormNode {
  final int colspan;
  const ImageNode({this.colspan = 1, Map<String, dynamic> attrs = const {}}) : super(attrs);

  /// Icon name, URL, colour – or the name of a field holding it.
  String get name => _string('name') ?? '';

  /// `icon` (default), `url` or `color`.
  String get type => _string('type') ?? 'icon';
  int get size => _int('size') ?? 48;

  /// `rounded` or `circle`.
  String? get border => _string('border');
  String? get urlSize => _string('url_size');
}

class ButtonNode extends FormNode {
  final String name;
  final String? string;
  final int colspan;
  final String? icon;

  /// Decoded PYSON states map – ready for PYSONEvaluator.
  final Map<String, dynamic>? statesRaw;

  /// Confirmation text shown before executing the button action.
  final String? confirm;

  /// Toolbar menu the button also appears in (`action`, `relate`,
  /// `print`; SAO: `keyword || 'action'`).
  final String? keyword;

  /// `instance` (values of [change] sent, changes applied without saving)
  /// or `class` (default: save, then `model.X.<name>(ids)`).
  final String? type;

  /// Fields sent to an instance button (decoded PYSON, evaluated with the
  /// record).
  final dynamic change;

  /// Button with click rules (`ir.model.button.rule`): counter of clicks.
  final bool rule;

  const ButtonNode({
    required this.name,
    this.string,
    this.colspan = 1,
    this.icon,
    this.statesRaw,
    this.confirm,
    this.keyword,
    this.type,
    this.change,
    this.rule = false,
    Map<String, dynamic> attrs = const {},
  }) : super(attrs);

  bool get isInstance => type == 'instance';
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
