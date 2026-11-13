import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// Grid of a form container (spec 9.2.2, GTK `Container`): the column
// widths are computed once for all rows, so cells of the same columns line
// up in every row.

/// What a cell needs at least in its columns (GTK: the size request of
/// the child is met before the free width is shared).
enum FormGridNeed {
  /// Nothing (inputs fill what they get).
  none,

  /// Its natural width on one line (labels, buttons).
  natural,

  /// Its minimum content (a group: the needs of its own cells).
  content,

  /// [formGridInputWidth] (an input that reports no width of its own,
  /// e.g. a selection – GTK: the size request of an entry).
  input,

  /// [formGridRelationWidth] (many2one/reference: buttons beside the
  /// text).
  relation,
}

/// The least width of an input ([FormGridNeed.input]).
const formGridInputWidth = 80.0;

/// The least width of a many2one/reference ([FormGridNeed.relation]): its
/// open/clear buttons and a few characters.
const formGridRelationWidth = 110.0;

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

  /// The width the cell needs in its columns before the free width is
  /// shared (labels, buttons, groups; also over several columns).
  final FormGridNeed need;

  const FormGridCell({
    super.key,
    required this.row,
    required this.column,
    required this.colspan,
    this.expand = true,
    this.xalign,
    this.fill = false,
    this.full = false,
    this.need = FormGridNeed.none,
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
        data.full != full ||
        data.need != need) {
      data
        ..row = row
        ..column = column
        ..colspan = colspan
        ..expand = expand
        ..xalign = xalign
        ..fill = fill
        ..full = full
        ..need = need;
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
  FormGridNeed need = FormGridNeed.none;
}

/// Answers 0 for the intrinsic sizes of [child] (widths and heights) and
/// the smallest size for a dry layout, without asking it: a list (x2many)
/// contains a LayoutBuilder, which has none, and needs no minimum in the
/// grid. (A group's minimum width asks its column, which asks the heights
/// of its children – e.g. a many2many in a titled group of a wizard.)
class GridIntrinsicBarrier extends SingleChildRenderObjectWidget {
  const GridIntrinsicBarrier({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderIntrinsicBarrier();
}

class _RenderIntrinsicBarrier extends RenderProxyBox {
  @override
  double computeMinIntrinsicWidth(double height) => 0;
  @override
  double computeMaxIntrinsicWidth(double height) => 0;
  @override
  double computeMinIntrinsicHeight(double width) => 0;
  @override
  double computeMaxIntrinsicHeight(double width) => 0;
  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.smallest;
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
      // labels and buttons keep their line (up to the whole width)
      child.layout(
          BoxConstraints(
              maxWidth: d.need == FormGridNeed.natural ? width : maxNatural),
          parentUsesSize: true);
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
    // the needs of labels, buttons and groups (also over several columns)
    // in the expanding columns – GTK meets them before sharing; the needs
    // of single cells (labels) are kept first when the width is short
    final multi = _addNeeds(minimum, widths, expand,
        (c) => c.getMaxIntrinsicWidth(double.infinity),
        (c) => c.getMinIntrinsicWidth(double.infinity));
    var used = widths.fold(0.0, (a, b) => a + b);
    if (used > width) {
      // more fixed width than there is: shrink all fixed columns
      final factor = width / used;
      for (var c = 0; c < n; c++) {
        widths[c] *= factor;
      }
      used = width;
    }
    // the needs of the expanding columns (e.g. a date beside a long
    // label) before the fixed columns' full line: a fixed column gives
    // width down to its longest word (the label wraps)
    final deficit = [for (var c = 0; c < n; c++) if (expand[c]) minimum[c]]
            .fold(0.0, (a, b) => a + b) -
        (width - used);
    if (deficit > 0) {
      final least = List.filled(n, 0.0);
      for (final child in fixed) {
        final d = _data(child);
        if (d.colspan != 1) continue;
        least[d.column] = math.max(
            least[d.column], child.getMinIntrinsicWidth(double.infinity));
      }
      final spare = [
        for (var c = 0; c < n; c++)
          expand[c] ? 0.0 : math.max(0.0, widths[c] - least[c])
      ];
      final total = spare.fold(0.0, (a, b) => a + b);
      if (total > 0) {
        final take = math.min(deficit, total);
        for (var c = 0; c < n; c++) {
          widths[c] -= spare[c] * take / total;
        }
        used -= take;
      }
    }
    // the expanding columns share the rest equally; a column whose minimum
    // is larger keeps its minimum and leaves the others the remainder
    final pool = {for (var c = 0; c < n; c++) if (expand[c]) c};
    var rest = width - used;
    final needed = pool.fold(0.0, (a, c) => a + minimum[c]);
    if (needed > rest) {
      final single = pool.fold(0.0, (a, c) => a + minimum[c] - multi[c]);
      final extra = needed - single;
      if (single <= rest) {
        for (final c in pool) {
          minimum[c] = minimum[c] -
              multi[c] +
              (extra > 0 ? multi[c] * (rest - single) / extra : 0);
        }
      } else {
        // too little for the single needs: first the floor of each column
        // (the longest word of a label, the width of a date/number), the
        // rest in proportion – a label does not break inside a word
        final floor = List.filled(n, 0.0);
        for (final child in _cells) {
          final d = _data(child);
          if (d.colspan != 1 || d.need != FormGridNeed.natural ||
              !pool.contains(d.column)) {
            continue;
          }
          floor[d.column] = math.min(
              math.max(floor[d.column],
                  child.getMinIntrinsicWidth(double.infinity)),
              minimum[d.column] - multi[d.column]);
        }
        final floors = pool.fold(0.0, (a, c) => a + floor[c]);
        final above = single - floors;
        for (final c in pool) {
          final own = minimum[c] - multi[c];
          minimum[c] = floors <= rest
              ? floor[c] +
                  (above > 0 ? (own - floor[c]) * (rest - floors) / above : 0)
              : floor[c] * (floors > 0 ? rest / floors : 0);
        }
      }
    }
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

  /// Adds the needs ([FormGridNeed]) of the cells to the [minimum] of the
  /// expanding columns: single columns first, then cells over several
  /// columns spread their missing width over their expanding columns
  /// (beside the [widths] of their fixed columns). Returns the share of
  /// each column that comes from cells over several columns.
  List<double> _addNeeds(List<double> minimum, List<double> widths,
      List<bool> expand, double Function(RenderBox) natural,
      double Function(RenderBox) content) {
    final multi = List.filled(minimum.length, 0.0);
    final cells = [
      for (final child in _cells)
        if (_data(child).need != FormGridNeed.none) child,
    ]..sort((a, b) => _data(a).colspan.compareTo(_data(b).colspan));
    for (final child in cells) {
      final d = _data(child);
      final columns = [for (var c = d.column; c < d.column + d.colspan; c++) c];
      final growing = [for (final c in columns) if (expand[c]) c];
      if (growing.isEmpty) continue;
      final need = switch (d.need) {
        FormGridNeed.natural => natural(child),
        FormGridNeed.content => content(child),
        FormGridNeed.relation => formGridRelationWidth,
        _ => formGridInputWidth,
      };
      final have = columns.fold(
          0.0, (a, c) => a + (expand[c] ? minimum[c] : widths[c]));
      if (need <= have) continue;
      final add = (need - have) / growing.length;
      for (final c in growing) {
        minimum[c] += add;
        if (d.colspan > 1) multi[c] += add;
      }
    }
    return multi;
  }

  /// The minimum content width (for a parent grid, intrinsic): the fixed
  /// cells' natural widths and the needs of labels, buttons and groups,
  /// per column – without laying out.
  double _minContent() {
    final n = _n;
    final expand = _expanding(n);
    final widths = List.filled(n, 0.0);
    final fixed = [
      for (final child in _cells)
        if (!Iterable.generate(_data(child).colspan, (i) => _data(child).column + i)
            .any((c) => expand[c]))
          child,
    ]..sort((a, b) => _data(a).colspan.compareTo(_data(b).colspan));
    for (final child in fixed) {
      final d = _data(child);
      final natural = child.getMaxIntrinsicWidth(double.infinity);
      var current = 0.0;
      for (var c = d.column; c < d.column + d.colspan; c++) {
        current += widths[c];
      }
      if (natural > current) widths[d.column + d.colspan - 1] += natural - current;
    }
    final minimum = List.filled(n, 0.0);
    _addNeeds(minimum, widths, expand,
        (c) => c.getMaxIntrinsicWidth(double.infinity),
        (c) => c.getMinIntrinsicWidth(double.infinity));
    var total = 0.0;
    for (var c = 0; c < n; c++) {
      total += expand[c] ? minimum[c] : widths[c];
    }
    return total;
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
  double computeMinIntrinsicWidth(double height) => _minContent();
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
