import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart' hide TextField;
import '../../core/serialization/tryton_serializer.dart';
import '../../shared/utils/file_actions.dart';
import 'record_field_widgets.dart';

// Binary widgets on the record (spec 9.2.4, Python form_gtk/binary.py,
// image.py, document.py): the value is the size (int) until the content
// is read with `BinaryField.getData` (separate `read`).

/// Largest image shown as preview (Python `image.max_size`).
const imageMaxSize = 1000000;

/// Content of a binary value (bytes) or null.
Uint8List? binaryBytes(dynamic value) => switch (value) {
      TrytonBytes() => Uint8List.fromList(value.bytes),
      Uint8List() => value,
      List<int>() => Uint8List.fromList(value),
      String() => Uint8List.fromList(value.codeUnits),
      _ => null,
    };

/// Shared actions of the binary widgets (Python `BinaryMixin`).
mixin _BinaryActions<T extends StatefulWidget> on State<T> {
  RecordFieldArgs get args;

  String? get _filenameName {
    final f = args.node.filename ?? args.field.description['filename'];
    return f is String && f.isNotEmpty ? f : null;
  }

  Field? get _filenameField =>
      _filenameName == null ? null : args.record.model.fields[_filenameName];

  String? get filename {
    final v = _filenameField?.get(args.record);
    return v is String && v.isNotEmpty ? v : null;
  }

  /// Size of the value (`get_size`).
  int get size {
    final field = args.field;
    final s = field is BinaryField ? field.getSize(args.record) : null;
    return s is int ? s : 0;
  }

  /// The content, read separately when only the size is loaded.
  Future<Uint8List?> data() async {
    final field = args.field;
    final value = field is BinaryField
        ? await field.getData(args.record)
        : field.get(args.record);
    return binaryBytes(value);
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (mounted) setState(() {});
  }

  /// „Select…“: the file becomes the value, its name the filename field.
  Future<void> select({bool images = false}) => run(() async {
        final files = await FileActions.instance.pick(images: images);
        if (files.isEmpty) return;
        final file = files.first;
        final filenameField = _filenameField;
        if (filenameField != null) {
          await filenameField.setClient(args.record, file.name);
        }
        args.onValue(TrytonBytes(file.bytes));
      });

  /// „Save As…“.
  Future<void> saveAs() => run(() async {
        final bytes = await data();
        if (bytes == null) return;
        await FileActions.instance.save(filename ?? args.fd.name, bytes);
      });

  /// „Open…“ (with a filename: written to a temporary file and opened).
  Future<void> openFile() => run(() async {
        final bytes = await data();
        if (bytes == null) return;
        final path = await FileActions.instance
            .writeTemp(filename ?? args.fd.name, bytes);
        await FileActions.instance.open(path);
      });

  /// „Clear“: value and filename.
  Future<void> clear() => run(() async {
        final filenameField = _filenameField;
        if (filenameField != null) {
          await filenameField.setClient(args.record, null);
        }
        args.onValue(null);
      });

  Widget toolButton(IconData icon, String iconName, String tip,
          VoidCallback? onPressed,
          {Key? key}) =>
      IconButton(
        key: key,
        icon: TrytonIcon(iconName: iconName, size: 18, fallback: icon),
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
      );

  /// Save As / Select / Clear like the Python toolbar: with a value Save
  /// and Clear, without one Select.
  List<Widget> toolbar(BuildContext context, {bool images = false}) {
    final l = context.l10n;
    final hasValue = size > 0;
    final name = args.node.name;
    return [
      if (hasValue)
        toolButton(Icons.download, 'tryton-download', l.saveAs, saveAs,
            key: ValueKey('binary-save-$name')),
      if (!hasValue && !args.readOnly)
        toolButton(Icons.search, 'tryton-search', l.selectFile,
            () => select(images: images),
            key: ValueKey('binary-select-$name')),
      if (hasValue && !args.readOnly)
        toolButton(Icons.clear, 'tryton-clear', l.clear, clear,
            key: ValueKey('binary-clear-$name')),
    ];
  }
}

/// `binary`: size, optionally the filename (`filename_visible`, editable,
/// with an Open icon), Save As / Select / Clear.
class RecordBinaryField extends StatefulWidget {
  final RecordFieldArgs args;
  const RecordBinaryField({super.key, required this.args});

  @override
  State<RecordBinaryField> createState() => _RecordBinaryFieldState();
}

class _RecordBinaryFieldState extends State<RecordBinaryField>
    with _BinaryActions {
  @override
  RecordFieldArgs get args => widget.args;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final showName = _filenameName != null && args.node.filenameVisible;
    return InputDecorator(
      decoration: args.decoration(context),
      child: Row(children: [
        if (showName)
          Expanded(
            child: RecordTextInput(
              key: ValueKey('binary-filename-${args.node.name}'),
              format: () => filename ?? '',
              parse: (t) => (ok: true, value: t.isEmpty ? null : t),
              readOnly: args.readOnly,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                prefixIcon: size > 0
                    ? IconButton(
                        icon: const TrytonIcon(
                            iconName: 'tryton-open', size: 16, fallback: Icons.open_in_new),
                        tooltip: l.openFile,
                        onPressed: openFile,
                      )
                    : null,
              ),
              onText: (v) {
                final f = _filenameField;
                if (f != null) f.setClient(args.record, v);
              },
            ),
          ),
        Expanded(
          flex: showName ? 0 : 1,
          child: Text(humanSize(size),
              key: ValueKey('binary-size-${args.node.name}'),
              textAlign: TextAlign.end),
        ),
        ...toolbar(context),
      ]),
    );
  }
}

/// `image`: preview (`width`/`height`, default 300×100; `border`
/// rounded/circle; at most [imageMaxSize]), Save As / Select / Clear.
class RecordImageField extends StatefulWidget {
  final RecordFieldArgs args;
  const RecordImageField({super.key, required this.args});

  @override
  State<RecordImageField> createState() => _RecordImageFieldState();
}

class _RecordImageFieldState extends State<RecordImageField>
    with _BinaryActions {
  @override
  RecordFieldArgs get args => widget.args;

  Uint8List? _bytes;
  Object? _shown;

  /// Loads the image when the value changed (only up to [imageMaxSize]).
  void _update() {
    final value = args.field.get(args.record);
    if (identical(value, _shown)) return;
    _shown = value;
    _bytes = binaryBytes(value);
    if (_bytes == null && value is int && value > 0 && value <= imageMaxSize) {
      data().then((bytes) {
        if (mounted) setState(() => _bytes = bytes);
      }).catchError((Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    _update();
    final width = (args.node.width ?? 300).toDouble();
    final height = (args.node.height ?? 100).toDouble();
    Widget image = _bytes == null || _bytes!.isEmpty
        ? Icon(Icons.image_outlined,
            size: height * 0.6, color: Theme.of(context).colorScheme.outline)
        : Image.memory(_bytes!,
            key: ValueKey('image-${args.node.name}'),
            width: width,
            height: height,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined));
    switch (args.node.attrs['border']) {
      case 'circle':
        image = ClipOval(child: SizedBox(width: height, height: height, child: image));
      case 'rounded':
        image = ClipRRect(borderRadius: BorderRadius.circular(8), child: image);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: width, height: height, child: Center(child: image)),
      Row(mainAxisSize: MainAxisSize.min, children: toolbar(context, images: true)),
    ]);
  }
}

/// `document`: preview of a PDF (printing) or an image, Open externally,
/// Save As / Select / Clear.
class RecordDocumentField extends StatefulWidget {
  final RecordFieldArgs args;
  const RecordDocumentField({super.key, required this.args});

  @override
  State<RecordDocumentField> createState() => _RecordDocumentFieldState();
}

class _RecordDocumentFieldState extends State<RecordDocumentField>
    with _BinaryActions {
  @override
  RecordFieldArgs get args => widget.args;

  Uint8List? _bytes;
  Object? _shown;

  void _update() {
    final value = args.field.get(args.record);
    if (identical(value, _shown)) return;
    _shown = value;
    _bytes = binaryBytes(value);
    if (_bytes == null && value is int && value > 0) {
      data().then((bytes) {
        if (mounted) setState(() => _bytes = bytes);
      }).catchError((Object _) {});
    }
  }

  static bool isPdf(Uint8List b) =>
      b.length > 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46;

  @override
  Widget build(BuildContext context) {
    _update();
    final bytes = _bytes;
    final height = (args.node.height ?? 400).toDouble();
    Widget preview;
    if (bytes == null || bytes.isEmpty) {
      preview = const SizedBox(height: 40);
    } else if (isPdf(bytes)) {
      preview = SizedBox(
        height: height,
        child: PdfPreview(
          key: ValueKey('document-pdf-${args.node.name}'),
          build: (_) async => bytes,
          useActions: false,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
        ),
      );
    } else {
      preview = SizedBox(
        height: height,
        child: Image.memory(bytes,
            key: ValueKey('document-image-${args.node.name}'),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Center(child: Text(humanSize(bytes.length)))),
      );
    }
    return InputDecorator(
      decoration: args.decoration(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        preview,
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (size > 0)
            toolButton(Icons.open_in_new, 'tryton-open', context.l10n.openFile, openFile,
                key: ValueKey('document-open-${args.node.name}')),
          ...toolbar(context),
        ]),
      ]),
    );
  }
}
