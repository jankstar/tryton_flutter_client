import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart' hide TextField;
import '../../core/rpc/error_processing.dart';
import '../../core/screen/screen.dart';
import '../model/field_support.dart';
import '../model/model_service.dart';
import 'form_dialog.dart';
import 'record_menu.dart';
import 'search_box.dart';
import 'tree_view.dart';

/// A record chosen in the search dialog: id and rec_name.
typedef SearchResult = ({int id, String name});

/// rec_name of [record]: the loaded value, else read.
Future<String> _recName(Record record) async {
  final loaded = record.values['rec_name'];
  return loaded is String ? loaded : record.recName();
}

/// Search popup (spec 11.2, T3, Python `WinSearch`, SAO
/// `Sao.Window.Search`) for [model]: a screen with the search bar
/// (Tryton syntax) and the same [TreeView] as every list – widths by type,
/// stored (`set_width`) and dragged, optional columns, sorting –, single
/// or multiple ([multi]) choice and the buttons Cancel, Find, New
/// ([allowNew]) and OK ([okLabel]). With [searchText] and exactly one
/// hit, the hit is returned without dialog.
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
    // the rights of the model (New, read only) like ScreenWidget
    if (session.accessOf?.call(model) == null) {
      try {
        await session.loadAccess?.call([model]);
      } catch (_) {
        // MetadataService: an error means read only
      }
    }
    await screen.switchView();
    screen.onViewAdded = (v) => markUnsupportedFields(screen.model, v);
    // the search bar parses Tryton syntax like the lists (DomainParser)
    if (context.mounted) {
      screen.parserContext = ProviderScope.containerOf(context, listen: false)
              .read(modelServiceProvider)
              .metadata
              ?.parserContext ??
          const {};
    }
    try {
      await screen.loadDomainParser();
    } catch (_) {
      // without parser the text searches the rec_name
    }
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
  // the text as the screen normalized it (DomainParser), else as typed
  late final TextEditingController _text = TextEditingController(
      text: widget.screen.searchText.isNotEmpty
          ? widget.screen.searchText
          : widget.initialText);
  final _searchFocus = FocusNode();
  final _table = TreeViewController();
  bool _busy = false;

  TrytonScreen get _screen => widget.screen;

  @override
  void initState() {
    super.initState();
    _screen.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _screen.removeListener(_onChanged);
    _text.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
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
        _table.reset();
        await _screen.searchFilter(_text.text.trim());
        _text.text = _screen.searchText;
      });

  /// End of the shown rows: the next search page.
  void _searchMore() {
    if (_busy || !_screen.hasMore) return;
    _run(_screen.searchMore);
  }

  /// The ticked records in the order of the rows.
  List<Record> get _selected => _screen.selectedRecords;

  /// Double click / Enter (Python `WinSearch` row activation): the row is
  /// chosen – with the ticked ones of a multiple choice – and the dialog
  /// closes; the form is never opened.
  void _activate(Record record) {
    final records = widget.multi
        ? [..._selected, if (!_selected.contains(record)) record]
        : [record];
    _ok(records);
  }

  Future<void> _ok([List<Record>? records]) async {
    final chosen = records ?? _selected;
    if (chosen.isEmpty) return;
    final result = <SearchResult>[
      for (final r in chosen) (id: r.id, name: await _recName(r))
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
    final view = _screen.currentView;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(l.searchTitle(widget.title),
              style: Theme.of(context).textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SearchBox(
            key: const ValueKey('search-dialog-text'),
            screen: _screen,
            controller: _text,
            focusNode: _searchFocus,
            onSearch: _find,
          ),
        ),
        const SizedBox(height: 4),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: view == null || _screen.group.isEmpty
              ? Center(child: Text(l.noRecordsFound))
              : TreeView(
                  screen: _screen,
                  view: view,
                  controller: _table,
                  keyPrefix: 'search-dialog',
                  picker: true,
                  multiSelect: widget.multi,
                  recordFunctions: false,
                  onActivate: _activate,
                  onSelectionChanged: () => setState(() {}),
                  onEndReached: _searchMore,
                ),
        ),
        Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(_screen.statusText,
              key: const ValueKey('search-dialog-status'),
              style: TextStyle(
                  fontSize: 11, color: Theme.of(context).colorScheme.outline)),
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
                    key: const ValueKey('search-dialog-new'),
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
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _cancel,
        // the record shortcut on the dialog's button (SAO `new_`)
        if (widget.allowNew && !_busy)
          recordShortcut(RecordAction.newRecord)!: _new,
      },
      child: _frame(MediaQuery.sizeOf(context), content),
    );
  }

  /// Like the form dialog: at least 90 % of the window's width, 90 % of
  /// its height (the list fills it); narrow windows (< 600 px) full
  /// screen.
  static Widget _frame(Size size, Widget child) {
    if (size.width < formDialogFullscreenWidth) {
      return Dialog.fullscreen(child: SafeArea(child: child));
    }
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
          horizontal: size.width * 0.05, vertical: size.height * 0.05),
      child: SizedBox(
        key: const ValueKey('search-dialog-frame'),
        width: size.width * 0.9,
        height: size.height * 0.9,
        child: child,
      ),
    );
  }
}
