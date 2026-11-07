import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/rpc/bus_service.dart';
import '../../core/screen/screen.dart';
import '../actions/action_service.dart';
import '../auth/auth_provider.dart';
import '../model/model_service.dart';
import '../shell/tab_manager.dart';

/// Messenger of the app for in-app messages outside a screen (bus popups).
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// The bus of the session (spec 2.10).
final busServiceProvider = Provider<BusService>((ref) {
  final bus = BusService();
  ref.onDispose(bus.stop);
  return bus;
});

/// Number of unread notifications for the badge (`get_count`, bus).
final notificationCountProvider = StateProvider<int>((ref) => 0);

/// A `res.notification.get()` entry (spec 14.1).
class AppNotification {
  final int id;
  final String label;
  final String description;
  final String? icon;
  final String? model;
  final List<int> records;
  final int? action;
  final bool unread;

  const AppNotification({
    required this.id,
    required this.label,
    this.description = '',
    this.icon,
    this.model,
    this.records = const [],
    this.action,
    this.unread = false,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    String text(dynamic v) => v == null || v == false ? '' : '$v';
    final action = json['action'];
    return AppNotification(
      id: json['id'] as int,
      label: text(json['label']),
      description: text(json['description']),
      icon: json['icon'] is String && (json['icon'] as String).isNotEmpty
          ? json['icon'] as String
          : null,
      model: json['model'] is String && (json['model'] as String).isNotEmpty
          ? json['model'] as String
          : null,
      records: [
        for (final r in (json['records'] as List? ?? const []))
          if (r is int) r
      ],
      action: action is int ? action : (action is List && action.isNotEmpty ? action.first as int? : null),
      unread: json['unread'] == true,
    );
  }
}

/// Notifications of the session (spec 14.1, Python `NotificationMenu`):
/// counter, list, opening, and the bus channels `notification:<user_id>`
/// (counter, messages) and `client:<bus id>` (popups, `type ==
/// 'notification'`). Popups and new notifications show as in-app snack
/// bars (system notifications would need a package).
class NotificationCenter {
  final Ref ref;
  NotificationCenter(this.ref);

  String? _userChannel;
  String? _clientChannel;

  BusService get _bus => ref.read(busServiceProvider);
  ModelService get _svc => ref.read(modelServiceProvider);

  /// After login (start sequence 3.2 step 8): channels, counter, polling
  /// (only with `bus_url_host`).
  Future<void> start() async {
    stop();
    final session = ref.read(sessionProvider);
    final auth = ref.read(rpcClientProvider).auth;
    final userId = session.userId;
    final database = session.database;
    if (userId == null || database == null) return;
    _userChannel = 'notification:$userId';
    _clientChannel = 'client:${session.clientId}';
    _bus.register(_userChannel!, _onUserMessage);
    _bus.register(_clientChannel!, _onClientMessage);
    await refreshCount();
    if (auth != null) {
      _bus.start(host: session.busUrlHost, database: database, auth: auth);
    }
  }

  /// Logout: polling ends, channels and counter are cleared.
  void stop() {
    _bus.stop();
    if (_userChannel != null) _bus.unregister(_userChannel!, _onUserMessage);
    if (_clientChannel != null) {
      _bus.unregister(_clientChannel!, _onClientMessage);
    }
    _userChannel = _clientChannel = null;
    ref.read(notificationCountProvider.notifier).state = 0;
  }

  /// `res.notification.get_count()` → badge.
  Future<void> refreshCount() async {
    try {
      final count = await _svc.execute<dynamic>(
          'res.notification', 'get_count', const [],
          processException: false);
      if (count is int) {
        ref.read(notificationCountProvider.notifier).state = count;
      }
    } catch (_) {}
  }

  /// `res.notification.get()`.
  Future<List<AppNotification>> fetch() async {
    final result = await _svc.execute<dynamic>(
        'res.notification', 'get', const [],
        processException: false);
    return [
      for (final n in (result as List? ?? const []))
        if (n is Map) AppNotification.fromJson(Map<String, dynamic>.from(n))
    ];
  }

  /// Opens [n] (a tab of its records – one record: form – and/or its
  /// action), then `mark_read` (Python `NotificationMenu.open`).
  Future<void> open(BuildContext context, AppNotification n) async {
    if (n.model != null && n.records.isNotEmpty) {
      final one = n.records.length == 1;
      final title = await _svc.metadata?.name(n.model!) ?? '';
      ref.read(tabsProvider.notifier).openTab(
            title: title.isEmpty ? n.label : title,
            attributes: ScreenAttributes(
              n.model!,
              mode: one ? const ['form', 'tree'] : const ['tree', 'form'],
              domain: [
                ['id', 'in', n.records]
              ],
              resId: one ? n.records.first : null,
            ),
          );
    }
    if (n.action != null && context.mounted) {
      await ref
          .read(actionServiceProvider)
          .execute(n.action, ui: DialogActionUi(context));
    }
    if (n.unread) {
      try {
        await _svc.execute<dynamic>('res.notification', 'mark_read', [
          [n.id]
        ], processException: false);
      } catch (_) {}
      await refreshCount();
    }
  }

  /// „All notifications“: tab of the user's `res.notification`.
  void openAll(String title) {
    final userId = ref.read(sessionProvider).userId;
    ref.read(tabsProvider.notifier).openTab(
          title: title,
          attributes: ScreenAttributes('res.notification', domain: [
            ['user', '=', userId]
          ]),
        );
  }

  /// `notification:<user_id>`: `{type: user-notification, count,
  /// content: ["label\ndescription"]}` → counter and messages.
  void _onUserMessage(Map<String, dynamic> message) {
    if (message['type'] != 'user-notification') return;
    final count = message['count'];
    if (count is int) {
      ref.read(notificationCountProvider.notifier).state = count;
    }
    for (final text in (message['content'] as List? ?? const [])) {
      _show('$text');
    }
  }

  /// `client:<bus id>`: `{type: notification, title, body, priority}`.
  void _onClientMessage(Map<String, dynamic> message) {
    if (message['type'] != 'notification') return;
    final title = '${message['title'] ?? ''}';
    final body = '${message['body'] ?? ''}';
    _show([title, body].where((t) => t.isNotEmpty).join('\n'));
  }

  void _show(String text) {
    if (text.isEmpty) return;
    rootMessengerKey.currentState
        ?.showSnackBar(SnackBar(content: Text(text)));
  }
}

final notificationCenterProvider =
    Provider<NotificationCenter>((ref) => NotificationCenter(ref));

/// Bell with the counter; opens the list (spec 14.1).
class NotificationButton extends ConsumerWidget {
  const NotificationButton({super.key});

  Future<void> _openMenu(BuildContext context, WidgetRef ref) async {
    final center = ref.read(notificationCenterProvider);
    final l = context.l10n;
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final position = box == null || overlay == null
        ? const RelativeRect.fromLTRB(0, 56, 0, 0)
        : RelativeRect.fromRect(
            Rect.fromPoints(
                box.localToGlobal(box.size.bottomLeft(Offset.zero),
                    ancestor: overlay),
                box.localToGlobal(box.size.bottomRight(Offset.zero),
                    ancestor: overlay)),
            Offset.zero & overlay.size);
    List<AppNotification> items;
    try {
      items = await center.fetch();
    } catch (_) {
      items = const [];
    }
    if (!context.mounted) return;
    // like Python: the indicator is cleared once the list was shown
    ref.read(notificationCountProvider.notifier).state = 0;
    final cs = Theme.of(context).colorScheme;
    final chosen = await showMenu<Object>(
      context: context,
      position: position,
      items: [
        if (items.isEmpty)
          PopupMenuItem<Object>(enabled: false, child: Text(l.noNotifications))
        else ...[
          for (final n in items)
            PopupMenuItem<Object>(
              key: ValueKey('notification-${n.id}'),
              value: n,
              child: SizedBox(
                width: 320,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 8),
                    child: TrytonIcon(
                        iconName: n.icon ?? 'tryton-notification',
                        size: 18,
                        fallback: Icons.notifications_outlined),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(n.label,
                            style: TextStyle(
                                fontWeight:
                                    n.unread ? FontWeight.w600 : FontWeight.normal)),
                        if (n.description.isNotEmpty)
                          Text(n.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: cs.outline)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          const PopupMenuDivider(),
          PopupMenuItem<Object>(
            key: const ValueKey('notification-all'),
            value: 'all',
            child: Text(l.allNotifications),
          ),
        ],
      ],
    );
    if (!context.mounted) return;
    if (chosen is AppNotification) {
      await center.open(context, chosen);
    } else if (chosen == 'all') {
      center.openAll(l.notifications);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(notificationCountProvider);
    return IconButton(
      key: const ValueKey('notification-button'),
      tooltip: context.l10n.notifications,
      onPressed: () => _openMenu(context, ref),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
