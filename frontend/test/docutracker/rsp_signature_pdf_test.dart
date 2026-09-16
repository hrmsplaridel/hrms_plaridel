import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';

import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/learning_development/models/action_brainstorming_coaching.dart';
import 'package:hrms_plaridel/features/learning_development/models/applicants_profile.dart';
import 'package:hrms_plaridel/features/learning_development/models/computation_of_points.dart';
import 'package:hrms_plaridel/features/learning_development/models/individual_development_plan.dart';
import 'package:hrms_plaridel/features/learning_development/models/selection_lineup.dart';
import 'package:hrms_plaridel/features/learning_development/models/turn_around_time.dart';
import 'package:hrms_plaridel/features/learning_development/models/work_experience_sheet.dart';

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

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

DocuTrackerSourceSignatureBundle _signatures(
  String table,
  List<String> slots, {
  String sourceModule = 'rsp',
}) {
  return DocuTrackerSourceSignatureBundle.fromJson(<String, dynamic>{
    'source_module': sourceModule,
    'source_table': table,
    'source_record_id': '11111111-1111-4111-8111-111111111111',
    'source_status': 'saved',
    'signatures': slots
        .map(
          (slot) => <String, dynamic>{
            'slot_key': slot,
            'label': slot,
            'assigned_signer_id': '22222222-2222-4222-8222-222222222222',
            'can_sign': true,
            'signature_asset_id': '33333333-3333-4333-8333-333333333333',
            'signature_image_base64': _onePixelPng,
            'mime_type': 'image/png',
            'signed_by': '22222222-2222-4222-8222-222222222222',
            'signer_name_snapshot': 'Verified Signer',
            'signed_at': '2026-09-16T01:00:00.000Z',
          },
        )
        .toList(growable: false),
  });
}

Future<void> _expectPdf(Future<pw.Document> documentFuture) async {
  final document = await documentFuture;
  final bytes = await document.save();
  expect(bytes.length, greaterThan(500));
  expect(ascii.decode(bytes.take(4).toList()), '%PDF');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all supported RSP forms generate PDFs with persisted signatures',
    () async {
      await _expectPdf(
        FormPdf.buildApplicantsProfilePdf(
          ApplicantsProfileEntry.fromJson(<String, dynamic>{
            'position_applied_for': 'Administrative Officer',
            'applicants': <dynamic>[],
            'prepared_by': 'Prepared Person',
            'checked_by': 'Checking Person',
          }),
          signatures: _signatures(ApplicantsProfileEntry.tableName, const [
            'prepared_by',
            'checked_by',
          ]),
        ),
      );

      await _expectPdf(
        FormPdf.buildSelectionLineupPdf(
          SelectionLineupEntry.fromJson(<String, dynamic>{
            'vacant_position': 'Administrative Officer',
            'applicants': <dynamic>[],
            'prepared_by_name': 'Prepared Person',
          }),
          signatures: _signatures(SelectionLineupEntry.tableName, const [
            'prepared_by',
          ]),
        ),
      );

      await _expectPdf(
        FormPdf.buildComputationOfPointsPdf(
          ComputationOfPointsEntry.fromJson(<String, dynamic>{
            'position': 'Administrative Officer',
            'candidates': <dynamic>[],
            'prepared_by_name': 'Prepared Person',
          }),
          signatures: _signatures(ComputationOfPointsEntry.tableName, const [
            'prepared_by',
          ]),
        ),
      );

      await _expectPdf(
        FormPdf.buildWorkExperienceSheetPdf(
          WorkExperienceSheetEntry.fromJson(<String, dynamic>{
            'position_applied_for': 'Administrative Officer',
            'applicant_name': 'Applicant Person',
          }),
          signatures: _signatures(WorkExperienceSheetEntry.tableName, const [
            'applicant',
          ]),
        ),
      );

      await _expectPdf(
        FormPdf.buildTurnAroundTimePdf(
          TurnAroundTimeEntry.fromJson(<String, dynamic>{
            'position': 'Administrative Officer',
            'applicants': <dynamic>[],
            'prepared_by_name': 'Prepared Person',
            'noted_by_name': 'Noting Person',
          }),
          signatures: _signatures(TurnAroundTimeEntry.tableName, const [
            'prepared_by',
            'noted_by',
          ]),
        ),
      );
    },
  );

  test('supported L&D forms generate PDFs with persisted signatures', () async {
    final previousPrinting = PrintingPlatform.instance;
    PrintingPlatform.instance = _NoRasterPrinting();
    addTearDown(() => PrintingPlatform.instance = previousPrinting);

    await _expectPdf(
      FormPdf.buildIdpPdf(
        IdpEntry.fromJson(<String, dynamic>{
          'name': 'Employee Person',
          'position': 'Administrative Officer',
          'department': 'Human Resource Management',
          'development_plan_rows': <dynamic>[],
          'prepared_by': 'Prepared Person',
          'reviewed_by': 'Reviewing Person',
          'noted_by': 'Noting Person',
          'approved_by': 'Approving Person',
        }),
        signatures: _signatures(IdpEntry.tableName, const [
          'prepared_by',
          'reviewed_by',
          'noted_by',
          'approved_by',
        ], sourceModule: 'ld'),
      ),
    );

    await _expectPdf(
      FormPdf.buildActionBrainstormingCoachingPdf(
        ActionBrainstormingEntry.fromJson(<String, dynamic>{
          'department': 'Human Resource Management',
          'date': '2026-09-16',
          'rows': <dynamic>[],
          'certified_by': 'Department Head',
        }),
        signatures: _signatures(ActionBrainstormingEntry.tableName, const [
          'certified_by',
        ], sourceModule: 'ld'),
      ),
    );
  });
}
