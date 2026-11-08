import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// yexpand of forms (spec 9.2.2 „Höhe und Scrollen“): a column whose
// marked children take the remaining height of the visible area.

/// Marks a child of [FillColumn] that takes the remaining height.
class FillChild extends ParentDataWidget<_FillParentData> {
  const FillChild({super.key, required super.child});

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _FillParentData;
    if (!data.fill) {
      data.fill = true;
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => FillColumn;
}

class _FillParentData extends ContainerBoxParentData<RenderBox> {
  bool fill = false;
}

/// A column of children in their natural height (spec 9.2.2 „Höhe und
/// Scrollen“). Given a minimum height larger than its content (the
/// visible height of the form), the [FillChild]ren (yexpand: notebook,
/// lists) share the remaining height; otherwise the column grows and the
/// form scrolls as a whole.
class FillColumn extends MultiChildRenderObjectWidget {
  const FillColumn({super.key, required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFillColumn();
}

class _RenderFillColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FillParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FillParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FillParentData) child.parentData = _FillParentData();
  }

  BoxConstraints _childConstraints(BoxConstraints constraints) =>
      constraints.hasBoundedWidth
          ? BoxConstraints.tightFor(width: constraints.maxWidth)
          : const BoxConstraints();

  @override
  void performLayout() {
    final childConstraints = _childConstraints(constraints);
    var total = 0.0;
    var width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    final fills = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      child.layout(childConstraints, parentUsesSize: true);
      total += child.size.height;
      if (!constraints.hasBoundedWidth && child.size.width > width) {
        width = child.size.width;
      }
      final data = child.parentData! as _FillParentData;
      if (data.fill) fills.add(child);
      child = data.nextSibling;
    }
    final extra = constraints.minHeight - total;
    if (extra > 0 && fills.isNotEmpty) {
      final share = extra / fills.length;
      for (final f in fills) {
        f.layout(
            childConstraints.copyWith(
                minHeight: f.size.height + share, maxHeight: double.infinity),
            parentUsesSize: true);
      }
    }
    var y = 0.0;
    child = firstChild;
    while (child != null) {
      final data = child.parentData! as _FillParentData;
      data.offset = Offset(0, y);
      y += child.size.height;
      child = data.nextSibling;
    }
    size = constraints.constrain(Size(width, y));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final childConstraints = _childConstraints(constraints);
    var total = 0.0;
    var width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    var child = firstChild;
    while (child != null) {
      final s = child.getDryLayout(childConstraints);
      total += s.height;
      if (!constraints.hasBoundedWidth && s.width > width) width = s.width;
      child = (child.parentData! as _FillParentData).nextSibling;
    }
    return constraints.constrain(Size(width, total));
  }

  double _sum(double Function(RenderBox) f) {
    var total = 0.0;
    var child = firstChild;
    while (child != null) {
      total += f(child);
      child = (child.parentData! as _FillParentData).nextSibling;
    }
    return total;
  }

  double _max(double Function(RenderBox) f) {
    var max = 0.0;
    var child = firstChild;
    while (child != null) {
      final v = f(child);
      if (v > max) max = v;
      child = (child.parentData! as _FillParentData).nextSibling;
    }
    return max;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _sum((c) => c.getMinIntrinsicHeight(width));
  @override
  double computeMaxIntrinsicHeight(double width) =>
      _sum((c) => c.getMaxIntrinsicHeight(width));
  @override
  double computeMinIntrinsicWidth(double height) =>
      _max((c) => c.getMinIntrinsicWidth(double.infinity));
  @override
  double computeMaxIntrinsicWidth(double height) =>
      _max((c) => c.getMaxIntrinsicWidth(double.infinity));

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
