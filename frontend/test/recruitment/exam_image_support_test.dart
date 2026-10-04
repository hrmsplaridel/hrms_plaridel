import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/recruitment/data/exam_image_support.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/widgets/rsp_applicant_exam_ui.dart';

const _img = 'exam-images/3f2b1c4e-1111-4222-8333-444455556666.png';

void main() {
  group('exam image helpers', () {
    test('examQuestionHasImages is false for legacy text-only questions', () {
      expect(
        examQuestionHasImages({
          'question_text': '2 + 2',
          'options': ['3', '4'],
          'correct': 1,
        }),
        isFalse,
      );
      expect(
        examQuestionHasImages({
          'question_text': 'x',
          'options': ['a', 'b'],
          'option_images': [null, null],
        }),
        isFalse,
      );
    });

    test('examQuestionHasImages detects question and choice images', () {
      expect(examQuestionHasImages({'question_image': _img}), isTrue);
      expect(
        examQuestionHasImages({
          'option_images': [null, _img],
        }),
        isTrue,
      );
    });

    test('examOptionImagesFrom aligns to the option count', () {
      expect(examOptionImagesFrom(null, 3), [null, null, null]);
      expect(examOptionImagesFrom([null, _img], 3), [null, _img, null]);
      expect(examOptionImagesFrom([_img, _img, _img, _img], 2), [_img, _img]);
    });

    test('examImageUrl builds a public file URL from the stored path', () {
      expect(examImageUrl(null), '');
      expect(
        examImageUrl(_img),
        endsWith('/api/files/exam-image/3f2b1c4e-1111-4222-8333-444455556666.png'),
      );
    });

    test('validateExamImage rejects bad type, empty, oversized and corrupt', () async {
      expect(
        await validateExamImage(bytes: Uint8List(10), fileName: 'a.gif'),
        contains('Unsupported'),
      );
      expect(
        await validateExamImage(bytes: Uint8List(0), fileName: 'a.png'),
        contains('empty'),
      );
      expect(
        await validateExamImage(
          bytes: Uint8List(kExamImageMaxBytes + 1),
          fileName: 'a.png',
        ),
        contains('too large'),
      );
      expect(
        await validateExamImage(
          bytes: Uint8List.fromList(List.filled(64, 7)),
          fileName: 'a.png',
        ),
        contains('corrupted'),
      );
    });
  });

  group('RspApplicantMcqQuestionCard', () {
    Future<void> pump(
      WidgetTester tester, {
      required double width,
      required List<String> options,
      required List<String?> optionImages,
      String? questionImage,
      String text = 'Which figure is next?',
      int selected = -1,
      ValueChanged<int>? onSelect,
    }) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: RspApplicantMcqQuestionCard(
                  index: 0,
                  questionText: text,
                  options: options,
                  selectedIndex: selected,
                  onSelect: onSelect ?? (_) {},
                  questionImage: questionImage,
                  questionImageCaption: questionImage == null
                      ? null
                      : 'Figure 1',
                  optionImages: optionImages,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('text-only question keeps the classic list tiles', (
      tester,
    ) async {
      await pump(
        tester,
        width: 600,
        options: ['3', '4', '5', '6'],
        optionImages: const [],
      );
      expect(find.byType(RspApplicantMcqOptionTile), findsNWidgets(4));
      expect(find.byType(RspApplicantMcqImageOptionTile), findsNothing);
    });

    for (final width in [360.0, 800.0, 1200.0]) {
      testWidgets('image choices render without overflow at $width px', (
        tester,
      ) async {
        await pump(
          tester,
          width: width,
          text: '',
          questionImage: _img,
          options: ['10', '', '', 'None of these'],
          optionImages: [null, _img, _img, null],
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(RspApplicantMcqImageOptionTile), findsNWidgets(4));
        expect(find.text('Figure 1'), findsOneWidget);
      });
    }

    testWidgets('tapping an image choice reports its own index', (
      tester,
    ) async {
      int? picked;
      await pump(
        tester,
        width: 800,
        options: ['', '', '', ''],
        optionImages: [_img, _img, _img, _img],
        onSelect: (j) => picked = j,
      );
      await tester.tap(find.byType(RspApplicantMcqImageOptionTile).at(2));
      expect(picked, 2);
    });
  });
}
