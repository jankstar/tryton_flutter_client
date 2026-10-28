import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/screen/screen.dart';
import '../auth/auth_provider.dart';
import '../model/model_service.dart';
import '../shell/tab_manager.dart';

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

  /// Localised texts.
  String get noActionDefined;
  String get nameSeparator;
  String generatingReport();
  String reportGenerated(String name, String format);
  String notSupported(String name, String type);
}

/// Executes Tryton actions (spec 12.1–12.6, SAO `Sao.Action`, Python
/// client `Action`): act_window opens a tab, url the browser, report runs
/// the report (file output with G2), wizard is a placeholder (G3).
class ActionService {
  final ModelService _svc;
  final TabsNotifier _tabs;
  /// Session context and user of the PYSON environment.
  final Map<String, dynamic> Function() sessionContext;
  final int? Function() userId;

  ActionService(this._svc, this._tabs,
      {required this.sessionContext, required this.userId});

  /// Default keywords of [execute] with `keyword` (name suffix).
  static const _keywords = {
    'ir.action.report': 'form_report',
    'ir.action.wizard': 'form_action',
    'ir.action.act_window': 'form_relate',
  };

  /// Runs [action] (values or id → `ir.action.get_action_value`) for
  /// [data] (`model`, `id`, `ids` of the calling records) with [context]
  /// (SAO `Action.execute`). With [keyword] the action's keyword defaults
  /// by type, which adds the record names to the tab name.
  Future<void> execute(
    dynamic action, {
    Map<String, dynamic> data = const {},
    Map<String, dynamic> context = const {},
    bool keyword = false,
    ActionUi? ui,
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
    await execAction(values, data: data, context: context, ui: ui);
  }

  /// Runs the action [values] by type (SAO `exec_action`); the context
  /// loses `active_id(s)`/`active_model`.
  Future<void> execAction(
    Map<String, dynamic> action, {
    Map<String, dynamic> data = const {},
    Map<String, dynamic> context = const {},
    ActionUi? ui,
  }) async {
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
        final title = action['keyword'] != null
            ? await _nameWithSuffix(name, data, attributes.context, ui)
            : name;
        _tabs.openTab(title: title, attributes: attributes);
      case 'ir.action.url':
        final url = action['url'];
        if (url is String && url.isNotEmpty) await ui?.openUrl(url);
      case 'ir.action.report':
        await _executeReport(action, data, ctx, ui);
      case 'ir.action.wizard':
        // Wizards follow with G3.
        await ui?.message(ui.notSupported(name, 'wizard'));
      default:
        await ui?.message(ui.notSupported(name, '${action['type']}'));
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
    await execAction(action, data: data, context: context, ui: ui);
  }
}

final actionServiceProvider = Provider<ActionService>((ref) => ActionService(
      ref.read(modelServiceProvider),
      ref.read(tabsProvider.notifier),
      sessionContext: () => ref.read(sessionProvider).context,
      userId: () => ref.read(sessionProvider).userId,
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
