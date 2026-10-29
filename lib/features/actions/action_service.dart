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
import '../model/model_service.dart';
import '../shell/tab_manager.dart';
import '../tabs/model_browser_screen.dart' show menuProvider;
import '../views/wizard_widget.dart';

/// Interaction of [ActionService] with the user (messages, selection,
/// external URLs); [DialogActionUi] for the app, fakes in tests.
abstract interface class ActionUi {
  /// Short message (e.g. "No action defined.", report generated).
  Future<void> message(String text);

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
        if (attributes.model.isEmpty || attributes.model == 'null') return;
        // Without action name: the translated model name (MODELNAME).
        var baseName = name;
        if (baseName.isEmpty) {
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

  Future<void> _executeReport(Map<String, dynamic> action,
      Map<String, dynamic> data, Map<String, dynamic> context, ActionUi? ui) async {
    final reportName = action['report_name'];
    if (reportName is! String) return;
    final ids = [
      for (final id in (data['ids'] as List? ?? const [])) id as int
    ];
    await ui?.message(ui.generatingReport());
    final result = await _svc.executeReport(
        reportName, ids, '${data['model'] ?? ''}');
    // result = [format, data, direct_print, name]; file output with G2
    final format = result[0] as String? ?? 'pdf';
    final name = result.length > 3
        ? result[3]?.toString() ?? '${action['name']}'
        : '${action['name']}';
    await ui?.message(ui.reportGenerated(name, format));
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

final actionServiceProvider = Provider<ActionService>((ref) => ActionService(
      ref.read(modelServiceProvider),
      ref.read(tabsProvider.notifier),
      sessionContext: () => ref.read(sessionProvider).context,
      userId: () => ref.read(sessionProvider).userId,
      clientAction: (action) async {
        if (action == 'reload context' || action == 'reload menu') {
          await ref.read(sessionProvider).reloadContext();
        }
        if (action == 'reload menu') ref.invalidate(menuProvider);
      },
    ));

/// [ActionUi] with snack bars and a selection dialog.
class DialogActionUi implements ActionUi {
  final BuildContext context;
  const DialogActionUi(this.context);

  @override
  Future<void> message(String text) async {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Future<Map<String, dynamic>?> choose(
      List<Map<String, dynamic>> actions) async {
    if (!context.mounted) return null;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(ctx.l10n.selectAction),
        children: [
          for (final a in actions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, a),
              child: Text('${a['name'] ?? ''}'.split(' / ').last),
            ),
        ],
      ),
    );
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
