import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart';
import '../../core/rpc/error_processing.dart';
import '../../core/wizard/wizard.dart';
import '../../core/xml/view_definition.dart';
import '../model/model_service.dart';
import '../model/selection_loader.dart';
import '../shell/tab_manager.dart';
import 'record_form.dart';
import 'record_widget_values.dart';

/// Texts of `invalidMessage` for wizard views.
InvalidMessages wizardInvalidTexts(BuildContext context) {
  final l = context.l10n;
  return InvalidMessages(
    required: l.invalidRequired('%s'),
    domain: l.invalidDomain('%s'),
    children: l.invalidChildren('%s'),
  );
}

/// Shows a [TrytonWizard] in a dialog: opened with the first view, closed
/// at the end; completes when the wizard has ended (spec 13).
Future<void> runWizardDialog(BuildContext context, TrytonWizard wizard) async {
  var shown = false;
  void show() {
    if (shown || wizard.done || wizard.screen == null || !context.mounted) {
      return;
    }
    shown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WizardWidget(wizard: wizard, dialog: true),
    );
  }

  wizard.addListener(show);
  try {
    await wizard.run();
  } on HandledRpcError {
    // shown
  } finally {
    show();
  }
  await wizard.finished;
  wizard.removeListener(show);
}

/// The current view of a [TrytonWizard] with its buttons (SAO
/// `Sao.Wizard.Dialog` / `Sao.Wizard.Form`): the default button is primary
/// and runs with Enter, the end-state button is a link and runs with
/// Escape; all buttons are disabled while a state is processed. Closing
/// (dialog, tab) runs the end-state button.
class WizardWidget extends ConsumerStatefulWidget {
  final TrytonWizard wizard;

  /// Dialog (closes itself at the end) or tab content.
  final bool dialog;

  const WizardWidget({super.key, required this.wizard, this.dialog = false});

  @override
  ConsumerState<WizardWidget> createState() => _WizardWidgetState();
}

class _WizardWidgetState extends ConsumerState<WizardWidget> {
  /// Text input not yet written to the record (on focus loss).
  final Map<String, dynamic> _pending = {};
  Record? _record;
  bool _closed = false;

  /// View definition of the current view with the options of method-based
  /// selections (null: not loaded yet → the plain definition).
  ViewDefinition? _viewDef;
  SelectionLoader? _selections;
  String? _selectionsModel;

  String? _tabId;
  TabsNotifier? _tabs;

  TrytonWizard get _wizard => widget.wizard;

  @override
  void initState() {
    super.initState();
    _wizard.addListener(_onChanged);
    if (!widget.dialog) _start();
  }

  /// Tab variant: the wizard runs from the tab.
  Future<void> _start() async {
    try {
      await _wizard.run();
    } on HandledRpcError {
      // shown
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.dialog) return;
    final tabId = TabScope.of(context);
    if (tabId != _tabId) {
      if (_tabId != null) _tabs?.removeCloseGuard(_tabId!, _closeGuard);
      _tabId = tabId;
      _tabs = ref.read(tabsProvider.notifier);
      if (tabId != null) _tabs!.addCloseGuard(tabId, _closeGuard);
    }
  }

  @override
  void dispose() {
    if (_tabId != null) _tabs?.removeCloseGuard(_tabId!, _closeGuard);
    _wizard.removeListener(_onChanged);
    super.dispose();
  }

  /// Closing the tab runs the end-state button; the tab closes when the
  /// wizard has ended.
  Future<bool> _closeGuard() async {
    if (_wizard.done) return true;
    await _cancel();
    return false;
  }

  void _onChanged() {
    if (!mounted) return;
    final record = _wizard.screen?.currentRecord;
    if (!identical(record, _record)) {
      _record = record;
      _pending.clear();
      _viewDef = null;
      _loadSelections();
    }
    if (_wizard.done && !_closed) {
      _closed = true;
      if (widget.dialog) {
        Navigator.of(context).pop();
      } else if (_tabId != null) {
        _tabs?.closeTab(_tabId!);
      }
      return;
    }
    setState(() {});
  }

  /// Options of the method-based selections of the current view (one
  /// loader per view model; cached per value combination).
  Future<void> _loadSelections() async {
    final screen = _wizard.screen;
    final view = screen?.currentView;
    final record = screen?.currentRecord;
    if (screen == null || view == null || record == null) return;
    if (!view.definition.fields.values.any(SelectionLoader.isDynamic)) return;
    final model = screen.model.name;
    final svc = ref.read(modelServiceProvider);
    if (_selectionsModel != model) {
      _selectionsModel = model;
      _selections = null;
    }
    final loader = _selections ??= SelectionLoader(
        (method, values) =>
            svc.getSelectionOptions(model, method, values: values));
    final viewDef =
        await loader.applyTo(view.definition, recordWidgetValues(record));
    if (mounted && identical(_wizard.screen?.currentRecord, record)) {
      setState(() => _viewDef = viewDef);
    }
  }

  Future<void> _flushPending() async {
    final record = _wizard.screen?.currentRecord;
    if (record == null) return;
    final pending = Map<String, dynamic>.from(_pending);
    _pending.clear();
    for (final MapEntry(key: name, value: value) in pending.entries) {
      await setRecordWidgetValue(record, name, value);
    }
    await record.idle;
  }

  Future<void> _write(String name, dynamic value) async {
    final record = _wizard.screen?.currentRecord;
    if (record == null) return;
    try {
      await setRecordWidgetValue(record, name, value);
    } on HandledRpcError {
      // shown
    }
    if (mounted) setState(() {});
    final view = _wizard.screen?.currentView;
    if (view != null && SelectionLoader.hasChangeWith(view.definition)) {
      await _loadSelections();
    }
  }

  Future<void> _press(WizardButton button) async {
    if (_wizard.processing) return;
    try {
      await _flushPending();
      if (!mounted) return;
      await _wizard.response(button, texts: wizardInvalidTexts(context));
    } on HandledRpcError {
      // shown; the wizard stays in its state
    }
  }

  Future<void> _cancel() async {
    try {
      await _wizard.cancel();
    } on HandledRpcError {
      // shown
    }
  }

  void _pressDefault() {
    for (final b in _wizard.buttons) {
      if (b.isDefault) {
        _press(b);
        return;
      }
    }
  }

  /// A view with expanding widgets (text, x2many, …) gets a large dialog.
  bool get _expand {
    final view = _wizard.screen?.currentView;
    final root = view?.formRoot;
    if (view == null || root == null) return false;
    bool expands(List<FormNode> nodes) => nodes.any((node) => switch (node) {
          FieldNode() => const {'richtext', 'html', 'image', 'text'}
                  .contains(node.widget) ||
              const {'text', 'one2many', 'many2many', 'binary', 'dict'}
                  .contains(view.definition.fields[node.name]?.type),
          GroupNode() => expands(node.children),
          NotebookNode() => true,
          PageNode() => expands(node.children),
          _ => false,
        });
    return expands(root.children);
  }

  @override
  Widget build(BuildContext context) {
    final screen = _wizard.screen;
    final view = screen?.currentView;
    final record = screen?.currentRecord;
    final cs = Theme.of(context).colorScheme;

    final Widget form = view?.formRoot == null || record == null
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: RecordForm(
              key: ObjectKey(record),
              model: screen!.model.name,
              root: view!.formRoot!,
              viewDef: _viewDef ?? view.definition,
              record: record,
              onTextChanged: (name, value) => _pending[name] = value,
              onBlur: (name) {
                if (_pending.containsKey(name)) {
                  _write(name, _pending.remove(name));
                }
              },
              onChangedImmediate: _write,
              isReadOnly: _wizard.processing,
            ),
          );

    final message = _wizard.invalidMessage;
    final content = Column(
      mainAxisSize: widget.dialog && !_expand ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message != null)
          Container(
            key: const ValueKey('wizard-invalid'),
            color: cs.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Icon(Icons.error_outline, color: cs.onErrorContainer, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(message,
                      style: TextStyle(color: cs.onErrorContainer))),
            ]),
          ),
        if (widget.dialog && !_expand)
          Flexible(child: form)
        else
          Expanded(child: form),
        _buildButtons(),
      ],
    );

    final shortcuts = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _cancel,
        const SingleActivator(LogicalKeyboardKey.enter): _pressDefault,
      },
      child: Focus(autofocus: true, child: content),
    );

    if (!widget.dialog) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerHighest,
          scrolledUnderElevation: 0,
          title: Text(_wizard.name),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: context.l10n.close,
              onPressed: _cancel,
            ),
          ],
        ),
        body: shortcuts,
      );
    }
    final size = MediaQuery.sizeOf(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _expand ? size.width * 0.9 : 640,
            maxHeight: size.height * (_expand ? 0.9 : 0.8),
          ),
          child: SizedBox(
            width: _expand ? size.width * 0.9 : null,
            height: _expand ? size.height * 0.9 : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(_wizard.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                Flexible(child: shortcuts),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButtons() {
    final disabled = _wizard.processing || _wizard.done;
    Widget label(WizardButton b) => b.icon == null
        ? Text(b.string)
        : Row(mainAxisSize: MainAxisSize.min, children: [
            TrytonIcon(iconName: b.icon, size: 16, fallback: Icons.circle),
            const SizedBox(width: 6),
            Text(b.string),
          ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 4,
        children: [
          if (_wizard.processing)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          for (final b in _wizard.buttons)
            if (b.isDefault)
              FilledButton(
                  onPressed: disabled ? null : () => _press(b),
                  child: label(b))
            else if (b.state == _wizard.endState)
              TextButton(
                  onPressed: disabled ? null : () => _press(b),
                  child: label(b))
            else
              OutlinedButton(
                  onPressed: disabled ? null : () => _press(b),
                  child: label(b)),
        ],
      ),
    );
  }
}
