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
  final Map<String, String> _cursors = {};
  final Map<String, Future<Map<String, Map<String, dynamic>>>> _more = {};
  int _generation = 0;
  int _session = 0;

  Future<Map<String, Map<String, dynamic>>> get(
    String kind,
    Future<dynamic> Function() load, {
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

      if (_pending == null) {
        _generation++;
        _more.clear();
      }
      final generation = _generation;
      final pending = _pending ??= Future<dynamic>.sync(load).then((data) {
        if (generation != _generation || session != _session) {
          return <dynamic>[];
        }
        final rows = _pageRows(data);
        final cursors = _pageCursors(data);
        _cursors
          ..clear()
          ..addAll(cursors);
        return rows;
      });
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
    _cursors.clear();
    _more.clear();
  }

  bool hasMore(String kind) => _cursors.containsKey(kind);

  Future<Map<String, Map<String, dynamic>>> loadMore(
    String kind,
    Future<dynamic> Function(String cursor) load,
  ) {
    if (_pending != null) {
      final session = _session;
      return _pending!.then((_) {
        if (session != _session) {
          throw StateError('The approval inbox session changed.');
        }
        return loadMore(kind, load);
      });
    }
    final existing = _more[kind];
    if (existing != null) return existing;
    final cursor = _cursors[kind];
    if (cursor == null) return Future.value(_forKind(_rows ?? [], kind));
    final generation = _generation, session = _session;
    late final Future<Map<String, Map<String, dynamic>>> pending;
    pending = Future<dynamic>.sync(() => load(cursor))
        .then((data) {
          if (generation != _generation || session != _session) {
            throw StateError(
              'The approval inbox changed. Refresh before loading more.',
            );
          }
          final pageRows = _pageRows(data);
          final cursors = _pageCursors(data);
          if (cursors[kind] == cursor) {
            throw const FormatException('Approval pagination did not advance.');
          }
          final merged = <String, dynamic>{
            for (final row in [...?_rows, ...pageRows].whereType<Map>())
              '${row['kind']}/${row['id']}': _copy(row),
          };
          _rows = merged.values.toList();
          _cursors.remove(kind);
          if (cursors[kind] != null) _cursors[kind] = cursors[kind]!;
          return _forKind(_rows!, kind);
        })
        .whenComplete(() {
          if (identical(_more[kind], pending)) _more.remove(kind);
        });
    _more[kind] = pending;
    return pending;
  }

  static List<dynamic> _pageRows(dynamic data) {
    if (data is List) return List<dynamic>.from(data);
    if (data is Map && data['items'] is List) {
      return List<dynamic>.from(data['items']);
    }
    throw const FormatException('Invalid approval inbox response.');
  }

  static Map<String, String> _pageCursors(dynamic data) {
    if (data is! Map) return {};
    final result = <String, String>{};
    final cursors = data['next_cursor'];
    final more = data['has_more'];
    if (cursors is! Map || more is! Map) {
      throw const FormatException('Missing approval pagination.');
    }
    for (final kind in ['leave', 'locator']) {
      if (more[kind] != true) continue;
      final cursor = cursors[kind];
      if (cursor is! String || cursor.isEmpty) {
        throw const FormatException('Invalid approval pagination cursor.');
      }
      result[kind] = cursor;
    }
    return result;
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
