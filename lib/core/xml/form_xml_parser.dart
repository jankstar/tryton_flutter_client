import 'dart:convert';

import 'package:xml/xml.dart';

import 'view_definition.dart';

/// Parses the Tryton `arch` XML string into a `FormNode` hierarchy. With
/// [fields] (the `fields` of `fields_view_get`) the attributes of nodes
/// with a field `name` are completed from the field description (spec 9.1,
/// Python `XMLViewParser._node_attributes`).
class FormXmlParser {
  /// Attributes taken from the field description when the XML has none.
  static const fieldAttributes = [
    'relation', 'domain', 'selection', 'string', 'states',
    'relation_field', 'views', 'invisible', 'add_remove', 'sort',
    'context', 'size', 'filename', 'autocomplete', 'translate', 'create',
    'delete', 'selection_change_with', 'schema_model', 'required',
    'help_selection', 'help_field', 'order', 'symbol', 'monetary',
  ];

  static const _boolAttributes = {'readonly', 'homogeneous'};
  static const _intAttributes = {
    'yexpand', 'yfill', 'xexpand', 'xfill', 'colspan', 'position',
    'height', 'width', 'expand',
  };
  static const _doubleAttributes = {'xalign', 'yalign'};

  Map<String, dynamic> _fields = const {};

  FormRoot parse(String arch, {Map<String, dynamic> fields = const {}}) {
    _fields = fields;
    final doc = XmlDocument.parse(arch);
    final root = doc.rootElement;
    final attrs = _attributes(root);
    return FormRoot(
        col: _col(root, 4), children: _parseChildren(root), attrs: attrs);
  }

  /// `col` as given; ≤ 0 = horizontal box (spec 9.2.2).
  int _col(XmlElement el, int defaultValue) =>
      int.tryParse(el.getAttribute('col') ?? '') ?? defaultValue;

  /// Converted and completed attributes of [el].
  Map<String, dynamic> _attributes(XmlElement el) {
    final attrs = <String, dynamic>{
      for (final a in el.attributes) a.localName: a.value
    };
    for (final name in attrs.keys.toList()) {
      final value = attrs[name] as String;
      if (_boolAttributes.contains(name)) {
        attrs[name] = (int.tryParse(value) ?? (value == 'True' ? 1 : 0)) != 0;
      } else if (_intAttributes.contains(name)) {
        attrs[name] = int.tryParse(value) ??
            (value == 'True' ? 1 : (value == 'False' ? 0 : null));
        if (attrs[name] == null) attrs.remove(name);
      } else if (_doubleAttributes.contains(name)) {
        final d = double.tryParse(value);
        if (d == null) {
          attrs.remove(name);
        } else {
          attrs[name] = d;
        }
      }
    }
    final name = attrs['name'];
    final field = name is String ? _fields[name] : null;
    if (field is Map) {
      attrs.putIfAbsent('widget', () => field['type']);
      final tag = el.name.local;
      if (tag == 'label' && !attrs.containsKey('string')) {
        attrs['string'] = '${field['string'] ?? name}:';
      }
      if (tag == 'field' && !attrs.containsKey('help')) {
        attrs['help'] = field['help'];
      }
      for (final key in fieldAttributes) {
        if (field.containsKey(key)) attrs.putIfAbsent(key, () => field[key]);
      }
    }
    return attrs;
  }

  /// A JSON attribute (PYSON encoded by the server); null if absent or
  /// not JSON.
  static dynamic _json(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  int _colspan(XmlElement el, [int defaultValue = 1]) {
    final raw = int.tryParse(el.getAttribute('colspan') ?? '') ?? defaultValue;
    return raw < 1 ? 1 : raw;
  }

  List<FormNode> _parseChildren(XmlElement parent) {
    final nodes = <FormNode>[];
    for (final child in parent.childElements) {
      final node = _parseNode(child);
      if (node != null) nodes.add(node);
    }
    return nodes;
  }

  FormNode? _parseNode(XmlElement el) {
    switch (el.name.local) {
      case 'field':
        final attrs = _attributes(el);
        return FieldNode(
          name: el.getAttribute('name') ?? '',
          colspan: _colspan(el),
          widget: attrs['widget'] as String?,
          readonly: _parseBool(el.getAttribute('readonly')),
          required: _parseBool(el.getAttribute('required')),
          invisible: _parseBool(el.getAttribute('invisible')),
          string: el.getAttribute('string'),
          symbol: el.getAttribute('symbol'),
          attrs: attrs,
        );

      case 'label':
        return LabelNode(
          fieldName: el.getAttribute('name'),
          string: el.getAttribute('string'),
          colspan: _colspan(el),
          attrs: _attributes(el),
        );

      case 'separator':
        return SeparatorNode(
          string: el.getAttribute('string'),
          name: el.getAttribute('name'),
          colspan: _colspan(el, 4),
          attrs: _attributes(el),
        );

      case 'newline':
        return const NewlineNode();

      case 'link':
        return LinkNode(colspan: _colspan(el), attrs: _attributes(el));

      case 'image':
        return ImageNode(colspan: _colspan(el), attrs: _attributes(el));

      case 'group':
        final expandable = el.getAttribute('expandable');
        return GroupNode(
          col: _col(el, 4),
          string: el.getAttribute('string'),
          colspan: _colspan(el),
          expandable: expandable != null && expandable.isNotEmpty,
          children: _parseChildren(el),
          attrs: _attributes(el),
        );

      case 'notebook':
        final pages = el.childElements
            .where((c) => c.name.local == 'page')
            .map(_parsePage)
            .toList();
        return NotebookNode(
          colspan: _colspan(el, 4),
          pages: pages,
          attrs: _attributes(el),
        );

      case 'button':
        final btnStatesStr = el.getAttribute('states');
        Map<String, dynamic>? btnStatesRaw;
        if (btnStatesStr != null && btnStatesStr.isNotEmpty) {
          try {
            final d = jsonDecode(btnStatesStr);
            if (d is Map<String, dynamic>) btnStatesRaw = d;
          } catch (_) {}
        }
        return ButtonNode(
          name: el.getAttribute('name') ?? '',
          string: el.getAttribute('string'),
          colspan: _colspan(el),
          icon: el.getAttribute('icon'),
          statesRaw: btnStatesRaw,
          confirm: el.getAttribute('confirm'),
          keyword: el.getAttribute('keyword'),
          type: el.getAttribute('type'),
          change: _json(el.getAttribute('change')),
          rule: (int.tryParse(el.getAttribute('rule') ?? '') ?? 0) != 0,
          attrs: _attributes(el),
        );

      case 'hpaned':
      case 'vpaned':
        // Treat as group: hpaned side by side, vpaned one below the other
        return GroupNode(
          col: el.name.local == 'hpaned' ? 2 : 1,
          colspan: _colspan(el, 4),
          children: _parseChildren(el),
          attrs: {'yexpand': 1, 'yfill': 1, ..._attributes(el)},
        );

      case 'child':
        return GroupNode(
          col: _col(el, 4),
          colspan: 1,
          children: _parseChildren(el),
          attrs: _attributes(el),
        );

      default:
        return null;
    }
  }

  PageNode _parsePage(XmlElement el) {
    // Static invisible from attribute invisible="1"
    final invAttr = el.getAttribute('invisible');
    final invisibleStatic =
        invAttr == '1' || invAttr?.toLowerCase() == 'true';

    // PYSON states from states="{...}" attribute
    // The value is a JSON string: e.g. '{"invisible": {"__class__": "Equal", ...}}'
    Map<String, dynamic>? statesRaw;
    final statesStr = el.getAttribute('states');
    if (statesStr != null && statesStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(statesStr);
        if (decoded is Map<String, dynamic>) statesRaw = decoded;
      } catch (_) {
        // Non-JSON states string (Python literal) → ignore, handle as invisible
        // if contains 'invisible' keyword heuristically
      }
    }

    final nameAttr = el.getAttribute('name');
    final stringAttr = el.getAttribute('string');
    // Like SAO: if no 'string' attribute, fall back to 'name' as tab label
    final displayString = (stringAttr != null && stringAttr.isNotEmpty)
        ? stringAttr
        : (nameAttr ?? '');

    return PageNode(
      string: displayString,
      name: nameAttr,
      col: _col(el, 4),
      children: _parseChildren(el),
      invisibleStatic: invisibleStatic,
      statesRaw: statesRaw,
      attrs: _attributes(el),
    );
  }

  bool? _parseBool(String? s) {
    if (s == null) return null;
    return s == '1' || s.toLowerCase() == 'true';
  }
}

/// Parses a tree-view `arch` into a `TreeViewDefinition`.
class TreeXmlParser {
  TreeViewDefinition parse(String arch, Map<String, dynamic> fields) {
    final doc = XmlDocument.parse(arch);
    final root = doc.rootElement;
    final editable = root.getAttribute('editable') == '1';
    final visual = root.getAttribute('visual');

    final columns = <TreeColumn>[];
    for (final child in root.childElements) {
      if (child.name.local != 'field') continue;
      final name = child.getAttribute('name') ?? '';
      if (name.isEmpty) continue;
      final fieldDef = fields[name] as Map<String, dynamic>?;
      final label = child.getAttribute('string') ??
          fieldDef?['string']?.toString() ??
          name;
      final invisible = child.getAttribute('tree_invisible');
      columns.add(TreeColumn(
        name: name,
        label: label,
        widget: child.getAttribute('widget'),
        treeInvisible: invisible == '1' || invisible == 'true',
        sum: child.getAttribute('sum'),
        expand: child.getAttribute('expand') == '1',
      ));
    }

    return TreeViewDefinition(
      columns: columns,
      fields: {},
      editable: editable,
      visual: visual,
    );
  }
}
