/// Wizard session (spec 07-actions-wizards.md 13, 12.3): port of
/// `Sao.Wizard` (SAO wizard.js), checked against the Python client
/// `tryton/gui/window/wizard.py` 8.0. No widgets: the state is announced
/// through [TrytonWizard] (a [ChangeNotifier]); the UI shows [screen] with
/// [buttons] in a dialog or a tab.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../model/model.dart';
import '../screen/screen.dart';
import '../xml/view_definition.dart';

/// `wizard.<name>.<method>(params…, context)`; [method] is the full name
/// (e.g. `wizard.party.check_vies.create`).
typedef WizardRpc = Future<dynamic> Function(
    String method, List<dynamic> params,
    {Map<String, dynamic>? context});

/// A button of a wizard view (`StateView` button: state, string, icon,
/// default, validate).
class WizardButton {
  final String state;
  final String string;
  final String? icon;
  final bool isDefault;
  final bool validate;

  const WizardButton(
      {required this.state,
      this.string = '',
      this.icon,
      this.isDefault = false,
      this.validate = false});

  factory WizardButton.fromJson(Map<String, dynamic> json) => WizardButton(
        state: '${json['state']}',
        string: '${json['string'] ?? ''}',
        icon: json['icon'] is String && (json['icon'] as String).isNotEmpty
            ? json['icon'] as String
            : null,
        isDefault: json['default'] == true,
        validate: json['validate'] == true,
      );
}

/// One wizard session: `create` → `execute` per state → `delete`.
class TrytonWizard extends ChangeNotifier {
  /// `wiz_name` of the action.
  final String action;
  final String name;
  final WizardRpc rpc;

  /// Session of the screens of the wizard views (rpc, context).
  final ModelSession session;

  /// Calling records: `model`, `id`, `ids`, `action_id`.
  final Map<String, dynamic> data;

  /// Context of the wizard: passed context ∪ `active_id`, `active_ids`,
  /// `active_model`, `action_id`.
  final Map<String, dynamic> context;

  /// Runs an action returned by `execute` (`[action, data]`) with the
  /// context without the wizard keys.
  Future<void> Function(dynamic action, Map<String, dynamic> data,
      Map<String, dynamic> context)? onAction;

  /// Called for each screen of a view (e.g. to mark fields without widget
  /// readonly).
  void Function(TrytonScreen screen)? onScreen;

  int? sessionId;
  String? startState;
  String? endState;
  String? state;

  /// Screen and state of the current view (null without view).
  TrytonScreen? screen;
  String? screenState;
  List<WizardButton> buttons = const [];

  /// Validation message of the last button with `validate` (info bar).
  String? invalidMessage;

  bool _processing = false;
  bool _waitingResponse = false;
  bool _disposed = false;
  final _finished = Completer<String?>();

  TrytonWizard({
    required this.action,
    required this.name,
    required this.rpc,
    required this.session,
    this.data = const {},
    Map<String, dynamic> context = const {},
  }) : context = {
          ...context,
          'active_id': data['id'],
          'active_ids': data['ids'] ?? const [],
          'active_model': data['model'],
          'action_id': data['action_id'],
        };

  /// Buttons are disabled while a state is processed.
  bool get processing => _processing;

  /// The session ended (`delete` called).
  bool get done => _finished.isCompleted;

  /// Completes at the end with the result of `delete` (a client action
  /// string like `reload menu`, or null).
  Future<String?> get finished => _finished.future;

  /// The button of the end state (link style, Escape, closing).
  WizardButton? get endButton {
    for (final b in buttons) {
      if (b.state == endState) return b;
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    screen?.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// `create`, then the start state. A failing `create` ends the wizard
  /// (the error is rethrown).
  Future<void> run() async {
    final dynamic result;
    try {
      result = await rpc('wizard.$action.create', const []);
    } catch (_) {
      if (!_finished.isCompleted) _finished.complete(null);
      _notify();
      rethrow;
    }
    final values = result as List;
    sessionId = values[0] as int;
    startState = '${values[1]}';
    endState = '${values[2]}';
    await process(startState!);
  }

  /// Executes [state] (SAO `process`): the end state ends the session;
  /// otherwise `execute(session, {view state: values}, state)`. A result
  /// with `view` shows it and waits for a button, without → end state;
  /// `actions` run (after the end when the wizard ends). On error the
  /// wizard ends without a screen, else it stays in the current state;
  /// the error is rethrown.
  Future<void> process(String state) async {
    if (_processing || _waitingResponse || done) return;
    _processing = true;
    _notify();
    final currentState = this.state;
    this.state = state;
    try {
      if (state == endState) {
        _complete(await _end());
        return;
      }
      final values = <String, dynamic>{};
      final record = screen?.currentRecord;
      if (record != null && screenState != null) {
        values[screenState!] = record.getOnChangeValue();
      }
      final dynamic result;
      try {
        result = await rpc(
            'wizard.$action.execute', [sessionId, values, state],
            context: {...context});
      } catch (_) {
        if (screen == null) {
          this.state = endState;
          _complete(await _end());
        } else {
          this.state = currentState;
        }
        rethrow;
      }
      final map = result is Map ? result : const {};
      final view = map['view'];
      if (view is Map) {
        await _show(view.cast<String, dynamic>());
        _waitingResponse = true;
      } else {
        this.state = endState;
      }
      if (this.state == endState) {
        final end = await _end();
        await _executeActions(map['actions']);
        _complete(end);
      } else {
        await _executeActions(map['actions']);
      }
    } finally {
      _processing = false;
      _notify();
    }
  }

  /// A new screen with exactly the view of [view] (no `fields_view_get`),
  /// a new record without `default_get`, then defaults and values.
  Future<void> _show(Map<String, dynamic> view) async {
    final fieldsView = Map<String, dynamic>.from(view['fields_view'] as Map);
    final old = screen;
    final next = TrytonScreen(
        ScreenAttributes('${fieldsView['model']}',
            mode: const [], context: context),
        session: session);
    onScreen?.call(next);
    next.currentView = next.addView(ViewDefinition.fromJson(fieldsView));
    final record = await next.newRecord(defaults: false);
    if (record != null) {
      final defaults = view['defaults'];
      if (defaults is Map && defaults.isNotEmpty) {
        await record.setDefault(defaults.cast<String, dynamic>());
      }
      final values = view['values'];
      if (values is Map && values.isNotEmpty) {
        record.set(values.cast<String, dynamic>());
      }
    }
    buttons = [
      for (final b in (view['buttons'] as List? ?? const []))
        if (b is Map) WizardButton.fromJson(b.cast<String, dynamic>())
    ];
    invalidMessage = null;
    screenState = '${view['state']}';
    screen = next;
    old?.dispose();
  }

  Future<void> _executeActions(dynamic actions) async {
    if (actions is! List) return;
    final ctx = {...context}
      ..remove('active_id')
      ..remove('active_ids')
      ..remove('active_model')
      ..remove('action_id');
    for (final a in actions) {
      if (a is List && a.isNotEmpty) {
        final data = a.length > 1 && a[1] is Map
            ? Map<String, dynamic>.from(a[1] as Map)
            : <String, dynamic>{};
        await onAction?.call(a[0], data, ctx);
      }
    }
  }

  /// `delete(session)`; returns its result (client action or null).
  Future<String?> _end() async {
    String? clientAction;
    try {
      final result = await rpc('wizard.$action.delete', [sessionId]);
      if (result is String && result.isNotEmpty) clientAction = result;
    } catch (_) {
      // Like SAO: the session could not be deleted; the wizard ends.
    }
    _waitingResponse = false;
    return clientAction;
  }

  void _complete(String? clientAction) {
    if (!_finished.isCompleted) _finished.complete(clientAction);
  }

  /// A button of the view (SAO `response`): with `validate` the record is
  /// validated first (message in [invalidMessage]), then its state runs.
  Future<void> response(WizardButton button,
      {InvalidMessages texts = const InvalidMessages()}) async {
    if (_processing || done) return;
    _waitingResponse = false;
    final record = screen?.currentRecord;
    if (button.validate && record != null && !record.validate()) {
      invalidMessage = record.invalidMessage(texts);
      _notify();
      return;
    }
    invalidMessage = null;
    await process(button.state);
  }

  /// Closing the dialog/tab: the end-state button, or the end directly.
  Future<void> cancel() async {
    final end = endButton;
    if (end != null) {
      await response(end);
    } else if (!done && endState != null) {
      _waitingResponse = false;
      await process(endState!);
    }
  }
}
