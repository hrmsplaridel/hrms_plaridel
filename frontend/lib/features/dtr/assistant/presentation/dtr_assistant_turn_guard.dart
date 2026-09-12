class DtrAssistantTurnGuard {
  int _generation = 0;

  int begin() => ++_generation;

  void invalidate() {
    _generation += 1;
  }

  bool isCurrent(int generation) => generation == _generation;
}
