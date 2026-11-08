import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart' hide TextField;
import '../../core/rpc/error_processing.dart';
import '../../core/screen/screen.dart';
import '../../core/serialization/tryton_serializer.dart';
import '../../shared/utils/date_format_utils.dart';
import '../../shared/utils/file_actions.dart';
import '../auth/user_preferences_provider.dart';
import '../model/model_service.dart';
import 'screen_widget.dart';

// Attachments, notes and logs of a record (spec 11.4–11.6, Python
// gui/window/attachment.py, note.py, log.py): dialogs on a screen of
// `ir.attachment` / `ir.note` / `ir.model.log` with `resource =
// <model>,<id>`.

/// The record a resource dialog belongs to.
typedef ResourceRef = ({String model, int id, String recName, Map<String, dynamic> context});

String _resource(ResourceRef r) => '${r.model},${r.id}';

/// `ir.attachment.search_read` of [r] (at most 20, Python
/// `Attachment.get_attachments`).
Future<List<Map<String, dynamic>>> attachmentsOf(ModelService svc, ResourceRef r) async {
  final result = await svc.execute<dynamic>('ir.attachment', 'search_read', [
    [
      ['resource', '=', _resource(r)]
    ],
    0,
    20,
    null,
    ['rec_name', 'name', 'type', 'link'],
  ], context: r.context, processException: false);
  return [
    for (final a in (result as List? ?? const []))
      if (a is Map) Map<String, dynamic>.from(a)
  ];
}

/// Opens an attachment: `link` → URL, `data` → content read and opened
/// (Python `open_link` / `open_data`).
Future<void> openAttachment(
    ModelService svc, Map<String, dynamic> attachment, Map<String, dynamic> context) async {
  if (attachment['type'] == 'link') {
    final link = attachment['link'];
    if (link is String && link.isNotEmpty) {
      await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    }
    return;
  }
  final rows = await svc.execute<dynamic>('ir.attachment', 'read', [
    [attachment['id']],
    ['data']
  ], context: context);
  final data = ((rows as List).first as Map)['data'];
  final bytes = data is TrytonBytes
      ? Uint8List.fromList(data.bytes)
      : Uint8List.fromList('${data ?? ''}'.codeUnits);
  final path = await FileActions.instance
      .writeTemp('${attachment['name'] ?? 'attachment'}', bytes);
  await FileActions.instance.open(path);
}

/// A dialog around a [ScreenWidget] of [attributes]; [header] above,
/// [onClose] when closed (with the screen).
Future<void> _showScreenDialog(BuildContext context,
    {required String title,
    required ScreenAttributes attributes,
    Widget? header,
    Future<void> Function(TrytonScreen screen)? onClose,
    Future<void> Function(TrytonScreen screen)? onReady,
    Key? key}) async {
  TrytonScreen? screen;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final size = MediaQuery.sizeOf(dialogContext);
      return Dialog(
        key: key,
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: math.min(size.width * 0.9, 1000),
          height: size.height * 0.85,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
              child: Row(children: [
                Expanded(
                  child: Text(title,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(dialogContext).textTheme.titleMedium),
                ),
                FilledButton(
                  key: const ValueKey('resource-dialog-close'),
                  onPressed: () async {
                    final s = screen;
                    if (s != null && onClose != null) {
                      try {
                        await onClose(s);
                      } catch (e) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext)
                              .showSnackBar(SnackBar(content: Text('$e')));
                        }
                        return;
                      }
                    }
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: Text(dialogContext.l10n.close),
                ),
              ]),
            ),
            ?header,
            const Divider(height: 1),
            Expanded(
              child: ScreenWidget(
                attributes: attributes,
                title: title,
                onScreen: (s) {
                  screen = s;
                  if (onReady != null) {
                    // after the first search of the screen
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      for (var i = 0; i < 50 && s.currentView == null; i++) {
                        await Future<void>.delayed(const Duration(milliseconds: 20));
                      }
                      await onReady(s);
                    });
                  }
                },
              ),
            ),
          ]),
        ),
      );
    },
  );
}

/// Attachments of [r] (spec 11.4): list/form of `ir.attachment`; [add]
/// files become new attachments (`data`, file name, type `data`); closing
/// saves (Python `Attachment.callback`).
Future<void> showAttachments(BuildContext context, ResourceRef r,
    {List<PickedFile> add = const [], VoidCallback? onChanged}) {
  return _showScreenDialog(
    context,
    key: const ValueKey('attachments-dialog'),
    title: context.l10n.attachmentsOf(r.recName),
    attributes: ScreenAttributes('ir.attachment',
        mode: const ['tree', 'form'],
        domain: [
          ['resource', '=', _resource(r)]
        ],
        context: r.context),
    onReady: add.isEmpty
        ? null
        : (screen) async {
            for (final file in add) {
              final record = await screen.newRecord();
              if (record == null) continue;
              final fields = record.model.fields;
              await fields['resource']?.setClient(record, _resource(r));
              final filename = fields['data']?.description['filename'];
              await fields[filename is String ? filename : 'name']
                  ?.setClient(record, file.name);
              await fields['type']?.setClient(record, 'data');
              await fields['data']?.setClient(record, TrytonBytes(file.bytes));
            }
          },
    onClose: (screen) async {
      // all new/changed attachments (Python: save_current of the list)
      if (screen.modified() && !await screen.group.save()) {
        throw StateError('not saved');
      }
      onChanged?.call();
    },
  );
}

/// Notes of [r] (spec 11.5): closing marks all shown notes as read (unless
/// changed by the user) and saves (Python `Note.callback`).
Future<void> showNotes(BuildContext context, ResourceRef r, {VoidCallback? onChanged}) {
  return _showScreenDialog(
    context,
    key: const ValueKey('notes-dialog'),
    title: context.l10n.notesOf(r.recName),
    attributes: ScreenAttributes('ir.note',
        mode: const ['tree', 'form'],
        domain: [
          ['resource', '=', _resource(r)]
        ],
        context: r.context),
    onClose: (screen) async {
      final unread = screen.model.fields['unread'];
      if (unread != null) {
        for (final record in screen.group) {
          if (record.modifiedFields.contains('unread')) continue;
          if (!record.isLoaded('unread') && record.id >= 0) {
            await record.load('unread');
          }
          if (unread.get(record) == true) await unread.setClient(record, false);
        }
      }
      if (screen.modified() && !await screen.group.save()) {
        throw StateError('not saved');
      }
      onChanged?.call();
    },
  );
}

/// Logs of [r] (spec 11.6): header with model, ID, module/XML ID, created
/// and modified by/at, below the `ir.model.log` list.
Future<void> showLogs(BuildContext context, WidgetRef ref, ResourceRef r) async {
  final svc = ref.read(modelServiceProvider);
  final rows = await svc.execute<dynamic>(r.model, 'read', [
    [r.id],
    ['create_uid.rec_name', 'create_date', 'write_uid.rec_name', 'write_date', 'xml_id']
  ], context: r.context);
  final log = ((rows as List).first as Map).cast<String, dynamic>();
  if (!context.mounted) return;
  final dateFormat = ref.read(dateFormatProvider);
  String date(dynamic v) => v is DateTime
      ? formatDate(v.toLocal(), '$dateFormat %H:%M:%S.%f')
      : '';
  String user(String key) {
    final related = log['$key.'];
    if (related is Map) return '${related['rec_name'] ?? ''}';
    return '${log['$key.rec_name'] ?? ''}';
  }

  final xmlId = log['xml_id'];
  final (module, xml) = xmlId is String && xmlId.contains('.')
      ? (xmlId.substring(0, xmlId.indexOf('.')), xmlId.substring(xmlId.indexOf('.') + 1))
      : (null, null);
  final l = context.l10n;
  Widget item(String label, String value, String key) => SizedBox(
        width: 300,
        child: TextField(
          key: ValueKey('log-$key'),
          controller: TextEditingController(text: value),
          readOnly: true,
          decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
        ),
      );
  final header = Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
    child: Wrap(spacing: 12, runSpacing: 10, children: [
      item(l.logModel, r.model, 'model'),
      item('ID', '${r.id}', 'id'),
      if (module != null) item(l.logModule, module, 'module'),
      if (xml != null) item(l.logXmlId, xml, 'xml_id'),
      item(l.logCreatedBy, user('create_uid'), 'create_uid'),
      item(l.logCreatedAt, date(log['create_date']), 'create_date'),
      item(l.logModifiedBy, user('write_uid'), 'write_uid'),
      item(l.logModifiedAt, date(log['write_date']), 'write_date'),
    ]),
  );
  await _showScreenDialog(
    context,
    key: const ValueKey('logs-dialog'),
    title: l.logsOf(r.recName),
    header: header,
    attributes: ScreenAttributes('ir.model.log',
        mode: const ['tree', 'form'],
        readonly: true,
        domain: [
          ['resource', '=', _resource(r)]
        ],
        context: r.context),
  );
}

/// Attachment button with counter and dropdown (Python
/// `Form.sig_attach`): the attachments (up to 20; link → URL, data →
/// open), „Add…“ (several files), „Manage…“.
class AttachmentMenuButton extends ConsumerWidget {
  final ResourceRef? resource;
  final int count;
  final VoidCallback? onChanged;

  const AttachmentMenuButton(
      {super.key, required this.resource, required this.count, this.onChanged});

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final r = resource;
    if (r == null) return;
    final svc = ref.read(modelServiceProvider);
    final l = context.l10n;
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final position = box == null || overlay == null
        ? const RelativeRect.fromLTRB(0, 56, 0, 0)
        : RelativeRect.fromRect(
            Rect.fromPoints(
                box.localToGlobal(box.size.bottomLeft(Offset.zero), ancestor: overlay),
                box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay)),
            Offset.zero & overlay.size);
    List<Map<String, dynamic>> attachments;
    try {
      attachments = await attachmentsOf(svc, r);
    } catch (_) {
      attachments = const [];
    }
    if (!context.mounted) return;
    final choice = await showMenu<Object>(
      context: context,
      position: position,
      items: [
        for (final a in attachments)
          PopupMenuItem<Object>(
            key: ValueKey('attachment-${a['id']}'),
            value: a,
            child: Row(children: [
              Icon(a['type'] == 'link' ? Icons.link : Icons.insert_drive_file_outlined, size: 16),
              const SizedBox(width: 8),
              Flexible(child: Text('${a['rec_name'] ?? a['name'] ?? ''}', overflow: TextOverflow.ellipsis)),
            ]),
          ),
        if (attachments.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem<Object>(
            key: const ValueKey('attachment-add'), value: 'add', child: Text(l.addFiles)),
        PopupMenuItem<Object>(
            key: const ValueKey('attachment-manage'), value: 'manage', child: Text(l.manage)),
      ],
    );
    if (!context.mounted || choice == null) return;
    try {
      if (choice is Map<String, dynamic>) {
        await openAttachment(svc, choice, r.context);
      } else if (choice == 'add') {
        final files = await FileActions.instance.pick(multiple: true);
        if (files.isEmpty || !context.mounted) return;
        await showAttachments(context, r, add: files, onChanged: onChanged);
      } else if (choice == 'manage') {
        await showAttachments(context, r, onChanged: onChanged);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      key: const ValueKey('attachment-button'),
      tooltip: context.l10n.attachmentCount(count),
      onPressed: resource == null ? null : () => _open(context, ref),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const TrytonIcon(iconName: 'tryton-attach', size: 22, fallback: Icons.attach_file),
      ),
    );
  }
}

/// [ResourceRef] of [record] (null for unsaved records).
Future<ResourceRef?> resourceOf(Record? record) async {
  if (record == null || record.id < 0) return null;
  String name;
  try {
    name = await record.recName();
  } catch (_) {
    name = '${record.id}';
  }
  return (model: record.model.name, id: record.id, recName: name, context: record.getContext());
}

/// Shown revision with milliseconds (SAO `%H:%M:%S.%f`).
String revisionText(DateTime dt) =>
    '${formatDateTimeValue(dt)}.${dt.toLocal().millisecond.toString().padLeft(3, '0')}';

/// Revisions of [ids] (spec 11.7, Python `Form.sig_revision`):
/// `history_revisions(ids)` and the choice of a revision or "Current".
/// Returns the chosen time, `'current'` or null (cancelled or error).
Future<Object?> chooseRevision(
    BuildContext context, TrytonScreen screen, List<int> ids) async {
  final List revisions;
  try {
    revisions = await screen.model.execute('history_revisions', [ids],
            context: screen.context) as List? ??
        const [];
  } on HandledRpcError {
    return null;
  }
  if (!context.mounted) return null;
  final l = context.l10n;
  return showDialog<Object>(
    context: context,
    builder: (ctx) => SimpleDialog(
      key: const ValueKey('revision-dialog'),
      title: Text(l.selectRevision),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'current'),
          child: Text(l.currentRevision),
        ),
        for (final r in revisions)
          if (r is List && r.isNotEmpty && r[0] is DateTime)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r[0]),
              child: Text('${revisionText(r[0] as DateTime)}'
                  '${r.length > 2 ? '  ${r[2]}' : ''}'),
            ),
      ],
    ),
  );
}
