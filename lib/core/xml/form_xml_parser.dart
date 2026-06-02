import 'dart:convert';

import 'package:xml/xml.dart';

import 'view_definition.dart';

/// Parses the Tryton `arch` XML string into a `FormNode` hierarchy.
class FormXmlParser {
  FormRoot parse(String arch) {
    final doc = XmlDocument.parse(arch);
    final root = doc.rootElement;
    final col = _col(root, 4);
    return FormRoot(col: col, children: _parseChildren(root));
  }

  // Tryton can use col="-1" for flexible layouts → normalise.
  int _col(XmlElement el, int defaultValue) {
    final raw = int.tryParse(el.getAttribute('col') ?? '') ?? defaultValue;
    return raw < 1 ? defaultValue : raw;
  }

  int _colspan(XmlElement el) {
    final raw = int.tryParse(el.getAttribute('colspan') ?? '') ?? 1;
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
        return FieldNode(
          name: el.getAttribute('name') ?? '',
          colspan: _colspan(el),
          widget: el.getAttribute('widget'),
          readonly: _parseBool(el.getAttribute('readonly')),
          required: _parseBool(el.getAttribute('required')),
          invisible: _parseBool(el.getAttribute('invisible')),
          string: el.getAttribute('string'),
          symbol: el.getAttribute('symbol'),
        );

      case 'label':
        return LabelNode(
          fieldName: el.getAttribute('name'),
          string: el.getAttribute('string'),
          colspan: _colspan(el),
        );

      case 'separator':
        return SeparatorNode(
          string: el.getAttribute('string'),
          colspan: _colspan(el),
        );

      case 'newline':
        return const NewlineNode();

      case 'group':
        return GroupNode(
          col: _col(el, 4),
          string: el.getAttribute('string'),
          colspan: _colspan(el),
          expandable: el.getAttribute('expandable') == '1',
          children: _parseChildren(el),
        );

      case 'notebook':
        final pages = el.childElements
            .where((c) => c.name.local == 'page')
            .map(_parsePage)
            .toList();
        return NotebookNode(
          colspan: _colspan(el),
          pages: pages,
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
          states: btnStatesStr,
          statesRaw: btnStatesRaw,
        );

      case 'hpaned':
      case 'vpaned':
        // Treat as group
        return GroupNode(
          col: 2,
          colspan: _colspan(el),
          children: _parseChildren(el),
        );

      case 'child':
        return GroupNode(
          col: _col(el, 4),
          colspan: 1,
          children: _parseChildren(el),
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
      children: _parseChildren(el),
      invisibleStatic: invisibleStatic,
      statesRaw: statesRaw,
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

    final columns = <TreeColumn>[];
    for (final child in root.childElements) {
      if (child.name.local != 'field') continue;
      final name = child.getAttribute('name') ?? '';
      if (name.isEmpty) continue;
      final fieldDef = fields[name] as Map<String, dynamic>?;
      final label = child.getAttribute('string') ??
          fieldDef?['string']?.toString() ??
          name;
      columns.add(TreeColumn(
        name: name,
        label: label,
        widget: child.getAttribute('widget'),
      ));
    }

    final fieldDefs = <String, dynamic>{};
    for (final col in columns) {
      if (fields.containsKey(col.name)) fieldDefs[col.name] = fields[col.name];
    }

    return TreeViewDefinition(
      columns: columns,
      fields: {},
      editable: editable,
    );
  }
}
