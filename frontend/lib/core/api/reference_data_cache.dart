/// Shares reference fetches and prevents invalidated responses from being reused.
class ReferenceDataCache<K, T> {
  ReferenceDataCache({required this.ttl});

  final Duration ttl;
  final Map<K, (T, DateTime)> _values = {};
  final Map<K, Future<T>> _pending = {};
  int _generation = 0;

  Future<T> get(
    K key,
    Future<T> Function() load, {
    bool forceRefresh = false,
  }) async {
    while (true) {
      final cached = _values[key];
      if (!_pending.containsKey(key) &&
          !forceRefresh &&
          cached != null &&
          DateTime.now().difference(cached.$2) < ttl) {
        return cached.$1;
      }
      final generation = _generation;
      final future = _pending[key] ??= load();
      try {
        final value = await future;
        if (generation == _generation) {
          _values[key] = (value, DateTime.now());
          return value;
        }
      } catch (_) {
        if (generation == _generation) rethrow;
      } finally {
        if (generation == _generation && identical(_pending[key], future)) {
          _pending.remove(key);
        }
      }
      // Invalidation superseded this fetch; join the current generation.
      forceRefresh = false;
    }
  }

  void invalidate() {
    _generation++;
    _values.clear();
    _pending.clear();
  }
}
