import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// Grid of a form container (spec 9.2.2, GTK `Container`): the column
// widths are computed once for all rows, so cells of the same columns line
// up in every row.

/// Position and behaviour of a child of [FormGrid].
class FormGridCell extends ParentDataWidget<_GridParentData> {
  /// Row of the cell (rows are laid out in ascending order).
  final int row;

  /// First column and number of columns of the cell.
  final int column;
  final int colspan;

  /// `xexpand`: the cell's columns share the free width.
  final bool expand;

  /// Horizontal position of a cell narrower than its columns (0 = start,
  /// 1 = end); null: an expanding cell fills its columns.
  final double? xalign;

  /// `yexpand` (notebook, list): the cell's row takes a share of the
  /// remaining height.
  final bool fill;

  /// A full-width row (notebook, separator): the whole width of the grid,
  /// no influence on the column widths.
  final bool full;

  const FormGridCell({
    super.key,
    required this.row,
    required this.column,
    required this.colspan,
    this.expand = true,
    this.xalign,
    this.fill = false,
    this.full = false,
    required super.child,
  });

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _GridParentData;
    if (data.row != row ||
        data.column != column ||
        data.colspan != colspan ||
        data.expand != expand ||
        data.xalign != xalign ||
        data.fill != fill ||
        data.full != full) {
      data
        ..row = row
        ..column = column
        ..colspan = colspan
        ..expand = expand
        ..xalign = xalign
        ..fill = fill
        ..full = full;
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => FormGrid;
}

class _GridParentData extends ContainerBoxParentData<RenderBox> {
  int row = 0;
  int column = 0;
  int colspan = 1;
  bool expand = true;
  double? xalign;
  bool fill = false;
  bool full = false;
}

/// Cells ([FormGridCell]) in [columns] columns (spec 9.2.2):
///
/// * columns without a cell collapse;
/// * columns with an expanding cell share the free width equally;
/// * the other columns take the natural width of their cells (at most
///   half of the grid each), the same in every row;
/// * rows have the height of their highest cell; given a minimum height
///   larger than the content (the visible height of the form), the rows
///   with a `fill` cell share the remaining height.
class FormGrid extends MultiChildRenderObjectWidget {
  final int columns;

  const FormGrid({super.key, required this.columns, required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFormGrid(columns);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderFormGrid).columns = columns;
  }
}

class _RenderFormGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _GridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _GridParentData> {
  _RenderFormGrid(this._columns);

  int _columns;
  set columns(int value) {
    if (value == _columns) return;
    _columns = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GridParentData) {
      child.parentData = _GridParentData();
    }
  }

  /// The cells placed in columns (not the full-width rows).
  List<RenderBox> get _cells =>
      [for (final c in _children) if (!_data(c).full) c];

  List<RenderBox> get _children {
    final result = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      result.add(child);
      child = (child.parentData! as _GridParentData).nextSibling;
    }
    return result;
  }

  static _GridParentData _data(RenderBox child) =>
      child.parentData! as _GridParentData;

  int get _n {
    var n = math.max(_columns, 1);
    for (final child in _cells) {
      final d = _data(child);
      n = math.max(n, d.column + d.colspan);
    }
    return n;
  }

  /// Columns with an expanding cell.
  List<bool> _expanding(int n) {
    final expand = List.filled(n, false);
    for (final child in _cells) {
      final d = _data(child);
      if (!d.expand) continue;
      for (var c = d.column; c < d.column + d.colspan; c++) {
        expand[c] = true;
      }
    }
    return expand;
  }

  /// Column widths for the grid width [width] (infinite: natural widths).
  List<double> _columnWidths(double width, int n) {
    final expand = _expanding(n);
    final widths = List.filled(n, 0.0);
    final bounded = width.isFinite;
    final maxNatural = bounded ? width / 2 : double.infinity;
    // natural widths of the cells in columns that do not expand (single
    // columns first, then the cells over several columns)
    final fixed = [
      for (final child in _cells)
        if (!bounded ||
            !Iterable.generate(_data(child).colspan, (i) => _data(child).column + i)
                .any((c) => expand[c]))
          child,
    ]..sort((a, b) => _data(a).colspan.compareTo(_data(b).colspan));
    for (final child in fixed) {
      final d = _data(child);
      child.layout(BoxConstraints(maxWidth: maxNatural), parentUsesSize: true);
      final natural = child.size.width;
      var current = 0.0;
      for (var c = d.column; c < d.column + d.colspan; c++) {
        current += widths[c];
      }
      if (natural > current) widths[d.column + d.colspan - 1] += natural - current;
    }
    if (!bounded) return widths;
    // minimum of an expanding column: its widest non-expanding cell of
    // one column (e.g. a label beside a field over several columns; spec
    // 9.2.2 `minmax(min-content, fr)`)
    final minimum = List.filled(n, 0.0);
    for (final child in _cells) {
      final d = _data(child);
      if (d.colspan != 1 || d.expand || !expand[d.column]) continue;
      child.layout(BoxConstraints(maxWidth: maxNatural), parentUsesSize: true);
      minimum[d.column] = math.max(minimum[d.column], child.size.width);
    }
    var used = widths.fold(0.0, (a, b) => a + b);
    if (used > width) {
      // more fixed width than there is: shrink all fixed columns
      final factor = width / used;
      for (var c = 0; c < n; c++) {
        widths[c] *= factor;
      }
      used = width;
    }
    // the expanding columns share the rest equally; a column whose minimum
    // is larger keeps its minimum and leaves the others the remainder
    final pool = {for (var c = 0; c < n; c++) if (expand[c]) c};
    var rest = width - used;
    while (pool.isNotEmpty) {
      final share = rest / pool.length;
      final wider = [for (final c in pool) if (minimum[c] > share) c];
      if (wider.isEmpty) {
        for (final c in pool) {
          widths[c] = share;
        }
        break;
      }
      for (final c in wider) {
        widths[c] = minimum[c];
        rest -= minimum[c];
        pool.remove(c);
      }
      if (rest < 0) rest = 0;
    }
    return widths;
  }

  /// Lays out [child] in its columns ([span] wide), at least [minHeight]
  /// high.
  void _layoutCell(RenderBox child, double span, double minHeight,
      bool spanExpands) {
    final d = _data(child);
    // an expanding cell (or one without own alignment in expanding
    // columns) fills its columns; others keep their natural width
    final tight = d.full || spanExpands && (d.expand || d.xalign == null);
    child.layout(
      BoxConstraints(
        minWidth: tight ? span : 0,
        maxWidth: span,
        minHeight: minHeight,
      ),
      parentUsesSize: true,
    );
  }

  @override
  void performLayout() {
    final children = _children;
    final n = _n;
    final width = constraints.maxWidth;
    final widths = _columnWidths(width, n);
    final expand = _expanding(n);
    final starts = List.filled(n + 1, 0.0);
    for (var c = 0; c < n; c++) {
      starts[c + 1] = starts[c] + widths[c];
    }
    final gridWidth = width.isFinite ? width : starts[n];
    double spanOf(_GridParentData d) =>
        d.full ? gridWidth : starts[d.column + d.colspan] - starts[d.column];
    bool expands(_GridParentData d) =>
        d.full ||
        Iterable.generate(d.colspan, (i) => d.column + i).any((c) => expand[c]);

    // rows in their natural height
    final rows = <int, double>{};
    final fillRows = <int>{};
    for (final child in children) {
      final d = _data(child);
      _layoutCell(child, spanOf(d), 0, expands(d));
      rows[d.row] = math.max(rows[d.row] ?? 0, child.size.height);
      if (d.fill) fillRows.add(d.row);
    }
    // the remaining height for the rows with a list/notebook (yexpand)
    final total = rows.values.fold(0.0, (a, b) => a + b);
    final extra = constraints.minHeight - total;
    if (extra > 0 && fillRows.isNotEmpty) {
      final share = extra / fillRows.length;
      for (final row in fillRows) {
        rows[row] = rows[row]! + share;
      }
      for (final child in children) {
        final d = _data(child);
        if (d.fill) _layoutCell(child, spanOf(d), rows[d.row]!, expands(d));
      }
    }
    final order = rows.keys.toList()..sort();
    final tops = <int, double>{};
    var y = 0.0;
    for (final row in order) {
      tops[row] = y;
      y += rows[row]!;
    }
    for (final child in children) {
      final d = _data(child);
      final free = spanOf(d) - child.size.width;
      final align = d.xalign ?? 0;
      final x = d.full ? 0.0 : starts[d.column];
      d.offset = Offset(x + (free > 0 ? free * align : 0), tops[d.row]!);
    }
    size = constraints.constrain(Size(gridWidth, y));
  }

  /// Per row the sum of [f] over its cells; the widest row.
  double _widestRow(double Function(RenderBox) f) {
    final rows = <int, double>{};
    for (final child in _children) {
      final d = _data(child);
      rows[d.row] = (rows[d.row] ?? 0) + f(child);
    }
    return rows.values.fold(0.0, math.max);
  }

  /// Per row the highest of [f] over its cells; the sum of the rows.
  double _rowHeights(double width, double Function(RenderBox, double) f) {
    final n = _n;
    final rows = <int, double>{};
    for (final child in _children) {
      final d = _data(child);
      final w = !width.isFinite
          ? double.infinity
          : d.full
              ? width
              : width * d.colspan / n;
      rows[d.row] = math.max(rows[d.row] ?? 0, f(child, w));
    }
    return rows.values.fold(0.0, (a, b) => a + b);
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _widestRow((c) => c.getMinIntrinsicWidth(double.infinity));
  @override
  double computeMaxIntrinsicWidth(double height) =>
      _widestRow((c) => c.getMaxIntrinsicWidth(double.infinity));
  @override
  double computeMinIntrinsicHeight(double width) =>
      _rowHeights(width, (c, w) => c.getMinIntrinsicHeight(w));
  @override
  double computeMaxIntrinsicHeight(double width) =>
      _rowHeights(width, (c, w) => c.getMaxIntrinsicHeight(w));

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
      Size(constraints.maxWidth, computeMaxIntrinsicHeight(constraints.maxWidth)));

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
