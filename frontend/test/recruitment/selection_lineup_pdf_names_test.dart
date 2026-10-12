import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selection line-up PDF does not invent an official name or title', () {
    final source = File('lib/core/utils/form_pdf.dart').readAsStringSync();
    final start = source.indexOf(
      'static Future<pw.Document> buildSelectionLineupPdf',
    );
    final end = source.indexOf(
      'static Future<pw.Document> buildComputationOfPointsPdf',
    );
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final body = source.substring(start, end);
    expect(body.contains('MARCELO'), isFalse);
    expect(body.contains('CAÑARES'), isFalse);
    expect(body.contains('Administrative Officer V'), isFalse);
    expect(body.contains('HRMDO'), isFalse);
    expect(body.contains('_signatureName'), isTrue);
    expect(body.contains('_signatureImage'), isTrue);
  });
}