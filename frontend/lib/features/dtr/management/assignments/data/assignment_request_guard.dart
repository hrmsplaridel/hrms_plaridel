import 'dart:convert';

class AssignmentRequestToken {
  const AssignmentRequestToken({
    required this.generation,
    required this.querySignature,
  });

  final int generation;
  final String querySignature;
}

class AssignmentRequestGuard {
  int _generation = 0;

  AssignmentRequestToken begin(Map<String, dynamic> query) {
    _generation += 1;
    return AssignmentRequestToken(
      generation: _generation,
      querySignature: _signature(query),
    );
  }

  bool accepts(
    AssignmentRequestToken token,
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
    return jsonEncode(<String, dynamic>{
      for (final key in sortedKeys) key: query[key],
    });
  }
}
