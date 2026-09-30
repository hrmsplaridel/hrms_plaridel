import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <String>[];
  var roles = <String, dynamic>{};
  setUp(() {
    ApiClient.instance.init();
    requests.clear();
    roles = {
      'dtr_office_hours_verifier': {
        'configured': true,
        'current': {
          'name': 'Selected Verifier',
          'position_title': 'Officer II',
        },
      },
      'dtr_hr_officer': {
        'configured': true,
        'current': {'name': 'Selected HR', 'position_title': 'HR Officer'},
      },
    };
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options.path);
          if (options.path == '/api/dtr-report-signatories') {
            handler.resolve(
              Response(requestOptions: options, data: {'roles': roles}),
            );
          } else if (options.path == '/api/employees') {
            handler.resolve(
              Response(
                requestOptions: options,
                data: [
                  {
                    'full_name': 'Legacy Verifier',
                    'current_position_name': 'HRAdminAide',
                  },
                  {
                    'full_name': 'Legacy HR',
                    'current_position_name':
                        "Human Resource Mgt. and Dev't. Officer",
                  },
                ],
              ),
            );
          } else {
            handler.reject(DioException(requestOptions: options));
          }
        },
      ),
    );
  });
  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  test(
    'explicit officials are used without employee-directory or admin-history access',
    () async {
      final result = await DtrExport.resolveSignatories(
        requireVerifiedSource: true,
      );
      expect(result.meedoManager.employeeName, 'Selected Verifier');
      expect(result.meedoManager.positionTitle, 'Officer II');
      expect(result.hrOfficer.employeeName, 'Selected HR');
      expect(result.isConfigured, isTrue);
      expect(requests, ['/api/dtr-report-signatories']);
    },
  );

  test(
    'expired or future designation does not fall back to a different employee',
    () async {
      roles['dtr_office_hours_verifier'] = {
        'configured': true,
        'current': null,
      };
      final result = await DtrExport.resolveSignatories(
        requireVerifiedSource: true,
      );
      expect(result.isConfigured, isFalse);
      expect(result.meedoManager.employeeName, isNull);
      expect(requests, ['/api/dtr-report-signatories']);
    },
  );

  test('unconfigured roles retain legacy position resolution', () async {
    roles.updateAll((key, value) => {'configured': false, 'current': null});
    final result = await DtrExport.resolveSignatories(
      requireVerifiedSource: true,
    );
    expect(result.isConfigured, isTrue);
    expect(result.meedoManager.employeeName, 'Legacy Verifier');
    expect(result.hrOfficer.employeeName, 'Legacy HR');
  });
}
