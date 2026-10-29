import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain/domain_inversion.dart' show domainEquals;
import '../../core/domain/domain_parser.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/pyson/pyson_encoder.dart';
import '../../core/rpc/error_processing.dart';
import '../../core/screen/screen.dart';
import '../../shared/errors/error_dialogs.dart';
import '../model/model_service.dart';

/// Search bar of a list (spec 8.4, SAO `ScreenContainer`): text with the
/// DomainParser syntax and completions, filter dialog, bookmarks (star +
/// saved searches of VIEW_SEARCH) and "Show inactive records" when the
/// tree view has `active`. [onSearch] runs the search with the text.
class SearchBox extends ConsumerStatefulWidget {
  final TrytonScreen screen;
  final TextEditingController controller;
  final VoidCallback onSearch;

  const SearchBox({
    super.key,
    required this.screen,
    required this.controller,
    required this.onSearch,
  });

  @override
  ConsumerState<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends ConsumerState<SearchBox> {
  final _focus = FocusNode();
  List<String> _completions = const [];

  TrytonScreen get _screen => widget.screen;
  DomainParser? get _parser => _screen.domainParser;
  String get _model => _screen.model.name;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        // Delay so a tap on a completion fires first.
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted && !_focus.hasFocus) setState(() => _completions = const []);
        });
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _focus.dispose();
    super.dispose();
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  void _updateCompletions(String text) {
    final parser = _parser;
    if (parser == null) return;
    final seen = <String>{};
    setState(() {
      _completions = [
        for (final c in parser.completion(text).map((c) => c.trim()))
          if (c.isNotEmpty && c != text.trim() && seen.add(c)) c
      ].take(8).toList();
    });
  }

  void _search() {
    setState(() => _completions = const []);
    widget.onSearch();
  }

  // ── Bookmarks ─────────────────────────────────────────────────────────────

  /// Saved searches of the model that can be written as text.
  List<List<dynamic>> get _bookmarks {
    final parser = _parser;
    final metadata = ref.read(modelServiceProvider).metadata;
    if (parser == null || metadata == null) return const [];
    return [
      for (final s in metadata.searches(_model))
        if (s is List && s.length >= 3 && s[2] is List && parser.stringable(s[2] as List))
          s
    ];
  }

  /// Bookmark matching the text (by text or domain), SAO `bookmark_match`.
  List<dynamic>? get _match {
    final parser = _parser;
    final text = widget.controller.text;
    if (parser == null || text.isEmpty) return null;
    final domain = parser.parse(text);
    for (final b in _bookmarks) {
      if (parser.string(b[2] as List) == text || domainEquals(b[2], domain)) {
        return b;
      }
    }
    return null;
  }

  Future<void> _star() async {
    final parser = _parser;
    final metadata = ref.read(modelServiceProvider).metadata;
    if (parser == null || metadata == null) return;
    final match = _match;
    try {
      if (match == null) {
        final text = widget.controller.text;
        if (text.isEmpty) return;
        final name = await _askName();
        if (name == null || name.isEmpty) return;
        final domain = parser.parse(text);
        await metadata.addSearch(
            _model, name, domain, PYSONEncoder().encode(domain));
        widget.controller.text = parser.string(domain);
      } else {
        await metadata.removeSearch(_model, match[0]);
      }
    } on HandledRpcError {
      // shown
    } catch (e) {
      if (mounted) await errorHandlerOf(context, ref).show(e);
    }
    if (mounted) setState(() {});
  }

  Future<String?> _askName() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.bookmarkName),
        content: TextField(
          key: const ValueKey('bookmark-name'),
          controller: ctrl,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(ctx.l10n.ok)),
        ],
      ),
    );
  }

  void _activateBookmark(List<dynamic> bookmark) {
    final parser = _parser;
    if (parser == null) return;
    widget.controller.text = parser.string(bookmark[2] as List);
    _search();
  }

  // ── Filter dialog ─────────────────────────────────────────────────────────

  Future<void> _filter() async {
    final parser = _parser;
    if (parser == null) return;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => FilterDialog(parser: parser),
    );
    if (text == null || !mounted) return;
    widget.controller.text = text;
    _search();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final primary = Theme.of(context).colorScheme.primary;
    final parser = _parser;
    final bookmarks = _bookmarks;
    final match = _match;
    final hasText = widget.controller.text.isNotEmpty;
    Widget button(IconData icon, String tip, VoidCallback? onPressed,
            {Key? key, Color? color}) =>
        IconButton(
          key: key,
          icon: Icon(icon, size: 18, color: color),
          tooltip: tip,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        );
    final field = TextField(
      key: const ValueKey('search-text'),
      controller: widget.controller,
      focusNode: _focus,
      decoration: InputDecoration(
        hintText: l.search,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
          if (hasText)
            button(Icons.clear, l.clearSearch, () {
              widget.controller.clear();
              _search();
            }),
          if (parser != null)
            button(Icons.tune, l.filters, _filter,
                key: const ValueKey('search-filter')),
          if (parser != null)
            button(match == null ? Icons.star_border : Icons.star,
                match == null ? l.bookmarkFilter : l.removeBookmark,
                (match == null && !hasText) ||
                        (match != null && match.length > 3 && match[3] == false)
                    ? null
                    : _star,
                key: const ValueKey('search-star'),
                color: match == null ? null : Colors.amber),
          if (parser != null && bookmarks.isNotEmpty)
            PopupMenuButton<List<dynamic>>(
              key: const ValueKey('search-bookmarks'),
              icon: const Icon(Icons.bookmarks_outlined, size: 18),
              tooltip: l.bookmarks,
              onSelected: _activateBookmark,
              itemBuilder: (_) => [
                for (final b in bookmarks)
                  PopupMenuItem(value: b, child: Text('${b[1]}')),
              ],
            ),
          if (_screen.hasActiveField)
            button(
              Icons.inventory_2_outlined,
              _screen.showInactive ? l.showActive : l.showInactive,
              () {
                setState(() => _screen.showInactive = !_screen.showInactive);
                _search();
              },
              key: const ValueKey('search-active'),
              color: _screen.showInactive ? primary : null,
            ),
          button(Icons.search, l.search, _search, color: primary),
        ]),
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onChanged: _updateCompletions,
      onTap: () => _updateCompletions(widget.controller.text),
      onSubmitted: (_) => _search(),
      textInputAction: TextInputAction.search,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        if (_completions.isNotEmpty)
          Material(
            elevation: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in _completions)
                  InkWell(
                    onTap: () {
                      widget.controller.text = c;
                      widget.controller.selection =
                          TextSelection.collapsed(offset: c.length);
                      _updateCompletions(c);
                      _focus.requestFocus();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Text(c, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Filter dialog (spec 8.4): one input per field (boolean: choice,
/// selection: multiple choice, date/number: from–to, else text); returns
/// the search text `Label: value …`.
class FilterDialog extends StatefulWidget {
  final DomainParser parser;
  const FilterDialog({super.key, required this.parser});

  @override
  State<FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<FilterDialog> {
  final Map<String, TextEditingController> _text = {};
  final Map<String, TextEditingController> _to = {};
  final Map<String, String?> _choice = {};
  final Map<String, Set<String>> _multi = {};

  static const _range = {
    'integer', 'float', 'numeric', 'date', 'datetime', 'timestamp', 'time'
  };

  List<Map<String, dynamic>> get _fields => [
        for (final f in widget.parser.fields.values)
          if (!'${f['name']}'.contains('.')) f
      ];

  TextEditingController _ctrl(Map<String, TextEditingController> map, String name) =>
      map.putIfAbsent(name, TextEditingController.new);

  @override
  void dispose() {
    for (final c in [..._text.values, ..._to.values]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Search text of the filled inputs.
  String _result() {
    final parts = <String>[];
    for (final f in _fields) {
      final name = '${f['name']}';
      final label = '${quote(f['string'])}';
      final type = f['type'];
      String? value;
      if (type == 'boolean') {
        value = _choice[name];
      } else if (type == 'selection' || type == 'multiselection') {
        final chosen = _multi[name] ?? const {};
        if (chosen.isNotEmpty) {
          value = [for (final c in chosen) '${quote(c, empty: true)}'].join(';');
        }
      } else if (_range.contains(type)) {
        final from = _text[name]?.text.trim() ?? '';
        final to = _to[name]?.text.trim() ?? '';
        if (from.isNotEmpty && to.isNotEmpty) {
          value = '${quote(from)}..${quote(to)}';
        } else if (from.isNotEmpty) {
          value = '>=${quote(from)}';
        } else if (to.isNotEmpty) {
          value = '<=${quote(to)}';
        }
      } else {
        final text = _text[name]?.text.trim() ?? '';
        if (text.isNotEmpty) value = '${quote(text)}';
      }
      if (value != null && value.isNotEmpty) parts.add('$label: $value');
    }
    return parts.join(' ');
  }

  Widget _input(Map<String, dynamic> f) {
    final l = context.l10n;
    final name = '${f['name']}';
    final label = '${f['string']}';
    final type = f['type'];
    if (type == 'boolean') {
      return DropdownButtonFormField<String?>(
        initialValue: _choice[name],
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          const DropdownMenuItem(value: null, child: Text('')),
          DropdownMenuItem(value: 'True', child: Text(l.boolYes)),
          DropdownMenuItem(value: 'False', child: Text(l.boolNo)),
        ],
        onChanged: (v) => setState(() => _choice[name] = v),
      );
    }
    if (type == 'selection' || type == 'multiselection') {
      final options = [
        for (final s in (f['selection'] as List? ?? const []))
          if (s is List && s.length >= 2 && '${s[1]}'.isNotEmpty) '${s[1]}'
      ];
      final chosen = _multi.putIfAbsent(name, () => {});
      return InputDecorator(
        decoration: InputDecoration(labelText: label, isDense: true),
        child: Wrap(spacing: 4, runSpacing: 4, children: [
          for (final o in options)
            FilterChip(
              label: Text(o),
              selected: chosen.contains(o),
              onSelected: (on) => setState(() {
                on ? chosen.add(o) : chosen.remove(o);
              }),
            ),
        ]),
      );
    }
    if (_range.contains(type)) {
      return Row(children: [
        Expanded(
          child: TextField(
            key: ValueKey('filter-from-$name'),
            controller: _ctrl(_text, name),
            decoration: InputDecoration(
                labelText: '$label (${l.rangeFrom})', isDense: true),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            key: ValueKey('filter-to-$name'),
            controller: _ctrl(_to, name),
            decoration: InputDecoration(
                labelText: '$label (${l.rangeTo})', isDense: true),
          ),
        ),
      ]);
    }
    return TextField(
      key: ValueKey('filter-$name'),
      controller: _ctrl(_text, name),
      decoration: InputDecoration(labelText: label, isDense: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.filters),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final f in _fields)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _input(f),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
            onPressed: () => Navigator.pop(context, _result()),
            child: Text(l.find)),
      ],
    );
  }
}
