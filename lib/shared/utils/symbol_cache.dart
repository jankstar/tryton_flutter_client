import '../../features/model/model_service.dart';

/// Session-level cache: '$relation,$id' → ('€', 1.0)
/// position < 0.5 = prefix, ≥ 0.5 = suffix (same as SAO)
final _cache = <String, (String, double)>{};

void clearSymbolCache() => _cache.clear();

/// Returns the currency symbol for a given relation+id, loading it if needed.
Future<(String, double)> resolveSymbol(
  ModelService svc,
  String relation,
  int id,
) async {
  final key = '$relation,$id';
  if (_cache.containsKey(key)) return _cache[key]!;

  // Strategy 1: get_symbol RPC
  try {
    final result = await svc.getSymbol(relation, id, 1);
    if (result.$1.isNotEmpty) {
      _cache[key] = result;
      return result;
    }
  } catch (_) {}

  // Strategy 2: read 'symbol' field directly
  try {
    final rows = await svc.read(relation, [id], ['symbol']);
    final sym = rows.isNotEmpty ? rows.first['symbol']?.toString() ?? '' : '';
    if (sym.isNotEmpty) {
      final result = (sym, 1.0);
      _cache[key] = result;
      return result;
    }
  } catch (_) {}

  _cache[key] = ('', 1.0);
  return ('', 1.0);
}
