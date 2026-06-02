import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../model/model_service.dart';
import '../model/toolbar_data.dart';
import '../../core/l10n/locale_provider.dart';

/// Executes Tryton actions (act_window, report, wizard).
class ActionExecutor {
  final ModelService _svc;
  ActionExecutor(this._svc);

  Future<void> execute(
    BuildContext context,
    TrytonActionItem action,
    String sourceModel,
    List<int> selectedIds,
  ) async {
    switch (action.type) {
      case 'ir.action.act_window':
        _openActWindow(context, action, sourceModel, selectedIds);
      case 'ir.action.report':
        await _executeReport(context, action, sourceModel, selectedIds);
      case 'ir.action.wizard':
        _showUnsupported(context, action.name, context.l10n.wizard);
      default:
        _showUnsupported(context, action.name, action.type);
    }
  }

  void _openActWindow(
    BuildContext context,
    TrytonActionItem action,
    String sourceModel,
    List<int> selectedIds,
  ) {
    final model = action.resModel;
    if (model == null || model.isEmpty) return;
    final title = Uri.encodeComponent(action.name);
    context.push('/models/$model?title=$title');
  }

  Future<void> _executeReport(
    BuildContext context,
    TrytonActionItem action,
    String sourceModel,
    List<int> selectedIds,
  ) async {
    if (action.reportName == null) return;
    try {
      _showSnack(context, context.l10n.generatingReport);
      final result = await _svc.executeReport(
        action.reportName!,
        selectedIds,
        sourceModel,
      );
      if (!context.mounted) return;
      // result = [format, base64data, direct_print, name]
      final format = result[0] as String? ?? 'pdf';
      final name = result.length > 3 ? result[3]?.toString() ?? action.name : action.name;
      _showSnack(context, context.l10n.reportGenerated(name, format));
      // TODO: Download or open the file
    } catch (e) {
      if (context.mounted) _showError(context, e.toString());
    }
  }

  void _showUnsupported(BuildContext context, String name, String type) {
    _showSnack(context, context.l10n.actionNotSupported(name, type));
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showError(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}

final actionExecutorProvider = Provider<ActionExecutor>((ref) {
  return ActionExecutor(ref.read(modelServiceProvider));
});
