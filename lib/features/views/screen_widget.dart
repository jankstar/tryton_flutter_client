import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart';
import '../../core/rpc/error_processing.dart';
import '../../core/screen/screen.dart';
import '../../shared/dialogs/tryton_dialogs.dart';
import '../../shared/errors/error_dialogs.dart';
import '../../shared/errors/error_handler.dart';
import '../../shared/widgets/concurrency_dialog.dart';
import '../actions/action_service.dart';
import '../model/concurrency.dart';
import '../model/field_support.dart';
import '../model/model_rpc.dart';
import '../model/model_service.dart';
import '../shell/tab_manager.dart';
import '../auth/session_bootstrap.dart';
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

  /// The screen is the root of a tab: the tab asks it whether its first
  /// view is active (an identical tab is activated then, spec 10.2).
  final bool tabRoot;

  /// A form opened for a new record closes itself after saving (e.g.
  /// "Add attachment") and pops the new id.
  final bool closeOnSaveNew;

  /// Called with the screen once it is created (dialogs that act on its
  /// records when closed, e.g. notes marked as read).
  final void Function(TrytonScreen screen)? onScreen;

  const ScreenWidget({
    super.key,
    required this.attributes,
    required this.title,
    this.onClose,
    this.closeOnSaveNew = false,
    this.tabRoot = false,
    this.onScreen,
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

  String? _tabId;
  TabsNotifier? _tabs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.tabRoot || _tabId != null) return;
    _tabId = TabScope.of(context);
    _tabs = ref.read(tabsProvider.notifier);
    if (_tabId != null) {
      _tabs!.setFirstViewCheck(_tabId!, () => (_screen?.viewIndex ?? 0) <= 0);
    }
  }

  @override
  void dispose() {
    if (_tabId != null) _tabs?.setFirstViewCheck(_tabId!, null);
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
          onCompare: (model, id) => _compare(svc, model, id),
          onMessage: () async {
            if (mounted) await showConcurrencyMessage(context);
          },
        ),
      );

  /// „Compare“ of the concurrency dialog (Python `ConcurrencyDialog`):
  /// the server version of the record in a new form tab „Compare:
  /// `rec_name`“.
  Future<void> _compare(ModelService svc, String model, int id) async {
    final context = _screen?.attributes.context ?? const <String, dynamic>{};
    var name = '$id';
    try {
      final rows = await svc.execute<dynamic>(model, 'read', [
        [id],
        ['rec_name'],
      ], context: context, processException: false);
      name = '${((rows as List).first as Map)['rec_name'] ?? id}';
    } catch (_) {
      // the id as title
    }
    if (!mounted) return;
    ref.read(tabsProvider.notifier).openTab(
          title: this.context.l10n.compareTabTitle(name),
          attributes: ScreenAttributes(
            model,
            mode: const ['form'],
            domain: [
              ['id', '=', id]
            ],
            context: context,
            resId: id,
          ),
        );
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
      ..onReloadContext =
          (() async => ref.read(sessionBootstrapProvider).reload())
      ..onReloadMenu =
          (() async => ref.read(sessionBootstrapProvider).reload());
    screen
      ..onViewAdded = ((v) => markUnsupportedFields(screen.model, v))
      ..onConfirm = _confirm
      ..onPreValidationFailed = _preValidationFailed
      ..invalidTexts = _invalidTexts
      ..onAction = (action, data, context) => ref
          .read(actionServiceProvider)
          .execute(action,
              data: data,
              context: context,
              keyword: true,
              ui: DialogActionUi(this.context),
              screen: screen);
    final cs = screen.contextScreen;
    if (cs != null) {
      cs
        ..screenSize = _screenSize
        ..onViewAdded = (v) => markUnsupportedFields(cs.model, v);
    }
    return screen;
  }

  /// `confirm` of a button: OK / Cancel (Sur, spec 11.3).
  Future<bool> _confirm(String text) => showSur(context, text);

  /// Warning „Pre-validation“ with the invalid fields.
  Future<void> _preValidationFailed(String message) =>
      showWarning(context, context.l10n.preValidation, message);

  InvalidMessages _invalidTexts() {
    final l = context.l10n;
    return InvalidMessages(
      required: l.invalidRequired('%s'),
      domain: l.invalidDomain('%s'),
      children: l.invalidChildren('%s'),
    );
  }

  /// DomainParser of the search bar with the locale of the preferences
  /// and translated common fields (spec 7.3, 8.4); without it the text is
  /// searched as `rec_name`.
  Future<void> _loadDomainParser(TrytonScreen screen) async {
    final l = context.l10n;
    screen
      ..parserContext =
          ref.read(modelServiceProvider).metadata?.parserContext ?? const {}
      ..commonFieldStrings = {
        'id': l.fieldId,
        'create_uid': l.createdBy,
        'create_date': l.createdAt,
        'write_uid': l.modifiedBy,
        'write_date': l.modifiedAt,
      };
    try {
      await screen.loadDomainParser();
    } catch (_) {
      // search without parser
    }
  }

  Future<void> _init() async {
    _screen?.removeListener(_onScreenChanged);
    _screen?.dispose();
    final screen = _screen = _newScreen();
    widget.onScreen?.call(screen);
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
      // Access rights of the model before the group decides readonly
      // (spec 4); afterwards of the relations of its fields.
      final loadAccess = screen.model.session.loadAccess;
      await loadAccess?.call([screen.model.name]);
      final resId = widget.attributes.resId;
      if (resId != null) {
        screen.load([resId]);
        screen.currentRecord = screen.group.get(resId);
      }
      // first day of the calendar weeks from the language (0 = Sunday)
      if (mounted) {
        final first = MaterialLocalizations.of(context).firstDayOfWeekIndex;
        ScreenView.firstWeekday = first == 0 ? DateTime.sunday : first;
      }
      await screen.switchView();
      await loadAccess?.call(relationModels(screen.model));
      final view = screen.currentView;
      if ((view?.viewType == 'tree' ||
              view?.viewType == 'list-form' ||
              view?.viewType == 'graph' ||
              view?.viewType == 'calendar') &&
          resId == null) {
        await _loadDomainParser(screen);
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
      // tree and list-form (cards) share the list shell
      _ => ListViewScreen(
          key: ObjectKey(view),
          screen: screen,
          title: widget.title,
          onClose: widget.onClose,
        ),
    };
  }
}

/// Relation models of the fields of [model] (for loading access rights).
Iterable<String> relationModels(TrytonModel model) => {
      for (final field in model.fields.values)
        if (field.description['relation'] case final String relation
            when relation.isNotEmpty)
          relation,
    };
