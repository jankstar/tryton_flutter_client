import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/actions/action_service.dart';
import '../../core/xml/view_definition.dart';
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

  /// Called before an action runs (e.g. the form's save prompt, spec
  /// 10.4); false cancels the action.
  final Future<bool> Function()? beforeExecute;

  /// Form buttons shown in this menu as well (`keyword`, spec 8.6), run
  /// with [onButton] (without [beforeExecute]: the button saves itself).
  final List<ButtonNode> buttons;
  final Future<void> Function(ButtonNode)? onButton;

  const ToolbarDropdownButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.items,
    required this.model,
    required this.selectedIds,
    this.enabled = true,
    this.beforeExecute,
    this.buttons = const [],
    this.onButton,
  });

  Future<void> _execute(
      BuildContext context, WidgetRef ref, TrytonActionItem action) async {
    final before = beforeExecute;
    if (before != null && !await before()) return;
    if (!context.mounted) return;
    // Like SAO's toolbar: Action.execute with keyword (name suffix).
    try {
      await ref.read(actionServiceProvider).execute(
            {'res_model': action.resModel, ...action.raw},
            data: {
              'model': model,
              'id': selectedIds.isEmpty ? null : selectedIds.first,
              'ids': selectedIds,
            },
            keyword: true,
            ui: DialogActionUi(context),
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shownButtons = onButton == null ? const <ButtonNode>[] : buttons;
    // Greyed out when disabled (no selection) or nothing configured
    if (!enabled || (items.isEmpty && shownButtons.isEmpty)) {
      return IconButton(
        icon: Icon(icon, color: Theme.of(context).disabledColor),
        tooltip: tooltip,
        onPressed: null,
      );
    }

    // Single item → execute directly
    if (items.length == 1 && shownButtons.isEmpty) {
      return IconButton(
        icon: Icon(icon),
        tooltip: '$tooltip: ${items.first.name}',
        onPressed: () => _execute(context, ref, items.first),
      );
    }

    // Multiple items → dropdown (actions, then the form buttons)
    return PopupMenuButton<Object>(
      icon: Icon(icon),
      tooltip: tooltip,
      position: PopupMenuPosition.under,
      onSelected: (entry) => switch (entry) {
        TrytonActionItem() => _execute(context, ref, entry),
        ButtonNode() => onButton?.call(entry),
        _ => null,
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<Object>(
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
        ...items.map((a) => PopupMenuItem<Object>(
              value: a,
              child: Row(children: [
                Icon(icon, size: 16,
                    color: Theme.of(ctx).colorScheme.onSurface),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(a.name, overflow: TextOverflow.ellipsis)),
              ]),
            )),
        if (items.isNotEmpty && shownButtons.isNotEmpty)
          const PopupMenuDivider(height: 1),
        ...shownButtons.map((b) => PopupMenuItem<Object>(
              value: b,
              child: Text(b.string ?? b.name,
                  overflow: TextOverflow.ellipsis),
            )),
      ],
    );
  }
}
