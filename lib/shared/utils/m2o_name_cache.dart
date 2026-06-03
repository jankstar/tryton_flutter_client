import '../../features/model/model_service.dart';
import '../../features/model/field_definition.dart';
import '../../features/model/record.dart';

/// Session-global Many2One name cache: '$model,$id' → 'Name'.
/// Shared between ListViewScreen and EmbeddedTreeWidget.
final m2oNameCache = <String, String>{};

void clearM2ONameCache() => m2oNameCache.clear();

/// Returns [v] as a non-empty String, or null.
/// Guards against Map/List values that would otherwise produce "{...}" / "[...]"
/// via .toString() and end up as visible JSON noise in the UI.
String? _asName(dynamic v) {
  if (v == null || v == false) return null;
  if (v is String && v.isNotEmpty) return v;
  return null; // Map, List, int, or other non-string → discard
}

/// Resolves unresolved Many2One / reference IDs in [records] for [columns].
/// Fills [m2oNameCache] so subsequent renders can use cached names.
Future<void> resolveM2ONames(
  ModelService svc,
  List<TrytonRecord> records,
  List<String> columns,
  Map<String, FieldDefinition?> fields,
) async {
  final toLoad = <String, Set<int>>{};

  for (final col in columns) {
    final fd = fields[col];
    final type = fd?.type;

    if (type == 'many2one') {
      final relModel = fd!.relation;
      if (relModel == null || relModel.isEmpty) continue;

      for (final r in records) {
        final val = r[col];
        final id = val is int
            ? val
            : (val is List && val.isNotEmpty ? (val[0] as num?)?.toInt() : null);
        if (id == null || id <= 0) continue;

        // [id, name] pair — only cache if name is actually a String.
        if (val is List && val.length > 1) {
          final name = _asName(val[1]);
          if (name != null) {
            m2oNameCache['$relModel,$id'] = name;
            continue;
          }
        }
        // Companion key 'col.rec_name' — only cache if it is a String.
        final companion = _asName(r['$col.rec_name']) ?? _asName(r['$col.']);
        if (companion != null) {
          m2oNameCache['$relModel,$id'] = companion;
          continue;
        }
        if (!m2oNameCache.containsKey('$relModel,$id')) {
          toLoad.putIfAbsent(relModel, () => {}).add(id);
        }
      }
    }
  }

  for (final entry in toLoad.entries) {
    try {
      final relRecords =
          await svc.read(entry.key, entry.value.toList(), ['rec_name']);
      for (final r in relRecords) {
        // Only store if rec_name is an actual String.
        final name = _asName(r['rec_name']);
        m2oNameCache['${entry.key},${r.id}'] = name ?? '';
      }
    } catch (_) {}
  }
}

/// Returns the cached display name for a Many2One value, or null if unknown.
String? m2oDisplayName(String relModel, dynamic value) {
  final id = value is int
      ? value
      : (value is List && value.isNotEmpty ? (value[0] as num?)?.toInt() : null);
  if (id == null || id <= 0) return null;
  if (value is List && value.length > 1) {
    final name = _asName(value[1]);
    if (name != null) return name;
  }
  return m2oNameCache['$relModel,$id'];
}
