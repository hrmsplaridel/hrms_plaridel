import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/leave_form_signatories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
  });
  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  for (final status in ['approved', 'pending_mayor', 'returned']) {
    for (final manual in [false, true]) {
     for (final policy in ['mayor', 'blank', 'actual_reviewer']) {
      test('shared replacement blocks honor $policy: $status manual=$manual', () async {
        final writes = <String>[];
        Map<String, dynamic> ink(String slot, String actor) => {
          'slot_key': slot, 'signed_by': actor, 'signature_asset_id': '$actor-asset',
          'signature_image_base64': 'aW5r', 'signed_at': '2026-10-18T01:00:00Z',
        };
        ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          if (o.method != 'GET') writes.add(o.method);
          h.resolve(Response(requestOptions: o, statusCode: 200, data: o.path == '/api/leave/signatories' ? {
            for (final slot in ['hr_certification_officer', 'recommendation_officer', 'approving_authority'])
              slot: slot != 'approving_authority' && policy == 'blank' ? {} : {
                'user_id': slot == 'approving_authority' || policy == 'mayor' ? 'mayor' : slot == 'recommendation_officer' ? 'backup-head' : 'backup-hr',
                'name': slot == 'approving_authority' || policy == 'mayor' ? 'Mayor' : 'Actual reviewer',
                'position_title': 'Official',
              },
          } : {
            'source_status': status,
            'workflow_snapshot': {'steps': [
              {'assignee_source': 'submitter_department_reviewers'},
              {'assignee_source': 'final_hr_reviewers'},
              {'assignee_source': manual ? 'manual_mayor' : 'active_mayor'},
            ]},
            'signatures': [
              ink('workflow_step_1', 'backup-head'),
              ink('workflow_step_2', 'backup-hr'),
              // Even a stale physical slot must not provide ink on inactive/manual forms.
              ink('hr_approver', 'mayor'),
              ink('certification_officer', 'backup-hr'),
              if (status == 'approved' && !manual) ink('workflow_step_3', 'mayor'),
            ],
          }));
        }));
        final result = await loadLeaveFormSignatories(request: LeaveRequest.fromJson({
          'id': 'request', 'user_id': 'applicant', 'leave_type': 'others', 'status': status,
        }));
        final signed = status == 'approved' && !manual;
        final actualSigned = policy == 'actual_reviewer' && status != 'returned';
        expect(result.recommendationOfficer?.name, policy == 'blank' ? null : policy == 'mayor' ? 'Mayor' : 'Actual reviewer');
        expect(result.certificationOfficer?.name, policy == 'blank' ? null : policy == 'mayor' ? 'Mayor' : 'Actual reviewer');
        expect(result.departmentHeadSignature?.signedBy, actualSigned ? 'backup-head' : policy == 'mayor' && signed ? 'mayor' : null);
        expect(result.certificationOfficerSignature?.signedBy, actualSigned ? 'backup-hr' : policy == 'mayor' && signed ? 'mayor' : null);
        expect(result.hrApproverSignature?.signedBy, signed ? 'mayor' : null);
        expect(writes, isEmpty);
      });
     }
    }
  }
}
