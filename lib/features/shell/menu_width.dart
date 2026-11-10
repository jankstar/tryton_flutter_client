import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Width of the menu beside the tabs, set by dragging the divider and kept
/// in `shared_preferences` like the language (restored at the next start).
class MenuWidthNotifier extends StateNotifier<double> {
  MenuWidthNotifier() : super(defaultWidth) {
    _load();
  }

  static const prefKey = 'tryton_menu_width';
  static const defaultWidth = 250.0;
  static const minWidth = 160.0;
  static const maxWidth = 640.0;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final width = prefs.getDouble(prefKey);
    if (width != null && mounted) state = width.clamp(minWidth, maxWidth);
  }

  /// Sets the width while dragging (not saved yet).
  void set(double width) => state = width.clamp(minWidth, maxWidth);

  /// Saves the current width (end of the drag).
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(prefKey, state);
  }

  /// Back to the default width (double click on the divider).
  Future<void> reset() async {
    state = defaultWidth;
    await save();
  }
}

final menuWidthProvider =
    StateNotifierProvider<MenuWidthNotifier, double>((ref) => MenuWidthNotifier());

/// The divider between menu and tabs: drag to change the menu width (at
/// most [maxWidth] for the window), double click for the default width.
class MenuResizeHandle extends ConsumerStatefulWidget {
  /// Largest width the window allows (the tabs keep their room).
  final double maxWidth;

  /// Called while dragging (true) and at its end (false).
  final ValueChanged<bool>? onDragging;

  const MenuResizeHandle({super.key, required this.maxWidth, this.onDragging});

  @override
  ConsumerState<MenuResizeHandle> createState() => _MenuResizeHandleState();
}

class _MenuResizeHandleState extends ConsumerState<MenuResizeHandle> {
  bool _hover = false;
  bool _dragging = false;

  MenuWidthNotifier get _menu => ref.read(menuWidthProvider.notifier);

  void _drag(bool on) {
    setState(() => _dragging = on);
    widget.onDragging?.call(on);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = _hover || _dragging;
    return MouseRegion(
      key: const ValueKey('menu-resize'),
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // the divider follows the pointer from where it was pressed
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (_) => _drag(true),
        onHorizontalDragUpdate: (d) {
          final width = ref.read(menuWidthProvider) + d.delta.dx;
          _menu.set(width > widget.maxWidth ? widget.maxWidth : width);
        },
        onHorizontalDragEnd: (_) {
          _drag(false);
          _menu.save();
        },
        onHorizontalDragCancel: () => _drag(false),
        onDoubleTap: _menu.reset,
        // a 7 px wide grip around the 1 px line
        child: SizedBox(
          width: 7,
          child: Center(
            child: Container(
              width: active ? 3 : 1,
              color: active ? cs.primary : cs.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// The place of the menu left of the tabs: [width] wide when [open], 0
/// when closed. Only opening/closing is animated; a new [width] (window
/// resized, divider dragged) applies at once – an animated width lagged
/// behind a shrinking window and overflowed the row.
class MenuSlot extends StatelessWidget {
  final bool open;
  final double width;
  final Widget child;

  const MenuSlot(
      {super.key, required this.open, required this.width, required this.child});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: open ? 1 : 0),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        builder: (context, t, child) => ClipRect(
          child: SizedBox(
            width: width * t,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              maxWidth: width,
              child: child,
            ),
          ),
        ),
        child: SizedBox(width: width, child: child),
      );
}
