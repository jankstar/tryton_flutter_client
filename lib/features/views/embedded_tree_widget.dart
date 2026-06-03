import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/xml/form_xml_parser.dart';
import '../../core/xml/view_definition.dart';
import '../model/field_definition.dart';
import '../shell/app_shell.dart' show pushFormScreen;
import '../model/model_service.dart';
import '../model/record.dart';
import 'navigation_context.dart';
import '../../core/l10n/locale_provider.dart';
import '../../shared/utils/m2o_name_cache.dart' as m2o;
import '../../shared/utils/number_format_utils.dart';
import '../../shared/utils/symbol_cache.dart' as sym_cache;

/// Displays a One2Many or Many2Many field as an embedded table in a form.
///
/// Deletion behaviour like SAO:
/// – clicking Delete marks rows with strikethrough (record.deleted)
/// – an Undelete button (tryton-undo) reverts the marking
/// – actual server deletion only happens when the parent form is saved,
///   communicated via onChanged([['delete', [ids]]])
class EmbeddedTreeWidget extends ConsumerStatefulWidget {
  final FieldDefinition fieldDef;
  final List<int> recordIds;
  final bool readOnly;
  /// Called with Tryton operation lists, e.g.:
  ///   [['delete', [1, 2]]]   – mark records for deletion
  ///   []                      – no pending changes
  ///   [{'op': 'reload'}]      – signal parent to re-read IDs
  final void Function(List<dynamic> ops)? onChanged;

  const EmbeddedTreeWidget({
    super.key,
    required this.fieldDef,
    required this.recordIds,
    this.readOnly = false,
    this.onChanged,
  });

  @override
  ConsumerState<EmbeddedTreeWidget> createState() =>
      _EmbeddedTreeWidgetState();
}

class _EmbeddedTreeWidgetState extends ConsumerState<EmbeddedTreeWidget> {
  TreeViewDefinition? _treeDef;
  List<TrytonRecord> _rows = [];
  final Set<int> _selected = {};

  /// Records marked for deletion – shown with strikethrough.
  /// Actual deletion happens when the parent form is saved.
  final Set<int> _markedForDeletion = {};

  bool _loading = false;
  String? _error;

  String get _relModel => widget.fieldDef.relation ?? '';

  @override
  void initState() {
    super.initState();
    _loadView();
  }

  @override
  void didUpdateWidget(EmbeddedTreeWidget old) {
    super.didUpdateWidget(old);
    // Use listEquals (content comparison) instead of != (reference comparison).
    // Without this, every form rebuild creates a new List object for recordIds,
    // causing _loadData() to fire even when the IDs haven't changed –
    // e.g. on every keystroke in a text field.
    if (!listEquals(old.recordIds, widget.recordIds)) _loadData();
  }

  // ─── Loading ──────────────────────────────────────────────────────────────

  Future<void> _loadView() async {
    if (_relModel.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final svc = ref.read(modelServiceProvider);
      final viewDef = await svc.fieldsViewGet(_relModel, viewType: 'tree');
      final treeDef = TreeXmlParser().parse(
        viewDef.arch,
        viewDef.fields.map((k, v) => MapEntry(k, <String, dynamic>{
          'string': v.label, 'type': v.type, 'selection': v.selection,
        })),
      );
      setState(() => _treeDef = TreeViewDefinition(
            columns: treeDef.columns, fields: viewDef.fields,
            editable: treeDef.editable));
      await _loadData();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadData() async {
    if (_relModel.isEmpty || _treeDef == null) return;
    if (widget.recordIds.isEmpty) {
      setState(() { _rows = []; _selected.retainAll({}); });
      return;
    }
    try {
      final svc = ref.read(modelServiceProvider);
      final cols = _treeDef!.columns.map((c) => c.name).toList();
      final fields = <String>['rec_name', ...cols];
      for (final col in cols) {
        if (_treeDef!.fields[col]?.type == 'many2one') {
          fields.add('$col.rec_name');
        }
      }
      final rows = await svc.read(_relModel, widget.recordIds, fields);
      // Batch-resolve any Many2One IDs that came back as plain integers
      await m2o.resolveM2ONames(svc, rows, cols,
          Map.fromEntries(cols.map((c) => MapEntry(c, _treeDef!.fields[c]))));
      if (mounted) {
        setState(() {
          _rows = rows;
          final validIds = rows.map((r) => r.id).toSet();
          _selected.retainAll(validIds);
          _markedForDeletion.retainAll(validIds);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _openRecord(int id) async {
    final allIds = _rows
        .where((r) => !_markedForDeletion.contains(r.id))
        .map((r) => r.id)
        .toList();
    final idx = allIds.indexOf(id);
    ref.read(navContextProvider.notifier).state = RecordNavContext(
      model: _relModel,
      title: widget.fieldDef.label,
      recordIds: allIds,
      currentIndex: idx < 0 ? 0 : idx,
    );
    await pushFormScreen(
      context,
      model: _relModel,
      recordId: id,
      title: widget.fieldDef.label,
      screenDomain: const [],
    );
    // Refresh the embedded table display only.
    // Do NOT call widget.onChanged – that would overwrite _values[fieldName]
    // in the parent with a non-ID value, making recordIds appear empty.
    await _loadData();
  }

  Future<void> _newRecord() async {
    await pushFormScreen(
      context,
      model: _relModel,
      recordId: -1,
      title: widget.fieldDef.label,
      screenDomain: const [],
    );
    // Newly created records are linked via the related model's parent field.
    // The parent form must be reloaded (Reload button) to see the new entry,
    // because we cannot update widget.recordIds without overwriting _values.
    // Just refresh with current IDs for now.
    await _loadData();
  }

  /// Mark selected records for deletion (like SAO's screen.remove).
  /// Rows show with strikethrough; actual deletion on parent save.
  void _markForDeletion() {
    setState(() => _markedForDeletion.addAll(_selected));
    _notifyParent();
  }

  /// Undo deletion marking (like SAO's screen.unremove / but_undel).
  void _undelete() {
    setState(() => _markedForDeletion.removeAll(_selected));
    _notifyParent();
  }

  /// Communicate current pending deletions to the parent form in
  /// Tryton operation format: [['delete', [id1, id2]]].
  void _notifyParent() {
    if (_markedForDeletion.isEmpty) {
      widget.onChanged?.call([]);
    } else {
      widget.onChanged?.call([
        ['delete', _markedForDeletion.toList()],
      ]);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
          height: 60,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_error != null) {
      return Text(_error!,
          style: const TextStyle(color: Colors.red, fontSize: 12));
    }
    if (_treeDef == null) return const SizedBox.shrink();

    final l = context.l10n;
    final primary = Theme.of(context).colorScheme.primary;
    final errorColor = Theme.of(context).colorScheme.error;
    final hasSelection = _selected.isNotEmpty;
    final singleSelection = _selected.length == 1;
    final selectedAreMarked = _selected.isNotEmpty &&
        _selected.every((id) => _markedForDeletion.contains(id));
    final selectedHaveMarked =
        _selected.any((id) => _markedForDeletion.contains(id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Toolbar ───────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            // ── Buttons (scrollable so narrow layouts don't overflow) ─────
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _TBtn(icon: Icons.refresh, tip: l.reload, onPressed: _loadView),
                  _TBtn(
                    icon: Icons.open_in_new,
                    tip: l.openInForm,
                    color: singleSelection &&
                            !_markedForDeletion.contains(_selected.firstOrNull)
                        ? primary
                        : null,
                    onPressed: singleSelection &&
                            !_markedForDeletion.contains(_selected.firstOrNull)
                        ? () => _openRecord(_selected.first)
                        : null,
                  ),
                  if (!widget.readOnly) ...[
                    _TBtn(icon: Icons.add, tip: l.createNew, onPressed: _newRecord),
                    _TBtn(
                      icon: Icons.undo,
                      tip: l.undelete,
                      color: selectedHaveMarked ? Colors.green : null,
                      onPressed: selectedHaveMarked ? _undelete : null,
                    ),
                    _TBtn(
                      icon: Icons.delete_outline,
                      tip: l.delete,
                      color: hasSelection && !selectedAreMarked ? errorColor : null,
                      onPressed:
                          hasSelection && !selectedAreMarked ? _markForDeletion : null,
                    ),
                  ],
                ]),
              ),
            ),
            // ── Counts (pinned right) ─────────────────────────────────────
            if (_markedForDeletion.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '${_markedForDeletion.length} ×',
                  style: TextStyle(fontSize: 11, color: errorColor),
                ),
              ),
            if (_rows.isNotEmpty)
              Text('${_rows.length}',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.outline)),
          ]),
        ),
        const SizedBox(height: 4),

        // ── Table ─────────────────────────────────────────────────────────
        if (_rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(l.noEntries,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 13)),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 12,
              headingRowHeight: 34,
              dataRowMinHeight: 30,
              dataRowMaxHeight: 44,
              headingRowColor: WidgetStateProperty.all(
                Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withAlpha(120),
              ),
              columns: [
                DataColumn(
                  label: Checkbox(
                    tristate: true,
                    value: _selected.length == _rows.length && _rows.isNotEmpty
                        ? true
                        : _selected.isEmpty
                            ? false
                            : null,
                    onChanged: (_) {
                      setState(() {
                        if (_selected.length == _rows.length) {
                          _selected.clear();
                        } else {
                          _selected.addAll(_rows.map((r) => r.id));
                        }
                      });
                    },
                  ),
                ),
                ..._treeDef!.columns.map((c) => DataColumn(
                      label: Text(c.label,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 11)),
                    )),
              ],
              rows: _rows.map((record) {
                final isSelected = _selected.contains(record.id);
                final isDeleted = _markedForDeletion.contains(record.id);

                return DataRow(
                  selected: isSelected,
                  color: WidgetStateProperty.resolveWith((states) {
                    if (isDeleted) {
                      return errorColor.withAlpha(20);
                    }
                    if (states.contains(WidgetState.selected)) {
                      return primary.withAlpha(40);
                    }
                    return null;
                  }),
                  cells: [
                    DataCell(Checkbox(
                      value: isSelected,
                      onChanged: (_) {
                        setState(() {
                          if (isSelected) {
                            _selected.remove(record.id);
                          } else {
                            _selected.add(record.id);
                          }
                        });
                      },
                    )),
                    ..._treeDef!.columns.map((col) {
                      final fd = _treeDef!.fields[col.name];
                      final isNum = fd?.type == 'float' ||
                          fd?.type == 'numeric' ||
                          fd?.type == 'integer';
                      final cellStyle = TextStyle(
                        fontSize: 12,
                        decoration: isDeleted ? TextDecoration.lineThrough : null,
                        decorationColor: isDeleted ? errorColor : null,
                        color: isDeleted ? errorColor.withAlpha(160) : null,
                      );
                      return DataCell(
                        isNum && fd != null
                            ? _EmbeddedNumericCell(
                                value: record[col.name],
                                field: fd,
                                record: record,
                                style: cellStyle,
                              )
                            : Text(
                                _fmt(record, col.name, fd),
                                style: cellStyle,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: isDeleted ? null : () => _openRecord(record.id),
                      );
                    }),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String _fmt(TrytonRecord record, String colName, FieldDefinition? fd) {
    final val = record[colName];
    if (val == null || val == false) return '';
    if (fd?.type == 'boolean') return (val as bool) ? '✓' : '';

    if (fd?.type == 'many2one' || _isM2OPair(val)) {
      // [id, rec_name] pair from read() — works even when fd is null
      if (val is List && val.length > 1 && val[1] is String &&
          (val[1] as String).isNotEmpty) {
        return val[1] as String;
      }
      // Companion key 'col.rec_name'
      final companion = record['$colName.rec_name'];
      if (companion != null && companion != false &&
          companion is String && companion.isNotEmpty) {
        return companion;
      }
      // Cache from batch-resolve — guard against stale non-string entries.
      final relModel = fd?.relation;
      final id = _safeId(val);
      if (id != null && relModel != null && relModel.isNotEmpty) {
        final cached = m2o.m2oNameCache['$relModel,$id'];
        if (cached != null && cached.isNotEmpty &&
            !cached.startsWith('{') && !cached.startsWith('[')) {
          return cached;
        }
      }
      return id != null ? '#$id' : '';
    }

    // reference field: value is [model_name, rec_name] — show rec_name only.
    if (fd?.type == 'reference' || _isReferencePair(val)) {
      if (val is List && val.length >= 2) {
        final recName = val[1];
        if (recName is String && recName.isNotEmpty) return recName;
      }
      return '';
    }

    if (fd?.type == 'selection' && fd!.selection != null) {
      // Guard first: a List/Map can never be a valid selection key.
      if (val is List || val is Map) return '';
      final match = fd.selection!
          .where((e) => e[0].toString() == val.toString())
          .firstOrNull;
      return match?[1]?.toString() ?? val.toString();
    }

    // Prevent raw List/Map from leaking as toString()
    if (val is List || val is Map) return '';
    return val.toString();
  }

  /// Returns true if [val] looks like a Tryton Many2One [id, rec_name] pair.
  static bool _isM2OPair(dynamic val) =>
      val is List && val.length == 2 && val[0] is int && val[1] is String;

  /// True if [val] looks like a Tryton reference [model_name, rec_name] pair.
  static bool _isReferencePair(dynamic val) =>
      val is List &&
      val.length == 2 &&
      val[0] is String &&
      (val[0] as String).contains('.') &&
      (val[1] is String || val[1] == false || val[1] == null);

  /// Safely extracts an integer ID from a Many2One value (int or [id, …]).
  static int? _safeId(dynamic val) {
    if (val is int) return val;
    if (val is List && val.isNotEmpty && val[0] is num) {
      return (val[0] as num).toInt();
    }
    return null;
  }
}

// ─── Numeric cell for embedded tree ──────────────────────────────────────────

class _EmbeddedNumericCell extends ConsumerStatefulWidget {
  final dynamic value;
  final FieldDefinition field;
  final TrytonRecord record;
  final TextStyle? style;
  const _EmbeddedNumericCell({
    required this.value,
    required this.field,
    required this.record,
    this.style,
  });
  @override
  ConsumerState<_EmbeddedNumericCell> createState() =>
      _EmbeddedNumericCellState();
}

class _EmbeddedNumericCellState extends ConsumerState<_EmbeddedNumericCell> {
  String _symbol = '';
  double _position = 1.0;

  @override
  void initState() {
    super.initState();
    _loadSymbol();
  }

  @override
  void didUpdateWidget(_EmbeddedNumericCell old) {
    super.didUpdateWidget(old);
    if (_currencyId(old.record) != _currencyId(widget.record)) _loadSymbol();
  }

  int? _currencyId(TrytonRecord rec) {
    final sf = widget.field.symbol;
    if (sf == null) return null;
    final v = rec[sf];
    if (v is List && v.isNotEmpty) return (v[0] as num?)?.toInt();
    if (v is int) return v;
    return null;
  }

  Future<void> _loadSymbol() async {
    final sf = widget.field.symbol;
    if (sf == null) return;
    final id = _currencyId(widget.record);
    if (id == null || id <= 0) return;
    const relation = 'res.currency';
    final svc = ref.read(modelServiceProvider);
    final (sym, pos) = await sym_cache.resolveSymbol(svc, relation, id);
    if (sym.isNotEmpty && mounted) {
      setState(() { _symbol = sym; _position = pos; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final formatted = formatNumericValue(
      widget.value,
      digits: widget.field.digits,
      locale: locale,
      isInteger: widget.field.type == 'integer',
    );
    final hasPrefix = _symbol.isNotEmpty && _position < 0.5;
    final hasSuffix = _symbol.isNotEmpty && _position >= 0.5;
    final text = hasPrefix
        ? '$_symbol $formatted'
        : hasSuffix ? '$formatted $_symbol' : formatted;
    return Text(
      text,
      style: widget.style,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
    );
  }
}

// ─── Compact toolbar button ───────────────────────────────────────────────────

class _TBtn extends StatelessWidget {
  final IconData icon;
  final String tip;
  final Color? color;
  final VoidCallback? onPressed;
  const _TBtn({required this.icon, required this.tip, this.color, this.onPressed});

  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(icon, size: 16, color: color),
        tooltip: tip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      );
}
