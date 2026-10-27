import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/locale_provider.dart';
import '../../features/model/model_service.dart';
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

/// `model.res.user.warning.skip(name, always, ctx)` (spec 2.6).
Future<void> skipUserWarning(ModelService svc, String name, bool always) =>
    svc.execute<dynamic>('res.user.warning', 'skip', [name, always]);

/// Material dialogs for [ErrorPresenter] (spec 2.6).
class DialogErrorPresenter implements ErrorPresenter {
  final BuildContext context;
  const DialogErrorPresenter(this.context);

  Future<T?> _dialog<T>(WidgetBuilder builder) async {
    if (!context.mounted) return null;
    return showDialog<T>(context: context, builder: builder);
  }

  @override
  Future<void> userError(String message, String description) =>
      _dialog<void>((ctx) => AlertDialog(
            icon: const Icon(Icons.warning_amber_rounded),
            title: Text(message),
            content: description.isEmpty
                ? null
                : SingleChildScrollView(child: Text(description)),
            actions: [
              FilledButton(
                autofocus: true,
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.l10n.ok),
              ),
            ],
          ));

  @override
  Future<WarningChoice> userWarning(String message, String description) async {
    final choice = await _dialog<WarningChoice>((ctx) => AlertDialog(
          icon: const Icon(Icons.info_outline),
          title: Text(message),
          content: description.isEmpty
              ? null
              : SingleChildScrollView(child: Text(description)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, WarningChoice.always),
              child: Text(ctx.l10n.alwaysIgnore),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, WarningChoice.cancel),
              child: Text(ctx.l10n.cancel),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(ctx, WarningChoice.ok),
              child: Text(ctx.l10n.ok),
            ),
          ],
        ));
    return choice ?? WarningChoice.cancel;
  }

  @override
  Future<void> applicationError(String title, String details) =>
      _dialog<void>((ctx) => AlertDialog(
            icon: Icon(Icons.error_outline,
                color: Theme.of(ctx).colorScheme.error),
            title: Text(ctx.l10n.applicationError),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(title,
                        style: Theme.of(ctx).textTheme.titleSmall),
                    if (details.isNotEmpty)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(ctx.l10n.details),
                        children: [
                          SelectableText(details,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.l10n.close),
              ),
            ],
          ));

  @override
  Future<void> httpError(int? code, String text) =>
      _dialog<void>((ctx) => AlertDialog(
            icon: const Icon(Icons.cloud_off_outlined),
            content: Text(code == null
                ? ctx.l10n.networkError(text)
                : ctx.l10n.httpError(code, text)),
            actions: [
              FilledButton(
                autofocus: true,
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.l10n.ok),
              ),
            ],
          ));

  @override
  Future<void> concurrency() async {
    if (context.mounted) await showConcurrencyMessage(context);
  }
}
