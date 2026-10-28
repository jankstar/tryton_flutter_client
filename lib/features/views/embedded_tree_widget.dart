import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart';
import '../../core/rpc/error_processing.dart';
import '../../core/xml/form_xml_parser.dart';
import '../../core/xml/view_definition.dart';
import '../../shared/errors/error_dialogs.dart';
import '../model/field_definition.dart';
import '../model/model_service.dart';
import 'record_cells.dart';
import 'record_form.dart';
import 'record_widget_values.dart';

/// Views of x2many relations (`fields_view_get`), loaded once per
/// relation and view type (values, not futures: a cached future would be
/// bound to the zone that created it).
final _viewCache = <String, ViewDefinition>{};

Future<ViewDefinition> _view(ModelService svc, String model, String type) async {
  final key = '$model|$type';
  final cached = _viewCache[key];
  if (cached != null) return cached;
  return _viewCache[key] = await svc.fieldsViewGet(model, viewType: type);
}

/// Clears the cached x2many views (e.g. after logout).
void clearEmbeddedViewCache() => _viewCache.clear();

/// One2Many/Many2Many field of a form (spec 9.2.7): a table of the child
/// group of [parent] plus an inline sub-form.
///
/// * New: `default_get` in a new child record, added to the group (the
///   parent field points to the parent), opened in the sub-form.
/// * Open/Edit: the sub-form works on the record of the group.
/// * Delete (one2many) / Remove (many2many): only marked, Undelete undoes.
///
/// Nothing is saved here: the parent writes the children with its x2many
/// commands (`add`, `create`, `write`, `remove`, `delete`).
class EmbeddedTreeWidget extends ConsumerStatefulWidget {
  final Record parent;
  final FieldDefinition fieldDef;
  final bool readOnly;

  const EmbeddedTreeWidget({
    super.key,
    required this.parent,
    required this.fieldDef,
    this.readOnly = false,
  });

  @override
  ConsumerState<EmbeddedTreeWidget> createState() => _EmbeddedTreeWidgetState();
}

class _EmbeddedTreeWidgetState extends ConsumerState<EmbeddedTreeWidget> {
  TreeViewDefinition? _treeDef;
  ViewDefinition? _treeView;
  ViewDefinition? _formView;
  FormRoot? _formRoot;

  final Set<Record> _selected = {};

  /// Record shown in the sub-form (null = table).
  Record? _open;

  /// Text input of the sub-form not yet written (on focus loss).
  final Map<String, dynamic> _pending = {};

  /// Records whose row values are being loaded.
  final Set<Record> _loading = {};

  final _hScrollController = ScrollController();
  bool _loadingView = false;
  String? _error;

  String get _relModel => widget.fieldDef.relation ?? '';
  bool get _isMany2Many => widget.fieldDef.type == 'many2many';

  RecordGroup? get _group {
    final value = widget.parent.fieldGetClient(widget.fieldDef.name);
    return value is RecordGroup ? value : null;
  }

  @override
  void initState() {
    super.initState();
    _loadView();
  }

  @override
  void dispose() {
    _hScrollController.dispose();
    super.dispose();
  }

  // ─── Loading ──────────────────────────────────────────────────────────────

  Future<void> _loadView() async {
    if (_relModel.isEmpty) return;
    setState(() {
      _loadingView = true;
      _error = null;
    });
    try {
      final view = await _view(ref.read(modelServiceProvider), _relModel, 'tree');
      final treeDef = TreeXmlParser().parse(
        view.arch,
        view.fields.map(
          (k, v) => MapEntry(k, <String, dynamic>{'string': v.label, 'type': v.type, 'selection': v.selection}),
        ),
      );
      if (!mounted) return;
      setState(() {
        _treeView = view;
        _treeDef = TreeViewDefinition(
          columns: treeDef.columns,
          fields: view.fields,
          editable: treeDef.editable,
          visual: treeDef.visual,
        );
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loadingView = false);
    }
  }

  /// The fields of [view] in the child model (the group's model is new
  /// after each reload of the parent).
  void _ensureFields(RecordGroup group, ViewDefinition? view) {
    if (view == null) return;
    if (view.rawFields.keys.every(group.model.fields.containsKey)) return;
    group.model.addFields(view.rawFields);
  }

  /// Loads the row values of [record] (eager: the neighbours of the group
  /// come in the same `read`), without error dialog.
  void _ensureLoaded(Record record, String field) {
    if (record.isLoaded(field) || _loading.contains(record)) return;
    _loading.add(record);
    record
        .load(field, processException: false)
        .catchError((Object _) {})
        .whenComplete(() {
      _loading.remove(record);
      if (mounted) setState(() {});
    });
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on HandledRpcError {
      // shown by the form's error handler
    } catch (e) {
      if (mounted) await errorHandlerOf(context, ref).show(e);
    }
    if (mounted) setState(() {});
  }

  Future<void> _ensureFormView(RecordGroup group) async {
    if (_formView == null) {
      final view = await _view(ref.read(modelServiceProvider), _relModel, 'form');
      _formView = view;
      _formRoot = FormXmlParser().parse(view.arch);
    }
    _ensureFields(group, _formView);
  }

  Future<void> _openRecord(Record record) => _run(() async {
        final group = _group;
        if (group == null) return;
        await _ensureFormView(group);
        if (record.id >= 0) await record.load('*');
        if (mounted) setState(() => _open = record);
      });

  Future<void> _newRecord() => _run(() async {
        final group = _group;
        if (group == null) return;
        await _ensureFormView(group);
        final record = await group.newRecordWithDefaults();
        group.add(record);
        await record.idle;
        if (mounted) setState(() => _open = record);
      });

  /// one2many: delete, many2many: remove the link – both only marked.
  void _markSelected() {
    final group = _group;
    if (group == null) return;
    for (final r in _selected.toList()) {
      group.remove(r, remove: _isMany2Many);
      if (!group.contains(r)) _selected.remove(r);
    }
    setState(() {});
  }

  void _unmarkSelected() {
    final group = _group;
    if (group == null) return;
    for (final r in _selected) {
      if (r.deleted || r.removed) group.unremove(r);
    }
    setState(() {});
  }

  // ─── Sub-form ─────────────────────────────────────────────────────────────

  Future<void> _write(String name, dynamic value) => _run(() async {
        final record = _open;
        if (record != null) await setRecordWidgetValue(record, name, value);
      });

  Future<void> _flushPending() async {
    final record = _open;
    if (record == null) return;
    final pending = Map<String, dynamic>.from(_pending);
    _pending.clear();
    for (final MapEntry(key: name, value: value) in pending.entries) {
      await _write(name, value);
    }
    await record.idle;
  }

  Future<void> _showRecord(Record? record) async {
    await _flushPending();
    if (record != null && record.id >= 0) {
      await _run(() => record.load('*'));
    }
    if (mounted) setState(() => _open = record);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loadingView) {
      return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_error != null) {
      return Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12));
    }
    final group = _group;
    if (_treeDef == null || group == null) return const SizedBox.shrink();
    _ensureFields(group, _treeView);

    // The parent was reloaded: its group (and records) are new.
    final open = _open;
    if (open != null && !group.contains(open)) _open = null;
    _selected.removeWhere((r) => !group.contains(r));

    return _open != null ? _buildSubForm(group, _open!) : _buildTable(group);
  }

  Widget _buildSubForm(RecordGroup group, Record record) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final records = [for (final r in group) if (!r.deleted && !r.removed) r];
    final index = records.indexOf(record);
    final hasPrev = index > 0;
    final hasNext = index >= 0 && index < records.length - 1;
    return SizedBox(
      height: 500,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            color: cs.surfaceContainerHighest,
            child: Row(children: [
              _TBtn(icon: Icons.arrow_back, tip: l.close, onPressed: () => _showRecord(null)),
              _TBtn(
                icon: Icons.arrow_back_ios,
                tip: l.previousRecord,
                onPressed: hasPrev ? () => _showRecord(records[index - 1]) : null,
              ),
              if (records.length > 1)
                Text('${index + 1} / ${records.length}', style: TextStyle(fontSize: 11, color: cs.outline)),
              _TBtn(
                icon: Icons.arrow_forward_ios,
                tip: l.nextRecord,
                onPressed: hasNext ? () => _showRecord(records[index + 1]) : null,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.fieldDef.label,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
          Expanded(
            child: (_formView == null || _formRoot == null)
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: RecordForm(
                      key: ObjectKey(record),
                      model: _relModel,
                      root: _formRoot!,
                      viewDef: _formView!,
                      record: record,
                      onTextChanged: (name, value) => _pending[name] = value,
                      onBlur: (name) {
                        if (_pending.containsKey(name)) {
                          _write(name, _pending.remove(name));
                        }
                      },
                      onChangedImmediate: _write,
                      isReadOnly: widget.readOnly || record.readonly,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(RecordGroup group) {
    final l = context.l10n;
    final primary = Theme.of(context).colorScheme.primary;
    final errorColor = Theme.of(context).colorScheme.error;
    final records = group.toList();
    final columns = _treeDef!.columns.where((c) => !c.treeInvisible).toList();
    final hasSelection = _selected.isNotEmpty;
    bool isMarked(Record r) => r.deleted || r.removed;
    final selectedAreMarked = hasSelection && _selected.every(isMarked);
    final selectedHaveMarked = _selected.any(isMarked);
    final markedCount = group.recordDeleted.length + group.recordRemoved.length;
    // Row values: one eager load reads the neighbours too.
    if (columns.isNotEmpty) {
      for (final r in records) {
        if (r.id >= 0 && !r.isLoaded(columns.first.name)) {
          _ensureLoaded(r, columns.first.name);
          break;
        }
      }
    }

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
          child: Row(
            children: [
              // ── Buttons (scrollable so narrow layouts don't overflow) ─────
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      IconButton(
                        icon: TrytonIcon(
                          iconName: 'tryton-switch',
                          size: 16,
                          color: hasSelection ? primary : Theme.of(context).disabledColor,
                          fallback: Icons.compare_arrows,
                        ),
                        tooltip: l.openInForm,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: hasSelection ? () => _openRecord(_selected.first) : null,
                      ),
                      if (!widget.readOnly) ...[
                        _TBtn(icon: Icons.add, tip: l.createNew, onPressed: _newRecord),
                        _TBtn(
                          icon: Icons.undo,
                          tip: l.undelete,
                          color: selectedHaveMarked ? Colors.green : null,
                          onPressed: selectedHaveMarked ? _unmarkSelected : null,
                        ),
                        _TBtn(
                          icon: _isMany2Many ? Icons.link_off : Icons.delete_outline,
                          tip: l.delete,
                          color: hasSelection && !selectedAreMarked ? errorColor : null,
                          onPressed: hasSelection && !selectedAreMarked ? _markSelected : null,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // ── Counts (pinned right) ─────────────────────────────────────
              if (markedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text('$markedCount ×', style: TextStyle(fontSize: 11, color: errorColor)),
                ),
              if (records.isNotEmpty)
                Text('${records.length}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // ── Table ─────────────────────────────────────────────────────────
        if (records.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(l.noEntries, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13)),
          )
        else
          Scrollbar(
            controller: _hScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _hScrollController,
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 12,
                headingRowHeight: 34,
                dataRowMinHeight: 30,
                dataRowMaxHeight: 44,
                headingRowColor: WidgetStateProperty.all(
                  Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(120),
                ),
                columns: [
                  DataColumn(
                    label: Checkbox(
                      tristate: true,
                      value: _selected.length == records.length
                          ? true
                          : _selected.isEmpty
                          ? false
                          : null,
                      onChanged: (_) {
                        setState(() {
                          if (_selected.length == records.length) {
                            _selected.clear();
                          } else {
                            _selected.addAll(records);
                          }
                        });
                      },
                    ),
                  ),
                  ...columns.map(
                    (c) => DataColumn(
                      label: Text(c.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ),
                ],
                rows: records.map((record) {
                  final isSelected = _selected.contains(record);
                  final isDeleted = isMarked(record);
                  final visual = recordVisual(record, _treeDef?.visual);

                  return DataRow(
                    selected: isSelected,
                    color: WidgetStateProperty.resolveWith((states) {
                      if (isDeleted) return errorColor.withAlpha(20);
                      if (states.contains(WidgetState.selected)) return primary.withAlpha(40);
                      switch (visual) {
                        case 'success':
                          return Colors.green.withAlpha(30);
                        case 'warning':
                          return Colors.orange.withAlpha(40);
                        case 'danger':
                          return errorColor.withAlpha(40);
                        default:
                          return null;
                      }
                    }),
                    cells: [
                      DataCell(
                        Checkbox(
                          value: isSelected,
                          onChanged: (_) {
                            setState(() {
                              if (isSelected) {
                                _selected.remove(record);
                              } else {
                                _selected.add(record);
                              }
                            });
                          },
                        ),
                      ),
                      ...columns.map((col) {
                        final fd = _treeDef!.fields[col.name];
                        final cellStyle = TextStyle(
                          fontSize: 12,
                          decoration: isDeleted ? TextDecoration.lineThrough : null,
                          decorationColor: isDeleted ? errorColor : null,
                          color: isDeleted ? errorColor.withAlpha(160) : null,
                        );
                        return DataCell(
                          isNumericField(fd)
                              ? RecordNumericCell.of(record, col.name, fd!, style: cellStyle)
                              : Text(recordCellText(record, col.name, fd), style: cellStyle, overflow: TextOverflow.ellipsis),
                          onTap: isDeleted ? null : () => _openRecord(record),
                        );
                      }),
                    ],
                  );
                }).toList(),
              ),
            ),
          ), // Scrollbar
      ],
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
