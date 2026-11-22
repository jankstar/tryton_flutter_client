import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/theme/tryton_colors.dart';
import 'tab_manager.dart';
import '../../shared/widgets/overflow_list_button.dart';

/// The tab chips of the shell (spec 10.1): a horizontal strip that
/// scrolls with the mouse wheel and brings the active tab into view;
/// when not all tabs fit, a button at its end lists all tabs (activate,
/// close).
class TabStrip extends StatefulWidget {
  final List<AppTab> tabs;
  final int activeIndex;
  final void Function(int index) onActivate;
  final void Function(int index) onClose;

  const TabStrip({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onActivate,
    required this.onClose,
  });

  @override
  State<TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<TabStrip> {
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};

  /// Not all tabs fit: the "all tabs" button is shown.
  bool _overflow = false;

  @override
  void initState() {
    super.initState();
    _showActiveLater();
  }

  @override
  void didUpdateWidget(TabStrip old) {
    super.didUpdateWidget(old);
    final activeId = _activeId(widget);
    if (activeId != _activeId(old) || widget.tabs.length != old.tabs.length) {
      _showActiveLater();
    }
    // keys of closed tabs
    final ids = {for (final t in widget.tabs) t.id};
    _keys.removeWhere((id, _) => !ids.contains(id));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static String? _activeId(TabStrip w) =>
      w.activeIndex >= 0 && w.activeIndex < w.tabs.length
          ? w.tabs[w.activeIndex].id
          : null;

  /// Scrolls the active chip into view after the layout.
  void _showActiveLater() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = _activeId(widget);
      final ctx = id == null ? null : _keys[id]?.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 150),
          alignmentPolicy: _alignment(ctx));
    });
  }

  /// Left of the view: align at the start, else at the end.
  ScrollPositionAlignmentPolicy _alignment(BuildContext chip) {
    final box = chip.findRenderObject() as RenderBox?;
    final strip = context.findRenderObject() as RenderBox?;
    if (box == null || strip == null) {
      return ScrollPositionAlignmentPolicy.explicit;
    }
    final left = box.localToGlobal(Offset.zero, ancestor: strip).dx;
    return left < 0
        ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
        : ScrollPositionAlignmentPolicy.keepVisibleAtEnd;
  }

  /// The mouse wheel (vertical or horizontal) scrolls the strip.
  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final delta = event.scrollDelta.dx != 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    final p = _scroll.position;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _scroll.jumpTo(
          (p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent));
    });
  }

  bool _metrics(ScrollMetricsNotification n) {
    final overflow = n.metrics.maxScrollExtent > 0;
    if (overflow != _overflow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _overflow = overflow);
        // the button narrows the strip: the active tab into view again
        _showActiveLater();
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Listener(
          onPointerSignal: _wheel,
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: _metrics,
            child: SingleChildScrollView(
              key: const ValueKey('tab-strip'),
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                for (var i = 0; i < widget.tabs.length; i++)
                  _TabChip(
                    key: _keys.putIfAbsent(widget.tabs[i].id, GlobalKey.new),
                    tab: widget.tabs[i],
                    isActive: i == widget.activeIndex,
                    onTap: () => widget.onActivate(i),
                    onClose: () => widget.onClose(i),
                  ),
              ]),
            ),
          ),
        ),
      ),
      if (_overflow) _allTabsButton(),
    ]);
  }

  /// All tabs as a list: a click activates, × closes (the list stays
  /// short-lived: it closes with the choice).
  Widget _allTabsButton() => OverflowListButton(
        key: const ValueKey('tabs-all'),
        tooltip: context.l10n.allTabs,
        count: widget.tabs.length,
        activeIndex: widget.activeIndex,
        label: (i) => widget.tabs[i].title.split(' / ').last,
        fullLabel: (i) => widget.tabs[i].title,
        itemKeyPrefix: 'tabs-all',
        onSelected: widget.onActivate,
        trailing: (context, i) => IconButton(
          key: ValueKey('tabs-all-close-$i'),
          icon: const Icon(Icons.close, size: 15),
          tooltip: context.l10n.close,
          visualDensity: VisualDensity.compact,
          onPressed: () {
            Navigator.of(context).pop();
            widget.onClose(i);
          },
        ),
      );
}

class _TabChip extends StatelessWidget {
  final AppTab tab;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _TabChip({
    super.key,
    required this.tab,
    required this.isActive,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final tc = TrytonColors.of(context);
    // a coloured tab bar (Blue Ocean): light chips on the band
    final onBar = tc.tabBarForeground;
    final chip = InputChip(
      // Keyword actions of the menu carry the menu path ("A / B / C"):
      // the chip shows the last part, the tooltip the full name.
      tooltip: tab.title,
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Text(
          tab.title.split(' / ').last,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: onBar == null
                ? null
                : (isActive ? tc.tabSelectedForeground : onBar),
          ),
        ),
      ),
      selected: isActive,
      onSelected: (_) => onTap(),
      onDeleted: onClose,
      deleteIcon: const Icon(Icons.close, size: 13),
      deleteIconColor: onBar == null
          ? null
          : (isActive ? tc.tabSelectedForeground : onBar),
      side: onBar == null || isActive
          ? null
          : BorderSide(color: onBar.withAlpha(120)),
      // (Material 3 chips paint `color` over `backgroundColor`)
      color: onBar == null
          ? null
          : WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? tc.tabSelected
                  : Colors.transparent),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
      selectedColor: TrytonColors.of(context).tabSelected,
      checkmarkColor: TrytonColors.of(context).tabSelectedForeground,
      showCheckmark: false,
    );
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      // the chip's material paints with the canvas colour (white): on a
      // coloured bar the inactive chips stay transparent
      child: onBar == null
          ? chip
          : Theme(
              data: Theme.of(context).copyWith(canvasColor: Colors.transparent),
              child: chip),
    );
  }
}
