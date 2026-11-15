import 'dart:async';

import 'package:flutter/widgets.dart';

/// Context of the built [AppShell] (menu and tabs; below the router's
/// Navigator and inside the ProviderScope): set after its first frame,
/// cleared when it is disposed. The start actions of the preferences run
/// on it (spec 3.2 step 4) – dialogs and wizard tabs need the shell.
final ValueNotifier<BuildContext?> shellContext =
    ValueNotifier<BuildContext?>(null);

BuildContext? get _mountedShell {
  final context = shellContext.value;
  return context != null && context.mounted ? context : null;
}

/// The context of the shell once it is built; null when it does not
/// appear within [timeout] (e.g. logout during the start).
Future<BuildContext?> waitForShell(
    {Duration timeout = const Duration(minutes: 1)}) async {
  final ready = _mountedShell;
  if (ready != null) return ready;
  final completer = Completer<BuildContext?>();
  void listener() {
    final context = _mountedShell;
    if (context != null && !completer.isCompleted) completer.complete(context);
  }

  shellContext.addListener(listener);
  try {
    return await completer.future.timeout(timeout, onTimeout: () => null);
  } finally {
    shellContext.removeListener(listener);
  }
}
