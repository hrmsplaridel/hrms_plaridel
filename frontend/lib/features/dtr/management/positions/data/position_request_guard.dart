import 'dart:convert';

class PositionRequestToken {
  const PositionRequestToken({
    required this.generation,
    required this.querySignature,
  });

  final int generation;
  final String querySignature;
}

class PositionRequestGuard {
  int _generation = 0;

  PositionRequestToken begin(Map<String, dynamic> query) {
    _generation += 1;
    return PositionRequestToken(
      generation: _generation,
      querySignature: _signature(query),
    );
  }

  bool accepts(PositionRequestToken token, Map<String, dynamic> currentQuery) {
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
