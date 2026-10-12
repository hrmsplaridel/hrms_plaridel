import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/reference_data_cache.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_type_definition_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/data/repositories/locator_slip_data_cache.dart';
import 'package:hrms_plaridel/features/dtr/locator/models/locator_request_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final leave = LeaveTypeDefinitionCache.instance;
  final locator = LocatorSlipDataCache.instance;
  final pending = <(RequestOptions, RequestInterceptorHandler)>[];
  void respond(int index, String name) {
    final (options, handler) = pending[index];
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: options.uri.path.endsWith('/check')
            ? {'canReviewPending': name == 'fresh'}
            : [
                {'name': name, 'code': name, 'display_name': name},
              ],
      ),
    );
  }

  Future<void> waitFor(int count) async {
    for (var i = 0; i < 100 && pending.length < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(pending.length, count);
  }

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    leave.invalidate();
    locator.invalidateAll();
    pending.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          pending.add((o, h));
        },
      ),
    );
  });
  tearDown(() {
    ApiClient.instance.dio.interceptors.clear();
    leave.invalidate();
    locator.invalidateAll();
  });

  final loaders = <String, Future<dynamic> Function(bool)>{
    'leave catalog': (force) => leave.listAll(forceRefresh: force),
    'employee leave catalog': (force) =>
        leave.listActiveEmployeeTypes(forceRefresh: force),
    'locator catalog': (force) => locator.listTypes(forceRefresh: force),
    'locator reviewer access': (force) => locator.checkDepartmentHeadAccess(
      userId: 'reviewer',
      forceRefresh: force,
    ),
  };
  for (final entry in loaders.entries) {
    test('${entry.key} retries after a shared failed fetch', () async {
      final first = entry.value(false);
      final second = entry.value(false);
      final failures = [
        expectLater(first, throwsA(isA<DioException>())),
        expectLater(second, throwsA(isA<DioException>())),
      ];
      await waitFor(1);
      pending[0].$2.reject(DioException(requestOptions: pending[0].$1));
      await Future.wait(failures);
      final retry = entry.value(false);
      await waitFor(2);
      respond(1, 'fresh');
      await retry;
    });
    test(
      '${entry.key} shares concurrent fetches including forced loads',
      () async {
        final first = entry.value(false);
        final second = entry.value(true);
        await waitFor(1);
        respond(0, 'fresh');
        await Future.wait([first, second]);
        await entry.value(false);
        expect(pending, hasLength(1));
      },
    );
    test('${entry.key} discards a result invalidated during fetch', () async {
      final first = entry.value(false);
      await waitFor(1);
      leave.invalidate();
      locator.invalidateAll();
      final second = entry.value(false);
      await waitFor(2);
      respond(1, 'fresh');
      final expected = await second;
      respond(0, 'stale');
      final actual = await first;
      if (actual is LocatorReviewerAccess) {
        expect(actual.canReviewPending, isTrue);
      } else {
        String key(dynamic e) =>
            e is LocatorRequestType ? e.code : e.name as String;
        expect(actual.map(key), expected.map(key));
      }
      await entry.value(false);
      expect(pending, hasLength(2));
    });
  }
  test(
    'account or role changes invalidate leave and locator catalogs',
    () async {
      final auth = AuthProvider();
      addTearDown(auth.dispose);
      auth.replaceUser(
        const AppUser(id: 'a', email: 'a@test.com', role: 'employee'),
      );
      final initial = Future.wait([leave.listAll(), locator.listTypes()]);
      await waitFor(2);
      respond(0, 'fresh');
      respond(1, 'fresh');
      await initial;
      auth.replaceUser(const AppUser(id: 'a', email: 'a@test.com', role: 'hr'));
      final next = Future.wait([leave.listAll(), locator.listTypes()]);
      await waitFor(4);
      respond(2, 'fresh');
      respond(3, 'fresh');
      await next;
      auth.replaceUser(const AppUser(id: 'b', email: 'b@test.com', role: 'hr'));
      final switched = Future.wait([leave.listAll(), locator.listTypes()]);
      await waitFor(6);
      respond(4, 'fresh');
      respond(5, 'fresh');
      await switched;
    },
  );
  test('reference cache respects expiry and separates query keys', () async {
    final cache = ReferenceDataCache<String, int>(ttl: Duration.zero);
    var fetches = 0;
    expect(await cache.get('a', () async => ++fetches), 1);
    expect(await cache.get('a', () async => ++fetches), 2);
    final fresh = ReferenceDataCache<String, int>(
      ttl: const Duration(minutes: 5),
    );
    expect(await fresh.get('a', () async => ++fetches), 3);
    expect(await fresh.get('b', () async => ++fetches), 4);
    expect(await fresh.get('a', () async => ++fetches), 3);
  });
  test(
    'employee catalog shares active fetch but keeps filing restrictions',
    () async {
      final all = leave.listAll(includeInactive: false);
      final employee = leave.listActiveEmployeeTypes();
      final inactive = leave.listAll(includeInactive: true);
      await waitFor(2);
      final (options, handler) = pending[0];
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: [
            {'name': 'available'},
            {'name': 'admin', 'admin_only': true},
            {'name': 'disabled', 'employee_can_file': false},
            {'name': 'inactive', 'is_active': false},
          ],
        ),
      );
      respond(1, 'historical');
      expect(await all, hasLength(4));
      final employeeTypes = await employee;
      expect(employeeTypes.single.name, 'available');
      employeeTypes.clear();
      expect(await leave.listActiveEmployeeTypes(), hasLength(1));
      expect((await inactive).single.name, 'historical');
      expect(pending[1].$1.queryParameters['include_inactive'], '1');
    },
  );
  test(
    'failed forced catalog refresh preserves the last successful cache',
    () async {
      final initial = leave.listAll();
      await waitFor(1);
      respond(0, 'fresh');
      await initial;
      final refresh = leave.listAll(forceRefresh: true);
      final failure = expectLater(refresh, throwsA(isA<DioException>()));
      await waitFor(2);
      pending[1].$2.reject(DioException(requestOptions: pending[1].$1));
      await failure;
      expect((await leave.listAll()).single.name, 'fresh');
      expect(pending, hasLength(2));
    },
  );
}
