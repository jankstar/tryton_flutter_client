import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart' show Record;
import '../../core/xml/view_definition.dart';
import '../../shared/errors/error_dialogs.dart';

// Code scanner (spec 11.11; Python gui/window/code_scanner.py, SAO
// window.js `CodeScanner`): a form with `scan_code` gets a Scan button;
// its dialog reads codes from the camera (mobile_scanner) or from the
// text entry (hand scanner, keyboard) and sends each to
// `on_scan_code`.

/// Preference key of the sound (SAO `sao_code_scanner_sound`).
const codeScannerSoundKey = 'tryton_code_scanner_sound';

/// Plays the sound of a scan ([success] or failure; Python `play_sound`
/// `success`/`danger`): the system sounds and a vibration. Replaceable in
/// tests.
void Function(bool success) codeScannerSound = (success) {
  if (success) {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
  } else {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
  }
};

/// The camera preview calling `onCode` with every detected code; null
/// where no camera is supported (Windows, Linux, tests). Replaceable in
/// tests.
Widget Function(void Function(String code) onCode)? codeScannerCamera =
    !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.macOS)
        ? (onCode) => _Camera(onCode: onCode)
        : null;

/// The Scan button of a form with `scan_code` (Python `Form.__init__`,
/// SAO `scan_code_btn`): states from `scan_code_states`; each code goes
/// to [Record.onScanCode] with `scan_code_depends`; `loop` keeps the
/// dialog open while codes change the record, `submit` calls [onSubmit]
/// after each code (form saved / wizard default button).
class ScanCodeButton extends StatelessWidget {
  final FormRoot root;
  final Record record;
  final VoidCallback? onSubmit;

  /// Disabled (record readonly or being processed).
  final bool readOnly;

  const ScanCodeButton({
    super.key,
    required this.root,
    required this.record,
    this.onSubmit,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final mode = root.scanCode;
    if (mode == null || mode.isEmpty) return const SizedBox.shrink();
    final states = record.exprEval(root.scanCodeStates);
    final invisible = states is Map && states['invisible'] == true;
    if (invisible) return const SizedBox.shrink();
    final disabled =
        readOnly || (states is Map && states['readonly'] == true);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: FilledButton.icon(
        key: const ValueKey('scan-code'),
        icon: const Icon(Icons.qr_code_scanner),
        label: Text(context.l10n.scanCode),
        onPressed: disabled
            ? null
            : () => showCodeScanner(
                  context,
                  loop: mode == 'loop',
                  onCode: (code) async {
                    final modified =
                        await record.onScanCode(code, root.scanCodeDepends);
                    if (mode == 'submit') onSubmit?.call();
                    return modified;
                  },
                ),
      ),
    );
  }
}

/// The scanner dialog (Python `CodeScanner`, SAO `Sao.Window.CodeScanner`):
/// [onCode] gets each code and answers whether it changed something;
/// success plays the success sound and closes unless [loop] and modified;
/// an error plays the failure sound, closes and shows the error.
Future<void> showCodeScanner(
  BuildContext context, {
  required Future<bool> Function(String code) onCode,
  bool loop = false,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => CodeScannerDialog(onCode: onCode, loop: loop),
    );

class CodeScannerDialog extends StatefulWidget {
  final Future<bool> Function(String code) onCode;
  final bool loop;

  const CodeScannerDialog({super.key, required this.onCode, this.loop = false});

  @override
  State<CodeScannerDialog> createState() => _CodeScannerDialogState();
}

class _CodeScannerDialogState extends State<CodeScannerDialog> {
  final _entry = TextEditingController();
  final _focus = FocusNode();
  bool _sound = true;
  bool _submitting = false;

  /// Camera shown (mobile at once, macOS on demand: no permission prompt
  /// for hand scanners).
  late bool _camera = codeScannerCamera != null &&
      defaultTargetPlatform != TargetPlatform.macOS;

  /// Last camera code and its time (the camera reports a code repeatedly).
  String? _lastCode;
  DateTime? _lastAt;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final sound = prefs.getBool(codeScannerSoundKey);
      if (sound != null && mounted) setState(() => _sound = sound);
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _entry.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _toggleSound() async {
    setState(() => _sound = !_sound);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(codeScannerSoundKey, _sound);
    } catch (_) {}
  }

  void _play(bool success) {
    if (_sound) codeScannerSound(success);
  }

  void _fromCamera(String code) {
    final now = DateTime.now();
    if (code == _lastCode &&
        _lastAt != null &&
        now.difference(_lastAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastCode = code;
    _lastAt = now;
    _submit(code);
  }

  Future<void> _submit(String code) async {
    if (_submitting || code.isEmpty) return;
    _entry.clear();
    setState(() => _submitting = true);
    final navigator = Navigator.of(context);
    try {
      final modified = await widget.onCode(code);
      _play(true);
      if (!widget.loop || !modified) {
        if (mounted) navigator.pop();
        return;
      }
    } catch (e) {
      _play(false);
      final outer = navigator.context;
      if (mounted) navigator.pop();
      if (outer.mounted) await showErrorDialog(outer, e);
      return;
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final camera = codeScannerCamera;
    return AlertDialog(
      title: Row(children: [
        Expanded(child: Text(l.codeScanner)),
        if (camera != null && defaultTargetPlatform == TargetPlatform.macOS)
          IconButton(
            key: const ValueKey('scan-code-camera'),
            tooltip: l.scanCodeCamera,
            isSelected: _camera,
            icon: const Icon(Icons.videocam_outlined),
            selectedIcon: const Icon(Icons.videocam),
            onPressed: () => setState(() => _camera = !_camera),
          ),
        IconButton(
          key: const ValueKey('scan-code-sound'),
          tooltip: l.scanCodeSound,
          isSelected: _sound,
          icon: const Icon(Icons.volume_off_outlined),
          selectedIcon: const Icon(Icons.volume_up_outlined),
          onPressed: _toggleSound,
        ),
      ]),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (camera != null && _camera)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(height: 240, child: camera(_fromCamera)),
            )
          else if (camera == null)
            Text(l.scanCodeNoCamera,
                style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('scan-code-entry'),
            controller: _entry,
            focusNode: _focus,
            autofocus: true,
            enabled: !_submitting,
            decoration: InputDecoration(
              hintText: l.scanCodeHint,
              prefixIcon: const Icon(Icons.qr_code),
            ),
            onSubmitted: (v) => _submit(v.trim()),
          ),
          if (_submitting) const LinearProgressIndicator(),
        ]),
      ),
      actions: [
        TextButton(
          key: const ValueKey('scan-code-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.close),
        ),
        FilledButton(
          key: const ValueKey('scan-code-ok'),
          onPressed: _submitting ? null : () => _submit(_entry.text.trim()),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

/// Camera preview of mobile_scanner (bar codes and QR codes).
class _Camera extends StatefulWidget {
  final void Function(String code) onCode;
  const _Camera({required this.onCode});

  @override
  State<_Camera> createState() => _CameraState();
}

class _CameraState extends State<_Camera> {
  final _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          for (final code in capture.barcodes) {
            final value = code.rawValue;
            if (value != null && value.isNotEmpty) {
              widget.onCode(value);
              break;
            }
          }
        },
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(context.l10n.scanCodeNoCamera,
                textAlign: TextAlign.center),
          ),
        ),
      );
}
