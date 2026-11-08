import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/model/model.dart';
import '../../core/rpc/error_processing.dart';
import '../../core/screen/screen.dart';
import '../../core/xml/view_definition.dart';
import '../../shared/errors/error_dialogs.dart';
import 'record_form.dart';
import 'record_widget_values.dart';

/// The list-form view of a [TrytonScreen] (spec 9.4, Python
/// `ViewListForm`): the records of the group as cards, each card the form
/// layout of the view's arch on its record (the same parser and widgets as
/// the form). A click selects (Ctrl/Cmd adds, Shift extends), a double
/// click or Enter activates; leaving a modified record validates and saves
/// it (root screen). Cards are built in steps of [displayStep]; at the end
/// [onEndReached] appends the next search page.
class ListFormView extends ConsumerStatefulWidget {
  final TrytonScreen screen;

  /// The list-form view of [screen] shown.
  final ScreenView view;

  /// Activation of a card (double click / Enter).
  final void Function(Record record) onActivate;
  final VoidCallback? onSelectionChanged;

  /// All group records are shown (next search page).
  final VoidCallback? onEndReached;
  final int displayStep;

  const ListFormView({
    super.key,
    required this.screen,
    required this.view,
    required this.onActivate,
    this.onSelectionChanged,
    this.onEndReached,
    this.displayStep = 100,
  });

  @override
  ConsumerState<ListFormView> createState() => _ListFormViewState();
}

class _ListFormViewState extends ConsumerState<ListFormView> {
  late int _visible = widget.displayStep;
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'list-form');

  /// Text typed in a card, written on focus loss (per record).
  final Map<Record, Map<String, dynamic>> _pending = {};
  final Set<Record> _loading = {};

  TrytonScreen get _screen => widget.screen;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Near the end: more cards, then the next search page.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - 200) return;
    if (_visible < _screen.group.length) {
      setState(() => _visible += widget.displayStep);
    } else {
      widget.onEndReached?.call();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on HandledRpcError {
      // shown by the screen's error handler
    } catch (e) {
      if (mounted) await errorHandlerOf(context, ref).show(e);
    }
  }

  /// Writes the pending text of [record] (before leaving it or saving).
  Future<void> _flush(Record record) async {
    final pending = _pending.remove(record);
    if (pending == null) return;
    for (final MapEntry(key: name, value: value) in pending.entries) {
      await _run(() => setRecordWidgetValue(record, name, value));
    }
  }

  /// Selects [records]; a modified record left behind is validated and
  /// saved first (root screen; Python `_row_selected`) – an invalid one
  /// keeps the selection.
  Future<void> _select(List<Record> records) async {
    final screen = _screen;
    final previous = screen.currentRecord;
    final next = records.isEmpty ? null : records.first;
    if (previous != null &&
        !identical(previous, next) &&
        !previous.destroyed &&
        screen.group.contains(previous)) {
      await _flush(previous);
      if ((previous.modified || previous.id < 0) &&
          screen.group.parent == null) {
        if (!previous.validate(fields: widget.view.fields)) {
          if (mounted) setState(() {});
          return;
        }
        await _run(() async => previous.save());
      } else if (screen.group.parent != null && screen.preValidate) {
        var valid = false;
        await _run(() async {
          await previous.preValidate();
          valid = true;
        });
        if (!valid) return;
      }
    }
    if (!mounted) return;
    setState(() {
      screen.selectedRecords = [
        for (final r in screen.group)
          if (records.contains(r)) r
      ];
      screen.currentRecord = next;
    });
    widget.onSelectionChanged?.call();
  }

  /// Click on a card: Ctrl/Cmd toggles, Shift extends from the current
  /// record, otherwise the card alone.
  void _tap(Record record) {
    final keys = HardwareKeyboard.instance;
    final selected = _screen.selectedRecords;
    if (keys.isControlPressed || keys.isMetaPressed) {
      final records = [...selected];
      if (!records.remove(record)) records.add(record);
      _select(records);
    } else if (keys.isShiftPressed && _screen.currentRecord != null) {
      final all = _screen.group.toList();
      final a = all.indexOf(_screen.currentRecord!);
      final b = all.indexOf(record);
      if (a < 0 || b < 0) {
        _select([record]);
        return;
      }
      final current = _screen.currentRecord!;
      final range = all.sublist(a < b ? a : b, (a < b ? b : a) + 1);
      _select([current, ...range.where((r) => !identical(r, current))]);
    } else if (!(selected.length == 1 && identical(selected.first, record))) {
      _select([record]);
    }
  }

  /// Values of the card of [record] (its neighbours in the same `read`).
  void _ensureLoaded(Record record) {
    final name = widget.view.fields.firstOrNull ?? 'rec_name';
    if (record.destroyed ||
        record.id < 0 ||
        !record.model.fields.containsKey(name) ||
        record.isLoaded(name) ||
        !_loading.add(record)) {
      return;
    }
    record.load(name, processException: false).catchError((Object _) {}).whenComplete(() {
      _loading.remove(record);
      if (mounted) setState(() {});
    });
  }

  /// A button of a card works only on the card selected alone (Python
  /// `ListBoxViewForm.button_clicked`).
  Future<void> _button(Record record, ButtonNode node) async {
    final selected = _screen.selectedRecords;
    if (selected.length != 1 || !identical(selected.first, record)) return;
    await _flush(record);
    await _run(() => _screen.button(node));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final current = _screen.currentRecord;
    if (event.logicalKey == LogicalKeyboardKey.enter && current != null) {
      widget.onActivate(current);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final records = _screen.group.toList();
    final count = records.length < _visible ? records.length : _visible;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: ListView.builder(
        key: const ValueKey('list-form'),
        controller: _scroll,
        padding: const EdgeInsets.all(8),
        itemCount: count,
        itemBuilder: (context, i) => _card(records[i]),
      ),
    );
  }

  Widget _card(Record record) {
    final cs = Theme.of(context).colorScheme;
    final selected = _screen.selectedRecords.contains(record);
    final marked = record.deleted || record.removed;
    _ensureLoaded(record);
    final loaded = record.id < 0 ||
        record.isLoaded(widget.view.fields.firstOrNull ?? 'rec_name');
    final root = widget.view.formRoot!;
    return Padding(
      key: ValueKey('list-form-card-${record.id}'),
      padding: const EdgeInsets.only(bottom: 6),
      // pointer down selects without competing with the inputs' gestures
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          _focus.requestFocus();
          _tap(record);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onDoubleTap: () => widget.onActivate(record),
          child: Card(
            margin: EdgeInsets.zero,
            elevation: selected ? 2 : 0,
            color: marked
                ? cs.error.withAlpha(20)
                : selected
                    ? cs.primaryContainer.withAlpha(90)
                    : cs.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: selected ? cs.primary : cs.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
              child: !loaded
                  ? const SizedBox(
                      height: 40,
                      child: Center(
                          child: SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))),
                    )
                  : RecordForm(
                      key: ObjectKey(record),
                      model: _screen.model.name,
                      root: root,
                      viewDef: widget.view.definition,
                      record: record,
                      onTextChanged: (name, value) =>
                          (_pending[record] ??= {})[name] = value,
                      onBlur: (name) {
                        final pending = _pending[record];
                        if (pending == null || !pending.containsKey(name)) {
                          return;
                        }
                        final value = pending.remove(name);
                        _run(() => setRecordWidgetValue(record, name, value));
                      },
                      onChangedImmediate: (name, value) =>
                          _run(() => setRecordWidgetValue(record, name, value)),
                      isReadOnly: record.readonly,
                      onButton: (node) => _button(record, node),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
