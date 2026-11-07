import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/model/model.dart';
import '../../core/screen/screen.dart';
import '../../core/xml/view_definition.dart';
import '../actions/action_service.dart';
import '../auth/auth_provider.dart';
import '../model/model_service.dart';

/// `ir.action.get_action_value` per action id of the links (session-wide).
final Map<int, Map<String, dynamic>> _actions = {};

/// Clears the cached link actions (logout, language change).
void clearLinkActionCache() => _actions.clear();

/// `<link id="…">` of a form (spec 9.2.1, Python `state_widget.Link`): a
/// button with the action name and a counter per tab domain with `count`
/// (else one for the action domain) from `search_count` up to 100
/// (`99+`), without error dialog. Hidden for new records; with
/// `empty="hide"` while all counters are 0. A click runs the action with
/// the record as data (keyword: name suffix).
class RecordLink extends ConsumerStatefulWidget {
  final LinkNode node;
  final Record record;

  const RecordLink({super.key, required this.node, required this.record});

  @override
  ConsumerState<RecordLink> createState() => _RecordLinkState();
}

class _RecordLinkState extends ConsumerState<RecordLink> {

  Map<String, dynamic>? _action;
  List<String> _tabNames = const [];

  /// Record whose counters are shown (a late answer of another one is
  /// dropped, Python `_current`).
  int? _current;

  int? get _actionId => widget.node.actionId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RecordLink old) {
    super.didUpdateWidget(old);
    if (!identical(old.record, widget.record) ||
        _current != widget.record.id) {
      _load();
    }
  }

  Map<String, dynamic> get _data => {
        'model': widget.record.model.name,
        'id': widget.record.id,
        'ids': [widget.record.id],
      };

  Future<void> _load() async {
    final record = widget.record;
    final actionId = _actionId;
    _current = record.id;
    if (actionId == null || record.id < 0) return;
    final svc = ref.read(modelServiceProvider);
    final context = record.getContext();
    var action = _actions[actionId];
    if (action == null) {
      try {
        final result = await svc.execute<dynamic>(
            'ir.action', 'get_action_value', [actionId],
            context: context, processException: false);
        if (result is! Map) return;
        action = _actions[actionId] = Map<String, dynamic>.from(result);
      } catch (_) {
        return;
      }
    }
    if (!mounted || _current != record.id) return;
    final session = ref.read(sessionProvider);
    final attributes = ScreenAttributes.fromActWindow(action,
        sessionContext: session.context,
        userId: session.userId,
        data: _data,
        context: context);
    final domain = attributes.searchValue == null ||
            attributes.searchValue!.isEmpty
        ? attributes.domain
        : [attributes.domain, attributes.searchValue];
    final tabs = [for (final t in attributes.tabDomain) if (t.count) t];
    setState(() {
      _action = action;
      _tabNames = [for (final t in tabs) t.name];
    });
    final cached = record.linksCounts['$actionId'];
    if (cached is List) return; // counted for this record already
    final counter = List<dynamic>.filled(tabs.isEmpty ? 1 : tabs.length, 0);
    record.linksCounts['$actionId'] = counter;
    final model = attributes.model;
    final domains = tabs.isEmpty
        ? [domain]
        : [
            for (final t in tabs) ['AND', domain, t.domain]
          ];
    await Future.wait([
      for (var i = 0; i < domains.length; i++)
        svc
            .execute<dynamic>(model, 'search_count', [domains[i], 0, 100],
                context: context, processException: false)
            .then((count) {
          if (count is int) counter[i] = count > 99 ? '99+' : count;
        }).catchError((Object _) {}),
    ]);
    if (mounted && _current == record.id) setState(() {});
  }

  Future<void> _open() async {
    final actionId = _actionId;
    if (actionId == null) return;
    await ref.read(actionServiceProvider).execute(actionId,
        data: _data,
        context: widget.record.getContext(),
        keyword: true,
        ui: DialogActionUi(context));
  }

  @override
  Widget build(BuildContext context) {
    final action = _action;
    if (widget.record.id < 0 || action == null) return const SizedBox.shrink();
    final counter =
        widget.record.linksCounts['$_actionId'] as List? ?? const [0];
    if (widget.node.hideEmpty && !counter.any((c) => c != 0)) {
      return const SizedBox.shrink();
    }
    final name = '${action['name'] ?? ''}';
    final label = _tabNames.isEmpty
        ? '$name (${counter.first})'
        : [
            name,
            for (var i = 0; i < _tabNames.length; i++)
              '${_tabNames[i]} (${i < counter.length ? counter[i] : 0})'
          ].join('\n');
    final icon = widget.node.icon;
    final cs = Theme.of(context).colorScheme;
    return TextButton(
      key: ValueKey('link-button-$_actionId'),
      onPressed: _open,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) TrytonIcon(iconName: icon, size: 24, color: cs.primary),
        Text(label, textAlign: TextAlign.center),
      ]),
    );
  }
}

/// `<image name="…" type="icon|url|color">` of a form (spec 9.2.1, Python
/// `state_widget.Image`): an icon, an image URL or a colour square; the
/// name may be a field of the record holding the value.
class RecordImage extends StatelessWidget {
  final ImageNode node;
  final Record record;

  const RecordImage({super.key, required this.node, required this.record});

  @override
  Widget build(BuildContext context) {
    var name = node.name;
    final field = record.model.fields[name];
    if (field != null) {
      final value = field.get(record);
      name = value == null || value == false ? '' : '$value';
    }
    final size = node.size.toDouble();
    Widget image;
    switch (node.type) {
      case 'url':
        if (name.isEmpty) return SizedBox(width: size, height: size);
        final url = node.urlSize == null
            ? name
            : Uri.parse(name).replace(queryParameters: {
                ...Uri.parse(name).queryParameters,
                node.urlSize!: '${node.size}',
              }).toString();
        image = Image.network(url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                Icon(Icons.broken_image_outlined, size: size));
      case 'color':
        image = Container(
            width: size, height: size, color: _parseColor(name) ?? Colors.transparent);
      default:
        image = TrytonIcon(
            iconName: name.isEmpty ? null : name,
            size: size,
            fallback: Icons.image_outlined);
    }
    switch (node.border) {
      case 'circle':
        image = ClipOval(child: image);
      case 'rounded':
        image = ClipRRect(borderRadius: BorderRadius.circular(size / 8), child: image);
    }
    return Align(alignment: Alignment.center, child: image);
  }

  /// `#rrggbb` / `#rgb` / `#rrggbbaa`.
  static Color? _parseColor(String text) => parseHexColor(text);
}

/// A CSS hex colour (`#rgb`, `#rrggbb`, `#rrggbbaa`) or null.
Color? parseHexColor(String? text) {
  if (text == null) return null;
  var hex = text.trim();
  if (!hex.startsWith('#')) return null;
  hex = hex.substring(1);
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length == 6) hex = '${hex}ff';
  if (hex.length != 8) return null;
  final v = int.tryParse(hex, radix: 16);
  if (v == null) return null;
  // rrggbbaa → aarrggbb
  return Color(((v & 0xff) << 24) | (v >> 8));
}
