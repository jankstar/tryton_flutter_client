import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// One running HTTP request of the [RpcClient] (Python `RPCProgress`).
class RpcActivity {
  final String method;

  /// Background calls (counters, autocomplete, icons, …) never show the
  /// wait indicator.
  final bool background;

  final CancelToken _cancel;
  bool _abandoned = false;

  RpcActivity._(this.method, this.background, this._cancel);

  /// The user stopped waiting ([RpcActivityMonitor.abandon]); the server
  /// may still be processing the request.
  bool get abandoned => _abandoned;
}

/// The requests the [RpcClient] is waiting for: the wait indicator shows
/// itself when a foreground request runs longer than a few seconds and
/// can stop waiting for them ([abandon]).
class RpcActivityMonitor extends ChangeNotifier {
  final List<RpcActivity> _running = [];

  List<RpcActivity> get running => List.unmodifiable(_running);

  /// Whether a request the user waits for is running.
  bool get waiting => _running.any((a) => !a.background && !a._abandoned);

  RpcActivity start(String method, CancelToken cancel,
      {bool background = false}) {
    final activity = RpcActivity._(method, background, cancel);
    _running.add(activity);
    notifyListeners();
    return activity;
  }

  void end(RpcActivity activity) {
    if (_running.remove(activity)) notifyListeners();
  }

  /// Stops waiting for every foreground request: they end with
  /// `RpcWaitAbandonedException` (the server is not told and keeps
  /// working; nothing is sent again).
  void abandon() {
    for (final activity in [..._running]) {
      if (activity.background || activity._abandoned) continue;
      activity._abandoned = true;
      activity._cancel.cancel('stopped waiting');
    }
    notifyListeners();
  }
}
