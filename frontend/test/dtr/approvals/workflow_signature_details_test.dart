import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_source_signature_card.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/pages/workflow_approval_inbox_page.dart';

const _ink =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

void main() {
  for (final kind in ['leave', 'locator']) {
    for (final width in [1400.0, 390.0]) {
      for (final completed in [false, true]) {
        for (final currentSigned in [false, true]) {
          testWidgets(
            '$kind shows only the active reviewer signature, completed=$completed, signed=$currentSigned, width=$width',
            (tester) async {
              tester.view.physicalSize = Size(width, 1200);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              ApiClient.instance.init();
              ApiClient.instance.dio.interceptors.clear();
              final calls = <RequestOptions>[];
              final stage = completed ? 4 : 2;
              final snapshot = {
                'name': 'Custom route',
                'version': 1,
                'current_step': stage,
                'steps': List.generate(
                  4,
                  (index) => {'label': 'Configured Review ${index + 1}'},
                ),
              };
              Map<String, dynamic> signature(String slot, String name) => {
                'slot_key': slot,
                'label': name,
                'assigned_signer_id': name,
                'assigned_signer_name': name,
                'signed_by': name,
                'signer_name_snapshot': name,
                'signature_asset_id': 'asset-$name',
                'signature_image_base64': _ink,
                'signed_at': '2026-10-17T10:00:00Z',
                'can_sign': true,
                'can_assign': true,
              };
              ApiClient.instance.dio.interceptors.add(
                InterceptorsWrapper(
                  onRequest: (o, h) {
                    calls.add(o);
                    h.resolve(
                      Response(
                        requestOptions: o,
                        statusCode: 200,
                        data: {
                          'source_module': 'dtr',
                          'source_table': kind == 'leave'
                              ? 'leave_requests'
                              : 'locator_slips',
                          'source_record_id': 'request',
                          'source_status': completed
                              ? 'approved'
                              : 'pending_hr',
                          'workflow_snapshot': snapshot,
                          'signatures': [
                            signature('applicant', 'Applicant'),
                            for (var i = 0; i < stage; i++)
                              signature(
                                'workflow_step_${i + 1}',
                                'Configured Review ${i + 1}',
                              ),
                            {
                              if (currentSigned)
                                ...signature('hr_approver', 'reviewer'),
                              'slot_key': 'hr_approver',
                              'label': 'Configured Review 3 Signature',
                              'assigned_signer_id': 'reviewer',
                              'assigned_signer_name': 'Current Reviewer',
                              'can_sign': !completed,
                            },
                          ],
                        },
                      ),
                    );
                  },
                ),
              );
              final auth = AuthProvider()
                ..replaceUser(
                  const AppUser(
                    id: 'reviewer',
                    email: 'reviewer@test.local',
                    role: 'employee',
                  ),
                );
              addTearDown(() async {
                await tester.pumpWidget(const SizedBox.shrink());
                ApiClient.instance.dio.interceptors.clear();
                auth.dispose();
              });
              final request = <String, dynamic>{
                'kind': kind,
                'id': 'request',
                'employee_name': 'Applicant',
                'step_label': 'Configured Review 3',
                'workflow_name': 'Custom route',
                'current_step': stage,
                'step_count': 4,
                'can_review': !completed,
                'allowed_actions': ['approve'],
                'days': 1,
                'request_data': {
                  'id': 'request',
                  'user_id': 'applicant',
                  'employee_id': 'applicant',
                  'employee_name': 'Applicant',
                  'status': completed ? 'approved' : 'pending_hr',
                  'start_date': '2026-10-20',
                  'end_date': '2026-10-20',
                  'slip_date': '2026-10-20',
                  'working_days_applied': 1,
                  'workflow_snapshot': snapshot,
                },
              };
              await tester.pumpWidget(
                ChangeNotifierProvider.value(
                  value: auth,
                  child: MaterialApp(
                    home: Scaffold(
                      body: Builder(
                        builder: (context) => TextButton(
                          onPressed: () =>
                              reviewAssignedWorkflowRequest(context, request),
                          child: const Text('Open'),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.tap(find.text('Open'));
              await tester.pumpAndSettle();
              final cards = tester
                  .widgetList<DocuTrackerSourceSignatureCard>(
                    find.byType(DocuTrackerSourceSignatureCard),
                  )
                  .toList();
              expect(cards, hasLength(completed ? 0 : 1));
              expect(cards.where((c) => c.slotKey == 'applicant'), isEmpty);
              for (var i = 0; i < stage; i++) {
                expect(
                  cards.where((c) => c.slotKey == 'workflow_step_${i + 1}'),
                  isEmpty,
                );
              }
              final signedImages = tester
                  .widgetList<Image>(find.byType(Image))
                  .where((image) => image.image is MemoryImage)
                  .toList();
              expect(
                signedImages,
                hasLength(!completed && currentSigned ? 1 : 0),
              );
              if (!completed && currentSigned) {
                expect(
                  (signedImages.single.image as MemoryImage).bytes,
                  base64Decode(_ink),
                );
              }
              expect(
                calls.where(
                  (o) =>
                      o.path.contains('/sources/') &&
                      o.path.endsWith('/signatures'),
                ),
                hasLength(completed ? 0 : 1),
                reason: 'Only the active review needs to fetch signature data.',
              );
              if (completed) {
                expect(find.text('Add Signature'), findsNothing);
                expect(find.text('Change Signature'), findsNothing);
                expect(find.text('Change signer'), findsNothing);
                expect(find.text('Approve'), findsNothing);
              } else {
                expect(
                  find.text(
                    currentSigned ? 'Change Signature' : 'Add Signature',
                  ),
                  findsOneWidget,
                );
                expect(
                  tester
                      .widget<FilledButton>(
                        find.widgetWithText(FilledButton, 'Approve'),
                      )
                      .onPressed,
                  currentSigned ? isNotNull : isNull,
                );
              }
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  }
}
