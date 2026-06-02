import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/pyson/pyson_evaluator.dart';
import '../../core/xml/form_xml_parser.dart';
import '../../core/xml/view_definition.dart';
import '../model/field_definition.dart';
import '../auth/auth_provider.dart';
import '../auth/user_preferences_provider.dart';
import '../model/model_service.dart';
import '../model/toolbar_data.dart';
import '../../shared/widgets/toolbar_dropdown_button.dart';
import '../../shared/widgets/field_widget.dart';
import 'embedded_tree_widget.dart';
import 'navigation_context.dart';
import '../../core/l10n/locale_provider.dart';

/// Server-driven form – loads the view definition via
/// `fields_view_get` and renders layout, groups and tabs dynamically.
class DynamicFormScreen extends ConsumerStatefulWidget {
  final String model;
  final String title;
  final int recordId; // < 0 for new records
  /// Domain from the action that opened this form (screen domain).
  /// Used for domain_readonly evaluation, like SAO's record.group.domain.
  final List<dynamic> screenDomain;

  const DynamicFormScreen({
    super.key,
    required this.model,
    required this.title,
    required this.recordId,
    this.screenDomain = const [],
  });

  @override
  ConsumerState<DynamicFormScreen> createState() => _DynamicFormScreenState();
}

/// Session-level cache: model technical name → translated display name.
/// Populated from ir.model on first access per model.
final _modelDisplayNameCache = <String, String>{};

class _DynamicFormScreenState extends ConsumerState<DynamicFormScreen>
    with TickerProviderStateMixin {
  // View definition from the server
  ViewDefinition? _viewDef;
  FormRoot? _formRoot;
  TrytonToolbar _toolbar = const TrytonToolbar();

  /// Translated model display name loaded from ir.model (e.g. "Base Object").
  String? _modelDisplayName;

  // Data values of the record
  Map<String, dynamic> _values = {};
  String? _timestamp;

  /// Like SAO's `modified_fields`: only these fields are passed to write()
  /// when saving. Function fields (without a setter) are thus never
  /// accidentally sent.
  final Set<String> _modifiedFields = {};

  // Attachment count badge
  int _attachmentCount = 0;

  bool _loading = false;
  bool _saving = false;
  bool get _isDirty => _modifiedFields.isNotEmpty;
  String? _error;

  bool get _isNew => widget.recordId < 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ─── Load data ───────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final svc = ref.read(modelServiceProvider);

      // Load translated model name early (also cached for subsequent opens)
      // Do this first so it's available as soon as possible.
      if (widget.title == widget.model) {
        _loadModelDisplayName(svc); // fire-and-forget, updates via setState
      }

      // 1. Load view definition
      final viewDef = await svc.fieldsViewGet(widget.model, viewType: 'form');
      final formRoot = FormXmlParser().parse(viewDef.arch);

      // 2. Load record
      // Skip binary fields – Tryton may return raw binary data as the HTTP
      // response body for those, breaking JSON parsing (e.g. res.user avatar).
      const skipTypes = {'binary'};
      final fieldNames = viewDef.fields.entries
          .where((e) => !skipTypes.contains(e.value.type))
          .map((e) => e.key)
          .toList();

      Map<String, dynamic> values = {};
      String? timestamp;
      if (_isNew) {
        values = await svc.defaultGet(widget.model, fieldNames);
      } else {
        final records = await svc.read(widget.model, [widget.recordId], fieldNames);
        if (records.isNotEmpty) {
          values = Map.from(records.first.values);
          timestamp = records.first.timestamp;
          // 'id' is removed from values in TrytonRecord.fromJson.
          // Write it back explicitly here so the id field in the form
          // shows the actual record number.
          values['id'] = records.first.id;
        }
      }

      setState(() {
        _viewDef = viewDef;
        _formRoot = formRoot;
        _values = values;
        _timestamp = timestamp;
        _modifiedFields.clear();
      });

      // Load toolbar, attachment count and translated model name in background
      _loadSideData(svc);  // also called for new records to get model display name
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadSideData(ModelService svc) async {
    // Toolbar actions (view_toolbar_get)
    try {
      final t = await svc.viewToolbarGet(widget.model);
      if (mounted) setState(() => _toolbar = t);
    } catch (_) {}

    // Attachment count
    try {
      final count = await svc.attachmentCount(widget.model, widget.recordId);
      if (mounted) setState(() => _attachmentCount = count);
    } catch (_) {}

    // Translated model display name from ir.model (cached per model)
    await _loadModelDisplayName(svc);
  }

  /// Loads the human-readable, translated model name from ir.model.
  /// Only fetches once per model per session (cached in _modelDisplayNameCache).
  Future<void> _loadModelDisplayName(ModelService svc) async {
    if (_modelDisplayNameCache.containsKey(widget.model)) {
      if (mounted) {
        setState(() =>
            _modelDisplayName = _modelDisplayNameCache[widget.model]);
      }
      return;
    }
    try {
      // In Tryton 8.x, ir.model.name IS the technical model name (e.g. "res.user").
      // We search by 'name' and then get the translated rec_name (display name).
      final result = await svc.searchRead(
        'ir.model',
        domain: [['name', '=', widget.model]],
        fields: ['name', 'rec_name'],
        limit: 1,
      );
      if (result.isNotEmpty) {
        // rec_name is the translated display name; if identical to technical
        // name, it means no translation available → don't bother showing it.
        final displayName = result.first['rec_name']?.toString()
            ?? result.first['name']?.toString()
            ?? '';
        if (displayName.isNotEmpty && displayName != widget.model) {
          _modelDisplayNameCache[widget.model] = displayName;
          if (mounted) setState(() => _modelDisplayName = displayName);
          return;
        }
      }
      // No result or name equals technical name → mark as "no display name"
      _modelDisplayNameCache[widget.model] = '';
    } catch (e) {
      debugPrint('ir.model load error for "${widget.model}": $e');
    }
  }

  /// Returns the best available title for the AppBar.
  /// When the widget title IS the technical model name → use the translated name.
  /// Otherwise the title was set explicitly (e.g. from a menu action) → keep it.
  String get _effectiveTitle {
    final isTechnicalName = widget.title == widget.model;
    if (isTechnicalName && _modelDisplayName != null && _modelDisplayName!.isNotEmpty) {
      return _modelDisplayName!;
    }
    return widget.title;
  }

  /// Subtitle line below the primary title.
  /// Combines model display name (when it differs from the primary title)
  /// and the record position from the navigation context (e.g. "3 / 47").
  /// Examples:
  ///   "Base Object · 3 / 47"   – navigated via list, model name available
  ///   "3 / 47"                 – model name same as title or unavailable
  ///   "Base Object"            – no navigation context
  String get _subtitleText {
    final nav = ref.read(navContextProvider);
    final pos = nav?.positionLabel ?? '';

    final showModelName = _modelDisplayName != null &&
        _modelDisplayName!.isNotEmpty &&
        _modelDisplayName != _effectiveTitle;

    if (showModelName && pos.isNotEmpty) return '$_modelDisplayName · $pos';
    if (showModelName) return _modelDisplayName!;
    if (pos.isNotEmpty) return pos;
    return '';
  }

  // ─── Language sync ───────────────────────────────────────────────────────

  /// Called after saving res.user – reloads session context and preferences.
  /// Mirrors what SAO does after preferences are changed:
  /// 1. reload_context() → refreshes session.context incl. language for all RPCs
  /// 2. apply new language to Flutter locale
  /// 3. clear userPreferences cache so name/currency in header chip refreshes
  Future<void> _reloadUserContext() async {
    try {
      final session = ref.read(sessionProvider);
      // Refresh session.context (language, company, employee, …)
      await session.reloadContext();
      // Apply new language to Flutter UI
      final langCode = session.context['language']?.toString();
      if (langCode != null) {
        await ref.read(localeProvider.notifier).applyServerLanguage(langCode);
      }
      // Clear cached preferences so header chip reloads name/currency
      clearUserPreferencesCache();
      ref.invalidate(userPreferencesProvider);
    } catch (_) {}
  }

  // ─── Save ────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final svc = ref.read(modelServiceProvider);

      // Like SAO: send only actually modified fields.
      // Function fields (no setter) and computed fields are thus
      // never accidentally passed to write() → no NotImplementedError.
      final saveValues = _buildSaveValues();

      if (_isNew) {
        final ids = await svc.create(widget.model, [saveValues]);
        if (mounted) {
          _showSnack(context.l10n.recordCreated);
          Navigator.of(context).pop(ids.firstOrNull);
        }
      } else {
        final isUserRecord = widget.model == 'res.user' &&
            widget.recordId == ref.read(sessionProvider).userId;
        await svc.write(widget.model, [widget.recordId], saveValues,
            timestamp: _timestamp);
        if (mounted) {
          _showSnack(context.l10n.saved);
          setState(() => _modifiedFields.clear());
        }
        // After saving the current user's own record: reload session context
        // so language + name changes take effect immediately everywhere.
        if (isUserRecord) {
          await _reloadUserContext();
        }
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _saving = false);
    }
  }

  /// Builds the dict of fields to be written.
  ///
  /// For new records: all non-system fields with a value.
  /// For existing records: only `_modifiedFields` (like SAO's modified_fields).
  /// One2Many/Many2Many fields with pending delete operations are included
  /// in Tryton operation format: `[['delete', [id1, id2]]]`.
  /// Encodes a field value for write()/create().
  /// Many2One UI stores [id, name] — Tryton expects just the integer id.
  dynamic _encodeFieldValue(String fieldName, dynamic val) {
    final fd = _viewDef?.fields[fieldName];
    if (fd != null && fd.type == 'many2one') {
      if (val is List && val.isNotEmpty) return (val[0] as num?)?.toInt();
      if (val is int) return val;
      return null;
    }
    return val;
  }

  Map<String, dynamic> _buildSaveValues() {
    const neverWrite = {'id', '_timestamp', '_write', '_delete'};

    if (_isNew) {
      return {
        for (final entry in _values.entries)
          if (!neverWrite.contains(entry.key) && entry.value != null && entry.value != false)
            entry.key: _encodeFieldValue(entry.key, entry.value),
      };
    }

    final result = <String, dynamic>{};
    for (final field in _modifiedFields) {
      if (neverWrite.contains(field)) continue;
      if (!_values.containsKey(field)) continue;
      final val = _values[field];
      // One2Many/Many2Many: include only if it contains Tryton operations
      // (a List<List> like [['delete', [id1, id2]]]).
      // Empty lists or non-operation values are skipped.
      final fd = _viewDef?.fields[field];
      if (fd != null && (fd.type == 'one2many' || fd.type == 'many2many')) {
        if (val is List && val.isNotEmpty && val.first is List) {
          result[field] = val; // Tryton operation list
        }
        // else: skip (no pending x2many changes)
      } else {
        result[field] = _encodeFieldValue(field, val);
      }
    }
    return result;
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.deleteRecord),
        content: Text(context.l10n.reallyDelete),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final svc = ref.read(modelServiceProvider);
      await svc.delete(widget.model, [widget.recordId]);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  /// Called by every field when its value changes (like SAO's set_client).
  /// Only updates local state – does NOT trigger on_change RPC.
  /// Use [_onFieldBlur] for the RPC trigger (on focus loss).
  void _onFieldChanged(String name, dynamic value) {
    setState(() {
      _values[name] = value;
      _modifiedFields.add(name);
    });
  }

  void _onFieldBlur(String name) {
    _triggerOnChange(name);
  }

  void _onFieldChangedImmediate(String name, dynamic value) {
    setState(() {
      _values[name] = value;
      _modifiedFields.add(name);
    });
    _triggerOnChange(name);
  }

  Future<void> _triggerOnChange(String field) async {
    final fd = _viewDef?.fields[field];
    if (fd?.onChange == null || fd!.onChange!.isEmpty) return;
    try {
      final svc = ref.read(modelServiceProvider);
      final updates = await svc.onChange(widget.model, _values, [field]);
      if (mounted) {
        setState(() {
          _values.addAll(updates);
          // on_change results are also "modified" (like SAO's set_on_change)
          _modifiedFields.addAll(updates.keys);
        });
      }
    } catch (_) {}
  }

  Future<void> _duplicate() async {
    if (_isNew) return;
    try {
      final svc = ref.read(modelServiceProvider);
      final newIds = await svc.copy(widget.model, [widget.recordId]);
      if (newIds.isNotEmpty && mounted) {
        context.pushReplacement('/models/${widget.model}/${newIds.first}');
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e');
    }
  }

  Future<void> _viewLogs() async {
    if (_isNew) return;
    context.push(
      '/models/ir.model.log?title=Logs&domain=${Uri.encodeComponent('[["resource","=","${widget.model},${widget.recordId}"]]')}',
    );
  }

  Future<void> _openNote() async {
    if (_isNew) return;
    context.push(
      '/models/ir.note?title=Notes&domain=${Uri.encodeComponent('[["resource","=","${widget.model},${widget.recordId}"]]')}',
    );
  }

  /// Shows the SAO-style "This record has been modified" dialog.
  /// Returns true if navigation should proceed (saved or discarded),
  /// false if the user chose Cancel (stay in form).
  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final l = context.l10n;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Text(l.recordModified),
        actions: [
          // Cancel – stay in form
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text(l.cancel),
          ),
          // No – discard changes and leave
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'no'),
            child: Text(l.no),
          ),
          // Yes – save and leave
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'yes'),
            child: Text(l.yes),
          ),
        ],
      ),
    );
    if (result == 'cancel' || result == null) return false;
    if (result == 'yes') {
      await _save();
      // If save failed (error set), stay in form
      if (_error != null) return false;
    }
    return true; // 'no' or successful save
  }

  Future<void> _navigatePrev() async {
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    final nav = ref.read(navContextProvider);
    final prevId = nav?.previousId;
    if (prevId == null) return;
    ref.read(navContextProvider.notifier).state =
        nav!.withIndex(nav.currentIndex - 1);
    if (mounted) context.pushReplacement('/models/${widget.model}/$prevId');
  }

  Future<void> _navigateNext() async {
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    final nav = ref.read(navContextProvider);
    final nextId = nav?.nextId;
    if (nextId == null) return;
    ref.read(navContextProvider.notifier).state =
        nav!.withIndex(nav.currentIndex + 1);
    if (mounted) context.pushReplacement('/models/${widget.model}/$nextId');
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // _withRecNames removed: read() automatically returns Many2One as [id, rec_name].

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final nav = ref.watch(navContextProvider);
    final hasPrev = nav?.hasPrevious ?? false;
    final hasNext = nav?.hasNext ?? false;
    final l = context.l10n;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard()) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Primary title: translated model name when available
            Text(_effectiveTitle, style: const TextStyle(fontSize: 14)),
            // Subtitle: model display name + record position (3 / 47)
            // Show both together, separated by · when both are available.
            if (_subtitleText.isNotEmpty)
              Text(
                _subtitleText,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline),
              ),
          ],
        ),
        actions: [
          // ── Navigation ────────────────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 16),
            tooltip: context.l10n.previousRecord,
            onPressed: hasPrev ? _navigatePrev : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 16),
            tooltip: context.l10n.nextRecord,
            onPressed: hasNext ? _navigateNext : null,
          ),

          // ── CRUD ──────────────────────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l.createNew,
            onPressed: _saving ? null : () async {
              final router = GoRouter.of(context);
              final ok = await _confirmDiscard();
              if (ok && mounted) router.push('/models/${widget.model}/new');
            },
          ),
          IconButton(
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            tooltip: l.save,
            onPressed: (_saving || (!_isDirty && !_isNew)) ? null : _save,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l.reload,
            onPressed: _saving ? null : _load,
          ),
          if (!_isNew) ...[
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: l.duplicate,
              onPressed: _saving ? null : _duplicate,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: _saving
                      ? Theme.of(context).disabledColor
                      : Theme.of(context).colorScheme.error),
              tooltip: l.delete,
              onPressed: _saving ? null : _delete,
            ),
          ],

          // ── Logs / Attachment / Note ──────────────────────────────────
          if (!_isNew) ...[
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: context.l10n.viewLogs,
              onPressed: _viewLogs,
            ),
            _AttachmentIconButton(
              model: widget.model,
              recordId: widget.recordId,
              count: _attachmentCount,
            ),
            IconButton(
              icon: const Icon(Icons.sticky_note_2_outlined),
              tooltip: context.l10n.note,
              onPressed: _openNote,
            ),
          ],

          // ── Action / Relate / Print / Email ──────────────────────────
          // Always shown like in SAO original (disabled when no items).
          if (!_isNew) ...[
            ToolbarDropdownButton(
              icon: Icons.rocket_launch_outlined, // tryton-launch
              tooltip: l.launchActions,
              items: _toolbar.actions,
              model: widget.model,
              selectedIds: _isNew ? [] : [widget.recordId],
            ),
            ToolbarDropdownButton(
              icon: Icons.link,                   // tryton-link
              tooltip: l.relatedRecords,
              items: _toolbar.relate,
              model: widget.model,
              selectedIds: _isNew ? [] : [widget.recordId],
            ),
            ToolbarDropdownButton(
              icon: Icons.print_outlined,         // tryton-print
              tooltip: l.reports,
              items: _toolbar.print,
              model: widget.model,
              selectedIds: _isNew ? [] : [widget.recordId],
            ),
            ToolbarDropdownButton(
              icon: Icons.email_outlined,         // tryton-email
              tooltip: l.email,
              items: _toolbar.emails,
              model: widget.model,
              selectedIds: _isNew ? [] : [widget.recordId],
            ),
          ],

          // ── Close – back to menu ──────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.close),  // tryton-close
            tooltip: context.l10n.close,
            onPressed: () async {
              final router = GoRouter.of(context);
              final ok = await _confirmDiscard();
              if (ok && mounted) router.go('/models');
            },
          ),
        ],
      ),
      body: _buildBody(),
    ), // Scaffold
    ); // PopScope
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(_error!),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _load, child: Text(context.l10n.reload)),
        ]),
      );
    }
    if (_formRoot == null || _viewDef == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: _FormRenderer(
            root: _formRoot!,
            viewDef: _viewDef!,
            values: _values,
            onChanged: _onFieldChanged,
            onBlur: _onFieldBlur,
            onChangedImmediate: _onFieldChangedImmediate,
            isReadOnly: false,
            screenDomain: widget.screenDomain,
          ),
        ),
      ),
    );
  }
}

// ─── Form-Renderer ────────────────────────────────────────────────────────────

class _FormRenderer extends StatefulWidget {
  final FormRoot root;
  final ViewDefinition viewDef;
  final Map<String, dynamic> values;
  final void Function(String, dynamic) onChanged;
  final void Function(String) onBlur;
  final void Function(String, dynamic) onChangedImmediate;
  final bool isReadOnly;
  /// Screen domain from the action that opened this form (for domain_readonly).
  final List<dynamic> screenDomain;

  const _FormRenderer({
    required this.root,
    required this.viewDef,
    required this.values,
    required this.onChanged,
    required this.onBlur,
    required this.onChangedImmediate,
    required this.isReadOnly,
    this.screenDomain = const [],
  });

  @override
  State<_FormRenderer> createState() => _FormRendererState();
}

class _FormRendererState extends State<_FormRenderer> {
  @override
  Widget build(BuildContext context) {
    return _renderNodes(widget.root.children, _safeCol(widget.root.col));
  }

  // Tryton can use col="-1" or col="0" for flexible layouts.
  // We normalise to at least 1 (default: 4).
  static int _safeCol(int col) => col < 1 ? 4 : col;

  Widget _renderNodes(List<FormNode> nodes, int totalCol) {
    // Labels with fieldName are skipped. Their column width is transferred to
    // the immediately following Field-Node with the same name, so that no
    // gaps appear in the grid and the field uses the full available space.
    // (The field already shows its name as a floating label internally.)
    final labelColspanMap = <String, int>{};
    for (final n in nodes) {
      if (n is LabelNode && n.fieldName != null) {
        labelColspanMap[n.fieldName!] = n.colspan;
      }
    }

    final rows = <Widget>[];
    final currentRow = <_Cell>[];
    int currentColUsed = 0;

    void flushRow() {
      if (currentRow.isEmpty) return;
      rows.add(_GridRow(cells: List.from(currentRow), totalCols: totalCol));
      currentRow.clear();
      currentColUsed = 0;
    }

    for (final node in nodes) {
      // LabelNode with field name → skip (field shows label internally)
      if (node is LabelNode && node.fieldName != null) continue;

      if (node is NewlineNode) {
        flushRow();
        continue;
      }
      if (node is NotebookNode) {
        flushRow();
        rows.add(_buildNotebook(node));
        continue;
      }
      if (node is SeparatorNode) {
        flushRow();
        rows.add(_buildSeparator(node));
        continue;
      }

      final w = _buildNode(node, totalCol);
      if (w == null) continue;

      // Field colspan + absorbed label colspan
      int colspan = _getColspan(node, totalCol);
      if (node is FieldNode) {
        final extra = labelColspanMap[node.name] ?? 0;
        colspan = (colspan + extra).clamp(1, totalCol);
      }

      if (currentColUsed + colspan > totalCol) flushRow();
      currentRow.add(_Cell(child: w, colspan: colspan));
      currentColUsed += colspan;

      if (colspan >= totalCol) flushRow();
    }
    flushRow();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget? _buildNode(FormNode node, int totalCol) {
    if (node is FieldNode) return _buildField(node);
    if (node is LabelNode) return _buildLabel(node);
    if (node is GroupNode) return _buildGroup(node);
    if (node is ButtonNode) return _buildButton(node);
    return null;
  }

  Widget _buildField(FieldNode node) {
    final fd = widget.viewDef.fields[node.name];
    if (fd == null) return _unknownField(node.name);

    // Evaluate PYSON states against the current field values
    final states = evaluateFieldStates(
      statesRaw: fd.statesRaw,
      staticInvisible: fd.invisible || (node.invisible ?? false),
      staticReadonly: fd.readonly || (node.readonly ?? false),
      staticRequired: fd.required || (node.required ?? false),
      values: widget.values,
    );

    // Invisible fields are not rendered (no placeholder, no spacing)
    if (states.invisible) return const SizedBox.shrink();

    // domain_readonly: if the merged domain (screen + field) constrains this
    // field to a single value, auto-set it and lock it (like SAO's domain_readonly).
    final domReadonly = evaluateDomainReadonly(
      fieldName: node.name,
      fieldDomainRaw: fd.domainRaw,
      screenDomain: widget.screenDomain,
      values: widget.values,
      ctx: const {},
    );
    if (domReadonly.forcedValue != null &&
        widget.values[node.name] != domReadonly.forcedValue) {
      // Defer the forced value update to avoid calling setState during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onChangedImmediate(node.name, domReadonly.forcedValue);
      });
    }

    final readOnly = widget.isReadOnly || states.readonly || domReadonly.readonly;

    // One2Many / Many2Many → inline table
    if (fd.type == 'one2many' || fd.type == 'many2many') {
      return _buildX2ManyField(fd, widget.values[node.name], readOnly);
    }

    // Many2One: combine value + rec_name if necessary
    final value = _resolveM2OValue(node.name, fd, widget.values);

    // Text-input fields: update local state on keystroke, trigger on_change
    // only on blur (focus loss) – like SAO's focus_out event.
    // Single-action fields (selection, date, many2one, boolean): trigger
    // on_change immediately since there is no "typing" involved.
    final isTextInput = fd.type == 'char' || fd.type == 'text' ||
        fd.type == 'integer' || fd.type == 'float' || fd.type == 'numeric';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: FieldWidget(
        field: fd,
        value: value,
        readOnly: readOnly,
        isRequired: states.required,
        recordValues: widget.values,
        // XML attr takes precedence; fall back to fields_get 'symbol'.
        symbolField: node.symbol ?? fd.symbol,
        // Resolve the relation model of the symbol field so _NumericField
        // can call get_symbol without hardcoding 'res.currency'.
        symbolRelation: _resolveSymbolRelation(node.symbol ?? fd.symbol),
        onChanged: isTextInput
            ? (v) => widget.onChanged(node.name, v)   // local only
            : (v) => widget.onChangedImmediate(node.name, v), // + RPC
        onBlur: isTextInput
            ? () => widget.onBlur(node.name)  // RPC on focus loss
            : null,
      ),
    );
  }

  /// Returns the relation model name of a symbol field (e.g. 'res.currency').
  String? _resolveSymbolRelation(String? symbolFieldName) {
    if (symbolFieldName == null) return null;
    return widget.viewDef.fields[symbolFieldName]?.relation;
  }

  /// Resolves the Many2One value: if only an ID is present,
  /// resolves the Many2One value.
  /// Tryton already returns [id, rec_name] via read().
  /// Also checked here for search_read() (companion key).
  /// Fallback: ID as string, so the field is never empty.
  static dynamic _resolveM2OValue(
    String name,
    FieldDefinition fd,
    Map<String, dynamic> values,
  ) {
    final raw = values[name];
    if (fd.type != 'many2one') return raw;
    if (raw == null || raw == false) return null;

    // Tryton read() returns [id, rec_name] → use directly
    if (raw is List && raw.isNotEmpty) {
      final id = raw[0];
      if (id == null || id == false) return null;
      final name2 = raw.length > 1 ? raw[1] : null;
      if (name2 != null && name2 != false) return raw;
      // ID present but name missing → check companion key
      final companion = values['$name.rec_name'] ?? values['$name.'];
      if (companion != null && companion != false) return [id, companion];
      return raw; // [id, null] → _updateFromValue loads name asynchronously
    }

    // Integer ID only (search_read without eager loading)
    if (raw is int && raw > 0) {
      final companion = values['$name.rec_name'] ?? values['$name.'];
      if (companion != null && companion != false) return [raw, companion];
      return raw; // Integer → _updateFromValue async loads
    }

    return null;
  }

  Widget _buildX2ManyField(FieldDefinition fd, dynamic value, bool readOnly) {
    // value is a list of IDs (integer) or null
    final ids = <int>[];
    if (value is List) {
      for (final item in value) {
        if (item is int && item > 0) ids.add(item);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(fd.label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  )),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline.withAlpha(80)),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.all(8),
          child: EmbeddedTreeWidget(
            key: ValueKey('${fd.name}_${ids.length}'),
            fieldDef: fd,
            recordIds: ids,
            readOnly: readOnly,
            onChanged: (ops) {
              // Tryton operation list [['delete', [ids]]] or []
              // Stored in _values so _buildSaveValues() can include it on save
              widget.onChanged(fd.name, ops.isEmpty ? null : ops);
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildLabel(LabelNode node) {
    // Hide label for a field if the field itself is invisible
    if (node.fieldName != null) {
      final fd = widget.viewDef.fields[node.fieldName!];
      if (fd != null) {
        final states = evaluateFieldStates(
          statesRaw: fd.statesRaw,
          staticInvisible: fd.invisible,
          staticReadonly: fd.readonly,
          staticRequired: fd.required,
          values: widget.values,
        );
        if (states.invisible) return const SizedBox.shrink();
      }
    }

    String text;
    if (node.string != null) {
      text = node.string!;
    } else if (node.fieldName != null) {
      text = widget.viewDef.fields[node.fieldName!]?.label ?? node.fieldName!;
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 4),
      child: Text(
        '$text:',
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
        textAlign: TextAlign.right,
      ),
    );
  }

  Widget _buildSeparator(SeparatorNode node) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        if (node.string != null) ...[
          // Flexible prevents overflow when the text is wider than available
          Flexible(
            child: Text(
              node.string!,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        const Expanded(child: Divider()),
      ]),
    );
  }

  Widget _buildGroup(GroupNode node) {
    final inner = _renderNodes(node.children, _safeCol(node.col));
    if (node.string != null) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(node.string!,
                  style: Theme.of(context).textTheme.titleSmall),
              const Divider(),
              inner,
            ],
          ),
        ),
      );
    }
    return inner;
  }

  Widget _buildButton(ButtonNode node) {
    // Evaluate PYSON states against current record values – like SAO's
    // Button.set_state(record) which calls record.expr_eval(attributes.states).
    final states = evaluateFieldStates(
      statesRaw: node.statesRaw,
      staticInvisible: false,
      staticReadonly: false,
      staticRequired: false,
      values: widget.values,
    );

    if (states.invisible) return const SizedBox.shrink();

    final label = node.string ?? node.name;
    final iconName = node.icon;
    final disabled = widget.isReadOnly || states.readonly;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: (iconName != null && iconName.isNotEmpty)
          ? OutlinedButton.icon(
              icon: TrytonIcon(
                iconName: iconName,
                size: 16,
                color: disabled
                    ? Theme.of(context).colorScheme.onSurface.withAlpha(97)
                    : Theme.of(context).colorScheme.primary,
                fallback: Icons.play_circle_outline,
              ),
              label: Text(label),
              onPressed: disabled ? null : () => _executeButton(node.name),
            )
          : OutlinedButton(
              onPressed: disabled ? null : () => _executeButton(node.name),
              child: Text(label),
            ),
    );
  }

  void _executeButton(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Executing button "$name"…')),
    );
  }

  Widget _buildNotebook(NotebookNode node) {
    // Filter pages based on their states/invisible conditions
    final visiblePages = node.pages.where(_isPageVisible).toList();
    if (visiblePages.isEmpty) return const SizedBox.shrink();

    return DefaultTabController(
      length: visiblePages.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: visiblePages.map((p) => Tab(text: _pageLabel(p))).toList(),
          ),
          SizedBox(
            height: _estimateNotebookHeight(visiblePages),
            child: TabBarView(
              children: visiblePages.map((page) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 8),
                  child: _renderNodes(page.children, _safeCol(widget.root.col)),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// Resolves the display label for a notebook page.
  ///
  /// Priority (like Tryton/SAO):
  /// 1. `string` attribute in the XML arch (already translated by server)
  /// 2. The `string` (label) of the field with the same name as `page.name`
  ///    (pages added via view inheritance often have only `name`, not `string`)
  /// 3. Capitalize the technical `name` as a last fallback
  String _pageLabel(PageNode page) {
    // If the page has an explicit string that looks like a real label, use it
    if (page.string.isNotEmpty &&
        (page.string.contains(' ') ||
            page.string != page.string.toLowerCase() ||
            page.name == null)) {
      return page.string;
    }

    // Look up the field whose name matches the page name → its translated label
    final name = page.name ?? page.string;
    final fieldLabel = widget.viewDef.fields[name]?.label;
    if (fieldLabel != null && fieldLabel.isNotEmpty) return fieldLabel;

    // Fallback: capitalize each word of the technical name
    if (name.isEmpty) return '';
    return name
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// Returns true when the page should be shown.
  /// Evaluates static `invisible` attribute and PYSON `states` against
  /// the current field values – same logic as SAO's page visibility check.
  bool _isPageVisible(PageNode page) {
    // Static invisible="1" → always hidden
    if (page.invisibleStatic) return false;

    // PYSON states evaluation
    if (page.statesRaw != null) {
      final result = evaluateFieldStates(
        statesRaw: page.statesRaw,
        staticInvisible: false,
        staticReadonly: false,
        staticRequired: false,
        values: widget.values,
      );
      if (result.invisible) return false;
    }

    return true;
  }

  // Estimates the minimum height of a notebook based on the number of fields
  double _estimateNotebookHeight(List<PageNode> pages) {
    final maxFields = pages.fold<int>(0, (max, page) {
      final count = page.children.whereType<FieldNode>().length;
      return count > max ? count : max;
    });
    final x2mCount = pages.fold<int>(0, (max, page) {
      final count = page.children.whereType<FieldNode>().where((f) {
        final fd = widget.viewDef.fields[f.name];
        return fd?.type == 'one2many' || fd?.type == 'many2many';
      }).length;
      return count > max ? count : max;
    });
    return (maxFields * 64.0 + x2mCount * 200.0 + 40).clamp(200, 800);
  }

  Widget _unknownField(String name) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text('[$name]', style: const TextStyle(color: Colors.grey, fontSize: 11)),
    );
  }

  int _getColspan(FormNode node, int totalCol) {
    final maxCol = _safeCol(totalCol); // Prevents clamp(1, 0) or clamp(1, -1)
    if (node is FieldNode) return node.colspan.clamp(1, maxCol);
    if (node is LabelNode) return node.colspan.clamp(1, maxCol);
    if (node is GroupNode) return node.colspan.clamp(1, maxCol);
    if (node is ButtonNode) return node.colspan.clamp(1, maxCol);
    return 1;
  }
}

// ─── Grid row ─────────────────────────────────────────────────────────────────

class _Cell {
  final Widget child;
  final int colspan;
  const _Cell({required this.child, required this.colspan});
}

class _GridRow extends StatelessWidget {
  final List<_Cell> cells;
  final int totalCols;
  const _GridRow({required this.cells, required this.totalCols});

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return const SizedBox.shrink();

    final usedCols = cells.fold(0, (sum, c) => sum + c.colspan);

    // Single cell filling the whole row → return directly (no Row overhead)
    if (cells.length == 1 && usedCols >= totalCols) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: cells.first.child,
      );
    }

    // Build Row children: one Expanded per cell + optional trailing Spacer
    // so that cells respect their proportional column width and don't stretch
    // to fill the entire available width when the row is not full.
    // Example: col=6, field(colspan=3) → field takes exactly 50%, not 100%.
    final children = <Widget>[];
    for (final cell in cells) {
      children.add(Expanded(
        flex: cell.colspan,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: cell.child,
        ),
      ));
    }
    final remaining = totalCols - usedCols;
    if (remaining > 0) {
      children.add(Spacer(flex: remaining));
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

// ─── Attachment button with count badge ──────────────────────────────────────

/// Attachment button with count badge and dropdown (Add / Manage)
/// – like SAO's attachment dropdown with Add, Preview, Manage.
class _AttachmentIconButton extends ConsumerWidget {
  final String model;
  final int recordId;
  final int count;

  const _AttachmentIconButton({
    required this.model,
    required this.recordId,
    required this.count,
  });

  String get _domain =>
      Uri.encodeComponent('[["resource","=","$model,$recordId"]]');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final badge = count > 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.attach_file),
          tooltip: l.attachments,
          position: PopupMenuPosition.under,
          onSelected: (choice) {
            switch (choice) {
              case 'add':
                // Open a new ir.attachment form pre-filled with the resource
                context.push(
                  '/models/ir.attachment/new?title=Add Attachment',
                );
              case 'manage':
                context.push(
                  '/models/ir.attachment?title=Attachments&domain=$_domain',
                );
            }
          },
          itemBuilder: (ctx) => [
            // Header
            PopupMenuItem<String>(
              enabled: false,
              height: 28,
              child: Text(
                '${l.attachments}${badge ? " ($count)" : ""}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
              ),
            ),
            const PopupMenuDivider(height: 1),
            // Add
            PopupMenuItem<String>(
              value: 'add',
              child: Row(children: [
                const Icon(Icons.add, size: 16),
                const SizedBox(width: 8),
                Text('Add'),
              ]),
            ),
            // Manage (always available)
            PopupMenuItem<String>(
              value: 'manage',
              child: Row(children: [
                const Icon(Icons.folder_outlined, size: 16),
                const SizedBox(width: 8),
                Text('Manage${badge ? " ($count)" : ""}'),
              ]),
            ),
          ],
        ),
        // Count badge
        if (badge)
          Positioned(
            right: 4,
            top: 4,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints:
                    const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(color: Colors.white, fontSize: 9),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

