/// Toolbar data received from the server via `view_toolbar_get`.
class TrytonToolbar {
  final List<TrytonActionItem> actions;
  final List<TrytonActionItem> relate;
  final List<TrytonActionItem> print;
  final List<TrytonActionItem> emails;

  /// Predefined CSV exports (`ir.export` with `export_fields.`, spec
  /// 11.9), shown in the print menu.
  final List<Map<String, dynamic>> exports;

  const TrytonToolbar({
    this.actions = const [],
    this.relate = const [],
    this.print = const [],
    this.emails = const [],
    this.exports = const [],
  });

  bool get isEmpty =>
      actions.isEmpty && relate.isEmpty && print.isEmpty && emails.isEmpty;

  factory TrytonToolbar.fromJson(Map<String, dynamic> json) {
    return TrytonToolbar(
      actions: _parseList(json['action']),
      relate: _parseList(json['relate']),
      print: _parseList(json['print']),
      emails: _parseList(json['emails']),
      exports: [
        if (json['exports'] case final List exports)
          for (final e in exports)
            if (e is Map) Map<String, dynamic>.from(e)
      ],
    );
  }

  static List<TrytonActionItem> _parseList(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(TrytonActionItem.fromJson)
        .toList();
  }
}

class TrytonActionItem {
  final int id;
  final String name;
  final String type; // ir.action.act_window, ir.action.report, ir.action.wizard
  final String? reportName; // for reports
  final String? wizzName;   // for wizards
  final String? resModel;   // for act_window
  /// The complete action as sent by `view_toolbar_get` (act_window:
  /// views, PYSON domain/context/order, tab domains, …).
  final Map<String, dynamic> raw;

  const TrytonActionItem({
    required this.id,
    required this.name,
    required this.type,
    this.reportName,
    this.wizzName,
    this.resModel,
    this.raw = const {},
  });

  factory TrytonActionItem.fromJson(Map<String, dynamic> json) {
    return TrytonActionItem(
      // Use num cast to safely handle both int and double JSON numbers
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      reportName: json['report_name']?.toString(),
      wizzName: json['wiz_name']?.toString(),
      resModel: json['res_model']?.toString(),
      raw: json,
    );
  }
}
