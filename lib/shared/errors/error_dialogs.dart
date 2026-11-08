import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/locale_provider.dart';
import '../../features/model/model_service.dart';
import '../dialogs/tryton_dialogs.dart';
import '../widgets/concurrency_dialog.dart';
import 'error_handler.dart';

/// [ErrorHandler] with real dialogs on [context]; `res.user.warning.skip`
/// goes through the [ModelService] (session context appended).
ErrorHandler errorHandlerOf(BuildContext context, WidgetRef ref) =>
    ErrorHandler(
      presenter: DialogErrorPresenter(context),
      skipWarning: (name, always) =>
          skipUserWarning(ref.read(modelServiceProvider), name, always),
    );

/// Shows [error] with the standard dialogs where no [WidgetRef] is at
/// hand (a [HandledRpcError] was shown already).
Future<void> showErrorDialog(BuildContext context, Object error) {
  final container = ProviderScope.containerOf(context, listen: false);
  return ErrorHandler(
    presenter: DialogErrorPresenter(context),
    skipWarning: (name, always) =>
        skipUserWarning(container.read(modelServiceProvider), name, always),
  ).show(error);
}

/// `model.res.user.warning.skip(name, always, ctx)` (spec 2.6).
Future<void> skipUserWarning(ModelService svc, String name, bool always) =>
    svc.execute<dynamic>('res.user.warning', 'skip', [name, always]);

/// The standard dialogs (spec 11.3, `tryton_dialogs.dart`) for
/// [ErrorPresenter] (spec 2.6).
class DialogErrorPresenter implements ErrorPresenter {
  final BuildContext context;
  const DialogErrorPresenter(this.context);

  @override
  Future<void> userError(String message, String description) =>
      showWarning(context, message, description);

  @override
  Future<WarningChoice> userWarning(String message, String description) =>
      showUserWarning(context, message, description);

  @override
  Future<void> applicationError(String title, String details) =>
      showApplicationError(context, title, details);

  @override
  Future<void> httpError(int? code, String text) async {
    if (!context.mounted) return;
    final l = context.l10n;
    await showMessage(
        context, code == null ? l.networkError(text) : l.httpError(code, text),
        icon: Icons.cloud_off_outlined);
  }

  @override
  Future<void> concurrency() async {
    if (context.mounted) await showConcurrencyMessage(context);
  }
}
