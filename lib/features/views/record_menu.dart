import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/l10n/locale_provider.dart';
import '../../l10n/app_localizations.dart';
import '../shell/tab_manager.dart';

// Record menu at the title of a form tab and the keyboard shortcuts of
// the tabs (spec 10.3, Anhang B; Python gui/window/tabcontent.py
// `menu_def` with `accel_path`, gui/main.py `Gtk.AccelMap` and
// `shortcuts`; SAO tab.js `menu_def`, sao.js `shortcuts_defs`).

/// The entries of the record menu in the order of Python `menu_def`.
enum RecordAction {
  switchView,
  previous,
  next,
  search,
  newRecord,
  save,
  reload,
  copy,
  delete,
  logs,
  revision,
  attach,
  note,
  chat,
  action,
  relate,
  print,
  email,
  export,
  import,
  copyUrl,
  close,
}

/// Groups of [RecordAction] (separators between them, Python `None`).
const recordMenuGroups = [
  [RecordAction.switchView, RecordAction.previous, RecordAction.next, RecordAction.search],
  [RecordAction.newRecord, RecordAction.save, RecordAction.reload, RecordAction.copy, RecordAction.delete],
  [RecordAction.logs, RecordAction.revision],
  [RecordAction.attach, RecordAction.note, RecordAction.chat, RecordAction.action, RecordAction.relate],
  [RecordAction.print, RecordAction.email],
  [RecordAction.export, RecordAction.import, RecordAction.copyUrl],
  [RecordAction.close],
];

/// Cmd instead of Ctrl on Apple platforms.
bool get _apple =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Ctrl (Cmd on macOS) + [key].
SingleActivator primaryShortcut(LogicalKeyboardKey key, {bool shift = false}) =>
    SingleActivator(key, control: !_apple, meta: _apple, shift: shift);

/// Shortcut of [action] (Anhang B, GTK `Gtk.AccelMap` defaults).
SingleActivator? recordShortcut(RecordAction action) => switch (action) {
      RecordAction.switchView => primaryShortcut(LogicalKeyboardKey.keyL),
      RecordAction.previous => primaryShortcut(LogicalKeyboardKey.arrowUp),
      RecordAction.next => primaryShortcut(LogicalKeyboardKey.arrowDown),
      RecordAction.search => primaryShortcut(LogicalKeyboardKey.keyF, shift: true),
      RecordAction.newRecord => primaryShortcut(LogicalKeyboardKey.keyN),
      RecordAction.save => primaryShortcut(LogicalKeyboardKey.keyS),
      RecordAction.reload => primaryShortcut(LogicalKeyboardKey.keyR),
      RecordAction.copy => primaryShortcut(LogicalKeyboardKey.keyD, shift: true),
      RecordAction.delete => primaryShortcut(LogicalKeyboardKey.keyD),
      RecordAction.attach => primaryShortcut(LogicalKeyboardKey.keyT, shift: true),
      RecordAction.note => primaryShortcut(LogicalKeyboardKey.keyO, shift: true),
      RecordAction.action => primaryShortcut(LogicalKeyboardKey.keyE),
      RecordAction.relate => primaryShortcut(LogicalKeyboardKey.keyR, shift: true),
      RecordAction.print => primaryShortcut(LogicalKeyboardKey.keyP),
      RecordAction.email => primaryShortcut(LogicalKeyboardKey.keyE, shift: true),
      RecordAction.close => primaryShortcut(LogicalKeyboardKey.keyW),
      RecordAction.logs ||
      RecordAction.revision ||
      RecordAction.export ||
      RecordAction.import ||
      RecordAction.chat ||
      RecordAction.copyUrl =>
        null,
    };

String recordActionLabel(AppLocalizations l, RecordAction action) =>
    switch (action) {
      RecordAction.switchView => l.menuSwitchView,
      RecordAction.previous => l.menuPrevious,
      RecordAction.next => l.menuNext,
      RecordAction.search => l.menuSearch,
      RecordAction.newRecord => l.menuNew,
      RecordAction.save => l.menuSave,
      RecordAction.reload => l.menuReload,
      RecordAction.copy => l.menuDuplicate,
      RecordAction.delete => l.menuDelete,
      RecordAction.logs => l.menuLogs,
      RecordAction.revision => l.menuRevisions,
      RecordAction.attach => l.menuAttachments,
      RecordAction.note => l.menuNotes,
      RecordAction.action => l.menuActions,
      RecordAction.relate => l.menuRelate,
      RecordAction.print => l.menuReport,
      RecordAction.email => l.menuEmail,
      RecordAction.export => l.exportData,
      RecordAction.import => l.importData,
      RecordAction.chat => l.chat,
      RecordAction.copyUrl => l.copyUrl,
      RecordAction.close => l.menuCloseTab,
    };

/// Tryton icon (Python `icon_name`) and Material fallback of [action].
(String, IconData) recordActionIcon(RecordAction action) => switch (action) {
      RecordAction.switchView => ('tryton-switch', Icons.compare_arrows),
      RecordAction.previous => ('tryton-back', Icons.arrow_back_ios),
      RecordAction.next => ('tryton-forward', Icons.arrow_forward_ios),
      RecordAction.search => ('tryton-search', Icons.search),
      RecordAction.newRecord => ('tryton-create', Icons.add),
      RecordAction.save => ('tryton-save', Icons.save),
      RecordAction.reload => ('tryton-refresh', Icons.refresh),
      RecordAction.copy => ('tryton-copy', Icons.copy_outlined),
      RecordAction.delete => ('tryton-delete', Icons.delete_outline),
      RecordAction.logs => ('tryton-log', Icons.history),
      RecordAction.revision => ('tryton-history', Icons.manage_history),
      RecordAction.attach => ('tryton-attach', Icons.attach_file),
      RecordAction.note => ('tryton-note', Icons.sticky_note_2_outlined),
      RecordAction.action => ('tryton-launch', Icons.rocket_launch_outlined),
      RecordAction.relate => ('tryton-link', Icons.link),
      RecordAction.print => ('tryton-print', Icons.print_outlined),
      RecordAction.email => ('tryton-email', Icons.email_outlined),
      RecordAction.export => ('tryton-export', Icons.file_download_outlined),
      RecordAction.import => ('tryton-import', Icons.file_upload_outlined),
      RecordAction.chat => ('tryton-chat', Icons.forum_outlined),
      RecordAction.copyUrl => ('tryton-public', Icons.public),
      RecordAction.close => ('tryton-close', Icons.close),
    };

/// The entries of a screen: an absent action is not shown (e.g.
/// revisions without MODELHISTORY), a null callback is disabled.
typedef RecordActions = Map<RecordAction, VoidCallback?>;

/// Text of [activator] for the help dialog (⌘⇧S on Apple, Ctrl+Shift+S
/// elsewhere).
String shortcutText(SingleActivator activator) {
  final key = switch (activator.trigger) {
    LogicalKeyboardKey.arrowUp => '↑',
    LogicalKeyboardKey.arrowDown => '↓',
    LogicalKeyboardKey.arrowLeft => '←',
    LogicalKeyboardKey.arrowRight => '→',
    LogicalKeyboardKey.comma => ',',
    final k => k.keyLabel,
  };
  if (_apple) {
    return [
      if (activator.control) '⌃',
      if (activator.alt) '⌥',
      if (activator.shift) '⇧',
      if (activator.meta) '⌘',
      key,
    ].join();
  }
  return [
    if (activator.control) 'Ctrl',
    if (activator.alt) 'Alt',
    if (activator.shift) 'Shift',
    if (activator.meta) 'Meta',
    key,
  ].join('+');
}

/// Dropdown at the title of a form tab with all entries of
/// [recordMenuGroups] – icon, label, shortcut and the activation of the
/// buttons (spec 10.3 „Datensatz-Menü“).
class RecordTitleMenu extends StatelessWidget {
  final Widget title;
  final RecordActions actions;

  const RecordTitleMenu({super.key, required this.title, required this.actions});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final groups = [
      for (final group in recordMenuGroups)
        [for (final a in group) if (actions.containsKey(a)) a]
    ].where((g) => g.isNotEmpty).toList();
    return MenuAnchor(
      key: const ValueKey('record-title-menu'),
      menuChildren: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          for (final a in groups[i])
            MenuItemButton(
              key: ValueKey('record-menu-${a.name}'),
              leadingIcon: TrytonIcon(
                  iconName: recordActionIcon(a).$1,
                  size: 18,
                  fallback: recordActionIcon(a).$2),
              shortcut: recordShortcut(a),
              onPressed: actions[a],
              child: Text(recordActionLabel(l, a)),
            ),
        ],
      ],
      builder: (context, controller, _) => InkWell(
        key: const ValueKey('record-title'),
        borderRadius: BorderRadius.circular(4),
        onTap: () =>
            controller.isOpen ? controller.close() : controller.open(),
        child: Tooltip(
          message: l.recordMenu,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: title),
            const Icon(Icons.arrow_drop_down, size: 20),
          ]),
        ),
      ),
    );
  }
}

/// The shortcuts of [actions] for the subtree of [child] (Anhang B):
/// handled when the focus is inside; the shell forwards them to the
/// active tab's top screen when the focus is elsewhere ([dispatch]).
class RecordShortcuts extends StatefulWidget {
  final RecordActions actions;
  final Widget child;

  const RecordShortcuts({super.key, required this.actions, required this.child});

  static final _registered = <_RecordShortcutsState>[];

  /// Runs [action] of the active screen (newest first: tab → pushed
  /// form); false when none is active or the action is disabled.
  static bool dispatch(RecordAction action) {
    for (final state in _registered.reversed) {
      if (!state._active) continue;
      final callback = state.widget.actions[action];
      if (callback == null) return false;
      callback();
      return true;
    }
    return false;
  }

  @override
  State<RecordShortcuts> createState() => _RecordShortcutsState();
}

class _RecordShortcutsState extends State<RecordShortcuts> {
  @override
  void initState() {
    super.initState();
    RecordShortcuts._registered.add(this);
  }

  @override
  void dispose() {
    RecordShortcuts._registered.remove(this);
    super.dispose();
  }

  /// Shown on top: the routes up to the root are current and the tab is
  /// the active one.
  bool get _active {
    if (!mounted) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    var nav = context.findAncestorStateOfType<NavigatorState>();
    while (nav != null) {
      if (ModalRoute.of(nav.context)?.isCurrent == false) return false;
      nav = nav.context.findAncestorStateOfType<NavigatorState>();
    }
    final tabId = TabScope.of(context);
    if (tabId == null) return true;
    final tabs = ProviderScope.containerOf(context, listen: false).read(tabsProvider);
    final active = tabs.activeIndex;
    return active >= 0 && active < tabs.tabs.length && tabs.tabs[active].id == tabId;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        for (final MapEntry(:key, :value) in widget.actions.entries)
          if (value != null && recordShortcut(key) != null)
            recordShortcut(key)!: value,
      },
      // no own autofocus: it would take the place of the form's `cursor`
      child: widget.child,
    );
  }
}

/// Bindings of the shell for the record shortcuts (forwarded with
/// [RecordShortcuts.dispatch]).
Map<ShortcutActivator, VoidCallback> recordShellBindings() => {
      for (final a in RecordAction.values)
        ?recordShortcut(a): () => RecordShortcuts.dispatch(a),
    };

/// The help with all shortcuts (Python `Main.shortcuts`, SAO
/// `help_dialog`; F1 / Ctrl+F1).
Future<void> showShortcutsHelp(BuildContext context) {
  final l = context.l10n;
  final sections = <(String, List<(String, String)>)>[
    (l.shortcutsGlobal, [
      (shortcutText(primaryShortcut(LogicalKeyboardKey.comma)), l.preferences),
      (shortcutText(primaryShortcut(LogicalKeyboardKey.keyK)), l.shortcutSearchMenu),
      (shortcutText(primaryShortcut(LogicalKeyboardKey.keyM)), l.shortcutToggleMenu),
      (shortcutText(const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true)),
          l.shortcutPreviousTab),
      (shortcutText(const SingleActivator(LogicalKeyboardKey.tab, control: true)),
          l.shortcutNextTab),
      ('F1 / ${shortcutText(primaryShortcut(LogicalKeyboardKey.f1))}', l.keyboardShortcuts),
      (shortcutText(primaryShortcut(LogicalKeyboardKey.keyQ)), l.shortcutQuit),
    ]),
    (l.shortcutsForm, [
      for (final a in RecordAction.values)
        if (recordShortcut(a) case final s?) (shortcutText(s), recordActionLabel(l, a)),
    ]),
    (l.shortcutsRelation, [
      ('F3', l.shortcutRelationNew),
      ('F2', l.shortcutRelationOpen),
    ]),
    (l.shortcutsList, [
      ('F4', l.shortcutListSwitch),
      ('F3', l.shortcutListNew),
      ('F2', l.shortcutListOpen),
      (l.keyDelete, l.shortcutListDelete),
      ('${_apple ? '⌘' : 'Ctrl+'}${l.keyDelete}', l.shortcutListRemove),
      (l.keyInsert, l.shortcutListUndelete),
    ]),
    (l.shortcutsDate, [
      ('=', l.shortcutDateToday),
      ('s i h d w m y', l.shortcutDateAdd),
      ('S I H D W M Y', l.shortcutDateSubtract),
    ]),
  ];
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('shortcuts-help'),
      title: Text(l.keyboardShortcuts),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (title, rows) in sections) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(title, style: Theme.of(ctx).textTheme.titleSmall),
              ),
              for (final (keys, label) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(child: Text(label)),
                    Text(keys,
                        style: TextStyle(
                            fontFamily: 'monospace',
                            color: Theme.of(ctx).colorScheme.primary)),
                  ]),
                ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(ctx.l10n.close),
        ),
      ],
    ),
  );
}

/// Activates the toolbar button below [key] like a click (record menu
/// entries and shortcuts of dropdown buttons, Python `sig_action` pops
/// up the button's menu): a dropdown opens, a plain button is pressed.
/// False when the button is missing or disabled.
bool pressButtonOf(GlobalKey key) {
  final element = key.currentContext as Element?;
  if (element == null) return false;
  PopupMenuButtonState<Object?>? popup;
  VoidCallback? onPressed;
  void visit(Element e) {
    if (popup != null || onPressed != null) return;
    if (e is StatefulElement && e.state is PopupMenuButtonState) {
      final button = e.widget as PopupMenuButton;
      if (button.enabled) popup = e.state as PopupMenuButtonState<Object?>;
      return;
    }
    final w = e.widget;
    if (w is IconButton) {
      onPressed = w.onPressed;
      if (onPressed == null) return;
      return;
    }
    e.visitChildElements(visit);
  }

  visit(element);
  if (popup case final p?) {
    p.showButtonMenu();
    return true;
  }
  if (onPressed case final f?) {
    f();
    return true;
  }
  return false;
}
