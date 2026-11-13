import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The ARB files after taking translations of the Tryton clients
/// (tool/l10n_from_tryton.py): every translation uses only the
/// placeholders of the English text, none is empty, no GTK mnemonic
/// (`_Save`) or shortcut (`<Del>`) is left over.
void main() {
  Map<String, dynamic> load(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final english = load('lib/l10n/app_en.arb');
  Set<String> placeholders(String text) =>
      {for (final m in RegExp(r'\{(\w+)\}').allMatches(text)) m.group(1)!};
  final files = [
    for (final f in Directory('lib/l10n').listSync())
      if (f.path.endsWith('.arb') && !f.path.endsWith('app_en.arb')) f.path
  ]..sort();

  for (final path in files) {
    test(path.split('/').last, () {
      final arb = load(path);
      for (final MapEntry(:key, :value) in arb.entries) {
        if (key.startsWith('@') || value is! String) continue;
        final source = english[key];
        expect(source, isA<String>(), reason: '$key: not in app_en.arb');
        expect(value.trim(), isNotEmpty, reason: key);
        expect(placeholders(value).difference(placeholders(source as String)),
            isEmpty,
            reason: '$key: unknown placeholder in "$value"');
        expect(RegExp(r'<(Del|Ins|Entf|Supr|F\d+)>').hasMatch(value), isFalse,
            reason: '$key: shortcut in "$value"');
        expect(RegExp(r'(^|\s)_\p{L}', unicode: true).hasMatch(value), isFalse,
            reason: '$key: mnemonic in "$value"');
      }
    });
  }
}
