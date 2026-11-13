import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/actions/action_service.dart';
import '../../core/screen/screen.dart';
import '../../core/xml/view_definition.dart';
import '../../features/model/toolbar_data.dart';
import '../errors/error_dialogs.dart';

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

  /// The calling screen (reloaded after a wizard, spec 13); its context
  /// (with the values of the context form) goes to the action.
  final TrytonScreen? screen;

  /// Ids of the listed records for actions with `records = listed`
  /// (Python `Form._action`); null: the selected ones.
  final List<int> Function()? listedIds;
  final Future<void> Function(ButtonNode)? onButton;

  /// Predefined CSV exports at the end of the print menu (spec 10.3,
  /// 11.9), run with [onExport] – also without a selection.
  final List<Map<String, dynamic>> exports;
  final Future<void> Function(Map<String, dynamic> export)? onExport;

  /// Reports go straight to the printer (`direct_print`, Python toolbar
  /// button „Print“ beside „Report“).
  final bool directPrint;

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
    this.listedIds,
    this.screen,
    this.exports = const [],
    this.onExport,
    this.directPrint = false,
  });

  Future<void> _execute(
      BuildContext context, WidgetRef ref, TrytonActionItem action) async {
    final before = beforeExecute;
    if (before != null && !await before()) return;
    if (!context.mounted) return;
    // Like Python `Form._action`: the ids (selected or, with
    // `records = listed`, listed), `model_context` and the screen's local
    // context – it holds the values of the context form (e.g. the fiscal
    // year of the general ledger, which its reports need).
    final listed = listedIds;
    final ids = action.raw['records'] == 'listed' && listed != null
        ? listed()
        : selectedIds;
    try {
      await ref.read(actionServiceProvider).execute(
            {
              'res_model': action.resModel,
              ...action.raw,
              if (directPrint) 'direct_print': true,
            },
            data: {
              'model': model,
              'model_context': screen?.contextScreen?.model.name,
              'id': selectedIds.isEmpty ? null : selectedIds.first,
              'ids': ids,
            },
            context: screen?.localContext ?? const {},
            keyword: true,
            ui: DialogActionUi(context),
            screen: screen,
          );
    } catch (e) {
      if (context.mounted) await showErrorDialog(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shownButtons = onButton == null ? const <ButtonNode>[] : buttons;
    final shownExports =
        onExport == null ? const <Map<String, dynamic>>[] : exports;
    // Greyed out when disabled (no selection) or nothing configured
    if ((!enabled || (items.isEmpty && shownButtons.isEmpty)) &&
        shownExports.isEmpty) {
      return IconButton(
        icon: Icon(icon, color: Theme.of(context).disabledColor),
        tooltip: tooltip,
        onPressed: null,
      );
    }

    // Single item → execute directly
    if (items.length == 1 && shownButtons.isEmpty && shownExports.isEmpty) {
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
        Map<String, dynamic>() => onExport?.call(entry),
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
              enabled: enabled,
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
              enabled: enabled,
              child: Text(b.string ?? b.name,
                  overflow: TextOverflow.ellipsis),
            )),
        if ((items.isNotEmpty || shownButtons.isNotEmpty) &&
            shownExports.isNotEmpty)
          const PopupMenuDivider(height: 1),
        ...shownExports.map((e) => PopupMenuItem<Object>(
              key: ValueKey('export-${e['id']}'),
              value: e,
              child: Text('${e['name']}', overflow: TextOverflow.ellipsis),
            )),
      ],
    );
  }
}
