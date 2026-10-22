/// One short-lived inbox for Leave and Locator within the current login session.
/// Cached rows are display data; the backend still authorizes every decision.
class WorkflowInboxCache {
  WorkflowInboxCache({
    this.ttl = const Duration(seconds: 15),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static final instance = WorkflowInboxCache();

  final Duration ttl;
  final DateTime Function() _now;
  List<dynamic>? _rows;
  DateTime? _loadedAt;
  Future<List<dynamic>>? _pending;
  int _generation = 0;
  int _session = 0;

  Future<Map<String, Map<String, dynamic>>> get(
    String kind,
    Future<List<dynamic>> Function() load, {
    bool forceRefresh = false,
  }) async {
    final session = _session;
    while (true) {
      if (session != _session) {
        throw StateError('The approval inbox session changed.');
      }
      if (_pending == null &&
          !forceRefresh &&
          _rows != null &&
          _now().difference(_loadedAt!) < ttl) {
        return _forKind(_rows!, kind);
      }

      final generation = _generation;
      final pending = _pending ??= Future<List<dynamic>>.sync(load);
      try {
        final rows = await pending;
        if (session != _session) {
          throw StateError('The approval inbox session changed.');
        }
        if (generation == _generation) {
          _rows = _copy(rows) as List<dynamic>;
          _loadedAt = _now();
          return _forKind(_rows!, kind);
        }
      } catch (_) {
        if (session != _session || generation == _generation) rethrow;
      } finally {
        if (identical(_pending, pending)) _pending = null;
      }
      // A mutation/event superseded this response. Share the newer fetch.
      forceRefresh = false;
    }
  }

  void invalidate() {
    _generation++;
    _rows = null;
    _loadedAt = null;
    _pending = null;
  }

  /// Unlike data invalidation, an account change must terminate old readers.
  void clearSession() {
    _session++;
    invalidate();
  }

  void invalidateAfterResponse(String method, String path, int? status) {
    if (const ['GET', 'HEAD', 'OPTIONS'].contains(method.toUpperCase())) return;
    if (status == null || (!(status >= 200 && status < 300) && status != 409)) {
      return;
    }
    final route = Uri.parse(path).path;
    if (_workflowMutation.hasMatch(route)) invalidate();
  }

  static final _workflowMutation = RegExp(
    r'^/api/(approval-workflows|leave(?:-[^/]+)?|locator-slips|departments|'
    r'assignments|employees|users|dtr-access|primary-reviewer-designations|'
    r'docutracker/official-signatories)(/|$)',
  );

  static Map<String, Map<String, dynamic>> _forKind(
    List<dynamic> rows,
    String kind,
  ) => {
    for (final row in rows.whereType<Map>())
      if (row['kind'] == kind)
        row['id'].toString(): _copy(row) as Map<String, dynamic>,
  };

  static dynamic _copy(dynamic value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _copy(entry.value),
      };
    }
    if (value is List) return value.map(_copy).toList();
    return value;
  }
}
