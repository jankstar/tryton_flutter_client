import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart' hide TextField;
import '../../core/rpc/error_processing.dart';
import '../../core/xml/form_xml_parser.dart';
import '../../core/xml/view_definition.dart';
import '../../shared/errors/error_dialogs.dart';
import '../model/field_support.dart';
import '../model/model_rpc.dart';
import '../model/model_service.dart';
import '../shell/tab_manager.dart';
import '../views/record_form.dart';
import '../views/record_widget_values.dart';
import 'auth_provider.dart';
import 'session_bootstrap.dart';

/// Preferences of the user (spec 3.3, Python `window/preference.py`):
/// all tabs are closed first (question), the view comes from
/// `res.user.get_preferences_fields_view()`, the values from
/// `get_preferences(false)` in a record with `id = user_id` (model access
/// of `res.user` skipped); OK sends the changed values with
/// `set_preferences` – the server wants a fresh session, a 401 asks for
/// the password again (re-login) and repeats –, then context,
/// preferences and menu are reloaded. Returns whether it was saved.
Future<bool> showPreferencesDialog(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final tabs = ref.read(tabsProvider.notifier);
  if (ref.read(tabsProvider).tabs.isNotEmpty) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.closeAllTabsQuestion),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.ok)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return false;
    if (!await tabs.requestCloseAll()) return false;
  }
  if (!context.mounted) return false;
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _PreferencesDialog(),
  );
  return saved == true;
}

/// Preferences as values for [Record.set]: `<field>.rec_name` of many2one
/// fields go to the related values (`<field>.`).
Map<String, dynamic> preferencesRecordValues(Map<String, dynamic> preferences) {
  final values = <String, dynamic>{};
  for (final MapEntry(:key, :value) in preferences.entries) {
    if (key.endsWith('.rec_name')) {
      final name = key.substring(0, key.length - '.rec_name'.length);
      values['$name.'] = {'rec_name': value};
    } else {
      values[key] = value;
    }
  }
  return values;
}

class _PreferencesDialog extends ConsumerStatefulWidget {
  const _PreferencesDialog();

  @override
  ConsumerState<_PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends ConsumerState<_PreferencesDialog> {
  ViewDefinition? _view;
  FormRoot? _root;
  Record? _record;
  Object? _error;
  bool _saving = false;

  /// Text typed and not yet written (on focus loss / before OK).
  final Map<String, dynamic> _pending = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final svc = ref.read(modelServiceProvider);
      final userId = ref.read(sessionProvider).userId;
      final view = await svc.execute<dynamic>(
          'res.user', 'get_preferences_fields_view', const []);
      final preferences = await svc.execute<dynamic>(
          'res.user', 'get_preferences', [false]);
      if (view is! Map || preferences is! Map || userId == null) return;
      final definition =
          ViewDefinition.fromJson(Map<String, dynamic>.from(view));
      final model = TrytonModel('res.user', session: modelSessionFor(svc));
      final group = RecordGroup(model)
        ..skipModelAccess = true
        ..readonly = false
        ..addFields(definition.rawFields);
      for (final name in definition.rawFields.keys) {
        model.fields[name]?.views.add(definition.viewId ?? 'form');
      }
      final root =
          FormXmlParser().parse(definition.arch, fields: definition.rawFields);
      // fields without own widget (avatar image, signature richtext) are
      // never written
      for (final name in unsupportedFieldNames(definition.fields, root)) {
        model.fields[name]?.description['readonly'] = true;
      }
      final record = Record(model, id: userId, group: group);
      group.add(record, modified: false);
      record.set(
          preferencesRecordValues(Map<String, dynamic>.from(preferences)),
          modified: false,
          validate: false);
      record.validate(softValidation: true);
      if (!mounted) return;
      setState(() {
        _view = definition;
        _root = root;
        _record = record;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _write(String name, dynamic value) async {
    final record = _record;
    if (record == null) return;
    try {
      await setRecordWidgetValue(record, name, value);
    } on HandledRpcError {
      // shown
    } catch (e) {
      if (mounted) await errorHandlerOf(context, ref).show(e);
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final record = _record;
    if (record == null || _saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    for (final MapEntry(key: name, value: value) in {..._pending}.entries) {
      await setRecordWidgetValue(record, name, value);
    }
    _pending.clear();
    await record.idle;
    if (!record.validate()) {
      setState(() {});
      return;
    }
    final values = record.get();
    setState(() => _saving = true);
    try {
      if (values.isNotEmpty) {
        await ref
            .read(modelServiceProvider)
            .execute<dynamic>('res.user', 'set_preferences', [values]);
      }
      // context, preferences, language, menu and user chip again (3.3)
      await ref.read(sessionBootstrapProvider).reload();
      if (mounted) Navigator.pop(context, true);
    } on HandledRpcError {
      if (mounted) setState(() => _saving = false);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        await errorHandlerOf(context, ref).show(e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final size = MediaQuery.sizeOf(context);
    final record = _record;
    Widget body;
    if (_error != null) {
      body = Center(child: Text('$_error'));
    } else if (record == null || _root == null || _view == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: RecordForm(
          key: ObjectKey(record),
          model: 'res.user',
          root: _root!,
          viewDef: _view!,
          record: record,
          onTextChanged: (name, value) => _pending[name] = value,
          onBlur: (name) {
            if (_pending.containsKey(name)) _write(name, _pending.remove(name));
          },
          onChangedImmediate: _write,
          isReadOnly: false,
        ),
      );
    }
    return Dialog(
      key: const ValueKey('preferences-dialog'),
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: math.min(size.width * 0.9, 900),
        height: size.height * 0.85,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(l.editUserPreferences,
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          Expanded(child: body),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: Text(l.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('preferences-ok'),
                onPressed: record == null || _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l.ok),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
