import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/rpc/rpc_activity.dart';

/// Wait indicator of long server calls (spec T1, Python `RPCProgress`:
/// the watch cursor after 3 s): when a foreground request runs longer
/// than [delay], a barrier over [child] blocks input and shows a spinner,
/// the elapsed time and „Stop waiting“ ([RpcActivityMonitor.abandon]: the
/// request ends with `RpcWaitAbandonedException`, nothing is sent again).
/// Placed above the router's navigator, so it covers tabs and dialogs.
class RpcWaitOverlay extends StatefulWidget {
  final RpcActivityMonitor monitor;
  final Widget child;
  final Duration delay;

  const RpcWaitOverlay({
    super.key,
    required this.monitor,
    required this.child,
    this.delay = const Duration(seconds: 3),
  });

  @override
  State<RpcWaitOverlay> createState() => _RpcWaitOverlayState();
}

class _RpcWaitOverlayState extends State<RpcWaitOverlay> {
  Timer? _show;
  Timer? _tick;
  bool _visible = false;

  /// Seconds since the wait began (counted by the timers, so fake time in
  /// tests advances it too).
  int _seconds = 0;

  final FocusNode _focus = FocusNode(debugLabel: 'rpc-wait');
  FocusNode? _previousFocus;

  @override
  void initState() {
    super.initState();
    widget.monitor.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(RpcWaitOverlay old) {
    super.didUpdateWidget(old);
    if (!identical(old.monitor, widget.monitor)) {
      old.monitor.removeListener(_changed);
      widget.monitor.addListener(_changed);
      _stop();
      _changed();
    }
  }

  @override
  void dispose() {
    widget.monitor.removeListener(_changed);
    _show?.cancel();
    _tick?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (widget.monitor.waiting) {
      if (_show != null || _visible) return;
      _seconds = 0;
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        _seconds++;
        if (_visible && mounted) setState(() {});
      });
      _show = Timer(widget.delay, () {
        _show = null;
        if (!mounted) return;
        _previousFocus = FocusManager.instance.primaryFocus;
        setState(() => _visible = true);
        // keys go to the barrier, not to the form underneath
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _focus.requestFocus());
      });
    } else {
      _stop();
    }
  }

  void _stop() {
    _show?.cancel();
    _show = null;
    _tick?.cancel();
    _tick = null;
    if (!_visible) return;
    final previous = _previousFocus;
    _previousFocus = null;
    if (mounted) setState(() => _visible = false);
    if (previous != null && previous.context != null) previous.requestFocus();
  }

  static String _elapsed(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_visible) ...[
          const Positioned.fill(
            child: ModalBarrier(
              key: ValueKey('rpc-wait-barrier'),
              dismissible: false,
              color: Color(0x33000000),
            ),
          ),
          Center(
            child: Focus(
              focusNode: _focus,
              // swallow the keys: no shortcut of the form runs meanwhile
              onKeyEvent: (_, _) => KeyEventResult.handled,
              child: _WaitCard(
                text: context.l10n.waitingForServer(_elapsed(_seconds)),
                stop: context.l10n.stopWaiting,
                onStop: widget.monitor.abandon,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _WaitCard extends StatelessWidget {
  final String text;
  final String stop;
  final VoidCallback onStop;

  const _WaitCard(
      {required this.text, required this.stop, required this.onStop});

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('rpc-wait'),
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 16),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('rpc-wait-stop'),
            onPressed: onStop,
            child: Text(stop),
          ),
        ]),
      ),
    );
  }
}
