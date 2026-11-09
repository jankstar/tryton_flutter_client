import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/rpc/bus_service.dart';
import '../../shared/dialogs/tryton_dialogs.dart';
import '../../shared/utils/date_format_utils.dart';
import '../auth/auth_provider.dart';
import '../model/model_service.dart';
import '../notifications/notifications.dart';

/// A message of `ir.chat.channel.get` (`ir.chat.message.as_dict`).
typedef ChatMessage = ({
  int id,
  DateTime? timestamp,
  String author,
  String content,
  bool internal,
});

/// A follower of `get_followers`/`search_followers`: `type` `user` or
/// `email`, `key` login or address, `name`.
typedef ChatFollower = ({String type, String key, String name});

/// The chat of a record (spec 14.2, Python `tryton/chat.py`): the
/// messages of `ir.chat.channel.get(resource)`, sending with
/// `post(resource, text, 'internal'|'public')`, the followers
/// (`get_followers`, `search_followers`, `subscribe`/`subscribe_email`,
/// `unsubscribe`/`unsubscribe_email`, oneself with `subscribe`/
/// `unsubscribe(resource)`), live updates over the bus channel
/// `chat:<model>,<id>` (registered while shown).
class ChatPanel extends ConsumerStatefulWidget {
  /// `<model>,<id>` of the record.
  final String resource;
  final VoidCallback? onClose;

  const ChatPanel({super.key, required this.resource, this.onClose});

  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  List<ChatMessage> _messages = const [];
  List<ChatFollower> _followers = const [];
  bool _loading = true;
  bool _internal = false;
  bool _sending = false;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final BusService _bus = ref.read(busServiceProvider);

  String get _channel => 'chat:${widget.resource}';
  String? get _login => ref.read(sessionProvider).login;

  /// The user follows the channel.
  bool get _subscribed =>
      _followers.any((f) => f.type == 'user' && f.key == _login);

  @override
  void initState() {
    super.initState();
    _bus.register(_channel, _onBus);
    _refresh();
    _loadFollowers();
  }

  @override
  void didUpdateWidget(ChatPanel old) {
    super.didUpdateWidget(old);
    if (old.resource != widget.resource) {
      // another record: another channel (Python `Form` re-creates Chat)
      _bus.unregister('chat:${old.resource}', _onBus);
      _bus.register(_channel, _onBus);
      _messages = const [];
      _followers = const [];
      _refresh();
      _loadFollowers();
    }
  }

  @override
  void dispose() {
    _bus.unregister(_channel, _onBus);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onBus(Map<String, dynamic> message) {
    if (message['type'] == 'message' && mounted) _refresh();
  }

  ModelService get _svc => ref.read(modelServiceProvider);

  Future<T?> _call<T>(String method, List<dynamic> params) async {
    try {
      return await _svc.execute<T>('ir.chat.channel', method, params,
          processException: false);
    } catch (_) {
      return null; // like Python: RPCException → nothing
    }
  }

  static ChatMessage? _message(dynamic m) {
    if (m is! Map) return null;
    final ts = m['timestamp'];
    return (
      id: (m['id'] as num?)?.toInt() ?? 0,
      timestamp: ts is DateTime ? ts : null,
      author: '${m['author'] ?? ''}',
      content: '${m['content'] ?? ''}',
      internal: m['audience'] == 'internal',
    );
  }

  static ChatFollower? _follower(dynamic f) => f is Map
      ? (type: '${f['type']}', key: '${f['key']}', name: '${f['name'] ?? f['key']}')
      : null;

  /// The messages again (Python `Chat.refresh`), scrolled to the end.
  Future<void> _refresh() async {
    final result = await _call<List>('get', [widget.resource]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _messages = [for (final m in result ?? const []) ?_message(m)];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _loadFollowers() async {
    final result = await _call<List>('get_followers', [widget.resource]);
    if (!mounted) return;
    setState(() =>
        _followers = [for (final f in result ?? const []) ?_follower(f)]);
  }

  /// Sends the text (Ctrl/Cmd+Enter or Send); without a running bus the
  /// messages are read again (Python `_submit`).
  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    await _call<dynamic>(
        'post', [widget.resource, text, _internal ? 'internal' : 'public']);
    if (!mounted) return;
    _input.clear();
    setState(() => _sending = false);
    if (!_bus.running) await _refresh();
  }

  Future<void> _toggleSubscribe() async {
    await _call<dynamic>(
        _subscribed ? 'unsubscribe' : 'subscribe', [widget.resource]);
    await _loadFollowers();
  }

  Future<void> _unsubscribe(ChatFollower f) async {
    final l = context.l10n;
    if (!await showSur(context, l.chatUnsubscribeQuestion(f.name))) return;
    await _call<dynamic>(f.type == 'email' ? 'unsubscribe_email' : 'unsubscribe',
        [widget.resource, f.key]);
    await _loadFollowers();
  }

  Future<void> _subscribeFollower(ChatFollower f) async {
    await _call<dynamic>(f.type == 'email' ? 'subscribe_email' : 'subscribe',
        [widget.resource, f.key]);
    await _loadFollowers();
  }

  Future<List<ChatFollower>> _search(String text) async {
    if (text.trim().isEmpty) return const [];
    final result =
        await _call<List>('search_followers', [widget.resource, text]);
    return [
      for (final f in result ?? const [])
        if (_follower(f) case final follower?)
          if (!(follower.type == 'user' && follower.key == _login)) follower
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('chat-panel'),
      decoration: BoxDecoration(
          border: Border(left: BorderSide(color: cs.outlineVariant))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: cs.surfaceContainerHigh,
          padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
          child: Row(children: [
            Expanded(child: _followerEntry()),
            _followerButton(),
            if (widget.onClose != null)
              IconButton(
                key: const ValueKey('chat-close'),
                icon: const Icon(Icons.close, size: 18),
                tooltip: l.close,
                onPressed: widget.onClose,
              ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _messages.isEmpty
                  ? Center(child: Text(l.chatEmpty))
                  : ListView.builder(
                      key: const ValueKey('chat-messages'),
                      controller: _scroll,
                      padding: const EdgeInsets.all(8),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) => _bubble(_messages[i]),
                    ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter, control: true):
                    _send,
                const SingleActivator(LogicalKeyboardKey.enter, meta: true): _send,
              },
              child: TextField(
                key: const ValueKey('chat-input'),
                controller: _input,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(), isDense: true),
              ),
            ),
            Row(children: [
              Checkbox(
                key: const ValueKey('chat-internal'),
                value: _internal,
                onChanged: (v) => setState(() => _internal = v ?? false),
              ),
              Expanded(child: Text(l.chatInternal, style: const TextStyle(fontSize: 12))),
              FilledButton.icon(
                key: const ValueKey('chat-send'),
                icon: const Icon(Icons.send, size: 16),
                label: Text(l.emailSend),
                onPressed: _sending ? null : _send,
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _bubble(ChatMessage m) {
    final cs = Theme.of(context).colorScheme;
    final time = m.timestamp;
    return Padding(
      key: ValueKey('chat-message-${m.id}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: m.internal ? cs.tertiaryContainer.withAlpha(90) : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(m.author,
                    style: Theme.of(context).textTheme.labelLarge,
                    overflow: TextOverflow.ellipsis),
              ),
              if (m.internal)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(context.l10n.chatInternalTag,
                      style: TextStyle(fontSize: 11, color: cs.tertiary)),
                ),
              if (time != null)
                Text(formatDateTimeValue(time.toLocal()),
                    style: TextStyle(fontSize: 11, color: cs.outline)),
            ]),
            const SizedBox(height: 4),
            SelectableText(m.content),
          ]),
        ),
      ),
    );
  }

  /// „Add a follower“: `search_followers` while typing, a choice
  /// subscribes the follower.
  Widget _followerEntry() => Autocomplete<ChatFollower>(
        displayStringForOption: (f) => f.name,
        optionsBuilder: (value) => _search(value.text),
        onSelected: (f) async {
          await _subscribeFollower(f);
        },
        fieldViewBuilder: (context, controller, focus, onSubmitted) {
          return TextField(
            key: const ValueKey('chat-add-follower'),
            controller: controller,
            focusNode: focus,
            decoration: InputDecoration(
              hintText: context.l10n.chatAddFollower,
              isDense: true,
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.person_add_alt, size: 18),
            ),
            onSubmitted: (_) => onSubmitted(),
          );
        },
      );

  /// The followers (others with ×) and „Subscribe/Unsubscribe“ oneself.
  Widget _followerButton() {
    final others = [
      for (final f in _followers)
        if (!(f.type == 'user' && f.key == _login)) f
    ];
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('chat-toggle-subscribe'),
          onPressed: _toggleSubscribe,
          child: Text(_subscribed
              ? context.l10n.chatUnsubscribe
              : context.l10n.chatSubscribe),
        ),
        for (final f in others)
          MenuItemButton(
            key: ValueKey('chat-follower-${f.key}'),
            trailingIcon: const Icon(Icons.close, size: 16),
            onPressed: () => _unsubscribe(f),
            child: Text(f.name),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        key: const ValueKey('chat-followers'),
        icon: Icon(_subscribed
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined),
        tooltip: context.l10n.chatFollowers,
        onPressed: () async {
          if (controller.isOpen) {
            controller.close();
          } else {
            await _loadFollowers();
            controller.open();
          }
        },
      ),
    );
  }
}
