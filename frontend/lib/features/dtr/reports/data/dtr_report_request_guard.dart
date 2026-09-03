class DtrReportRequestToken {
  const DtrReportRequestToken({
    required this.generation,
    required this.employeeId,
    required this.departmentId,
    required this.employeeStatus,
    required this.year,
    required this.month,
  });

  final int generation;
  final String? employeeId;
  final String? departmentId;
  final String employeeStatus;
  final int year;
  final int month;
}

/// Rejects report responses that belong to a superseded filter selection.
class DtrReportRequestGuard {
  int _generation = 0;

  DtrReportRequestToken begin({
    required String? employeeId,
    required String? departmentId,
    required String employeeStatus,
    required int year,
    required int month,
  }) {
    _generation += 1;
    return DtrReportRequestToken(
      generation: _generation,
      employeeId: employeeId,
      departmentId: departmentId,
      employeeStatus: employeeStatus,
      year: year,
      month: month,
    );
  }

  bool accepts(
    DtrReportRequestToken token, {
    required String? employeeId,
    required String? departmentId,
    required String employeeStatus,
    required int year,
    required int month,
  }) {
    return token.generation == _generation &&
        token.employeeId == employeeId &&
        token.departmentId == departmentId &&
        token.employeeStatus == employeeStatus &&
        token.year == year &&
        token.month == month;
  }

  void invalidate() {
    _generation += 1;
  }
}
