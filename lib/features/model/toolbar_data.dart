/// One tab from `ir.action.act_window.domain` — evaluated PYSON domain + count flag.
class TabDomain {
  final int id;
  final String name;
  final List<dynamic> domain;
  final bool count;

  const TabDomain({
    required this.id,
    required this.name,
    required this.domain,
    required this.count,
  });
}

/// Toolbar data received from the server via `view_toolbar_get`.
class TrytonToolbar {
  final List<TrytonActionItem> actions;
  final List<TrytonActionItem> relate;
  final List<TrytonActionItem> print;
  final List<TrytonActionItem> emails;

  const TrytonToolbar({
    this.actions = const [],
    this.relate = const [],
    this.print = const [],
    this.emails = const [],
  });

  bool get isEmpty =>
      actions.isEmpty && relate.isEmpty && print.isEmpty && emails.isEmpty;

  factory TrytonToolbar.fromJson(Map<String, dynamic> json) {
    return TrytonToolbar(
      actions: _parseList(json['action']),
      relate: _parseList(json['relate']),
      print: _parseList(json['print']),
      emails: _parseList(json['emails']),
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

  const TrytonActionItem({
    required this.id,
    required this.name,
    required this.type,
    this.reportName,
    this.wizzName,
    this.resModel,
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
    );
  }
}
