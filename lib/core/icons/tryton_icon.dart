import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../features/model/model_service.dart';

// ─── Global SVG cache (name → SVG string) ────────────────────────────────────

final _svgCache = <String, String?>{};

/// Stores SVG data in the cache – called when the menu is loaded.
void cacheIconSvg(String name, String? svg) {
  _svgCache[name] = svg;
}

/// Checks whether an icon is already in the cache.
bool isIconCached(String name) => _svgCache.containsKey(name);

// ─── TrytonIcon widget ────────────────────────────────────────────────────────

/// Displays a Tryton icon.
/// SVG data is taken from the global cache (preloaded when the menu is loaded).
/// Fallback: Material icon if no SVG is available.
class TrytonIcon extends StatelessWidget {
  final String? iconName;
  final double size;
  final Color? color;
  final IconData fallback;

  const TrytonIcon({
    super.key,
    required this.iconName,
    this.size = 24,
    this.color,
    this.fallback = Icons.widgets_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final col = color ?? Theme.of(context).colorScheme.primary;

    if (iconName == null || iconName!.isEmpty) {
      return Icon(fallback, size: size, color: col);
    }

    // SVG from cache – colorFilter correctly preserves transparency
    // (no manual replacement of fill attributes, which would break fill="none")
    final svg = _svgCache[iconName!];
    if (svg != null && svg.isNotEmpty) {
      try {
        return SvgPicture.string(
          svg,
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(col, BlendMode.srcIn),
        );
      } catch (_) {
        // Invalid SVG → fallback
      }
    }

    // Not in cache: Material fallback
    if (_svgCache.containsKey(iconName!)) {
      // In cache but SVG was null → no icon found on the server
      final mat = _materialIcon(iconName!);
      return Icon(mat ?? fallback, size: size, color: col);
    }

    // Not yet attempted to load → load asynchronously
    return _AsyncIconLoader(
      iconName: iconName!,
      size: size,
      color: col,
      fallback: fallback,
    );
  }

  /// Known Tryton icon names → Material Icons.
  /// Covers both Tryton built-in icons and module icons.
  static IconData? _materialIcon(String name) {
    const map = <String, IconData>{
      // ── Navigation ────────────────────────────────────────────────────────────
      'tryton-go-home': Icons.home,
      'tryton-go-next': Icons.arrow_forward,
      'tryton-go-previous': Icons.arrow_back,
      'tryton-first': Icons.first_page,
      'tryton-last': Icons.last_page,

      // ── CRUD ──────────────────────────────────────────────────────────────────
      'tryton-new': Icons.add,
      'tryton-save': Icons.save,
      'tryton-delete': Icons.delete_outline,
      'tryton-copy': Icons.copy,
      'tryton-clear': Icons.clear,
      'tryton-refresh': Icons.refresh,
      'tryton-search': Icons.search,
      'tryton-find': Icons.search,
      'tryton-close': Icons.close,
      'tryton-open': Icons.open_in_new,
      'tryton-launch': Icons.launch,
      'tryton-edit': Icons.edit,

      // ── Documents & communication ─────────────────────────────────────────────
      'tryton-note': Icons.note,
      'tryton-attachment': Icons.attach_file,
      'tryton-email': Icons.email_outlined,
      'tryton-print': Icons.print_outlined,
      'tryton-star': Icons.star,
      'tryton-star-border': Icons.star_border,
      'tryton-bookmarks': Icons.bookmarks,
      'tryton-log': Icons.history,
      'tryton-switch': Icons.compare_arrows, // switch between tree and form view
      'tryton-chat': Icons.chat_outlined,

      // ── Status / Info ──────────────────────────────────────────────────────────
      'tryton-information': Icons.info_outline,
      'tryton-warning': Icons.warning_amber,
      'tryton-error': Icons.error_outline,
      'tryton-ok': Icons.check_circle_outline,
      'tryton-cancel': Icons.cancel_outlined,

      // ── Settings / Admin ──────────────────────────────────────────────────────
      'tryton-settings': Icons.settings_outlined,
      'tryton-preferences': Icons.settings_outlined,
      'tryton-administration': Icons.admin_panel_settings,
      'tryton-public': Icons.public,
      'tryton-password': Icons.lock_outline,

      // ── Business modules (LOCAL_ICONS in SAO – not in ir.ui.icon) ────────────
      // party
      'tryton-party': Icons.people_outline,
      'party': Icons.people_outline,
      // product
      'tryton-product': Icons.inventory_2_outlined,
      'product': Icons.inventory_2_outlined,
      // account / finance
      'tryton-account': Icons.account_balance_outlined,
      'account': Icons.account_balance_outlined,
      'tryton-currency': Icons.euro_outlined,
      'currency': Icons.euro_outlined,
      // sale
      'tryton-sale': Icons.shopping_cart_outlined,
      'sale': Icons.shopping_cart_outlined,
      // purchase
      'tryton-purchase': Icons.local_shipping_outlined,
      'purchase': Icons.local_shipping_outlined,
      // stock / warehouse
      'tryton-stock': Icons.warehouse_outlined,
      'stock': Icons.warehouse_outlined,
      // invoice
      'tryton-invoice': Icons.receipt_long_outlined,
      'invoice': Icons.receipt_long_outlined,
      // project
      'tryton-project': Icons.work_outline,
      'project': Icons.work_outline,
      // calendar
      'tryton-calendar': Icons.calendar_month_outlined,
      'calendar': Icons.calendar_month_outlined,
      // hr / payroll
      'tryton-hr': Icons.badge_outlined,
      'hr': Icons.badge_outlined,
      'tryton-payroll': Icons.payments_outlined,
      'payroll': Icons.payments_outlined,
      // production
      'tryton-production': Icons.precision_manufacturing_outlined,
      'production': Icons.precision_manufacturing_outlined,
      // shipment
      'tryton-shipment': Icons.local_shipping_outlined,
      'carrier': Icons.local_shipping_outlined,
      // country / language
      'tryton-country': Icons.flag_outlined,
      'country': Icons.flag_outlined,
      'tryton-language': Icons.language,
      // user / group
      'tryton-user': Icons.person_outline,
      'user': Icons.person_outline,
      'tryton-group': Icons.group_outlined,
      'group': Icons.group_outlined,
      // board / reporting
      'tryton-board': Icons.dashboard_outlined,
      'board': Icons.dashboard_outlined,
      'tryton-report': Icons.bar_chart,
      'report': Icons.bar_chart,
    };

    // Exact match
    if (map.containsKey(name)) return map[name];

    // Prefix match (e.g. "tryton-party-form" → "tryton-party")
    for (final entry in map.entries) {
      if (name.startsWith(entry.key)) return entry.value;
    }

    return null;
  }
}

// ─── Asynchronous loader ──────────────────────────────────────────────────────

/// Loads an icon asynchronously if it is not yet in the cache.
/// Only used for icons that were not pre-cached when the menu was loaded.
class _AsyncIconLoader extends StatefulWidget {
  final String iconName;
  final double size;
  final Color color;
  final IconData fallback;

  const _AsyncIconLoader({
    required this.iconName,
    required this.size,
    required this.color,
    required this.fallback,
  });

  @override
  State<_AsyncIconLoader> createState() => _AsyncIconLoaderState();
}

class _AsyncIconLoaderState extends State<_AsyncIconLoader> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final svg = _svgCache[widget.iconName];
    if (svg != null && svg.isNotEmpty) {
      return SvgPicture.string(
        svg,
        width: widget.size,
        height: widget.size,
        colorFilter: ColorFilter.mode(widget.color, BlendMode.srcIn),
      );
    }
    final mat = TrytonIcon._materialIcon(widget.iconName);
    return Icon(mat ?? widget.fallback, size: widget.size, color: widget.color);
  }
}

// ─── Bulk preloading of icons from the server ─────────────────────────────────

/// Loads SVG data for the given icon IDs into the cache.
/// Called from the menu provider so that all menu icons
/// are synchronously available when the menu is rendered.
Future<Map<int, String>> loadIconSvgs(
  ModelService svc,
  List<int> iconIds,
) async {
  if (iconIds.isEmpty) return {};

  final idToName = <int, String>{};
  try {
    // Both fields at once: 'name' (identifier) + 'icon' (SVG text)
    final records = await svc.read(
      'ir.ui.icon',
      iconIds,
      ['name', 'icon'],
    );

    for (final r in records) {
      final name = r['name']?.toString() ?? '';
      final svgVal = r['icon'];

      // `icon` is a text field → comes as String
      String? svg;
      if (svgVal is String && svgVal.isNotEmpty) {
        svg = svgVal;
      }

      if (name.isNotEmpty) {
        idToName[r.id] = name;
        cacheIconSvg(name, svg);
      }
    }
  } catch (_) {
    // Icons are optional
  }

  return idToName;
}
