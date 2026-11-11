import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays [child] out normally while the width suffices for its minimum
/// intrinsic width; below that (a narrow grid column while resizing) the
/// child gets that minimum and is scaled down to fit instead of
/// overflowing. Unlike `FittedBox` a wide child still fills the width,
/// and intrinsic sizes pass through (FormGrid measures its cells).
class ShrinkToFit extends SingleChildRenderObjectWidget {
  const ShrinkToFit({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderShrinkToFit();
}

class _RenderShrinkToFit extends RenderProxyBox {
  double _scale = 1;

  /// Minimum width of the child, or null when the width suffices.
  double? _needed(BoxConstraints constraints) {
    final child = this.child;
    if (child == null || !constraints.hasBoundedWidth) return null;
    final min = child.getMinIntrinsicWidth(double.infinity);
    return min > constraints.maxWidth + 0.01 && constraints.maxWidth > 0
        ? min
        : null;
  }

  BoxConstraints _childConstraints(BoxConstraints constraints, double need) =>
      BoxConstraints.tightFor(width: need).copyWith(
        minHeight: 0,
        maxHeight: constraints.hasBoundedHeight
            ? constraints.maxHeight * need / constraints.maxWidth
            : double.infinity,
      );

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    final need = _needed(constraints);
    if (need == null) {
      _scale = 1;
      child.layout(constraints, parentUsesSize: true);
      size = child.size;
      return;
    }
    _scale = constraints.maxWidth / need;
    child.layout(_childConstraints(constraints, need), parentUsesSize: true);
    size = constraints.constrain(
        Size(constraints.maxWidth, child.size.height * _scale));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    final need = _needed(constraints);
    if (need == null) return child.getDryLayout(constraints);
    final childSize = child.getDryLayout(_childConstraints(constraints, need));
    final scale = constraints.maxWidth / need;
    return constraints.constrain(
        Size(constraints.maxWidth, childSize.height * math.min(1, scale)));
  }

  Matrix4 get _transform => Matrix4.diagonal3Values(_scale, _scale, 1);

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (_scale >= 1) return super.paint(context, offset);
    layer = context.pushTransform(needsCompositing, offset, _transform,
        (context, offset) => context.paintChild(child!, offset),
        oldLayer: layer is TransformLayer ? layer as TransformLayer : null);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (_scale < 1) transform.multiply(_transform);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    if (_scale >= 1) return child.hitTest(result, position: position);
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }
}
