import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// A file chosen by the user: name and content.
typedef PickedFile = ({String name, Uint8List bytes});

/// File operations of the client (Python `common.file_open` /
/// `file_write`, SAO downloads): choosing, saving, opening, sharing and
/// printing. [instance] is replaced in tests.
class FileActions {
  static FileActions instance = FileActions();

  /// Desktop platforms open files with the system; mobile ones share them
  /// (preview and „open in …“ of the share sheet).
  bool get desktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// Chooses files ([multiple]; [images] only images); empty when
  /// cancelled.
  Future<List<PickedFile>> pick({bool multiple = false, bool images = false}) async {
    final type = images ? FileType.image : FileType.any;
    final files = multiple
        ? await FilePicker.pickFiles(type: type)
        : [?await FilePicker.pickFile(type: type)];
    return [
      for (final f in files) (name: f.name, bytes: await f.xFile.readAsBytes())
    ];
  }

  /// Asks where to save [bytes] as [name] and writes them; false when
  /// cancelled.
  Future<bool> save(String name, Uint8List bytes) async =>
      await FilePicker.saveFile(fileName: name, bytes: bytes) != null;

  /// Writes [bytes] to a new temporary directory as [name] (Python
  /// `file_write`); returns the path.
  Future<String> writeTemp(String name, List<int> bytes) async {
    final dir = await Directory.systemTemp.createTemp('tryton');
    final safe = name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    final file = File('${dir.path}${Platform.pathSeparator}${safe.isEmpty ? 'file' : safe}');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Opens the file at [path] (desktop: system application, mobile: share
  /// sheet with preview).
  Future<void> open(String path) async {
    if (desktop) {
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) {
        throw FileSystemException(result.message, path);
      }
      return;
    }
    await share(path);
  }

  /// Shares the file at [path].
  Future<void> share(String path) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
  }

  /// Prints [bytes] (PDF through the system print dialog); other types are
  /// opened.
  Future<void> print(String name, String type, Uint8List bytes, String path) async {
    if (type.toLowerCase() == 'pdf') {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
      return;
    }
    await open(path);
  }
}

/// Size like Python `common.humanize(size, 'B')`: `950B`, `1.2kB`,
/// `3MB` (decimal units, at most 2 decimals).
String humanSize(num size) {
  const units = ['', 'k', 'M', 'G', 'T', 'P'];
  var value = size.toDouble();
  var unit = 0;
  while (value.abs() > 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final text = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return '$text${units[unit]}B';
}
