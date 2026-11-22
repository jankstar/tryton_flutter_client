import 'package:flutter/material.dart';

/// The „all entries“ button of a row of tabs that does not fit (the shell's
/// tab bar, a form's notebook): a frame with the number of entries and an
/// arrow; a click lists them, the active one with a check mark.
class OverflowListButton extends StatelessWidget {
  final String tooltip;
  final int count;
  final int activeIndex;

  /// The label of entry [index].
  final String Function(int index) label;

  /// Full text as tooltip (null: none).
  final String? Function(int index)? fullLabel;

  /// Something after the label of entry [index] (e.g. a close button).
  final Widget Function(BuildContext context, int index)? trailing;

  /// Key prefix of the entries (`<prefix>-<index>`).
  final String itemKeyPrefix;
  final ValueChanged<int> onSelected;

  const OverflowListButton({
    super.key,
    required this.tooltip,
    required this.count,
    required this.activeIndex,
    required this.label,
    required this.itemKeyPrefix,
    required this.onSelected,
    this.fullLabel,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<int>(
      tooltip: tooltip,
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      // number of entries and arrow
      child: Container(
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.only(left: 8, right: 2),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
      itemBuilder: (context) => [
        for (var i = 0; i < count; i++)
          PopupMenuItem<int>(
            key: ValueKey('$itemKeyPrefix-$i'),
            value: i,
            height: 36,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: i == activeIndex
                      ? Icon(Icons.check, size: 16, color: cs.primary)
                      : null,
                ),
                Expanded(child: _label(i)),
                if (trailing != null) trailing!(context, i),
              ],
            ),
          ),
      ],
    );
  }

  Widget _label(int i) {
    final text = Text(
      label(i),
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        fontWeight: i == activeIndex ? FontWeight.w600 : null,
      ),
    );
    final full = fullLabel?.call(i);
    return full == null
        ? text
        : Tooltip(
            message: full,
            waitDuration: const Duration(milliseconds: 600),
            child: text,
          );
  }
}
