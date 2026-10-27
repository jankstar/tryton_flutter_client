import 'dart:convert';

import 'package:tryton_flutter_client/core/pyson/pyson_encoder.dart';
import 'package:tryton_flutter_client/core/pyson/pyson_evaluator.dart';

/// PYSON builders like SAO's `new Sao.PYSON.X(...)` (only the `.pyson()`
/// dict, as the server sends it).
Map<String, dynamic> eval_(String v, [dynamic d = '']) =>
    {'__class__': 'Eval', 'v': v, 'd': d};
Map<String, dynamic> not(dynamic v) => {'__class__': 'Not', 'v': v};
Map<String, dynamic> bool_(dynamic v) => {'__class__': 'Bool', 'v': v};
Map<String, dynamic> and(List<dynamic> s) => {'__class__': 'And', 's': s};
Map<String, dynamic> or(List<dynamic> s) => {'__class__': 'Or', 's': s};
Map<String, dynamic> equal(dynamic s1, dynamic s2) =>
    {'__class__': 'Equal', 's1': s1, 's2': s2};
Map<String, dynamic> greater(dynamic s1, dynamic s2, [bool e = false]) =>
    {'__class__': 'Greater', 's1': s1, 's2': s2, 'e': e};
Map<String, dynamic> less(dynamic s1, dynamic s2, [bool e = false]) =>
    {'__class__': 'Less', 's1': s1, 's2': s2, 'e': e};
Map<String, dynamic> if_(dynamic c, dynamic t, [dynamic e]) =>
    {'__class__': 'If', 'c': c, 't': t, 'e': e};
Map<String, dynamic> get(dynamic v, dynamic k, [dynamic d]) =>
    {'__class__': 'Get', 'v': v, 'k': k, 'd': d};
Map<String, dynamic> in_(dynamic k, dynamic v) =>
    {'__class__': 'In', 'k': k, 'v': v};
Map<String, dynamic> len(dynamic v) => {'__class__': 'Len', 'v': v};
Map<String, dynamic> timeDelta([int d = 0, int s = 0, int m = 0]) =>
    {'__class__': 'TimeDelta', 'd': d, 's': s, 'm': m};

Map<String, dynamic> date({
  int? y,
  int? M,
  int? d,
  int dy = 0,
  int dM = 0,
  int dd = 0,
  dynamic start,
}) =>
    {
      '__class__': 'Date',
      'y': y,
      'M': M,
      'd': d,
      'dy': dy,
      'dM': dM,
      'dd': dd,
      'start': start,
    };

Map<String, dynamic> dateTime({
  int? y,
  int? M,
  int? d,
  int? h,
  int? m,
  int? s,
  int? ms,
  int dy = 0,
  int dM = 0,
  int dd = 0,
  int dh = 0,
  int dm = 0,
  int ds = 0,
  int dms = 0,
  dynamic start,
}) =>
    {
      ...date(y: y, M: M, d: d, dy: dy, dM: dM, dd: dd, start: start),
      '__class__': 'DateTime',
      'h': h,
      'm': m,
      's': s,
      'ms': ms,
      'dh': dh,
      'dm': dm,
      'ds': ds,
      'dms': dms,
    };

/// SAO's test pattern `new Decoder(ctx).decode(new Encoder().encode(x))`.
dynamic decode(dynamic expr, [Map<String, dynamic> ctx = const {}]) =>
    PYSONEvaluator(ctx).eval(jsonDecode(const PYSONEncoder().encode(expr)));
