import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart' hide TextField;
import '../../core/rpc/error_processing.dart';
import '../../core/screen/screen.dart';
import '../../core/xml/form_xml_parser.dart';
import '../../core/xml/view_definition.dart';
import '../model/field_support.dart';
import 'form_dialog.dart';
import 'record_cells.dart';

/// A record chosen in the search dialog: id and rec_name.
typedef SearchResult = ({int id, String name});

/// rec_name of [record]: the loaded value, else read.
Future<String> _recName(Record record) async {
  final loaded = record.values['rec_name'];
  return loaded is String ? loaded : record.recName();
}

/// Search popup (spec 11.2, SAO `Sao.Window.Search`) for [model]: a list
/// with search, single or multiple ([multi]) selection and the buttons
/// Cancel, Find, New ([allowNew]) and OK ([okLabel]). With [searchText]
/// and exactly one hit, the hit is returned without dialog.
///
/// Returns the chosen records; empty when cancelled.
Future<List<SearchResult>> showSearchDialog(
  BuildContext context, {
  required String model,
  required ModelSession session,
  List<dynamic> domain = const [],
  Map<String, dynamic> searchContext = const {},
  List<dynamic>? order,
  List<int?> viewIds = const [],
  Map<String, Map<String, dynamic>> viewsPreload = const {},
  bool multi = false,
  bool allowNew = false,
  String? searchText,
  String? title,
  String? excludeField,
  String? okLabel,
}) async {
  final screen = TrytonScreen(
    ScreenAttributes(
      model,
      mode: const ['tree'],
      viewIds: viewIds,
      viewsPreload: viewsPreload,
      domain: domain,
      context: searchContext,
      order: order,
      readonly: true,
      excludeField: excludeField,
    ),
    session: session,
  );
  try {
    await screen.switchView();
    screen.onViewAdded = (v) => markUnsupportedFields(screen.model, v);
    await screen.searchFilter(searchText ?? '');
    if ((searchText ?? '').isNotEmpty && screen.group.length == 1) {
      final record = screen.group.first;
      return [(id: record.id, name: await _recName(record))];
    }
    if (!context.mounted) return const [];
    final result = await showDialog<List<SearchResult>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SearchDialog(
        screen: screen,
        multi: multi,
        allowNew: allowNew && screen.model.access.create,
        title: title ?? model,
        okLabel: okLabel,
        initialText: searchText ?? '',
        newScreen: () => TrytonScreen(
          ScreenAttributes(
            model,
            mode: const ['form'],
            // The first (tree) view is not used for the form.
            viewIds: viewIds.isEmpty ? const [] : viewIds.sublist(1),
            viewsPreload: viewsPreload,
            domain: domain,
            context: searchContext,
            excludeField: excludeField,
          ),
          session: session,
        ),
      ),
    );
    return result ?? const [];
  } on HandledRpcError {
    return const [];
  } finally {
    screen.dispose();
  }
}

class SearchDialog extends ConsumerStatefulWidget {
  final TrytonScreen screen;
  final bool multi;
  final bool allowNew;
  final String title;
  final String? okLabel;
  final String initialText;

  /// Screen for "New" (form only, saves itself).
  final TrytonScreen Function() newScreen;

  const SearchDialog({
    super.key,
    required this.screen,
    required this.multi,
    required this.allowNew,
    required this.title,
    required this.newScreen,
    this.okLabel,
    this.initialText = '',
  });

  @override
  ConsumerState<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends ConsumerState<SearchDialog> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initialText);
  final _scroll = ScrollController();
  final Set<Record> _selected = {};
  final Set<Record> _loading = {};
  List<TreeColumn> _columns = const [];
  bool _busy = false;

  TrytonScreen get _screen => widget.screen;

  @override
  void initState() {
    super.initState();
    _screen.addListener(_onChanged);
    _scroll.addListener(_onScroll);
    final view = _screen.currentView;
    if (view != null) {
      _columns = [
        for (final c in TreeXmlParser()
            .parse(view.definition.arch, view.definition.rawFields)
            .columns)
          if (!c.treeInvisible) c
      ];
    }
  }

  @override
  void dispose() {
    _screen.removeListener(_onChanged);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_scroll.hasClients || _busy) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 100 && _screen.hasMore) {
      _run(_screen.searchMore);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on HandledRpcError {
      // shown
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _find() => _run(() async {
        _selected.clear();
        await _screen.searchFilter(_text.text.trim());
      });

  void _ensureLoaded(Record record) {
    final name = _columns.isNotEmpty ? _columns.first.name : 'rec_name';
    if (record.isLoaded(name) || _loading.contains(record)) return;
    _loading.add(record);
    record
        .load(name, processException: false)
        .catchError((Object _) {})
        .whenComplete(() {
      _loading.remove(record);
      if (mounted) setState(() {});
    });
  }

  void _tap(Record record) {
    setState(() {
      if (widget.multi) {
        if (!_selected.remove(record)) _selected.add(record);
      } else {
        _selected
          ..clear()
          ..add(record);
      }
    });
  }

  Future<void> _ok([Record? record]) async {
    final records = record != null
        ? [record]
        : [
            for (final r in _screen.group)
              if (_selected.contains(r)) r
          ];
    final result = <SearchResult>[
      for (final r in records) (id: r.id, name: await _recName(r))
    ];
    if (mounted) Navigator.of(context).pop(result);
  }

  void _cancel() => Navigator.of(context).pop(const <SearchResult>[]);

  /// New: form popup of a new record that saves itself; it is the result.
  Future<void> _new() async {
    final screen = widget.newScreen();
    try {
      final ok = await showFormDialog(context, screen,
          newRecord: true, saveCurrent: true, title: widget.title);
      final record = screen.currentRecord;
      if (ok && record != null && record.id >= 0 && mounted) {
        Navigator.of(context)
            .pop([(id: record.id, name: await _recName(record))]);
      }
    } on HandledRpcError {
      // shown
    } finally {
      screen.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final size = MediaQuery.sizeOf(context);
    final records = _screen.group.toList();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _cancel,
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: math.min(size.width * 0.9, 960),
          height: size.height * 0.85,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(l.searchTitle(widget.title),
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  key: const ValueKey('search-dialog-text'),
                  controller: _text,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: l.search,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _find(),
                ),
              ),
              if (_busy) const LinearProgressIndicator(),
              Expanded(
                child: records.isEmpty
                    ? Center(child: Text(l.noRecordsFound))
                    : ListView.builder(
                        controller: _scroll,
                        itemCount: records.length + 1,
                        itemBuilder: (ctx, i) =>
                            i == 0 ? _header() : _row(records[i - 1]),
                      ),
              ),
              Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_screen.statusText,
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.outline)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    TextButton(onPressed: _cancel, child: Text(l.cancel)),
                    OutlinedButton(
                        onPressed: _busy ? null : _find, child: Text(l.find)),
                    if (widget.allowNew)
                      OutlinedButton(
                          onPressed: _busy ? null : _new,
                          child: Text(l.createNew)),
                    FilledButton(
                      onPressed: _busy || _selected.isEmpty ? null : _ok,
                      child: Text(widget.okLabel ?? l.ok),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          if (widget.multi) const SizedBox(width: 40),
          for (final c in _columns)
            Expanded(
              child: Text(c.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12)),
            ),
        ]),
      );

  Widget _row(Record record) {
    _ensureLoaded(record);
    final selected = _selected.contains(record);
    final fields = _screen.currentView?.definition.fields ?? const {};
    return InkWell(
      onTap: () => _tap(record),
      onDoubleTap: () => _ok(record),
      child: Container(
        color: selected
            ? Theme.of(context).colorScheme.primaryContainer.withAlpha(80)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          if (widget.multi)
            SizedBox(
              width: 40,
              child: Checkbox(value: selected, onChanged: (_) => _tap(record)),
            ),
          for (final c in _columns)
            Expanded(
              child: !record.isLoaded(c.name)
                  ? const Text('')
                  : isNumericField(fields[c.name])
                      ? RecordNumericCell.of(record, c.name, fields[c.name]!,
                          style: const TextStyle(fontSize: 13))
                      : Text(recordCellText(record, c.name, fields[c.name]),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
            ),
        ]),
      ),
    );
  }
}
