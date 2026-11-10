import 'package:flutter/material.dart';

// Label style of the form fields (spec 9.2.2, decision 2026-11-09):
// * wide windows (≥ 600 px): the label before the field (GTK/SAO label
//   cells), the field with an underline only;
// * narrow windows: the floating label in or above the underline.
// Read-only fields have a dotted underline (SAO `theme.less`: `[readonly]`
// → `border-bottom: 2px dotted`), their colours stay as they are.

/// The label style of the fields below (set by `RecordForm`).
class FormLabelScope extends InheritedWidget {
  /// The labels stand before the fields (not in them).
  final bool side;

  /// The fields have an underline instead of a box.
  final bool underline;

  const FormLabelScope({
    super.key,
    required this.side,
    required this.underline,
    required super.child,
  });

  static FormLabelScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FormLabelScope>();

  @override
  bool updateShouldNotify(FormLabelScope old) =>
      old.side != side || old.underline != underline;
}

/// The border of a form field: an underline in forms (dotted when
/// [readOnly]), a box elsewhere.
InputBorder formBorder(BuildContext context, {bool readOnly = false}) =>
    FormLabelScope.of(context)?.underline ?? false
        ? (readOnly
            ? const DottedUnderlineInputBorder()
            : const UnderlineInputBorder())
        : const OutlineInputBorder();

/// [label] of a form field, null when the labels stand before the fields.
T? formLabel<T>(BuildContext context, T? label) =>
    FormLabelScope.of(context)?.side ?? false ? null : label;

/// An underline of dots (read-only form fields). The decorator only
/// changes its colour and width per state, it stays dotted.
class DottedUnderlineInputBorder extends UnderlineInputBorder {
  const DottedUnderlineInputBorder({super.borderSide});

  @override
  DottedUnderlineInputBorder copyWith(
          {BorderSide? borderSide, BorderRadius? borderRadius}) =>
      DottedUnderlineInputBorder(borderSide: borderSide ?? this.borderSide);

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is UnderlineInputBorder
      ? DottedUnderlineInputBorder(
          borderSide: BorderSide.lerp(a.borderSide, borderSide, t))
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) =>
      b is DottedUnderlineInputBorder
          ? DottedUnderlineInputBorder(
              borderSide: BorderSide.lerp(borderSide, b.borderSide, t))
          : super.lerpTo(b, t);

  @override
  void paint(Canvas canvas, Rect rect,
      {double? gapStart,
      double gapExtent = 0.0,
      double gapPercentage = 0.0,
      TextDirection? textDirection}) {
    if (borderSide.style == BorderStyle.none) return;
    // dots as thick as SAO's 2 px (at least the line width)
    final width = borderSide.width < 2 ? 2.0 : borderSide.width;
    final paint = borderSide.toPaint()..strokeWidth = width;
    final y = rect.bottom - width / 2;
    for (var x = rect.left; x < rect.right; x += width * 2) {
      canvas.drawLine(Offset(x, y),
          Offset((x + width).clamp(rect.left, rect.right), y), paint);
    }
  }
}
