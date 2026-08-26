import 'dart:convert';

class EmployeeListRequestToken {
  const EmployeeListRequestToken({
    required this.generation,
    required this.querySignature,
  });

  final int generation;
  final String querySignature;
}

class EmployeeListRequestGuard {
  int _generation = 0;

  EmployeeListRequestToken begin(Map<String, dynamic> query) {
    _generation += 1;
    return EmployeeListRequestToken(
      generation: _generation,
      querySignature: _signature(query),
    );
  }

  bool accepts(
    EmployeeListRequestToken token,
    Map<String, dynamic> currentQuery,
  ) {
    return token.generation == _generation &&
        token.querySignature == _signature(currentQuery);
  }

  void invalidate() {
    _generation += 1;
  }

  String _signature(Map<String, dynamic> query) {
    final sortedKeys = query.keys.toList()..sort();
    final normalized = <String, dynamic>{
      for (final key in sortedKeys) key: query[key],
    };
    return jsonEncode(normalized);
  }
}
