import 'dart:async';

/// Bridges the RPC layer (which has no BuildContext) with the UI layer.
///
/// When the server returns 401 (session expired), RpcClient calls
/// [requestReAuth]. The app root widget listens to [reAuthRequests]
/// and shows a compact re-login dialog. Once the user re-authenticates,
/// the Completer is resolved and the RPC client retries the request.
class ReAuthService {
  static final _controller =
      StreamController<Completer<void>>.broadcast();

  /// UI listens to this stream and shows the re-login dialog.
  static Stream<Completer<void>> get reAuthRequests => _controller.stream;

  static Completer<void>? _pending;

  /// Called by RpcClient on 401.
  /// Returns a Future that resolves when re-auth completes.
  static Future<void> requestReAuth() {
    // If already waiting for re-auth, reuse the same Completer
    if (_pending != null && !_pending!.isCompleted) {
      return _pending!.future;
    }
    _pending = Completer<void>();
    _controller.add(_pending!);
    return _pending!.future;
  }

  /// Called by the re-login dialog after successful login.
  static void complete() {
    if (_pending != null && !_pending!.isCompleted) {
      _pending!.complete();
    }
    _pending = null;
  }

  /// Called by the re-login dialog on failure / cancel.
  static void fail() {
    if (_pending != null && !_pending!.isCompleted) {
      _pending!.completeError('Re-authentication failed');
    }
    _pending = null;
  }
}
