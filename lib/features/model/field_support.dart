import '../../core/xml/view_definition.dart';
import 'field_definition.dart';

/// Field types without an own widget yet (E13). They are shown as a
/// read-only placeholder and never sent to write/create.
const unsupportedFieldTypes = {
  'binary',
  'dict',
  'reference',
  'multiselection',
  'timedelta',
  'time',
};

/// `widget=` attributes without an own widget yet (E13), e.g.
/// `<field name="photo" widget="image"/>` or a char with `widget="color"`.
const unsupportedWidgets = {
  ...unsupportedFieldTypes,
  'image',
  'document',
  'richtext',
  'html',
  'color',
  'pyson',
};

/// True when [type] / [widget] has no own representation in this client.
bool isUnsupportedField(String type, [String? widget]) =>
    unsupportedFieldTypes.contains(type) || unsupportedWidgets.contains(widget);

/// Names of fields that must not be written because the user cannot edit
/// them correctly: unsupported type, or every occurrence in [root] uses an
/// unsupported widget (a supported second occurrence keeps it editable).
Set<String> unsupportedFieldNames(
  Map<String, FieldDefinition> fields, [
  FormRoot? root,
]) {
  final result = {
    for (final e in fields.entries)
      if (isUnsupportedField(e.value.type)) e.key,
  };
  if (root == null) return result;

  final widgetsByField = <String, List<String?>>{};
  void walk(List<FormNode> nodes) {
    for (final node in nodes) {
      switch (node) {
        case FieldNode():
          (widgetsByField[node.name] ??= []).add(node.widget);
        case GroupNode():
          walk(node.children);
        case NotebookNode():
          for (final page in node.pages) {
            walk(page.children);
          }
        case PageNode():
          walk(node.children);
        case FormRoot():
          walk(node.children);
        default:
          break;
      }
    }
  }

  walk(root.children);
  for (final MapEntry(key: name, value: widgets) in widgetsByField.entries) {
    if (widgets.every((w) => unsupportedWidgets.contains(w))) result.add(name);
  }
  return result;
}
