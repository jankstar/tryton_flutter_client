import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/locale_provider.dart';

/// From this many entries the check lists (search filter, multiselection)
/// get a search entry above the list (spec T2).
const selectionSearchThreshold = 15;

/// Height of an entry of the popup list (fixed: virtualised, scrolled to
/// the current entry).
const selectionItemExtent = 32.0;

/// Highest share of the window the popup list takes.
const selectionPopupMaxHeight = 0.6;

const _fold = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
  'ă': 'a', 'ą': 'a', 'æ': 'ae', 'ç': 'c', 'ć': 'c', 'č': 'c', 'ď': 'd',
  'đ': 'd', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e',
  'ę': 'e', 'ě': 'e', 'ğ': 'g', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ī': 'i', 'į': 'i', 'ı': 'i', 'ł': 'l', 'ľ': 'l', 'ñ': 'n', 'ń': 'n',
  'ň': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o',
  'ō': 'o', 'ő': 'o', 'œ': 'oe', 'ř': 'r', 'ś': 's', 'š': 's', 'ş': 's',
  'ș': 's', 'ß': 'ss', 'ť': 't', 'ţ': 't', 'ț': 't', 'ù': 'u', 'ú': 'u',
  'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u', 'ý': 'y',
  'ÿ': 'y', 'ź': 'z', 'ż': 'z', 'ž': 'z',
};

/// [text] for comparing: lower case, accents and umlauts folded to their
/// base letters („Zürich“ → „zurich“).
String foldSelectionText(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final c = String.fromCharCode(rune);
    out.write(_fold[c] ?? c);
  }
  return out.toString();
}

bool _isWordChar(int unit) {
  final c = String.fromCharCode(unit);
  return c.toLowerCase() != c.toUpperCase() ||
      (unit >= 0x30 && unit <= 0x39);
}

/// Positions of the [labels] that contain [query] (case, accents and
/// umlauts ignored): matches at the start of a word first („berl“ →
/// „Europe/Berlin“ before „Oberlin“), each group in the original order;
/// an empty query gives all.
List<int> filterSelection(List<String> labels, String query) {
  final q = foldSelectionText(query.trim());
  if (q.isEmpty) return [for (var i = 0; i < labels.length; i++) i];
  final word = <int>[], inner = <int>[];
  for (var i = 0; i < labels.length; i++) {
    final label = foldSelectionText(labels[i]);
    var at = label.indexOf(q);
    if (at < 0) continue;
    var atWord = false;
    while (at >= 0) {
      if (at == 0 || !_isWordChar(label.codeUnitAt(at - 1))) {
        atWord = true;
        break;
      }
      at = label.indexOf(q, at + 1);
    }
    (atWord ? word : inner).add(i);
  }
  return [...word, ...inner];
}

/// Selection input (spec T2, Python `form_gtk/selection.py`
/// `Gtk.ComboBox(has_entry=True)` with `PopdownMixin`'s completion): an
/// entry with the label of the value and a list of the [items]
/// (`[key, label]`).
///
/// * Typing filters the list ([filterSelection]); arrow keys move,
///   Enter or a click chooses, Escape restores the value; Alt+Down or the
///   arrow button shows all entries, scrolled to the current one.
/// * [onSelected] runs only for a chosen entry (on_change once); leaving
///   with a text of no entry keeps the value, an empty text clears it
///   unless [required] (an exactly typed label chooses its entry).
/// * The list is virtualised, at most 60 % of the window high.
/// * Touch platforms: a tap opens a bottom sheet with a search entry.
/// * [readOnly]: only the text.
class SelectionInput extends StatefulWidget {
  final List<List<dynamic>> items;
  final dynamic value;
  final bool readOnly;
  final bool required;
  final bool autofocus;
  final InputDecoration decoration;
  final ValueChanged<dynamic> onSelected;

  /// Key of the entry (tests: `selection-<field>`).
  final Key? fieldKey;

  /// Tooltip of an entry (many2one `help_field`).
  final String? Function(int index)? tooltipOf;

  /// Text style of the entry (lists use a smaller one).
  final TextStyle? style;

  const SelectionInput({
    super.key,
    required this.items,
    required this.value,
    required this.onSelected,
    this.decoration = const InputDecoration(),
    this.readOnly = false,
    this.required = false,
    this.autofocus = false,
    this.fieldKey,
    this.tooltipOf,
    this.style,
  });

  @override
  State<SelectionInput> createState() => _SelectionInputState();
}

class _SelectionInputState extends State<SelectionInput> {
  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'selection');
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _fieldKey = GlobalKey();
  final _scroll = ScrollController();

  /// The text was edited since it showed the value.
  bool _typed = false;

  /// Positions of the shown entries and the highlighted one.
  List<int> _options = const [];
  int _highlight = 0;
  bool _above = false;
  double _width = 200;
  double _maxHeight = 300;

  List<String> get _labels =>
      [for (final i in widget.items) '${i.length > 1 ? i[1] ?? '' : ''}'];

  bool get _touch => switch (Theme.of(context).platform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.fuchsia =>
          true,
        _ => false,
      };

  /// Position of the value among the items (same key, else same text).
  int? get _current {
    final value = widget.value;
    final empty = value == null || value == false;
    final items = widget.items;
    for (var i = 0; i < items.length; i++) {
      final key = items[i][0];
      if (empty ? (key == null || key == '') : key == value) return i;
    }
    if (empty) return null;
    for (var i = 0; i < items.length; i++) {
      if ('${items[i][0]}' == '$value') return i;
    }
    return null;
  }

  /// The text of the value: its label; a value without entry (inactive)
  /// as it is.
  String get _valueText {
    final i = _current;
    if (i != null) return _labels[i];
    final value = widget.value;
    return value == null || value == false ? '' : '$value';
  }

  @override
  void initState() {
    super.initState();
    _controller.text = _valueText;
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(SelectionInput old) {
    super.didUpdateWidget(old);
    // a new value (on_change, another record) or new entries: the text
    // follows unless the user is typing
    if (!(_focus.hasFocus && _typed)) _sync();
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _sync() {
    final text = _valueText;
    if (_controller.text != text) _controller.text = text;
    _typed = false;
  }

  void _focusChanged() {
    if (!_focus.hasFocus) _commit();
  }

  /// Leaving the entry: an exactly typed label chooses its entry, an empty
  /// text clears a field that is not required, any other text keeps the
  /// value.
  void _commit() {
    _close();
    if (!_typed) return;
    final text = _controller.text.trim();
    if (text.isEmpty) {
      if (!widget.required && _current != null && _valueText.isNotEmpty) {
        _typed = false;
        widget.onSelected(null);
        return;
      }
    } else {
      final folded = foldSelectionText(text);
      final labels = _labels;
      final exact = [
        for (var i = 0; i < labels.length; i++)
          if (foldSelectionText(labels[i]) == folded) i
      ];
      if (exact.length == 1) {
        _choose(exact.single);
        return;
      }
    }
    _sync();
  }

  void _choose(int index) {
    _close();
    final key = widget.items[index][0];
    final text = _labels[index];
    if (_controller.text != text) _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    _typed = false;
    final current = _current;
    if (current == null || widget.items[current][0] != key) {
      widget.onSelected(key);
    }
  }

  void _restore() {
    _close();
    _sync();
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
  }

  // ─── popup ───────────────────────────────────────────────────────────────

  void _open({required bool all}) {
    if (widget.readOnly || widget.items.isEmpty) return;
    _options = all
        ? [for (var i = 0; i < widget.items.length; i++) i]
        : filterSelection(_labels, _controller.text);
    final current = _current;
    _highlight = all && current != null ? _options.indexOf(current) : 0;
    if (_highlight < 0) _highlight = 0;
    _place();
    if (!_portal.isShowing) _portal.show();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(center: all));
  }

  void _close() {
    if (_portal.isShowing) _portal.hide();
  }

  /// Width of the field, side (below unless the room above is larger) and
  /// height of the list.
  void _place() {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final screen = MediaQuery.sizeOf(context);
    final limit = screen.height * selectionPopupMaxHeight;
    if (box == null || !box.hasSize) {
      _maxHeight = limit;
      return;
    }
    _width = box.size.width;
    final top = box.localToGlobal(Offset.zero).dy;
    final below = screen.height - top - box.size.height - 8;
    final above = top - 8;
    final needed = math.min(_options.length * selectionItemExtent, limit);
    _above = below < needed && above > below;
    _maxHeight = math.max(
        selectionItemExtent, math.min(limit, _above ? above : below));
  }

  /// Scrolls the highlighted entry into view (opened: in the middle).
  void _reveal({bool center = false}) {
    if (!_scroll.hasClients) return;
    final view = _scroll.position.viewportDimension;
    final top = _highlight * selectionItemExtent;
    double? to;
    if (center) {
      to = top - (view - selectionItemExtent) / 2;
    } else if (top < _scroll.offset) {
      to = top;
    } else if (top + selectionItemExtent > _scroll.offset + view) {
      to = top + selectionItemExtent - view;
    }
    if (to == null) return;
    _scroll.jumpTo(to.clamp(0.0, _scroll.position.maxScrollExtent));
  }

  void _move(int delta) {
    if (_options.isEmpty) return;
    setState(() =>
        _highlight = (_highlight + delta).clamp(0, _options.length - 1));
    _reveal();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final open = _portal.isShowing;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      if (open) {
        _move(key == LogicalKeyboardKey.arrowDown ? 1 : -1);
        return KeyEventResult.handled;
      }
      // Alt+Down opens (GTK combo); plain arrows stay with the host (the
      // rows of an editable list)
      if (HardwareKeyboard.instance.isAltPressed &&
          key == LogicalKeyboardKey.arrowDown) {
        _open(all: true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (open &&
        (key == LogicalKeyboardKey.pageDown ||
            key == LogicalKeyboardKey.pageUp)) {
      final page = math.max(1, _maxHeight ~/ selectionItemExtent - 1);
      _move(key == LogicalKeyboardKey.pageDown ? page : -page);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (open && _options.isNotEmpty) {
        _choose(_options[_highlight]);
        return KeyEventResult.handled;
      }
      if (_typed) _commit();
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape && (open || _typed)) {
      _restore();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _changed(String _) {
    _typed = true;
    _open(all: false);
  }

  Widget _popup(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final list = _options.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(12),
            child: Text(context.l10n.noRecordsFound,
                style: TextStyle(color: cs.outline)),
          )
        : ListView.builder(
            key: const ValueKey('selection-options'),
            controller: _scroll,
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemExtent: selectionItemExtent,
            itemCount: _options.length,
            itemBuilder: (context, i) => _entry(context, i),
          );
    return CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      targetAnchor: _above ? Alignment.topLeft : Alignment.bottomLeft,
      followerAnchor: _above ? Alignment.bottomLeft : Alignment.topLeft,
      child: Align(
        alignment: _above ? Alignment.bottomLeft : Alignment.topLeft,
        // a press in the list does not count as leaving the entry
        child: TextFieldTapRegion(
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(4),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minWidth: _width, maxWidth: _width, maxHeight: _maxHeight),
              child: list,
            ),
          ),
        ),
      ),
    );
  }

  Widget _entry(BuildContext context, int i) {
    final cs = Theme.of(context).colorScheme;
    final index = _options[i];
    final current = index == _current;
    Widget text = Text(_labels[index],
        overflow: TextOverflow.ellipsis,
        style: (widget.style ?? Theme.of(context).textTheme.bodyMedium)
            ?.copyWith(fontWeight: current ? FontWeight.w600 : null));
    final tip = widget.tooltipOf?.call(index);
    if (tip != null && tip.isNotEmpty) {
      text = Tooltip(message: tip, child: text);
    }
    return InkWell(
      key: ValueKey('selection-option-$index'),
      onTap: () => _choose(index),
      child: Container(
        color: i == _highlight ? cs.primaryContainer.withAlpha(120) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        child: text,
      ),
    );
  }

  // ─── touch: bottom sheet ─────────────────────────────────────────────────

  Future<void> _sheet() async {
    if (widget.readOnly || widget.items.isEmpty) return;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SelectionSheet(
        labels: _labels,
        current: _current,
        tooltipOf: widget.tooltipOf,
      ),
    );
    if (chosen != null && mounted) _choose(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final touch = _touch;
    final base = widget.decoration;
    final arrow = widget.readOnly
        ? null
        : IconButton(
            key: widget.fieldKey == null
                ? null
                : ValueKey('${(widget.fieldKey as ValueKey).value}-arrow'),
            icon: const Icon(Icons.arrow_drop_down, size: 20),
            padding: EdgeInsets.zero,
            // no taller than the text line: as high as the other inputs
            constraints: const BoxConstraints(minWidth: 28, minHeight: 20),
            style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onPressed: () {
              if (touch) {
                _sheet();
                return;
              }
              if (_portal.isShowing) {
                _close();
                return;
              }
              _focus.requestFocus();
              _open(all: true);
            },
          );
    final suffix = base.suffixIcon == null
        ? arrow
        : Row(mainAxisSize: MainAxisSize.min, children: [
            base.suffixIcon!,
            ?arrow,
          ]);
    final field = TextField(
      key: widget.fieldKey,
      controller: _controller,
      focusNode: _focus,
      autofocus: widget.autofocus,
      readOnly: widget.readOnly || touch,
      style: widget.style,
      decoration: base.copyWith(
          suffixIcon: suffix,
          suffixIconConstraints:
              const BoxConstraints(minWidth: 28, minHeight: 20)),
      onChanged: _changed,
      onTap: touch ? _sheet : null,
      // a press beside entry and list (the list is in the entry's tap
      // region) closes the list like leaving the entry
      onTapOutside: (_) {
        if (_portal.isShowing) _commit();
      },
    );
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _popup,
      child: CompositedTransformTarget(
        link: _link,
        child: KeyedSubtree(
          key: _fieldKey,
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onKey,
            child: field,
          ),
        ),
      ),
    );
  }
}

/// The list of a selection on touch devices: search entry on top (the
/// keyboard would hide suggestions below the field), the list below.
class _SelectionSheet extends StatefulWidget {
  final List<String> labels;
  final int? current;
  final String? Function(int index)? tooltipOf;

  const _SelectionSheet(
      {required this.labels, required this.current, this.tooltipOf});

  @override
  State<_SelectionSheet> createState() => _SelectionSheetState();
}

class _SelectionSheetState extends State<_SelectionSheet> {
  String _query = '';
  late final ScrollController _scroll = ScrollController(
      initialScrollOffset: widget.current == null
          ? 0
          : math.max(0, (widget.current! - 3) * selectionItemExtent * 1.5));

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = filterSelection(widget.labels, _query);
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            key: const ValueKey('selection-sheet-search'),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: context.l10n.search,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (text) => setState(() => _query = text),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            itemExtent: selectionItemExtent * 1.5,
            itemCount: options.length,
            itemBuilder: (context, i) {
              final index = options[i];
              final current = index == widget.current;
              final tip = widget.tooltipOf?.call(index);
              return ListTile(
                key: ValueKey('selection-sheet-option-$index'),
                dense: true,
                selected: current,
                selectedTileColor: cs.primaryContainer.withAlpha(80),
                title: Text(widget.labels[index],
                    overflow: TextOverflow.ellipsis),
                subtitle: tip == null || tip.isEmpty
                    ? null
                    : Text(tip, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.of(context).pop(index),
              );
            },
          ),
        ),
      ]),
    );
  }
}
