import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/rpc/error_processing.dart';
import '../../core/screen/screen.dart';
import '../../core/wizard/wizard.dart';
import '../../shared/errors/error_dialogs.dart';
import '../../shared/errors/error_handler.dart';
import '../auth/auth_provider.dart';
import '../model/field_support.dart';
import '../model/model_rpc.dart';
import '../../core/serialization/tryton_serializer.dart';
import '../../shared/utils/file_actions.dart';
import '../../shared/utils/zip_reader.dart';
import '../model/model_service.dart';
import '../../shared/dialogs/tryton_dialogs.dart';
import '../shell/tab_manager.dart';
import '../auth/session_bootstrap.dart';
import '../views/wizard_widget.dart';

/// Interaction of [ActionService] with the user (messages, selection,
/// external URLs); [DialogActionUi] for the app, fakes in tests.
abstract interface class ActionUi {
  /// Message to confirm (e.g. "No action defined.", spec 11.3 Message).
  Future<void> message(String text);

  /// Short notice that needs no answer (e.g. "Generating report…").
  Future<void> notify(String text);

  /// Lets the user choose one of [actions] (names without the menu path);
  /// null = cancelled.
  Future<Map<String, dynamic>?> choose(List<Map<String, dynamic>> actions);

  /// Opens [url] outside the app.
  Future<void> openUrl(String url);

  /// Shows [wizard] (dialog, or with [window] a tab named [title]) and
  /// runs it; completes when the wizard has ended.
  Future<void> runWizard(TrytonWizard wizard,
      {required bool window, required String title});

  /// Error dialogs of the server calls (null: errors reach the caller).
  RpcErrorProcessor? get errorProcessor;

  /// Localised texts.
  String get noActionDefined;
  String get nameSeparator;
  String generatingReport();
  String reportGenerated(String name, String format);
  String notSupported(String name, String type);
}

/// Executes Tryton actions (spec 12.1–12.6, SAO `Sao.Action`, Python
/// client `Action`): act_window opens a tab, url the browser, report runs
/// the report (file output with G2), wizard runs a [TrytonWizard] (13).
class ActionService {
  final ModelService _svc;
  final TabsNotifier _tabs;
  /// Session context and user of the PYSON environment.
  final Map<String, dynamic> Function() sessionContext;
  final int? Function() userId;

  /// Client action without calling screen (end of a wizard from the
  /// menu: `reload menu`, `reload context`).
  final Future<void> Function(String action)? clientAction;

  ActionService(this._svc, this._tabs,
      {required this.sessionContext,
      required this.userId,
      this.clientAction});

  /// Default keywords of [execute] with `keyword` (name suffix).
  static const _keywords = {
    'ir.action.report': 'form_report',
    'ir.action.wizard': 'form_action',
    'ir.action.act_window': 'form_relate',
  };

  /// Runs [action] (values or id → `ir.action.get_action_value`) for
  /// [data] (`model`, `id`, `ids` of the calling records) with [context]
  /// (SAO `Action.execute`). With [keyword] the action's keyword defaults
  /// by type, which adds the record names to the tab name. [screen] is the
  /// calling screen (reloaded after a wizard).
  Future<void> execute(
    dynamic action, {
    Map<String, dynamic> data = const {},
    Map<String, dynamic> context = const {},
    bool keyword = false,
    ActionUi? ui,
    TrytonScreen? screen,
  }) async {
    Map<String, dynamic> values;
    if (action is int) {
      final result = await _svc.execute<dynamic>(
          'ir.action', 'get_action_value', [action],
          context: context);
      if (result is! Map) return;
      values = Map<String, dynamic>.from(result);
    } else {
      values = Map<String, dynamic>.from(action as Map);
    }
    if (keyword && values['keyword'] == null) {
      final defaultKeyword = _keywords[values['type']];
      if (defaultKeyword != null) values['keyword'] = defaultKeyword;
    }
    await execAction(values,
        data: data, context: context, ui: ui, screen: screen);
  }

  /// Runs the action [values] by type (SAO `exec_action`); the context
  /// loses `active_id(s)`/`active_model`.
  Future<void> execAction(
    Map<String, dynamic> action, {
    Map<String, dynamic> data = const {},
    Map<String, dynamic> context = const {},
    ActionUi? ui,
    TrytonScreen? screen,
  }) async {
    data = {...data, 'action_id': action['id']};
    final ctx = {...context}
      ..remove('active_id')
      ..remove('active_ids')
      ..remove('active_model');
    final name = '${action['name'] ?? ''}';
    switch (action['type']) {
      case 'ir.action.act_window':
        final attributes = ScreenAttributes.fromActWindow(
          action,
          sessionContext: sessionContext(),
          userId: userId(),
          data: data,
          context: ctx,
        );
        // a board (spec 9.7) has no model of its own
        final board = attributes.mode.firstOrNull == 'board';
        if (!board && (attributes.model.isEmpty || attributes.model == 'null')) {
          return;
        }
        // Without action name: the translated model name (MODELNAME).
        var baseName = name;
        if (baseName.isEmpty && !board) {
          baseName = await _svc.metadata?.name(attributes.model) ?? '';
          if (baseName.isEmpty) baseName = attributes.model;
        }
        final title = action['keyword'] != null
            ? await _nameWithSuffix(baseName, data, attributes.context, ui)
            : baseName;
        _tabs.openTab(title: title, attributes: attributes);
      case 'ir.action.url':
        final url = action['url'];
        if (url is String && url.isNotEmpty) await ui?.openUrl(url);
      case 'ir.action.report':
        await _executeReport(action, data, ctx, ui);
      case 'ir.action.wizard':
        final title = (action['keyword'] ?? 'form_action') == 'form_action'
            ? await _nameWithSuffix(name, data, ctx, ui)
            : name;
        await _runWizard(action, data, ctx, title, ui, screen);
      default:
        await ui?.message(ui.notSupported(name, '${action['type']}'));
    }
  }

  /// A wizard session (spec 13) in a dialog or (`window`) a tab; at the
  /// end the calling [screen] is reloaded (its records or, for a wizard
  /// of a child record, the current record) and the result of `delete`
  /// runs as client action there.
  Future<void> _runWizard(
      Map<String, dynamic> action,
      Map<String, dynamic> data,
      Map<String, dynamic> context,
      String title,
      ActionUi? ui,
      TrytonScreen? screen) async {
    final wizName = action['wiz_name'];
    if (wizName is! String) return;
    final processor = ui?.errorProcessor;
    final wizard = TrytonWizard(
      action: wizName,
      name: title,
      data: data,
      context: context,
      session: modelSessionFor(_svc, processor: processor),
      rpc: (method, params, {context}) => processor == null
          ? _svc.executeMethod<dynamic>(method, params,
              context: context, processException: false)
          : processor.process(() => _svc.executeMethod<dynamic>(
              method, params,
              context: context, processException: false)),
    )
      ..onAction = (a, d, c) => execute(a, data: d, context: c, ui: ui);
    wizard.onScreen = (s) =>
        s.onViewAdded = (v) => markUnsupportedFields(s.model, v);
    try {
      if (ui != null) {
        await ui.runWizard(wizard, window: action['window'] == true, title: title);
      } else {
        await wizard.run();
        if (!wizard.done) await wizard.cancel();
      }
      final result = await wizard.finished;
      await _afterWizard(result, data, screen);
    } finally {
      wizard.dispose();
    }
  }

  Future<void> _afterWizard(String? result, Map<String, dynamic> data,
      TrytonScreen? screen) async {
    if (screen != null) {
      final current = screen.currentRecord;
      if (screen.model.name == data['model']) {
        final ids = [
          for (final id in (data['ids'] as List? ?? const []))
            if (id is int) id
        ];
        await screen.reload(ids, written: true);
      } else if (current != null) {
        // Wizard of a child record: reload the parent record.
        await screen.reload([current.id], written: true);
      }
      if (result != null) await screen.clientAction(result);
    } else if (result != null) {
      await clientAction?.call(result);
    }
  }

  /// [name] with the rec_names of the first 5 records of [data]
  /// (`name (a, b, ...)`, SAO `add_name_suffix`).
  Future<String> _nameWithSuffix(String name, Map<String, dynamic> data,
      Map<String, dynamic> context, ActionUi? ui) async {
    final model = data['model'];
    final allIds = [
      for (final id in (data['ids'] as List? ?? const []))
        if (id is int && id >= 0) id
    ];
    if (model is! String || allIds.isEmpty) return name;
    final ids = allIds.take(5).toList();
    final separator = ui?.nameSeparator ?? ', ';
    try {
      final result = await _svc.execute<List>(model, 'read', [
        ids,
        ['rec_name']
      ], context: context);
      var suffix = [for (final r in result) '${(r as Map)['rec_name']}']
          .join(separator);
      if ((data['ids'] as List).length > ids.length) suffix += ',...';
      return suffix.isEmpty ? name : '$name ($suffix)';
    } catch (_) {
      return name;
    }
  }

  /// `ir.action.report` (spec 12.4, Python `Action.exec_report`):
  /// `report.<report_name>.execute(ids, data, ctx ∪ {direct_print})` →
  /// `[type, data, print_p, name]`; the file `<name>.<type>` is written to
  /// a temporary directory, then printed (`print_p` or `direct_print`) or
  /// opened (desktop: system application, mobile: share sheet); a `zip`
  /// gives its files one by one.
  Future<void> _executeReport(Map<String, dynamic> action,
      Map<String, dynamic> data, Map<String, dynamic> context, ActionUi? ui) async {
    final reportName = action['report_name'];
    if (reportName is! String) return;
    final ids = [
      for (final id in (data['ids'] as List? ?? const [])) id as int
    ];
    final directPrint = action['direct_print'] == true;
    await ui?.notify(ui.generatingReport());
    final result = await _svc.executeMethod<dynamic>(
        'report.$reportName.execute', [ids, data],
        context: {...context, 'direct_print': directPrint});
    if (result is! List || result.length < 2) return;
    final type = '${result[0] ?? 'pdf'}';
    final content = result[1];
    final bytes = content is TrytonBytes
        ? Uint8List.fromList(content.bytes)
        : Uint8List.fromList(utf8.encode('${content ?? ''}'));
    final printP = (result.length > 2 && result[2] == true) || directPrint;
    final name = result.length > 3 && result[3] != null
        ? '${result[3]}'
        : '${action['name'] ?? reportName}';
    await outputReport(name, type, bytes, print: printP);
  }

  /// Writes a report and prints or opens it; a `zip` gives its files one
  /// by one (each with its own extension).
  static Future<void> outputReport(String name, String type, Uint8List bytes,
      {bool print = false}) async {
    final files = FileActions.instance;
    final parts = type == 'zip'
        ? [
            for (final f in readZip(bytes))
              (
                name: f.name.split('/').last,
                type: f.name.contains('.') ? f.name.split('.').last : '',
                bytes: f.bytes
              )
          ]
        : [(name: '$name.$type', type: type, bytes: bytes)];
    for (final part in parts) {
      final path = await files.writeTemp(part.name, part.bytes);
      if (print) {
        await files.print(part.name, part.type, part.bytes, path);
      } else {
        await files.open(path);
      }
    }
  }

  /// Actions of [keyword] for the record of [data] (`get_keyword`): one is
  /// run directly, several are offered for selection, none → "No action
  /// defined." (with [warning]) (SAO `exec_keyword`, spec 12.6).
  Future<void> execKeyword(
    String keyword,
    Map<String, dynamic> data, {
    Map<String, dynamic> context = const {},
    bool warning = true,
    ActionUi? ui,
    TrytonScreen? screen,
  }) async {
    final result = await _svc.execute<dynamic>('ir.action.keyword',
        'get_keyword', [
      keyword,
      [data['model'], data['id']]
    ]);
    final actions = [
      for (final a in (result as List? ?? const []))
        if (a is Map) Map<String, dynamic>.from(a)
    ];
    if (actions.isEmpty) {
      if (warning) await ui?.message(ui.noActionDefined);
      return;
    }
    final action = actions.length == 1 ? actions.first : await ui?.choose(actions);
    if (action == null) return;
    await execAction(action,
        data: data, context: context, ui: ui, screen: screen);
  }
}

final Provider<ActionService> actionServiceProvider =
    Provider<ActionService>((ref) => ActionService(
      ref.read(modelServiceProvider),
      ref.read(tabsProvider.notifier),
      sessionContext: () => ref.read(sessionProvider).context,
      userId: () => ref.read(sessionProvider).userId,
      // reload context / reload menu: preferences again (menu and user
      // chip are rebuilt from them, spec 3.4).
      clientAction: (action) async {
        if (action == 'reload context' || action == 'reload menu') {
          await ref.read(sessionBootstrapProvider).reload();
        }
      },
    ));

/// [ActionUi] with the standard dialogs (spec 11.3).
class DialogActionUi implements ActionUi {
  final BuildContext context;
  const DialogActionUi(this.context);

  @override
  Future<void> message(String text) => showMessage(context, text);

  @override
  Future<void> notify(String text) async {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  /// „Select your action“ (Python `selection`, one action runs directly
  /// – the caller passes several).
  @override
  Future<Map<String, dynamic>?> choose(
      List<Map<String, dynamic>> actions) async {
    if (!context.mounted) return null;
    final labels = <String, Map<String, dynamic>>{};
    for (final a in actions) {
      var label = '${a['name'] ?? ''}'.split(' / ').last;
      // equal names stay distinct (the map is keyed by label)
      while (labels.containsKey(label)) {
        label = '$label ';
      }
      labels[label] = a;
    }
    final chosen = await showSelection(
        context, context.l10n.selectAction, labels,
        alwaysAsk: true);
    return chosen?.value;
  }

  @override
  Future<void> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Future<void> runWizard(TrytonWizard wizard,
      {required bool window, required String title}) async {
    if (!context.mounted) return;
    if (window) {
      // The tab runs the wizard and closes itself at the end.
      ProviderScope.containerOf(context, listen: false)
          .read(tabsProvider.notifier)
          .openTab(title: title, wizard: wizard);
      await wizard.finished;
    } else {
      await runWizardDialog(context, wizard);
    }
  }

  @override
  RpcErrorProcessor? get errorProcessor {
    final svc = ProviderScope.containerOf(context, listen: false)
        .read(modelServiceProvider);
    return ErrorHandler(
      presenter: DialogErrorPresenter(context),
      skipWarning: (name, always) => skipUserWarning(svc, name, always),
    );
  }

  @override
  String get noActionDefined => context.l10n.noActionDefined;

  @override
  String get nameSeparator => ', ';

  @override
  String generatingReport() => context.l10n.generatingReport;

  @override
  String reportGenerated(String name, String format) =>
      context.l10n.reportGenerated(name, format);

  @override
  String notSupported(String name, String type) => context.l10n
      .actionNotSupported(name, type == 'wizard' ? context.l10n.wizard : type);
}
