import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/field_definition.dart';
import '../model/model_service.dart';
import '../../shared/widgets/field_widget.dart';
import '../../core/l10n/locale_provider.dart';

/// Form view for a single Tryton record.
/// Called with [recordId] = -1 for new records.
class FormViewScreen extends ConsumerStatefulWidget {
  final String model;
  final String title;
  final int recordId;

  const FormViewScreen({
    super.key,
    required this.model,
    required this.title,
    required this.recordId,
  });

  @override
  ConsumerState<FormViewScreen> createState() => _FormViewScreenState();
}

class _FormViewScreenState extends ConsumerState<FormViewScreen> {
  Map<String, FieldDefinition> _fields = {};
  Map<String, dynamic> _values = {};
  String? _timestamp;
  bool _loading = false;
  bool _saving = false;
  bool _isDirty = false;
  String? _error;

  bool get _isNew => widget.recordId < 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = ref.read(modelServiceProvider);
      _fields = await svc.fieldsGet(widget.model);
      final fieldNames = _fields.keys.toList();

      if (_isNew) {
        _values = await svc.defaultGet(widget.model, fieldNames);
      } else {
        final records = await svc.read(widget.model, [widget.recordId], fieldNames);
        if (records.isNotEmpty) {
          final r = records.first;
          _values = Map<String, dynamic>.from(r.values);
          _timestamp = r.timestamp;
        }
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final svc = ref.read(modelServiceProvider);
      if (_isNew) {
        final ids = await svc.create(widget.model, [_values]);
        if (ids.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Record saved.')),
          );
          Navigator.of(context).pop(ids.first);
        }
      } else {
        await svc.write(
          widget.model,
          [widget.recordId],
          _values,
          timestamp: _timestamp,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Änderungen gespeichert.')),
          );
          setState(() => _isDirty = false);
        }
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.deleteRecord),
        content: const Text('Really delete? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final svc = ref.read(modelServiceProvider);
      await svc.delete(widget.model, [widget.recordId]);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _onFieldChanged(String fieldName, dynamic newValue) {
    setState(() {
      _values[fieldName] = newValue;
      _isDirty = true;
    });
    _triggerOnChange(fieldName);
  }

  Future<void> _triggerOnChange(String changedField) async {
    final field = _fields[changedField];
    if (field?.onChange == null || field!.onChange!.isEmpty) return;
    try {
      final svc = ref.read(modelServiceProvider);
      final updates = await svc.onChange(widget.model, _values, [changedField]);
      setState(() => _values.addAll(updates));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Neu: ${widget.title}' : widget.title),
        actions: [
          if (!_isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: context.l10n.delete,
              onPressed: _saving ? null : _delete,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: context.l10n.reload,
            onPressed: _saving ? null : _load,
          ),
          FilledButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text(context.l10n.save),
            onPressed: (_saving || !_isDirty && !_isNew) ? null : _save,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 8),
          FilledButton(onPressed: _load, child: Text(context.l10n.retry)),
        ]),
      );
    }

    final visibleFields = _fields.entries
        .where((e) => !e.value.invisible)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in visibleFields)
              FieldWidget(
                field: entry.value,
                value: _values[entry.key],
                onChanged: (v) => _onFieldChanged(entry.key, v),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
