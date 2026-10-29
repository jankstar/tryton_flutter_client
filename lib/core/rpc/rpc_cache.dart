import 'dart:collection';

/// Cache of RPC results (spec 2.7, SAO `Session.cache`, Python client
/// `rpc.cache`): the server marks cacheable read methods with the header
/// `X-Tryton-Cache: <seconds>`; the response is kept per (method,
/// parameters) until it expires. Only methods that came with the header
/// once are looked up.
class RpcCache {
  /// Entries in total (GTK `rpc.cache_size`); the oldest go first.
  final int maxSize;

  /// Current time (replaceable in tests).
  final DateTime Function() _now;

  RpcCache({this.maxSize = 1024, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// method → (key → entry); insertion order = age.
  final Map<String, LinkedHashMap<String, _Entry>> _store = {};
  int _size = 0;

  /// The method came with a cache header once.
  bool cached(String method) => _store.containsKey(method);

  /// Response body of [method] with the parameters [key], or null when
  /// missing or expired.
  String? get(String method, String key) {
    final entries = _store[method];
    final entry = entries?[key];
    if (entry == null) return null;
    if (!entry.expire.isAfter(_now())) {
      entries!.remove(key);
      _size--;
      return null;
    }
    return entry.body;
  }

  /// Keeps [body] for [seconds].
  void set(String method, String key, int seconds, String body) {
    final entries = _store.putIfAbsent(method, LinkedHashMap.new);
    if (entries.remove(key) != null) _size--;
    entries[key] =
        _Entry(_now().add(Duration(seconds: seconds)), body);
    _size++;
    while (_size > maxSize) {
      _evictOldest();
    }
  }

  void _evictOldest() {
    String? oldestMethod;
    String? oldestKey;
    int? oldest;
    for (final MapEntry(key: method, value: entries) in _store.entries) {
      if (entries.isEmpty) continue;
      final first = entries.entries.first;
      if (oldest == null || first.value.created < oldest) {
        oldest = first.value.created;
        oldestMethod = method;
        oldestKey = first.key;
      }
    }
    if (oldestMethod == null) return;
    _store[oldestMethod]!.remove(oldestKey);
    _size--;
  }

  /// Removes the methods starting with [prefix] (all without prefix),
  /// e.g. `model.party.party.view_toolbar_get` after an export was saved
  /// or `model.ir.ui.view_tree_state.get` (Python `clear_cache(prefix)`).
  void clear([String? prefix]) {
    if (prefix == null) {
      _store.clear();
      _size = 0;
      return;
    }
    _store.removeWhere((method, entries) {
      if (!method.startsWith(prefix)) return false;
      _size -= entries.length;
      return true;
    });
  }

  int get length => _size;
}

class _Entry {
  static int _counter = 0;
  final DateTime expire;
  final String body;

  /// Age order across methods.
  final int created = _counter++;
  _Entry(this.expire, this.body);
}
