import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/actions/action_executor.dart';
import '../../features/model/toolbar_data.dart';

/// Reusable toolbar button for Action / Relate / Print / Email categories.
/// Shows the category icon; opens a dropdown if multiple items are available.
/// Always visible – greyed out when the category has no items (like SAO).
class ToolbarDropdownButton extends ConsumerWidget {
  final IconData icon;
  final String tooltip;
  final List<TrytonActionItem> items;
  final String model;
  final List<int> selectedIds;
  /// When false the button is always greyed out regardless of item count.
  /// Use this to disable the button when no record is selected.
  final bool enabled;

  const ToolbarDropdownButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.items,
    required this.model,
    required this.selectedIds,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Greyed out when disabled (no selection) or no items configured
    if (!enabled || items.isEmpty) {
      return IconButton(
        icon: Icon(icon, color: Theme.of(context).disabledColor),
        tooltip: tooltip,
        onPressed: null,
      );
    }

    // Single item → execute directly
    if (items.length == 1) {
      return IconButton(
        icon: Icon(icon),
        tooltip: '$tooltip: ${items.first.name}',
        onPressed: () async {
          final executor = ref.read(actionExecutorProvider);
          await executor.execute(context, items.first, model, selectedIds);
        },
      );
    }

    // Multiple items → dropdown
    return PopupMenuButton<TrytonActionItem>(
      icon: Icon(icon),
      tooltip: tooltip,
      position: PopupMenuPosition.under,
      onSelected: (action) async {
        final executor = ref.read(actionExecutorProvider);
        await executor.execute(context, action, model, selectedIds);
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<TrytonActionItem>(
          enabled: false,
          height: 28,
          child: Text(
            tooltip,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Theme.of(ctx).colorScheme.primary,
            ),
          ),
        ),
        const PopupMenuDivider(height: 1),
        ...items.map((a) => PopupMenuItem<TrytonActionItem>(
              value: a,
              child: Row(children: [
                Icon(icon, size: 16,
                    color: Theme.of(ctx).colorScheme.onSurface),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(a.name, overflow: TextOverflow.ellipsis)),
              ]),
            )),
      ],
    );
  }
}
