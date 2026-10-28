import '../../core/screen/screen.dart';
import '../../core/session/session.dart';
import '../shell/tab_manager.dart';

/// Fields of `ir.action.act_window` needed to open it (Python client
/// `Action.exec_action`).
const actWindowFields = [
  'name',
  'res_model',
  'views',
  'pyson_domain',
  'pyson_context',
  'pyson_order',
  'pyson_search_value',
  'domains',
  'context_model',
  'context_domain',
  'limit',
];

/// Opens the `act_window` [action] in a new tab; [data] is the calling
/// record (`model`, `id`, `ids`) for the PYSON environment.
void openActWindow(
  TabsNotifier tabs,
  TrytonSession session,
  Map<String, dynamic> action, {
  Map<String, dynamic> data = const {},
  String? title,
}) {
  final attributes = ScreenAttributes.fromActWindow(
    action,
    sessionContext: session.context,
    userId: session.userId,
    data: data,
  );
  if (attributes.model.isEmpty || attributes.model == 'null') return;
  tabs.openTab(
    title: title ?? '${action['name'] ?? attributes.model}',
    attributes: attributes,
  );
}
