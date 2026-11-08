import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'record_field_widgets.dart';
import 'richtext_html.dart';

/// widget="richtext" (spec 9.2.4, SAO `Sao.View.Form.RichText`, Python
/// `richtextbox.py`): editor with the toolbar of SAO (bold, italic,
/// underline, font, size, alignment, colour); the value is the sanitized
/// HTML of [deltaToHtml], written on focus loss. Read-only: the formatted
/// text without toolbar.
class RecordRichTextField extends StatefulWidget {
  final RecordFieldArgs args;
  const RecordRichTextField({super.key, required this.args});

  @override
  State<RecordRichTextField> createState() => _RecordRichTextFieldState();
}

class _RecordRichTextFieldState extends State<RecordRichTextField> {
  late QuillController _controller;
  final _focus = FocusNode();
  final _scroll = ScrollController();
  StreamSubscription<DocChange>? _changes;

  /// HTML currently in the editor (to recognise own changes).
  String _html = '';

  RecordFieldArgs get a => widget.args;

  String get _value {
    final v = a.field.get(a.record);
    return v is String ? v : '';
  }

  @override
  void initState() {
    super.initState();
    _controller = _controllerFor(_value);
    _focus.addListener(_onFocus);
  }

  QuillController _controllerFor(String html) {
    _html = html;
    final controller = QuillController(
      document: Document.fromDelta(htmlToDelta(html)),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: a.readOnly,
    );
    _changes?.cancel();
    _changes = controller.document.changes.listen((_) {
      final html = deltaToHtml(controller.document.toDelta());
      if (html == _html) return;
      _html = html;
      a.onText(html.isEmpty ? null : html);
    });
    return controller;
  }

  void _onFocus() {
    if (!_focus.hasFocus) a.onBlur();
  }

  @override
  void didUpdateWidget(RecordRichTextField old) {
    super.didUpdateWidget(old);
    _controller.readOnly = a.readOnly;
    // a new value from outside (other record, on_change, reload)
    final value = _value;
    if (!_focus.hasFocus &&
        deltaToHtml(htmlToDelta(value)) != deltaToHtml(htmlToDelta(_html))) {
      final old = _controller;
      _controller = _controllerFor(value);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = (a.node.height ?? 200).toDouble();
    final editor = QuillEditor(
      key: ValueKey('richtext-${a.node.name}'),
      controller: _controller,
      focusNode: _focus,
      scrollController: _scroll,
      config: QuillEditorConfig(
        minHeight: a.readOnly ? null : height,
        padding: const EdgeInsets.all(8),
        expands: false,
        showCursor: !a.readOnly,
      ),
    );
    return InputDecorator(
      decoration: a.decoration(context).copyWith(contentPadding: EdgeInsets.zero),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!a.readOnly)
          richTextToolbar(_controller,
              key: ValueKey('richtext-toolbar-${a.node.name}')),
        editor,
      ]),
    );
  }
}

/// The toolbar of rich text (SAO toolbar: only what the sanitized HTML of
/// [deltaToHtml] can store) – fields and the email body.
QuillSimpleToolbar richTextToolbar(QuillController controller, {Key? key}) =>
    QuillSimpleToolbar(
      key: key,
      controller: controller,
      config: const QuillSimpleToolbarConfig(
        multiRowsDisplay: false,
        showBoldButton: true,
        showItalicButton: true,
        showUnderLineButton: true,
        showFontFamily: true,
        showFontSize: true,
        showAlignmentButtons: true,
        showLeftAlignment: true,
        showCenterAlignment: true,
        showRightAlignment: true,
        showJustifyAlignment: true,
        showColorButton: true,
        // only what the sanitized HTML can store (SAO toolbar)
        showSmallButton: false,
        showLineHeightButton: false,
        showStrikeThrough: false,
        showInlineCode: false,
        showBackgroundColorButton: false,
        showClearFormat: true,
        showHeaderStyle: false,
        showListNumbers: false,
        showListBullets: false,
        showListCheck: false,
        showCodeBlock: false,
        showQuote: false,
        showIndent: false,
        showLink: false,
        showUndo: true,
        showRedo: true,
        showDirection: false,
        showSearchButton: false,
        showSubscript: false,
        showSuperscript: false,
        buttonOptions: QuillSimpleToolbarButtonOptions(
          fontFamily: QuillToolbarFontFamilyButtonOptions(items: {
            'Normal': 'Clear',
            'Sans': 'sans-serif',
            'Serif': 'serif',
            'Monospace': 'monospace',
          }),
          fontSize: QuillToolbarFontSizeButtonOptions(items: {
            '1': '10',
            '2': '13',
            '3': '16',
            '4': '18',
            '5': '24',
            '6': '32',
            '7': '48',
            'Normal': '0',
          }),
        ),
      ),
    );
