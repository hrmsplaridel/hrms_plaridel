import 'dart:math' as math;

/// Shared logic for screening exam percentages stored in [answers_json].
class RspScreeningScores {
  RspScreeningScores._();

  static int _coerceOptionIndex(dynamic e) {
    if (e is int) return e;
    if (e is num) return e.toInt();
    return int.tryParse(e.toString()) ?? -1;
  }

  /// MCQ section map: uses `selected` vs `correct`, else falls back to `score`.
  static double? mcqSectionPercent(Map<String, dynamic>? section) {
    if (section == null) return null;
    final correctRaw = section['correct'];
    final selectedRaw = section['selected'];
    if (correctRaw is List && selectedRaw is List && correctRaw.isNotEmpty) {
      final correct = correctRaw.map(_coerceOptionIndex).toList();
      final selected = selectedRaw.map(_coerceOptionIndex).toList();
      int correctCount = 0;
      for (int i = 0; i < correct.length; i++) {
        final chosen = i < selected.length ? selected[i] : -1;
        if (chosen == correct[i]) correctCount++;
      }
      return (correctCount / correct.length) * 100.0;
    }
    final stored = section['score'];
    if (stored is num) return stored.toDouble();
    return double.tryParse(stored?.toString() ?? '');
  }

  /// True if there is no BEI narrative to grade, or every BEI answer has an HR score.
  static bool isBeiFullyGraded(Map<String, dynamic>? answersJson) {
    if (answersJson == null || answersJson.isEmpty) return true;
    final bei = _subsection(answersJson, 'bei');
    if (bei == null) return true;
    final answers = bei['answers'];
    if (answers is! List || answers.isEmpty) return true;
    return beiSectionPercent(bei) != null;
  }

  /// BEI average when every question has a numeric score in [0, 100].
  static double? beiSectionPercent(Map<String, dynamic>? bei) {
    if (bei == null) return null;
    final scoresRaw = bei['scores'];
    if (scoresRaw is! List || scoresRaw.isEmpty) return null;
    final answersRaw = bei['answers'];
    final nAnswers = answersRaw is List ? answersRaw.length : scoresRaw.length;
    if (scoresRaw.length != nAnswers) return null;
    double sum = 0;
    for (final s in scoresRaw) {
      if (s == null) return null;
      final v = double.tryParse(s.toString());
      if (v == null) return null;
      sum += v.clamp(0.0, 100.0);
    }
    return sum / scoresRaw.length;
  }

  /// Overall screening %: unweighted mean of available machine sections plus BEI when fully graded.
  static double? overallPercent(Map<String, dynamic>? answersJson) {
    if (answersJson == null) return null;
    final parts = <double>[];
    final g = mcqSectionPercent(_subsection(answersJson, 'general'));
    final m = mcqSectionPercent(_subsection(answersJson, 'math'));
    final i = mcqSectionPercent(_subsection(answersJson, 'general_info'));
    final b = beiSectionPercent(_subsection(answersJson, 'bei'));
    if (g != null) parts.add(g);
    if (m != null) parts.add(m);
    if (i != null) parts.add(i);
    if (b != null) parts.add(b);
    if (parts.isEmpty) return null;
    return parts.reduce((a, c) => a + c) / parts.length;
  }

  static bool passedOverall(Map<String, dynamic>? answersJson) {
    final o = overallPercent(answersJson);
    if (o == null) return false;
    return o >= 60.0;
  }

  static Map<String, dynamic>? _subsection(
    Map<String, dynamic> answersJson,
    String key,
  ) {
    final v = answersJson[key];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  /// Clamp and round for display / API (1 decimal).
  static double roundOverall(double v) =>
      (math.min(100, math.max(0, v)) * 10).roundToDouble() / 10.0;

  /// Perfect scores for all four screening sections when HR bypasses the exam.
  static Map<String, dynamic> buildAdminExamBypassAnswersJson({
    int beiQuestionCount = 8,
  }) {
    const perfect = 100.0;
    final n = beiQuestionCount < 1 ? 8 : beiQuestionCount;
    final section = <String, dynamic>{
      'score': perfect,
      'passed': true,
      'admin_override': true,
    };
    return {
      'general': Map<String, dynamic>.from(section),
      'math': Map<String, dynamic>.from(section),
      'general_info': Map<String, dynamic>.from(section),
      'bei': {
        'questions': List<String>.filled(n, 'Admin bypass'),
        'answers': List<String>.filled(n, 'Admin bypass — waived by HR'),
        'scores': List<double>.filled(n, perfect),
        'admin_override': true,
      },
    };
  }
}
