class AttendancePolicyRequestToken {
  const AttendancePolicyRequestToken({
    required this.generation,
    required this.status,
  });

  final int generation;
  final String status;
}

class AttendancePolicyRequestGuard {
  int _generation = 0;

  AttendancePolicyRequestToken begin(String status) {
    _generation += 1;
    return AttendancePolicyRequestToken(
      generation: _generation,
      status: status,
    );
  }

  bool accepts(AttendancePolicyRequestToken token, String currentStatus) {
    return token.generation == _generation && token.status == currentStatus;
  }

  void invalidate() {
    _generation += 1;
  }
}
