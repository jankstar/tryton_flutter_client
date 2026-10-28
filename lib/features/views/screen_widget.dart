import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart';
import '../../core/rpc/error_processing.dart';
import '../../core/screen/screen.dart';
import '../../shared/errors/error_dialogs.dart';
import '../../shared/errors/error_handler.dart';
import '../../shared/widgets/concurrency_dialog.dart';
import '../actions/action_service.dart';
import '../auth/auth_provider.dart';
import '../model/concurrency.dart';
import '../model/field_support.dart';
import '../model/model_rpc.dart';
import '../model/model_service.dart';
import '../shell/tab_manager.dart';
import '../tabs/model_browser_screen.dart' show menuProvider;
import 'dynamic_form_screen.dart';
import 'list_view_screen.dart';

/// A [TrytonScreen] with its views (spec 8): the list and the form are two
/// views of the same screen and share its group and current record. The
/// widget owns the screen and shows its current view.
///
/// Start (like the Python client's `Form` tab): with `res_id` the record
/// is loaded and the first view shown; a list searches; a form without
/// record starts with a new record.
class ScreenWidget extends ConsumerStatefulWidget {
  final ScreenAttributes attributes;
  final String title;

  /// "Close" of the screen: closes the tab or pops the route.
  final Future<void> Function()? onClose;

  /// A form opened for a new record closes itself after saving (e.g.
  /// "Add attachment") and pops the new id.
  final bool closeOnSaveNew;

  const ScreenWidget({
    super.key,
    required this.attributes,
    required this.title,
    this.onClose,
    this.closeOnSaveNew = false,
  });

  @override
  ConsumerState<ScreenWidget> createState() => _ScreenWidgetState();
}

class _ScreenWidgetState extends ConsumerState<ScreenWidget> {
  TrytonScreen? _screen;
  ScreenView? _view;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _screen?.removeListener(_onScreenChanged);
    _screen?.dispose();
    super.dispose();
  }

  /// Rebuilds when the current view changes (the views listen to the
  /// screen themselves).
  void _onScreenChanged() {
    final view = _screen?.currentView;
    if (mounted && !identical(view, _view)) setState(() => _view = view);
  }

  /// Data-layer session of this screen: errors go to this screen's
  /// dialogs, conflicts to the A1 dialog.
  ModelSession _modelSession(ModelService svc) => modelSessionFor(
        svc,
        processor: errorHandlerOf(context, ref),
        concurrencyRunner: concurrencyRunner(
          ask: () async => mounted
              ? showConcurrencyDialog(context)
              : ConcurrencyChoice.cancel,
          onCompare: (model, id) async =>
              ref.read(tabsProvider.notifier).openTab(
                    title: context.l10n.compareTabTitle('$id'),
                    model: model,
                    initialDomain: [
                      ['id', '=', id]
                    ],
                    resId: id,
                  ),
          onMessage: () async {
            if (mounted) await showConcurrencyMessage(context);
          },
        ),
      );

  /// Fields without an own widget (E13) are never written: as readonly
  /// they are left out of create/write (`Record.get`).
  static void _markUnsupported(TrytonModel model, ScreenView view) {
    final root = view.formRoot;
    if (root == null) return;
    for (final name in unsupportedFieldNames(view.definition.fields, root)) {
      model.fields[name]?.description['readonly'] = true;
    }
  }

  /// Logical size of the window (`screen_size`), without depending on an
  /// inherited widget (the first view is loaded from initState).
  static List<int> _screenSize() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return const [1024, 768];
    final view = views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    return [size.width.round(), size.height.round()];
  }

  TrytonScreen _newScreen() {
    final svc = ref.read(modelServiceProvider);
    final screen = TrytonScreen(widget.attributes, session: _modelSession(svc))
      ..screenSize = _screenSize
      ..onClose = (() async => widget.onClose?.call())
      ..onReloadContext = (() => ref.read(sessionProvider).reloadContext())
      ..onReloadMenu = (() async => ref.invalidate(menuProvider));
    screen
      ..onViewAdded = ((v) => _markUnsupported(screen.model, v))
      ..onConfirm = _confirm
      ..onPreValidationFailed = _preValidationFailed
      ..invalidTexts = _invalidTexts
      ..onAction = (action, data, context) => ref
          .read(actionServiceProvider)
          .execute(action,
              data: data,
              context: context,
              keyword: true,
              ui: DialogActionUi(this.context));
    final cs = screen.contextScreen;
    if (cs != null) {
      cs
        ..screenSize = _screenSize
        ..onViewAdded = (v) => _markUnsupported(cs.model, v);
    }
    return screen;
  }

  /// `confirm` of a button: OK / Cancel.
  Future<bool> _confirm(String text) async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.ok),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Warning „Pre-validation“ with the invalid fields.
  Future<void> _preValidationFailed(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: Text(ctx.l10n.preValidation),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.ok),
          ),
        ],
      ),
    );
  }

  InvalidMessages _invalidTexts() {
    final l = context.l10n;
    return InvalidMessages(
      required: l.invalidRequired('%s'),
      domain: l.invalidDomain('%s'),
      children: l.invalidChildren('%s'),
    );
  }

  Future<void> _init() async {
    _screen?.removeListener(_onScreenChanged);
    _screen?.dispose();
    final screen = _screen = _newScreen();
    setState(() {
      _view = null;
      _loading = true;
      _error = null;
    });
    try {
      final cs = screen.contextScreen;
      if (cs != null) {
        await cs.switchView();
        await cs.newRecord();
      }
      final resId = widget.attributes.resId;
      if (resId != null) {
        screen.load([resId]);
        screen.currentRecord = screen.group.get(resId);
      }
      await screen.switchView();
      final view = screen.currentView;
      if (view?.viewType == 'tree' && resId == null) {
        await screen.searchFilter();
      } else if (view?.viewType == 'form' && screen.currentRecord == null) {
        await screen.newRecord();
      }
      screen.addListener(_onScreenChanged);
      if (mounted) setState(() => _view = screen.currentView);
    } on HandledRpcError catch (e) {
      if (mounted) setState(() => _error = ErrorHandler.describe(e));
    } catch (e) {
      if (mounted) {
        errorHandlerOf(context, ref).show(e);
        setState(() => _error = ErrorHandler.describe(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = _screen;
    final view = _view;
    if (screen == null || view == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
          scrolledUnderElevation: 0,
          title: Text(widget.title),
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: context.l10n.close,
              onPressed: () => widget.onClose?.call(),
            ),
          ],
        ),
        body: _loading || _error == null
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                      onPressed: _init, child: Text(context.l10n.retry)),
                ]),
              ),
      );
    }
    return switch (view.viewType) {
      'form' => DynamicFormScreen(
          key: ObjectKey(view),
          screen: screen,
          title: widget.title,
          onClose: widget.onClose,
          closeOnSaveNew: widget.closeOnSaveNew,
        ),
      _ => ListViewScreen(
          key: ObjectKey(view),
          screen: screen,
          title: widget.title,
          onClose: widget.onClose,
        ),
    };
  }
}
