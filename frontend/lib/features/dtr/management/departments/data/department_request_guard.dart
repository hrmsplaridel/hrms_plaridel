class DepartmentRequestToken {
  const DepartmentRequestToken({
    required this.generation,
    required this.status,
  });

  final int generation;
  final String status;
}

class DepartmentRequestGuard {
  int _generation = 0;

  DepartmentRequestToken begin(String status) {
    _generation += 1;
    return DepartmentRequestToken(generation: _generation, status: status);
  }

  bool accepts(DepartmentRequestToken token, String currentStatus) {
    return token.generation == _generation && token.status == currentStatus;
  }

  void invalidate() {
    _generation += 1;
  }
}
