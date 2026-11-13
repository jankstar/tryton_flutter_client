import '../../core/model/model.dart';
import '../../core/screen/screen.dart';
import '../model/field_definition.dart';
import '../model/model_service.dart';
import '../model/selection_loader.dart';
import 'record_widget_values.dart';

/// Options of the selection/multiselection columns of a list whose
/// selection is a server method (e.g. `party.identifier.type` →
/// `get_types`), so cells show labels instead of keys also for records
/// without the server's `<f>:string` (new or changed ones) – Python
/// `list_gtk.Selection.get_textual_value` with `update_selection`.
///
/// Without `selection_change_with` the options come from the screen
/// ([TrytonScreen.selectionOptions], shared with the domain parser), with
/// it per value combination of the record ([SelectionLoader]). Each
/// request starts once; [onLoaded] rebuilds the list.
class ColumnSelections {
  final TrytonScreen screen;
  final ModelService service;
  final void Function() onLoaded;

  late final SelectionLoader _loader = SelectionLoader((method, values) async {
    if (values == null) {
      final options = await screen.selectionOptions({'selection': method});
      return [
        for (final o in options)
          if (o is List) o.cast<dynamic>()
      ];
    }
    return service.getSelectionOptions(screen.model.name, method,
        values: values);
  });
  final Set<String> _requested = {};

  ColumnSelections(
      {required this.screen, required this.service, required this.onLoaded});

  /// [fd] of the column for [record], with the loaded options of a method
  /// selection (unchanged while they load).
  FieldDefinition? field(
      Record record, FieldDefinition? fd, Map<String, FieldDefinition> fields) {
    if (fd == null || !SelectionLoader.isDynamic(fd)) return fd;
    final values = fd.selectionChangeWith?.isNotEmpty ?? false
        ? recordWidgetValues(record)
        : const <String, dynamic>{};
    final options = _loader.cached(fd, values, fields);
    if (options != null) return fd.copyWithSelection(options);
    final key = SelectionLoader.cacheKey(fd.selectionFunction!,
        SelectionLoader.changeWithValues(fd, values, fields));
    if (_requested.add(key)) {
      _loader.load(fd, values, fields).then((_) => onLoaded());
    }
    return fd;
  }
}
