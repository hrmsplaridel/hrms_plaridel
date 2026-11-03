import 'dart:math' as math;

/// Shared logic for screening exam percentages stored in [answers_json].
///
/// Pass/fail uses General + Math + Gen. info only (default 10 + 10 + 5 = 25
/// items; pass at 20 correct / 80%). BEI is scored separately and never
/// enters the overall used for passed/failed.
class RspScreeningScores {
  RspScreeningScores._();

  static const int generalItemCount = 10;
  static const int mathItemCount = 10;
  static const int generalInfoItemCount = 5;
  static const int mcqTotalItems = 25;
  static const int mcqPassingCorrect = 20;

  /// 20 / 25 items.
  static const double mcqPassingPercent = 80.0;

  static const Map<String, int> _defaultItemWeights = {
    'general': generalItemCount,
    'math': mathItemCount,
    'general_info': generalInfoItemCount,
  };

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

  /// Item weight for one MCQ section (actual question count, else default).
  static int mcqSectionWeight(String key, Map<String, dynamic>? section) {
    final fallback = _defaultItemWeights[key] ?? 0;
    if (section == null) return fallback;
    final correctRaw = section['correct'];
    if (correctRaw is List && correctRaw.isNotEmpty) return correctRaw.length;
    final selectedRaw = section['selected'];
    if (selectedRaw is List && selectedRaw.isNotEmpty) {
      return selectedRaw.length;
    }
    return fallback;
  }

  /// Correct answers in one MCQ section, or null if the section has no score.
  static int? mcqSectionCorrectCount(
    String key,
    Map<String, dynamic>? section,
  ) {
    if (section == null) return null;
    final correctRaw = section['correct'];
    final selectedRaw = section['selected'];
    if (correctRaw is List && selectedRaw is List && correctRaw.isNotEmpty) {
      final correct = correctRaw.map(_coerceOptionIndex).toList();
      final selected = selectedRaw.map(_coerceOptionIndex).toList();
      var count = 0;
      for (var i = 0; i < correct.length; i++) {
        final chosen = i < selected.length ? selected[i] : -1;
        if (chosen == correct[i]) count++;
      }
      return count;
    }
    final percent = mcqSectionPercent(section);
    if (percent == null) return null;
    final weight = mcqSectionWeight(key, section);
    if (weight <= 0) return null;
    return ((percent / 100.0) * weight).round().clamp(0, weight);
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

  /// Weighted MCQ overall from section percents (General 10, Math 10, Gen.info 5).
  static double? weightedMcqOverallFromPercents({
    double? general,
    double? math,
    double? generalInfo,
  }) {
    var weighted = 0.0;
    var totalWeight = 0;
    void add(double? percent, int weight) {
      if (percent == null || weight <= 0) return;
      weighted += percent.clamp(0.0, 100.0) * weight;
      totalWeight += weight;
    }

    add(general, generalItemCount);
    add(math, mathItemCount);
    add(generalInfo, generalInfoItemCount);
    if (totalWeight <= 0) return null;
    return weighted / totalWeight;
  }

  /// Overall screening % from General + Math + Gen. info only (BEI excluded).
  /// Weights follow actual item counts when present, else 10 / 10 / 5.
  static double? overallPercent(Map<String, dynamic>? answersJson) {
    if (answersJson == null) return null;
    var correctTotal = 0;
    var itemTotal = 0;
    var sawSection = false;

    for (final key in _defaultItemWeights.keys) {
      final section = _subsection(answersJson, key);
      if (section == null) continue;
      final correct = mcqSectionCorrectCount(key, section);
      if (correct == null) continue;
      sawSection = true;
      correctTotal += correct;
      itemTotal += mcqSectionWeight(key, section);
    }
    if (!sawSection || itemTotal <= 0) return null;
    return (correctTotal / itemTotal) * 100.0;
  }

  /// Pass when MCQ overall is at least 20/25 (80%). BEI does not affect this.
  static bool passedOverall(Map<String, dynamic>? answersJson) {
    final o = overallPercent(answersJson);
    if (o == null) return false;
    return o + 1e-9 >= mcqPassingPercent;
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

  /// Admin override with explicit section scores.
  /// [beiScore] is stored for records only; overall pass uses MCQ sections.
  static Map<String, dynamic> buildAdminExamOverrideAnswersJson({
    required double generalScore,
    required double mathScore,
    required double generalInfoScore,
    required double beiScore,
    int beiQuestionCount = 8,
  }) {
    final g = generalScore.clamp(0.0, 100.0).toDouble();
    final m = mathScore.clamp(0.0, 100.0).toDouble();
    final i = generalInfoScore.clamp(0.0, 100.0).toDouble();
    final b = beiScore.clamp(0.0, 100.0).toDouble();
    final n = beiQuestionCount < 1 ? 8 : beiQuestionCount;
    Map<String, dynamic> mcq(double score) => <String, dynamic>{
      'score': score,
      'passed': score + 1e-9 >= mcqPassingPercent,
      'admin_override': true,
    };
    return {
      'general': mcq(g),
      'math': mcq(m),
      'general_info': mcq(i),
      'bei': {
        'questions': List<String>.filled(n, 'Admin override'),
        'answers': List<String>.filled(n, 'Manually graded by HR'),
        'scores': List<double>.filled(n, b),
        'admin_override': true,
      },
    };
  }
}
