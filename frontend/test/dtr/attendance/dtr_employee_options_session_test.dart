import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
  });

  late Completer<void> started;
  late Completer<void> release;
  late DtrProvider provider;
  var calls = 0;

  setUp(() {
    started = Completer<void>();
    release = Completer<void>();
    calls = 0;
    provider = DtrProvider();
    final dio = ApiClient.instance.dio;
    dio.interceptors.clear();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          calls++;
          final first = calls == 1;
          if (first) {
            started.complete();
            await release.future;
          }
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: [
                {
                  'id': first ? 'old-employee' : 'new-employee',
                  'full_name': first ? 'Old Employee' : 'New Employee',
                },
              ],
            ),
          );
        },
      ),
    );
    addTearDown(dio.interceptors.clear);
    addTearDown(provider.dispose);
  });

  for (final shared in [true, false]) {
    test('${shared ? 'loadEmployees' : 'fetchEmployeeOptions'} rejects stale '
        'session data without refilling the employee cache', () async {
      provider.onAuthUserChanged('account-a');
      final pending = shared
          ? provider
                .loadEmployees(forceRefresh: true)
                .then((_) => <EmployeeOption>[])
          : provider.fetchEmployeeOptions(forceRefresh: true);
      await started.future;

      provider.onAuthUserChanged('account-b');
      final checked = shared
          ? expectLater(pending, completion(isEmpty))
          : expectLater(pending, throwsStateError);
      release.complete();
      await checked;

      expect(provider.employees, isEmpty);
      await provider.loadEmployees();
      expect(calls, 2);
      expect(provider.employees.single.id, 'new-employee');
    });
  }
}
