import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';
import 'package:hrms_plaridel/features/dtr/leave/utils/configured_leave_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => ApiClient.instance.init());
  setUp(() => ApiClient.instance.dio.interceptors.clear());
  tearDown(() => ApiClient.instance.dio.interceptors.clear());
  const request = LeaveRequest(
    id: 'request',
    userId: 'employee',
    employeeName: 'Sample Employee',
    leaveType: LeaveType.others,
  );
  test(
    'unconfigured CSC output remains unchanged without a background',
    () async {
      var calls = 0;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            calls++;
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {'layout': 'csc', 'has_background': false},
              ),
            );
          },
        ),
      );
      final doc = pw.Document()..addPage(pw.Page(build: (_) => pw.Text('CSC')));
      final original = await doc.save();
      expect(
        await saveConfiguredLeavePdf(request: request, document: doc),
        orderedEquals(original),
      );
      expect(calls, 1);
    },
  );
  test(
    'wellness output uses pinned version and merges its background',
    () async {
      final merged = Uint8List.fromList([37, 80, 68, 70]);
      FormData? rendered;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            if (o.method == 'GET') {
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: {
                    'id': 'version',
                    'layout': 'wellness',
                    'has_background': true,
                    'mayor_name': 'Mayor Example',
                  },
                ),
              );
            } else {
              rendered = o.data as FormData;
              h.resolve(
                Response(requestOptions: o, statusCode: 200, data: merged),
              );
            }
          },
        ),
      );
      final doc = pw.Document()..addPage(pw.Page(build: (_) => pw.Text('CSC')));
      expect(
        await saveConfiguredLeavePdf(request: request, document: doc),
        orderedEquals(merged),
      );
      expect(
        rendered!.fields.firstWhere((f) => f.key == 'version_id').value,
        'version',
      );
      expect(rendered!.files.single.value.length, greaterThan(1000));
    },
  );
  test('approved manual Mayor form ignores an electronic final signature', () async {
    ApiClient.instance.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      h.resolve(Response(requestOptions: o, statusCode: 200,
        data: {'layout': 'wellness', 'has_background': false, 'mayor_name': 'Local Mayor'}));
    }));
    final approved = request.copyWith(status: LeaveRequestStatus.approved, finalReviewRoute: 'mayor');
    final doc = pw.Document()..addPage(pw.Page(build: (_) => pw.Text('CSC')));
    // These bytes are deliberately not an image: attempting to print them would fail.
    final bytes = await saveConfiguredLeavePdf(request: approved, document: doc,
      finalSignature: Uint8List.fromList([1,2,3]));
    expect(bytes.length, greaterThan(1000));
  });
  test(
    'configuration errors stop printing rather than silently using a wrong form',
    () async {
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) => h.reject(DioException(requestOptions: o)),
        ),
      );
      final doc = pw.Document()..addPage(pw.Page(build: (_) => pw.Text('CSC')));
      await expectLater(
        saveConfiguredLeavePdf(request: request, document: doc),
        throwsA(isA<DioException>()),
      );
    },
  );
}
