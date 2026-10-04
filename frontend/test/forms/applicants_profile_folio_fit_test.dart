import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';

import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/learning_development/models/applicants_profile.dart';

class _NoRasterPrinting extends PrintingPlatform {
  @override
  Stream<PdfRaster> raster(
    Uint8List document,
    List<int>? pages,
    double dpi,
  ) async* {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousPrinting = PrintingPlatform.instance;
  final previousFit = FormPdf.fitToPrintableArea;

  setUp(() {
    PrintingPlatform.instance = _NoRasterPrinting();
    FormPdf.fitToPrintableArea = true;
  });

  tearDown(() {
    PrintingPlatform.instance = previousPrinting;
    FormPdf.fitToPrintableArea = previousFit;
  });

  test('Applicants Profile fills the Folio landscape safe area', () async {
    final document = await FormPdf.buildApplicantsProfilePdf(
      ApplicantsProfileEntry(
        positionAppliedFor: 'Nurse I',
        applicants: [
          for (var i = 0; i < 10; i++)
            ApplicantsProfileApplicant(name: 'Applicant $i'),
        ],
      ),
    );
    final bytes = await document.save();
    final raw = latin1.decode(bytes, allowInvalid: true);
    expect(RegExp(r'/Type\s*/Page(?!s)').allMatches(raw).length, 1);
    expect(raw, contains('/MediaBox[0 0 935.43307 612.28346]'));

    final text = _inflateStreams(bytes, raw);
    const pt = 72 / 25.4;
    final pageW = 330 * pt;
    final pageH = 216 * pt;
    final left = 5 * pt;
    final right = 5 * pt;
    final top = 5 * pt;
    final bottom = 7 * pt;
    final availW = pageW - left - right;
    final availH = pageH - top - bottom;
    final scale = math.min(availW / pageW, availH / pageH);
    final renderedW = pageW * scale;
    final renderedH = pageH * scale;
    final offsetX = left + (availW - renderedW) / 2;
    final offsetY = bottom + (availH - renderedH) / 2;
    final rightGap = pageW - offsetX - renderedW;
    expect((offsetX - rightGap).abs(), lessThan(0.05));
    expect(text, contains(_cm(1, 0, 0, 1, offsetX, offsetY)));
    expect(text, contains('${_num(scale)} 0 0 ${_num(scale)}'));
    expect(text, contains('0 0 ${_num(renderedW)} ${_num(renderedH)} re'));
    expect(renderedH, closeTo(availH, 0.05));
  });
}

String _num(double value) {
  var text = value.toStringAsFixed(5);
  while (text.contains('.') && text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text;
}

String _cm(double a, double b, double c, double d, double e, double f) =>
    '${_num(a)} ${_num(b)} ${_num(c)} ${_num(d)} ${_num(e)} ${_num(f)} cm';

String _inflateStreams(Uint8List bytes, String raw) {
  final out = StringBuffer();
  final streamRe = RegExp(r'stream\r?\n');
  for (final match in streamRe.allMatches(raw)) {
    final start = match.end;
    final end = raw.indexOf('endstream', start);
    if (end < 0) continue;
    try {
      out.write(
        latin1.decode(
          zlib.decode(bytes.sublist(start, end)),
          allowInvalid: true,
        ),
      );
    } catch (_) {}
  }
  return out.toString();
}
