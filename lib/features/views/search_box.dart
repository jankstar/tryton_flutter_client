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
import '../../shared/dialogs/tryton_dialogs.dart';

/// Search bar of a list (spec 8.4, SAO `ScreenContainer`): text with the
/// DomainParser syntax and completions, filter dialog, bookmarks (star +
/// saved searches of VIEW_SEARCH) and "Show inactive records" when the
/// tree view has `active`. [onSearch] runs the search with the text.
class SearchBox extends ConsumerStatefulWidget {
  final TrytonScreen screen;
  final TextEditingController controller;
  final VoidCallback onSearch;

  /// Focus of the entry (record menu „Search“, Ctrl+Shift+F).
  final FocusNode? focusNode;

  const SearchBox({
    super.key,
    required this.screen,
    required this.controller,
    required this.onSearch,
    this.focusNode,
  });

  @override
  ConsumerState<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends ConsumerState<SearchBox> {
  late final _focus = widget.focusNode ?? FocusNode();
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
    if (widget.focusNode == null) _focus.dispose();
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

  Future<String?> _askName() async =>
      (await showAsk(context, context.l10n.bookmarkName))?.trim();

  void _activateBookmark(List<dynamic> bookmark) {
    final parser = _parser;
    if (parser == null) return;
    widget.controller.text = parser.string(bookmark[2] as List);
    _search();
  }

  // ── Filter dialog ─────────────────────────────────────────────────────────

  /// Inputs of the filter dialog and the search text they gave (Python
  /// `last_search_text`): another text (cleared, typed, bookmark) empties
  /// them; reopening after the search keeps them.
  final FilterValues _filterValues = FilterValues();
  String? _filterText;

  Future<void> _filter() async {
    final parser = _parser;
    if (parser == null) return;
    // (compared as domain: the search shows the text normalized)
    final last = _filterText;
    if (last == null ||
        !domainEquals(parser.parse(last), parser.parse(widget.controller.text))) {
      _filterValues.clear();
    }
    final text = await showDialog<String>(
      context: context,
      builder: (_) => FilterDialog(parser: parser, values: _filterValues),
    );
    if (text == null || !mounted) return;
    widget.controller.text = text;
    _filterText = text;
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

/// Inputs of the filter dialog, kept by the search bar between openings
/// (Python `search_popover`): emptied when the search text is no longer
/// the one the dialog wrote (cleared, typed, bookmark).
class FilterValues {
  final Map<String, String> text = {};
  final Map<String, String> to = {};
  final Map<String, String?> choice = {};
  final Map<String, Set<String>> multi = {};

  void clear() {
    text.clear();
    to.clear();
    choice.clear();
    multi.clear();
  }
}

/// Labels of a selection field for the filter dialog (Python
/// `screen_container.search_box`): all labels of `selection` (method
/// selections are resolved by `TrytonScreen.loadDomainParser`), sorted
/// unless `sort` is false.
List<String> filterSelectionLabels(Map<String, dynamic> field) {
  final selection = field['selection'];
  final labels = <String>[
    if (selection is List)
      for (final s in selection)
        if (s is List && s.length >= 2) '${s[1] ?? ''}'
  ];
  if (field['sort'] != false) labels.sort();
  final seen = <String>{};
  return [for (final l in labels) if (seen.add(l)) l];
}

/// Filter dialog (spec 8.4, Python `ScreenContainer.search_box`): one
/// input per searchable field of the parser (boolean: choice, selection:
/// list with multiple choice, date/number: from–to, else text); returns
/// the search text `Label: value …` (several selection values `A;B`).
class FilterDialog extends StatefulWidget {
  final DomainParser parser;

  /// Inputs to start with and to keep (else a fresh set).
  final FilterValues? values;
  const FilterDialog({super.key, required this.parser, this.values});

  @override
  State<FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<FilterDialog> {
  late final FilterValues _values = widget.values ?? FilterValues();
  final Map<String, TextEditingController> _text = {};
  final Map<String, TextEditingController> _to = {};
  Map<String, String?> get _choice => _values.choice;
  Map<String, Set<String>> get _multi => _values.multi;

  /// Rebuilds the inputs after „Clear“ (new keys for the form fields).
  int _generation = 0;

  static const _range = {
    'integer', 'float', 'numeric', 'date', 'datetime', 'timestamp', 'time'
  };

  List<Map<String, dynamic>> get _fields => [
        for (final f in widget.parser.fields.values)
          if (!'${f['name']}'.contains('.') && f['searchable'] != false) f
      ];

  TextEditingController _ctrl(Map<String, TextEditingController> map,
      Map<String, String> store, String name) =>
      map.putIfAbsent(name, () {
        final c = TextEditingController(text: store[name] ?? '');
        c.addListener(() => store[name] = c.text);
        return c;
      });

  @override
  void dispose() {
    for (final c in [..._text.values, ..._to.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _clear() => setState(() {
        _values.clear();
        for (final c in [..._text.values, ..._to.values]) {
          c.clear();
        }
        _generation++;
      });

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
          // in the order of the list (Python `get_selected_rows`)
          value = [
            for (final c in filterSelectionLabels(f))
              if (chosen.contains(c)) '${quote(c, empty: true)}'
          ].join(';');
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

  /// Framed list of the options with a check box per row (Python
  /// `Selection`: multiple choice, up to 200 px high).
  Widget _selection(String name, String label, List<String> options) {
    final theme = Theme.of(context);
    final chosen = _multi.putIfAbsent(name, () => {});
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: ListView(
          key: ValueKey('filter-$name'),
          shrinkWrap: true,
          children: [
            for (final o in options)
              InkWell(
                key: ValueKey('filter-$name-$o'),
                onTap: () => setState(() {
                  chosen.contains(o) ? chosen.remove(o) : chosen.add(o);
                }),
                child: Container(
                  color: chosen.contains(o)
                      ? theme.colorScheme.primary.withValues(alpha: 0.08)
                      : null,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Checkbox(
                      value: chosen.contains(o),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (on) => setState(() {
                        on == true ? chosen.add(o) : chosen.remove(o);
                      }),
                    ),
                    const SizedBox(width: 4),
                    Expanded(child: Text(o.isEmpty ? '""' : o)),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _input(Map<String, dynamic> f) {
    final l = context.l10n;
    final name = '${f['name']}';
    final label = '${f['string']}';
    final type = f['type'];
    if (type == 'boolean') {
      return DropdownButtonFormField<String?>(
        key: ValueKey('filter-$name-$_generation'),
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
      return _selection(name, label, filterSelectionLabels(f));
    }
    if (_range.contains(type)) {
      return Row(children: [
        Expanded(
          child: TextField(
            key: ValueKey('filter-from-$name'),
            controller: _ctrl(_text, _values.text, name),
            decoration: InputDecoration(
                labelText: '$label (${l.rangeFrom})', isDense: true),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            key: ValueKey('filter-to-$name'),
            controller: _ctrl(_to, _values.to, name),
            decoration: InputDecoration(
                labelText: '$label (${l.rangeTo})', isDense: true),
          ),
        ),
      ]);
    }
    return TextField(
      key: ValueKey('filter-$name'),
      controller: _ctrl(_text, _values.text, name),
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
            key: const ValueKey('filter-clear'),
            onPressed: _clear,
            child: Text(l.clear)),
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
            key: const ValueKey('filter-find'),
            onPressed: () => Navigator.pop(context, _result()),
            child: Text(l.find)),
      ],
    );
  }
}
