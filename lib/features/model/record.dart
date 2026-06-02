/// A single record from the Tryton backend.
class TrytonRecord {
  final int id;
  final Map<String, dynamic> values;
  final String? timestamp;
  final bool canWrite;
  final bool canDelete;

  const TrytonRecord({
    required this.id,
    required this.values,
    this.timestamp,
    this.canWrite = true,
    this.canDelete = true,
  });

  factory TrytonRecord.fromJson(Map<String, dynamic> json) {
    final values = Map<String, dynamic>.from(json);
    final id = values.remove('id') as int? ?? -1;
    final timestamp = values.remove('_timestamp') as String?;
    final canWrite = values.remove('_write') as bool? ?? true;
    final canDelete = values.remove('_delete') as bool? ?? true;
    return TrytonRecord(
      id: id,
      values: values,
      timestamp: timestamp,
      canWrite: canWrite,
      canDelete: canDelete,
    );
  }

  dynamic operator [](String field) => values[field];

  String get recName => values['rec_name']?.toString() ?? id.toString();

  TrytonRecord copyWith(Map<String, dynamic> changes) => TrytonRecord(
        id: id,
        values: {...values, ...changes},
        timestamp: timestamp,
        canWrite: canWrite,
        canDelete: canDelete,
      );
}
