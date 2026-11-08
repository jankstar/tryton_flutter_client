import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/screen/screen.dart';
import '../actions/action_service.dart';
import '../model/model_service.dart';
import '../model/toolbar_data.dart';
import '../shell/tab_manager.dart';
import 'resource_dialogs.dart';

// Record entries of the context menu of a list (spec 9.3.4, Python
// common/popup_menu.py `populate`): logs, attachments, notes and the
// actions of `view_toolbar_get` for a record – of the row, or of the
// record of a many2one/reference column in a submenu with its title.

/// A record of the context menu: [model], [id], shown name, context; for
/// a column's record [string] (submenu title) and [viewIds] (`Edit…`).
typedef MenuRecord = ({
  String model,
  int id,
  String recName,
  Map<String, dynamic> context,
});

/// The entries for [record] (Python `populate`); with [title] in a
/// submenu that also offers „Edit…“ (a form tab with [viewIds]).
Future<List<Widget>> recordMenuEntries(
  BuildContext context,
  WidgetRef ref,
  MenuRecord record, {
  String? title,
  List<int?> viewIds = const [],
  Key? key,
}) async {
  if (record.id < 0) return const [];
  final l = context.l10n;
  TrytonToolbar toolbar;
  try {
    toolbar = await ref.read(modelServiceProvider).viewToolbarGet(record.model);
  } catch (_) {
    toolbar = const TrytonToolbar();
  }
  if (!context.mounted) return const [];
  final resource = (
    model: record.model,
    id: record.id,
    recName: record.recName,
    context: record.context,
  );
  void run(TrytonActionItem action, {bool directPrint = false}) {
    ref.read(actionServiceProvider).execute(
      {
        'res_model': action.resModel,
        ...action.raw,
        if (directPrint) 'direct_print': true,
      },
      data: {
        'model': record.model,
        'id': record.id,
        'ids': [record.id],
      },
      context: record.context,
      ui: DialogActionUi(context),
    ).catchError((Object _) {});
  }

  Widget submenu(String name, String label, List<TrytonActionItem> actions,
          {bool directPrint = false}) =>
      actions.isEmpty
          ? MenuItemButton(
              key: ValueKey('ctx-$name'), onPressed: null, child: Text(label))
          : SubmenuButton(
              key: ValueKey('ctx-$name'),
              menuChildren: [
                for (final a in actions)
                  MenuItemButton(
                    key: ValueKey('ctx-$name-${a.id}'),
                    onPressed: () => run(a, directPrint: directPrint),
                    child: Text(a.name),
                  ),
              ],
              child: Text(label),
            );

  final entries = <Widget>[
    if (title != null) ...[
      MenuItemButton(
        key: const ValueKey('ctx-edit'),
        onPressed: () => ref.read(tabsProvider.notifier).openTab(
              title: title,
              attributes: ScreenAttributes(record.model,
                  mode: const ['form'],
                  viewIds: viewIds.length > 1 ? viewIds.sublist(1) : const [],
                  resId: record.id,
                  context: record.context),
            ),
        child: Text(l.ctxEdit),
      ),
      const Divider(height: 1),
    ],
    MenuItemButton(
      key: const ValueKey('ctx-logs'),
      onPressed: () => showLogs(context, ref, resource).catchError((Object _) {}),
      child: Text(l.menuLogs),
    ),
    MenuItemButton(
      key: const ValueKey('ctx-attachments'),
      onPressed: () => showAttachments(context, resource),
      child: Text(l.menuAttachments),
    ),
    MenuItemButton(
      key: const ValueKey('ctx-notes'),
      onPressed: () => showNotes(context, resource),
      child: Text(l.menuNotes),
    ),
    const Divider(height: 1),
    submenu('action', l.menuActions, toolbar.actions),
    submenu('relate', l.menuRelate, toolbar.relate),
    submenu('report', l.menuReport, toolbar.print),
    submenu('print', l.ctxPrint, toolbar.print, directPrint: true),
    // the e-mail dialog (spec 11.10) is not there yet
    MenuItemButton(
        key: const ValueKey('ctx-email'), onPressed: null, child: Text(l.menuEmail)),
  ];
  if (title == null) return entries;
  return [
    SubmenuButton(key: key, menuChildren: entries, child: Text(title)),
  ];
}
