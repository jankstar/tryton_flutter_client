import '../../features/model/model_service.dart';
import '../../features/model/field_definition.dart';
import '../../features/model/record.dart';

/// Session-global Many2One name cache: '$model,$id' → 'Name'.
/// Shared between ListViewScreen and EmbeddedTreeWidget.
final m2oNameCache = <String, String>{};

void clearM2ONameCache() => m2oNameCache.clear();

/// Resolves unresolved Many2One IDs in [records] for the given [columns].
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
    if (fd?.type != 'many2one') continue;
    final relModel = fd!.relation;
    if (relModel == null || relModel.isEmpty) continue;

    for (final r in records) {
      final val = r[col];
      final id = val is int
          ? val
          : (val is List && val.isNotEmpty ? (val[0] as num?)?.toInt() : null);
      if (id == null || id <= 0) continue;

      // Already a [id, name] pair?
      if (val is List && val.length > 1 &&
          val[1] != null && val[1] != false) {
        m2oNameCache['$relModel,$id'] = val[1].toString();
        continue;
      }
      // Companion key ('col.rec_name')?
      final companion = r['$col.rec_name'] ?? r['$col.'];
      if (companion != null && companion != false) {
        m2oNameCache['$relModel,$id'] = companion.toString();
        continue;
      }
      if (!m2oNameCache.containsKey('$relModel,$id')) {
        toLoad.putIfAbsent(relModel, () => {}).add(id);
      }
    }
  }

  for (final entry in toLoad.entries) {
    try {
      final relRecords =
          await svc.read(entry.key, entry.value.toList(), ['rec_name']);
      for (final r in relRecords) {
        m2oNameCache['${entry.key},${r.id}'] =
            r['rec_name']?.toString() ?? '';
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
  if (value is List && value.length > 1 &&
      value[1] != null && value[1] != false) {
    return value[1].toString();
  }
  return m2oNameCache['$relModel,$id'];
}
