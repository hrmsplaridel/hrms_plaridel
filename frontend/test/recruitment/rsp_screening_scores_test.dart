import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/recruitment/models/rsp_screening_scores.dart';

void main() {
  group('RspScreeningScores MCQ overall', () {
    test('weights General 10 + Math 10 + Gen.info 5 and excludes BEI', () {
      final answers = {
        'general': {
          'correct': List<int>.filled(10, 0),
          'selected': List<int>.filled(10, 0), // 10/10
        },
        'math': {
          'correct': List<int>.filled(10, 0),
          'selected': [...List<int>.filled(8, 0), 1, 1], // 8/10
        },
        'general_info': {
          'correct': List<int>.filled(5, 0),
          'selected': [...List<int>.filled(2, 0), 1, 1, 1], // 2/5
        },
        'bei': {
          'answers': ['a', 'b'],
          'scores': [100.0, 100.0],
        },
      };

      // 10 + 8 + 2 = 20 / 25 = 80%
      expect(RspScreeningScores.overallPercent(answers), closeTo(80.0, 0.01));
      expect(RspScreeningScores.passedOverall(answers), isTrue);
      expect(RspScreeningScores.beiSectionPercent(answers['bei']!), 100.0);
    });

    test('fails below 20 of 25 even with perfect BEI', () {
      final answers = {
        'general': {
          'correct': List<int>.filled(10, 0),
          'selected': List<int>.filled(10, 0), // 10
        },
        'math': {
          'correct': List<int>.filled(10, 0),
          'selected': [...List<int>.filled(7, 0), 1, 1, 1], // 7
        },
        'general_info': {
          'correct': List<int>.filled(5, 0),
          'selected': [...List<int>.filled(2, 0), 1, 1, 1], // 2
        },
        'bei': {
          'answers': ['a'],
          'scores': [100.0],
        },
      };

      // 19/25 = 76%
      expect(RspScreeningScores.overallPercent(answers), closeTo(76.0, 0.01));
      expect(RspScreeningScores.passedOverall(answers), isFalse);
    });

    test('weighted percents match item weights without BEI', () {
      final overall = RspScreeningScores.weightedMcqOverallFromPercents(
        general: 100,
        math: 80,
        generalInfo: 40,
      );
      // (100*10 + 80*10 + 40*5) / 25 = 80
      expect(overall, closeTo(80.0, 0.01));
    });
  });
}
