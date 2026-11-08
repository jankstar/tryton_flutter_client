import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart' hide TextField;
import '../../core/rpc/error_processing.dart';
import '../../core/screen/screen.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/csv_format.dart';
import '../../shared/utils/file_actions.dart';
import '../model/model_service.dart';

// CSV export and import (spec 11.8, 11.9, Python gui/window/win_csv.py,
// win_export.py, win_import.py): a tree of all fields (relations
// expanded lazily with `fields_get`), the selected fields and the CSV
// parameters.

/// A field of the CSV field tree: [path] is the name for `export_data` /
/// `import_data` (`party/name`, `state.translated`, `name:lang=de`),
/// [label] the name with the labels of the parents (`Party/Name`).
class CsvField {
  final String path;
  final String string;
  final String label;
  final Map<String, dynamic> attrs;

  /// Model of a relation that can be expanded (null: no children or
  /// the [children] are fixed, e.g. the languages of a translated field).
  final String? relation;
  List<CsvField>? children;

  CsvField(this.path, this.string, this.label, this.attrs,
      {this.relation, this.children});

  bool get expandable => relation != null || (children?.isNotEmpty ?? false);
  String? get type => attrs['type'] as String?;
}

/// The fields of [model] for the CSV dialogs (Python `model_populate`):
/// export – all fields, selection with `(string)`, reference with
/// `(model name)` and `/Record Name`, every relation expandable; import
/// – only writable fields and `id`, only One2Many expandable. Translated
/// fields get one entry per translatable language.
class CsvFieldTree {
  final ModelService svc;
  final String model;
  final Map<String, dynamic> context;
  final bool import;
  final AppLocalizations l10n;

  CsvFieldTree(this.svc, this.model, this.context,
      {required this.import, required this.l10n});

  /// path → field (Python `self.fields`) and, for the import, label →
  /// path (`fields_invert`).
  final fields = <String, CsvField>{};
  final byLabel = <String, String>{};
  List<CsvField> roots = const [];
  List<Map> _languages = const [];

  Future<void> load() async {
    try {
      final langs = await svc.execute<dynamic>('ir.lang', 'search_read', [
        [
          ['translatable', '=', true]
        ],
        0,
        null,
        [
          ['name', 'ASC']
        ],
        ['code', 'name'],
      ], context: context, processException: false);
      _languages = [for (final l in langs as List? ?? const []) if (l is Map) l];
    } catch (_) {
      _languages = const [];
    }
    roots = await _populate(model, '', '');
  }

  Future<Map<String, dynamic>> _fieldsGet(String model) async {
    try {
      final result = await svc.execute<dynamic>(model, 'fields_get', [null],
          context: context, processException: false);
      return result is Map ? Map<String, dynamic>.from(result) : const {};
    } catch (_) {
      return const {};
    }
  }

  Future<List<CsvField>> _populate(
      String model, String prefixPath, String prefixLabel) async {
    final raw = await _fieldsGet(model);
    String key(String name) {
      final f = raw[name];
      final s = f is Map ? f['string'] : null;
      return s is String && s.isNotEmpty ? s : name;
    }

    final names = raw.keys.toList()..sort((a, b) => key(a).compareTo(key(b)));
    final nodes = <CsvField>[];
    for (final name in names) {
      final attrs = Map<String, dynamic>.from(raw[name] as Map);
      final string = key(name);
      if (import && attrs['readonly'] == true && name != 'id') continue;
      final items = <(String, String)>[(name, string)];
      if (!import) {
        if (attrs['type'] == 'selection') {
          items.add(('$name.translated', l10n.csvFieldString(string)));
        } else if (attrs['type'] == 'reference') {
          items.add(('$name.translated', l10n.csvFieldModelName(string)));
          items.add(('$name/rec_name', l10n.csvFieldRecordName(string)));
        }
      }
      for (final (itemName, itemString) in items) {
        final path = prefixPath + itemName;
        final label = prefixLabel + itemString;
        final relation = attrs['relation'] as String?;
        final real = !itemName.contains('.') && !itemName.contains('/');
        final expandable = real &&
            relation != null &&
            (!import || attrs['type'] == 'one2many');
        List<CsvField>? languages;
        if (real && !expandable && attrs['translate'] == true) {
          languages = [
            for (final lang in _languages)
              CsvField('$path:lang=${lang['code']}', '${lang['name']}',
                  '$label (${lang['name']})', attrs),
          ];
          for (final l in languages) {
            fields[l.path] = l;
            byLabel[l.label] = l.path;
          }
        }
        final node = CsvField(path, itemString, label, attrs,
            relation: expandable ? relation : null, children: languages);
        fields[path] = node;
        byLabel[label] = path;
        nodes.add(node);
      }
    }
    return nodes;
  }

  /// The children of [field] (loaded on the first expansion).
  Future<List<CsvField>> expand(CsvField field) async {
    final children = field.children;
    if (children != null) return children;
    final relation = field.relation;
    if (relation == null) return const [];
    return field.children =
        await _populate(relation, '${field.path}/', '${field.label}/');
  }

  /// The field of a path or (import) a label – the parents are expanded
  /// first (Python `sel_predef` / `sig_autodetect`).
  Future<CsvField?> resolve(String word) async {
    CsvField? known() =>
        fields[word] ?? (byLabel[word] != null ? fields[byLabel[word]] : null);
    if (known() case final f?) return f;
    final parts = word.split('/');
    var nodes = roots;
    var prefix = '';
    for (final parent in parts.sublist(0, parts.length - 1)) {
      final node = nodes
          .where((n) => n.path == '$prefix$parent' || n.string == parent)
          .firstOrNull;
      if (node == null || !node.expandable) break;
      nodes = await expand(node);
      prefix = '${node.path}/';
    }
    return known();
  }
}

/// Depth of [record] below the root group of [screen] (Python
/// `selected_paths`/`listed_paths`: indentation of the first column).
int recordDepth(Record record, TrytonScreen screen) {
  var depth = 0;
  var group = record.group;
  while (group != screen.group && group.parent != null) {
    depth++;
    group = group.parent!.group;
  }
  return depth;
}

/// Default delimiter: `;` on Windows with a decimal comma (Python).
String _defaultDelimiter(TrytonScreen screen) =>
    Platform.isWindows && screen.context['decimal_point'] == ',' ? ';' : ',';

String _slug(String name) {
  final s = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s-]', unicode: true), '')
      .trim()
      .replaceAll(RegExp(r'[-\s]+'), '-');
  return s.isEmpty ? 'export' : s;
}

Future<void> _message(BuildContext context, String title, String text) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.ok),
          ),
        ],
      ),
    );

/// The records and depths of an export with `records` [selected] or
/// listed ([listed], default: the records of the group).
({List<int> ids, List<int> depths}) _exportRecords(TrytonScreen screen,
    {required bool selected, List<Record>? listed}) {
  final List<Record> records;
  if (selected) {
    records = screen.currentView?.viewType == 'tree'
        ? screen.selectedRecords
        : [?screen.currentRecord];
  } else {
    records = listed ?? [...screen.group];
  }
  final saved = [for (final r in records) if (r.id >= 0) r];
  return (
    ids: [for (final r in saved) r.id],
    depths: [for (final r in saved) recordDepth(r, screen)],
  );
}

/// CSV bytes of [data] (header row without indentation).
Uint8List _csvBytes(List data, List<int>? depths,
    {required bool header,
    required bool localeFormat,
    required String delimiter,
    required String quote,
    required String encoding,
    Map? context}) {
  final rows = <List<Object?>>[];
  for (var i = 0; i < data.length; i++) {
    final row = data[i];
    if (row is! List || row.isEmpty) continue;
    final index = header ? i - 1 : i;
    final indent =
        depths != null && index >= 0 && index < depths.length ? depths[index] : 0;
    rows.add(formatCsvRow(row,
        indent: indent, localeFormat: localeFormat, context: context));
  }
  return csvEncode(csvText(rows, delimiter: delimiter, quote: quote), encoding);
}

/// A predefined export of the print menu (Python `Form.do_export`):
/// `export_data` of the listed or selected records, CSV with the default
/// parameters into a temporary file that is opened.
Future<void> runPredefinedExport(BuildContext context, TrytonScreen screen,
    Map<String, dynamic> export, {List<Record>? listed}) async {
  final svc = ProviderScope.containerOf(context, listen: false)
      .read(modelServiceProvider);
  final records = _exportRecords(screen,
      selected: export['records'] != 'listed', listed: listed);
  final fields = [
    for (final f in export['export_fields.'] as List? ?? const [])
      if (f is Map) '${f['name']}'
  ];
  final header = export['header'] == true;
  try {
    final data = await svc.execute<dynamic>(
        screen.model.name, 'export_data', [records.ids, fields, header],
        context: screen.context) as List? ?? const [];
    final bytes = _csvBytes(data, records.depths,
        header: header,
        localeFormat: true,
        delimiter: _defaultDelimiter(screen),
        quote: '"',
        encoding: 'utf_8',
        context: svc.metadata?.parserContext);
    final path = await FileActions.instance
        .writeTemp('${_slug('${export['name']}')}.csv', bytes);
    await FileActions.instance.open(path);
  } on HandledRpcError {
    // shown
  }
}

// ── Field selection (both dialogs) ────────────────────────────────────────

/// Tree of all fields (left) and the selected fields (right, order
/// changeable); double tap adds or removes a field.
class _CsvFieldsPanel extends StatefulWidget {
  final CsvFieldTree tree;
  final List<CsvField> selected;
  final VoidCallback onChanged;

  const _CsvFieldsPanel(
      {required this.tree, required this.selected, required this.onChanged});

  @override
  State<_CsvFieldsPanel> createState() => _CsvFieldsPanelState();
}

class _CsvFieldsPanelState extends State<_CsvFieldsPanel> {
  final _expanded = <String>{};
  CsvField? _current;
  int? _currentSelected;

  List<(CsvField, int)> get _visible {
    final rows = <(CsvField, int)>[];
    void add(List<CsvField> nodes, int depth) {
      for (final n in nodes) {
        rows.add((n, depth));
        if (_expanded.contains(n.path) && n.children != null) {
          add(n.children!, depth + 1);
        }
      }
    }

    add(widget.tree.roots, 0);
    return rows;
  }

  Future<void> _toggle(CsvField field) async {
    if (_expanded.remove(field.path)) {
      setState(() {});
      return;
    }
    await widget.tree.expand(field);
    if (mounted) setState(() => _expanded.add(field.path));
  }

  void _add(CsvField? field) {
    if (field == null) return;
    widget.selected.add(field);
    widget.onChanged();
  }

  void _remove(int? index) {
    if (index == null || index >= widget.selected.length) return;
    widget.selected.removeAt(index);
    _currentSelected = null;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    Widget frame(String title, Widget child) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(4)),
                child: child,
              ),
            ),
          ]),
        );
    final visible = _visible;
    final all = frame(
      l.csvAllFields,
      ListView.builder(
        key: const ValueKey('csv-all-fields'),
        itemCount: visible.length,
        itemExtent: 32,
        itemBuilder: (context, i) {
          final (field, depth) = visible[i];
          // the expander outside the row: its double tap would delay it
          return Container(
            color: _current == field ? cs.primaryContainer : null,
            padding: EdgeInsets.only(left: 4 + depth * 16.0),
            child: Row(children: [
              SizedBox(
                width: 28,
                child: field.expandable
                    ? IconButton(
                        key: ValueKey('csv-expand-${field.path}'),
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        icon: Icon(_expanded.contains(field.path)
                            ? Icons.expand_more
                            : Icons.chevron_right),
                        onPressed: () => _toggle(field),
                      )
                    : null,
              ),
              Expanded(
                child: InkWell(
                  key: ValueKey('csv-field-${field.path}'),
                  onTap: () => setState(() => _current = field),
                  onDoubleTap: () => _add(field),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(field.string, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ]),
          );
        },
      ),
    );
    final selected = frame(
      l.csvFieldsSelected,
      ReorderableListView.builder(
        key: const ValueKey('csv-selected-fields'),
        buildDefaultDragHandles: true,
        itemCount: widget.selected.length,
        onReorderItem: (from, to) {
          widget.selected.insert(to, widget.selected.removeAt(from));
          _currentSelected = null;
          widget.onChanged();
        },
        itemBuilder: (context, i) {
          final field = widget.selected[i];
          return InkWell(
            key: ValueKey('csv-selected-$i'),
            onTap: () => setState(() => _currentSelected = i),
            onDoubleTap: () => _remove(i),
            child: Container(
              height: 32,
              alignment: Alignment.centerLeft,
              color: _currentSelected == i ? cs.primaryContainer : null,
              padding: const EdgeInsets.only(left: 8, right: 32),
              child: Text(field.label, overflow: TextOverflow.ellipsis),
            ),
          );
        },
      ),
    );
    final buttons = Wrap(
      direction: Axis.vertical,
      spacing: 4,
      children: [
        IconButton(
          key: const ValueKey('csv-add'),
          tooltip: l.add,
          icon: const Icon(Icons.arrow_forward),
          onPressed: _current == null ? null : () => _add(_current),
        ),
        IconButton(
          key: const ValueKey('csv-remove'),
          tooltip: l.remove,
          icon: const Icon(Icons.arrow_back),
          onPressed:
              _currentSelected == null ? null : () => _remove(_currentSelected),
        ),
        IconButton(
          key: const ValueKey('csv-clear'),
          tooltip: l.csvRemoveAll,
          icon: const Icon(Icons.clear_all),
          onPressed: widget.selected.isEmpty
              ? null
              : () {
                  widget.selected.clear();
                  _currentSelected = null;
                  widget.onChanged();
                },
        ),
      ],
    );
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 560) {
        return Column(children: [
          all,
          RotatedBox(quarterTurns: 1, child: buttons),
          selected,
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        all,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Center(child: buttons),
        ),
        selected,
      ]);
    });
  }
}

/// Delimiter, quote, encoding and locale format (Python
/// `WinCSV` parameters) plus the dialog's own [extra] entries.
class _CsvParameters extends StatelessWidget {
  final TextEditingController delimiter;
  final TextEditingController quote;
  final String encoding;
  final ValueChanged<String> onEncoding;
  final bool localeFormat;
  final ValueChanged<bool> onLocaleFormat;
  final List<Widget> extra;
  final bool initiallyExpanded;

  const _CsvParameters({
    required this.delimiter,
    required this.quote,
    required this.encoding,
    required this.onEncoding,
    required this.localeFormat,
    required this.onLocaleFormat,
    this.extra = const [],
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Widget char(String key, String label, TextEditingController c) => SizedBox(
          width: 120,
          child: TextField(
            key: ValueKey(key),
            controller: c,
            maxLength: 1,
            decoration: InputDecoration(
                labelText: label, counterText: '', isDense: true),
          ),
        );
    return ExpansionTile(
      key: const ValueKey('csv-parameters'),
      title: Text(l.csvParameters),
      initiallyExpanded: initiallyExpanded,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedAlignment: Alignment.centerLeft,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            char('csv-delimiter', l.csvDelimiter, delimiter),
            char('csv-quote', l.csvQuoteChar, quote),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                key: const ValueKey('csv-encoding'),
                initialValue: encoding,
                isDense: true,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.csvEncoding),
                items: [
                  for (final e in csvEncodings)
                    DropdownMenuItem(value: e, child: Text(e)),
                ],
                onChanged: (v) => onEncoding(v ?? encoding),
              ),
            ),
            ...extra,
            Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(
                key: const ValueKey('csv-locale'),
                value: localeFormat,
                onChanged: (v) => onLocaleFormat(v ?? true),
              ),
              Text(l.csvLocaleFormat),
            ]),
          ],
        ),
      ],
    );
  }
}

Widget _dialogFrame(BuildContext context,
    {required Key key,
    required String title,
    required List<Widget> children,
    required List<Widget> actions}) {
  final size = MediaQuery.sizeOf(context);
  return Dialog(
    key: key,
    insetPadding: const EdgeInsets.all(24),
    child: SizedBox(
      width: math.min(size.width * 0.9, 1000),
      height: size.height * 0.85,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...children,
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: actions,
          ),
        ]),
      ),
    ),
  );
}

// ── Export ────────────────────────────────────────────────────────────────

/// CSV export of [screen] (spec 11.9, Python `WinExport`); [name] is the
/// title of the tab, [listed] the shown records of a tree view.
Future<void> showCsvExport(BuildContext context,
    {required TrytonScreen screen,
    required String name,
    List<Record>? listed}) async {
  final svc = ProviderScope.containerOf(context, listen: false)
      .read(modelServiceProvider);
  final tree = CsvFieldTree(svc, screen.model.name, screen.context,
      import: false, l10n: context.l10n);
  await tree.load();
  // the fields of the current view (Python `Form.sig_export`)
  final selected = <CsvField>[];
  final view = screen.currentView;
  if (view != null) {
    for (final name in view.fields) {
      final type = view.definition.rawFields[name]?['type'];
      final paths = switch (type) {
        'selection' => ['$name.translated'],
        'reference' => ['$name.translated', '$name/rec_name'],
        _ => [name],
      };
      for (final p in paths) {
        if (tree.fields[p] case final f?) selected.add(f);
      }
    }
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CsvExportDialog(
        screen: screen, name: name, tree: tree, selected: selected, listed: listed),
  );
}

class _CsvExportDialog extends StatefulWidget {
  final TrytonScreen screen;
  final String name;
  final CsvFieldTree tree;
  final List<CsvField> selected;
  final List<Record>? listed;

  const _CsvExportDialog(
      {required this.screen,
      required this.name,
      required this.tree,
      required this.selected,
      this.listed});

  @override
  State<_CsvExportDialog> createState() => _CsvExportDialogState();
}

class _CsvExportDialogState extends State<_CsvExportDialog> {
  late final _delimiter =
      TextEditingController(text: _defaultDelimiter(widget.screen));
  final _quote = TextEditingController(text: '"');
  String _encoding = 'utf_8_sig';
  bool _localeFormat = true;
  bool _header = true;
  late bool _selectedRecords;
  bool _ignoreSearchLimit = false;
  List<Map<String, dynamic>> _predefs = const [];
  int? _predef;

  TrytonScreen get _screen => widget.screen;
  ModelService get _svc => widget.tree.svc;

  /// Tree view with children (Python `screen_is_tree`).
  bool get _isTree =>
      _screen.currentView?.viewType == 'tree' &&
      _screen.currentView?.fieldChilds != null;

  @override
  void initState() {
    super.initState();
    // Python `screen_has_selected` (form: the current record)
    _selectedRecords = !_isTree &&
        _exportRecords(_screen, selected: true).ids.isNotEmpty;
    _loadPredefs();
  }

  @override
  void dispose() {
    _delimiter.dispose();
    _quote.dispose();
    super.dispose();
  }

  Future<void> _loadPredefs() async {
    try {
      final result = await _svc.execute<dynamic>('ir.export', 'get', [
        _screen.model.name,
        ['name', 'header', 'records', 'ignore_search_limit', 'export_fields.name'],
      ], context: _screen.context);
      if (!mounted) return;
      setState(() => _predefs = [
            for (final e in result as List? ?? const [])
              if (e is Map) Map<String, dynamic>.from(e)
          ]);
    } on HandledRpcError {
      // shown
    }
  }

  Future<void> _selectPredef(int index) async {
    final export = _predefs[index];
    final fields = <CsvField>[];
    for (final f in export['export_fields.'] as List? ?? const []) {
      if (f is! Map) continue;
      final field = await widget.tree.resolve('${f['name']}');
      if (field != null) fields.add(field);
    }
    if (!mounted) return;
    setState(() {
      _predef = index;
      widget.selected
        ..clear()
        ..addAll(fields);
      _header = export['header'] == true;
      _selectedRecords = export['records'] == 'selected';
      _ignoreSearchLimit = export['ignore_search_limit'] == true;
    });
  }

  Future<String?> _askName() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.csvExportName),
        content: TextField(
          key: const ValueKey('csv-export-name'),
          controller: c,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.l10n.cancel)),
          FilledButton(
              key: const ValueKey('csv-export-name-ok'),
              onPressed: () => Navigator.pop(ctx, c.text),
              child: Text(ctx.l10n.ok)),
        ],
      ),
    );
    // not disposed: the closing dialog still shows the field
    return name == null || name.trim().isEmpty ? null : name.trim();
  }

  Future<bool> _confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.l10n.no)),
            FilledButton(
                key: const ValueKey('csv-confirm-yes'),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ctx.l10n.yes)),
          ],
        ),
      ) ??
      false;

  /// Save Export (Python `addreplace_predef`): new → `ir.export.set`,
  /// chosen → `ir.export.update`; then the toolbar cache is cleared.
  Future<void> _savePredef() async {
    final fields = [for (final f in widget.selected) f.path];
    if (fields.isEmpty) return;
    final index = _predef;
    final String name;
    if (index == null) {
      final n = await _askName();
      if (n == null) return;
      name = n;
    } else {
      name = '${_predefs[index]['name']}';
      if (!await _confirm(context.l10n.csvOverrideExport(name))) return;
    }
    final values = <String, dynamic>{
      'header': _header,
      'records': _selectedRecords ? 'selected' : 'listed',
      'ignore_search_limit': _ignoreSearchLimit,
    };
    try {
      int id;
      if (index == null) {
        id = (await _svc.execute<dynamic>('ir.export', 'set', [
          {
            ...values,
            'name': name,
            'resource': _screen.model.name,
            'export_fields': [
              for (final f in fields) {'name': f}
            ],
          }
        ], context: _screen.context) as num)
            .toInt();
      } else {
        id = (_predefs[index]['id'] as num).toInt();
        await _svc.execute<dynamic>('ir.export', 'update', [id, values, fields],
            context: _screen.context);
      }
      _svc.clearCache('model.${_screen.model.name}.view_toolbar_get');
      final export = {
        'id': id,
        'name': name,
        ...values,
        'export_fields.': [
          for (final f in fields) {'name': f}
        ],
      };
      if (!mounted) return;
      setState(() {
        if (index == null) {
          _predefs = [..._predefs, export];
          _predef = _predefs.length - 1;
        } else {
          _predefs = [..._predefs]..[index] = export;
        }
      });
    } on HandledRpcError {
      // shown
    }
  }

  /// Delete Export (`ir.export.unset`).
  Future<void> _deletePredef() async {
    final index = _predef;
    if (index == null) return;
    try {
      await _svc.execute<dynamic>('ir.export', 'unset', [_predefs[index]['id']],
          context: _screen.context);
      _svc.clearCache('model.${_screen.model.name}.view_toolbar_get');
      if (mounted) {
        setState(() {
          _predefs = [..._predefs]..removeAt(index);
          _predef = null;
        });
      }
    } on HandledRpcError {
      // shown
    }
  }

  /// `export_data` of the selected/listed records or `export_data_domain`
  /// of the search (Python `WinExport.response`).
  Future<(List, List<int>?)> _data(List<String> fields) async {
    final model = _screen.model.name;
    if (_selectedRecords || _isTree) {
      final records = _exportRecords(_screen,
          selected: _selectedRecords, listed: widget.listed);
      final data = await _svc.execute<dynamic>(
          model, 'export_data', [records.ids, fields, _header],
          context: _screen.context);
      return (data as List? ?? const [], records.depths);
    }
    final domain = _screen.searchDomain(text: _screen.searchText);
    final data = await _svc.execute<dynamic>(model, 'export_data_domain', [
      domain,
      fields,
      _ignoreSearchLimit ? 0 : _screen.offset,
      _ignoreSearchLimit ? null : _screen.limit,
      _screen.order,
      _header,
    ], context: _screen.context);
    return (data as List? ?? const [], null);
  }

  Future<void> _export({required bool saveAs}) async {
    final l = context.l10n;
    final fields = [for (final f in widget.selected) f.path];
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final (data, depths) = await _data(fields);
      final bytes = _csvBytes(data, depths,
          header: _header,
          localeFormat: _localeFormat,
          delimiter: _delimiter.text.isEmpty ? ',' : _delimiter.text,
          quote: _quote.text.isEmpty ? '"' : _quote.text,
          encoding: _encoding,
          context: _svc.metadata?.parserContext);
      final fileName = '${_slug(widget.name)}.csv';
      if (saveAs) {
        if (!await FileActions.instance.save(fileName, bytes)) return;
      } else {
        await FileActions.instance
            .open(await FileActions.instance.writeTemp(fileName, bytes));
      }
      final count = data.length - (_header && data.isNotEmpty ? 1 : 0);
      messenger?.showSnackBar(SnackBar(content: Text(l.csvRecordsSaved(count))));
    } on HandledRpcError {
      // shown
    } on FormatException catch (e) {
      if (mounted) await _message(context, l.csvExportFailed, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final listedVisible = !_selectedRecords && !_isTree;
    return _dialogFrame(
      context,
      key: const ValueKey('csv-export-dialog'),
      title: l.csvExportTitle(widget.name),
      children: [
        // predefined exports
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              key: ValueKey('csv-predef-${_predefs.length}-$_predef'),
              initialValue: _predef,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: l.csvPredefinedExports, isDense: true),
              items: [
                for (var i = 0; i < _predefs.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text('${_predefs[i]['name']}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (i) {
                if (i != null) _selectPredef(i);
              },
            ),
          ),
          IconButton(
            key: const ValueKey('csv-save-export'),
            tooltip: l.csvSaveExport,
            icon: const Icon(Icons.save_outlined),
            onPressed: widget.selected.isEmpty ? null : _savePredef,
          ),
          IconButton(
            key: const ValueKey('csv-delete-export'),
            tooltip: l.csvDeleteExport,
            icon: const Icon(Icons.delete_outline),
            onPressed: _predef == null ? null : _deletePredef,
          ),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: _CsvFieldsPanel(
            tree: widget.tree,
            selected: widget.selected,
            onChanged: () => setState(() {}),
          ),
        ),
        Wrap(
          spacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<bool>(
              key: const ValueKey('csv-records'),
              value: _selectedRecords,
              items: [
                DropdownMenuItem(value: false, child: Text(l.csvListedRecords)),
                DropdownMenuItem(value: true, child: Text(l.csvSelectedRecords)),
              ],
              onChanged: (v) => setState(() => _selectedRecords = v ?? false),
            ),
            if (listedVisible)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Checkbox(
                  key: const ValueKey('csv-ignore-limit'),
                  value: _ignoreSearchLimit,
                  onChanged: (v) =>
                      setState(() => _ignoreSearchLimit = v ?? false),
                ),
                Text(l.csvIgnoreSearchLimit),
              ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(
                key: const ValueKey('csv-header'),
                value: _header,
                onChanged: (v) => setState(() => _header = v ?? true),
              ),
              Text(l.csvAddFieldNames),
            ]),
          ],
        ),
        _CsvParameters(
          delimiter: _delimiter,
          quote: _quote,
          encoding: _encoding,
          onEncoding: (v) => setState(() => _encoding = v),
          localeFormat: _localeFormat,
          onLocaleFormat: (v) => setState(() => _localeFormat = v),
        ),
      ],
      actions: [
        TextButton(
          key: const ValueKey('csv-close'),
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
        OutlinedButton(
          key: const ValueKey('csv-open'),
          onPressed: widget.selected.isEmpty ? null : () => _export(saveAs: false),
          child: Text(l.open),
        ),
        FilledButton(
          key: const ValueKey('csv-save-as'),
          onPressed: widget.selected.isEmpty ? null : () => _export(saveAs: true),
          child: Text(l.saveAs),
        ),
      ],
    );
  }
}

// ── Import ────────────────────────────────────────────────────────────────

/// CSV import into [model] (spec 11.8, Python `WinImport`); returns the
/// number of imported records (null: nothing imported).
Future<int?> showCsvImport(BuildContext context,
    {required String model,
    required Map<String, dynamic> importContext,
    required String name}) async {
  final svc = ProviderScope.containerOf(context, listen: false)
      .read(modelServiceProvider);
  final tree = CsvFieldTree(svc, model, importContext, import: true, l10n: context.l10n);
  await tree.load();
  if (!context.mounted) return null;
  return showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CsvImportDialog(tree: tree, name: name),
  );
}

class _CsvImportDialog extends StatefulWidget {
  final CsvFieldTree tree;
  final String name;
  const _CsvImportDialog({required this.tree, required this.name});

  @override
  State<_CsvImportDialog> createState() => _CsvImportDialogState();
}

class _CsvImportDialogState extends State<_CsvImportDialog> {
  final _delimiter = TextEditingController(text: ',');
  final _quote = TextEditingController(text: '"');
  final _skip = TextEditingController(text: '0');
  String _encoding = 'utf_8_sig';
  bool _localeFormat = true;
  PickedFile? _file;
  final _selected = <CsvField>[];

  CsvFieldTree get _tree => widget.tree;

  @override
  void dispose() {
    _delimiter.dispose();
    _quote.dispose();
    _skip.dispose();
    super.dispose();
  }

  List<List<String>> _rows() => parseCsv(csvDecode(_file!.bytes, _encoding),
      delimiter: _delimiter.text.isEmpty ? ',' : _delimiter.text,
      quote: _quote.text.isEmpty ? '"' : _quote.text);

  Future<void> _pick() async {
    final files = await FileActions.instance.pick();
    if (files.isNotEmpty && mounted) setState(() => _file = files.first);
  }

  /// Auto-Detect (Python `sig_autodetect`): the first row are labels or
  /// field names; the lines to skip become 1.
  Future<void> _autodetect() async {
    final l = context.l10n;
    if (_file == null) {
      await _message(context, l.csvImport, l.csvSelectImportFile);
      return;
    }
    _skip.text = '1';
    final List<List<String>> rows;
    try {
      rows = _rows();
    } on FormatException catch (e) {
      if (mounted) await _message(context, l.csvDetectionFailed, e.message);
      return;
    }
    final fields = <CsvField>[];
    for (final word in rows.isEmpty ? const <String>[] : rows.first) {
      final field = await _tree.resolve(word);
      if (field == null) {
        if (mounted) {
          await _message(context, l.csvDetectionFailed, l.csvUnknownHeader(word));
        }
        setState(() => _selected
          ..clear()
          ..addAll(fields));
        return;
      }
      fields.add(field);
    }
    if (mounted) {
      setState(() => _selected
        ..clear()
        ..addAll(fields));
    }
  }

  /// `import_data(fields, rows)` (Python `import_csv`).
  Future<void> _import() async {
    final l = context.l10n;
    if (_file == null) {
      await _message(context, l.csvImport, l.csvSelectImportFile);
      return;
    }
    final skip = int.tryParse(_skip.text) ?? 0;
    final parser = _tree.svc.metadata?.parserContext;
    final data = <List<Object?>>[];
    try {
      final rows = _rows();
      for (var i = 0; i < rows.length; i++) {
        final line = rows[i];
        if (i < skip || line.isEmpty) continue;
        data.add([
          for (var j = 0; j < line.length && j < _selected.length; j++)
            parseCsvValue(line[j], _selected[j].type,
                localeFormat: _localeFormat, context: parser),
        ]);
      }
    } on FormatException catch (e) {
      if (mounted) await _message(context, l.csvImportFailed, e.message);
      return;
    }
    try {
      final count = await _tree.svc.execute<dynamic>(_tree.model, 'import_data',
          [
            [for (final f in _selected) f.path],
            data
          ],
          context: _tree.context);
      if (!mounted) return;
      final n = (count as num?)?.toInt() ?? 0;
      await _message(context, l.csvImport, l.csvRecordsImported(n));
      if (mounted) Navigator.pop(context, n);
    } on HandledRpcError {
      // shown
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return _dialogFrame(
      context,
      key: const ValueKey('csv-import-dialog'),
      title: l.csvImportTitle(widget.name),
      children: [
        Row(children: [
          Text('${l.csvFileToImport}: '),
          Expanded(
            child: Text(_file?.name ?? '–',
                key: const ValueKey('csv-import-file'),
                overflow: TextOverflow.ellipsis),
          ),
          OutlinedButton.icon(
            key: const ValueKey('csv-import-pick'),
            onPressed: _pick,
            icon: const Icon(Icons.file_open_outlined),
            label: Text(l.selectFile),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const ValueKey('csv-autodetect'),
            onPressed: _autodetect,
            icon: const Icon(Icons.search),
            label: Text(l.csvAutoDetect),
          ),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: _CsvFieldsPanel(
            tree: _tree,
            selected: _selected,
            onChanged: () => setState(() {}),
          ),
        ),
        _CsvParameters(
          delimiter: _delimiter,
          quote: _quote,
          encoding: _encoding,
          onEncoding: (v) => setState(() => _encoding = v),
          localeFormat: _localeFormat,
          onLocaleFormat: (v) => setState(() => _localeFormat = v),
          initiallyExpanded: true,
          extra: [
            SizedBox(
              width: 140,
              child: TextField(
                key: const ValueKey('csv-skip'),
                controller: _skip,
                keyboardType: TextInputType.number,
                decoration:
                    InputDecoration(labelText: l.csvLinesToSkip, isDense: true),
              ),
            ),
          ],
        ),
      ],
      actions: [
        TextButton(
          key: const ValueKey('csv-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('csv-import'),
          onPressed: _selected.isEmpty ? null : _import,
          child: Text(l.csvImport),
        ),
      ],
    );
  }
}

