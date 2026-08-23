class DtrReportRequestToken {
  const DtrReportRequestToken({
    required this.generation,
    required this.employeeId,
    required this.departmentId,
    required this.year,
    required this.month,
  });

  final int generation;
  final String? employeeId;
  final String? departmentId;
  final int year;
  final int month;
}

/// Rejects report responses that belong to a superseded filter selection.
class DtrReportRequestGuard {
  int _generation = 0;

  DtrReportRequestToken begin({
    required String? employeeId,
    required String? departmentId,
    required int year,
    required int month,
  }) {
    _generation += 1;
    return DtrReportRequestToken(
      generation: _generation,
      employeeId: employeeId,
      departmentId: departmentId,
      year: year,
      month: month,
    );
  }

  bool accepts(
    DtrReportRequestToken token, {
    required String? employeeId,
    required String? departmentId,
    required int year,
    required int month,
  }) {
    return token.generation == _generation &&
        token.employeeId == employeeId &&
        token.departmentId == departmentId &&
        token.year == year &&
        token.month == month;
  }

  void invalidate() {
    _generation += 1;
  }
}
