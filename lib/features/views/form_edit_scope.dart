import 'package:flutter/widgets.dart';

/// Inputs of a form report here whether their shown text differs from
/// the value of the record (Python `widget.modified` → `view.modified`,
/// `screen.modified()`): the screen enables Save at the first keystroke,
/// not only when the input writes its value on focus loss.
///
/// The form screen provides it; editable lists and form dialogs block it
/// with [onEdit] null (Python `ListView.modified` is always false, a
/// dialog has its own buttons). Inputs of nested forms (x2many) reach the
/// screen of the parent form, like Python `screen.record_modified` of the
/// parent screens.
class FormEditScope extends InheritedWidget {
  /// [key] identifies the input; [modified]: its text differs from the
  /// record.
  final void Function(Object key, bool modified)? onEdit;

  const FormEditScope({super.key, required this.onEdit, required super.child});

  /// The report function of the nearest scope (null: none or blocked).
  /// Inputs keep it from their build: `dispose` may not look up the
  /// ancestors any more.
  static void Function(Object key, bool modified)? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FormEditScope>()?.onEdit;

  @override
  bool updateShouldNotify(FormEditScope oldWidget) => false;
}
