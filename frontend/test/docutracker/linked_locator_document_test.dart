import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_document_detail_screen.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/pages/docutracker_documents_screen.dart';
import 'package:hrms_plaridel/features/docutracker/models/document_status.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_source_status_text.dart';

class _Auth extends AuthProvider {
  @override
  AppUser get user => const AppUser(
    id: 'viewer',
    email: 'viewer@test.invalid',
    role: 'employee',
  );
}

class _Documents extends DocuTrackerProvider {
  static int signatureReads = 0;
  @override
  Future<DocuTrackerSourceSignatureBundle?> loadSourceSignatures({
    required String sourceModule,
    required String sourceTable,
    required String sourceRecordId,
  }) async {
    signatureReads++;
    return DocuTrackerSourceSignatureBundle(
      sourceModule: sourceModule,
      sourceTable: sourceTable,
      sourceRecordId: sourceRecordId,
      sourceStatus: 'approved',
      signatures: const [],
    );
  }
}

const document = DocuTrackerDocument(
  id: 'source:dtr:locator-1',
  documentType: 'dtr',
  title: 'Official Business',
  createdBy: 'owner',
  sourceOnly: true,
  sourceModule: 'dtr',
  sourceTable: 'locator_slips',
  sourceRecordId: 'locator-1',
  sourceStatus: 'revoked',
);

void main() {
  setUpAll(() => ApiClient.instance.init());
  setUp(() => _Documents.signatureReads = 0);
  tearDown(() => ApiClient.instance.dio.interceptors.clear());
  test('Locator revoked and correction states retain their source wording', () {
    expect(docuTrackerSourceBadgeLabel(document), 'Revoked');
    expect(
      docuTrackerSourceBadgeLabel(
        document.copyWith(sourceStatus: 'returned_for_correction'),
      ),
      'Needs correction',
    );
  });
  testWidgets(
    'Required actions distinguish Locator from Leave and open the selected source',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final locator = document.copyWith(
        title: 'Locator review',
        status: DocumentStatus.inReview,
        sourceStatus: 'pending_hr',
        sourceAction: 'review_locator_in_dtr',
        sourceActionLabel: 'Review in Locator',
      );
      final leave = document.copyWith(
        id: 'leave',
        title: 'Leave review',
        sourceTable: 'leave_requests',
        sourceAction: 'hr_review_in_dtr',
        sourceActionLabel: 'Review in DTR',
      );
      String? opened;
      await tester.pumpWidget(
        ChangeNotifierProvider<DocuTrackerProvider>(
          create: (_) => _Documents(),
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DocuTrackerRequiredActionsPanel(
                  documents: [locator, leave],
                  sourceRequests: const [],
                  loading: false,
                  hasPartialError: false,
                  currentUserId: 'viewer',
                  onRefreshSignatures: () async {},
                  onDocumentTap: (doc) async {
                    opened = doc.sourceTable;
                    return true;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('DTR · Locator'), findsOneWidget);
      expect(find.text('DTR · Leave'), findsOneWidget);
      await tester.tap(find.text('Locator review'));
      await tester.pumpAndSettle();
      expect(opened, 'locator_slips');
    },
  );
  testWidgets(
    'Locator details load the real workflow and audit trail instead of native document routing',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final paths = <String>[];
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            paths.add(o.path);
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {
                  'steps': [
                    {
                      'step_order': 1,
                      'label': 'Specific Locator Reviewer',
                      'indicator': {'kind': 'approved', 'label': 'APPROVED'},
                      'reviewers': [
                        {
                          'id': 'reviewer',
                          'name': 'Ben Reviewer',
                          'role': 'actual_reviewer',
                        },
                      ],
                    },
                  ],
                  'history': [
                    {
                      'id': 'h1',
                      'document_id': document.id,
                      'action': 'approved',
                      'actor_name': 'Ben Reviewer',
                      'to_status': 'approved',
                      'created_at': '2026-11-04T01:00:00Z',
                    },
                  ],
                  'request_data': {
                    'employee_name': 'Ana Employee',
                    'slip_date': '2026-11-04',
                    'office': 'Municipal Hall',
                    'reason': 'Official transaction',
                    'attachment_name': 'SignedOriginal.pdf',
                  },
                },
              ),
            );
          },
        ),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
            ChangeNotifierProvider<DocuTrackerProvider>(
              create: (_) => _Documents(),
            ),
          ],
          child: const MaterialApp(
            home: DocuTrackerDocumentDetailScreen(document: document),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        paths,
        contains(
          '/api/docutracker/sources/dtr/locator_slips/locator-1/workflow',
        ),
      );
      expect(paths.where((p) => p.contains('/documents/')), isEmpty);
      expect(find.text('Linked Locator Form'), findsOneWidget);
      expect(find.text('Follows the DTR locator workflow'), findsOneWidget);
      expect(find.text('Specific Locator Reviewer'), findsWidgets);
      expect(find.text('Linked Leave Form'), findsNothing);
      expect(find.text('SignedOriginal.pdf'), findsOneWidget);
      expect(find.text('Open Source Document'), findsOneWidget);
      expect(
        _Documents.signatureReads,
        1,
        reason: 'All Locator signature cards should share one source request.',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
