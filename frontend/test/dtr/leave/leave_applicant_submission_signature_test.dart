import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/api_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

void main() {
  test(
    'submission carries an explicit applicant signature asset outside employee details',
    () async {
      ApiClient.instance.init();
      ApiClient.instance.dio.interceptors.clear();
      addTearDown(() => ApiClient.instance.dio.interceptors.clear());
      Map? payload;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            payload = o.data as Map;
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {
                  'id': 'request',
                  'user_id': 'applicant',
                  'leave_type': 'vacationLeave',
                  'status': 'pending_hr',
                },
              ),
            );
          },
        ),
      );
      final request = LeaveRequest(
        id: 'request',
        userId: 'applicant',
        leaveType: LeaveType.vacationLeave,
        status: LeaveRequestStatus.pending,
        applicantSignatureAssetId: 'chosen-asset',
      );
      await const ApiLeaveRepository().updateRequest(
        request.copyWith(reason: 'Updated purpose'),
      );
      expect(payload?['applicant_signature_asset_id'], 'chosen-asset');
      expect(
        (payload?['details'] as Map).containsKey(
          'applicant_signature_asset_id',
        ),
        isFalse,
      );
      expect(
        LeaveRequest.fromJson({
          'user_id': 'applicant',
          'applicant_signature_asset_id': 'untrusted',
        }).applicantSignatureAssetId,
        isNull,
      );
    },
  );
}
