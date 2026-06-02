import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stores the record navigation context so the form view can
/// navigate to Previous / Next records from the list.
class RecordNavContext {
  final String model;
  final String title;
  final List<int> recordIds;
  final int currentIndex;

  const RecordNavContext({
    required this.model,
    required this.title,
    required this.recordIds,
    required this.currentIndex,
  });

  bool get hasPrevious => currentIndex > 0;
  bool get hasNext => currentIndex < recordIds.length - 1;

  int? get previousId =>
      hasPrevious ? recordIds[currentIndex - 1] : null;
  int? get nextId =>
      hasNext ? recordIds[currentIndex + 1] : null;

  RecordNavContext withIndex(int index) => RecordNavContext(
        model: model,
        title: title,
        recordIds: recordIds,
        currentIndex: index,
      );

  String get positionLabel =>
      '${currentIndex + 1} / ${recordIds.length}';
}

final navContextProvider =
    StateProvider<RecordNavContext?>((ref) => null);
