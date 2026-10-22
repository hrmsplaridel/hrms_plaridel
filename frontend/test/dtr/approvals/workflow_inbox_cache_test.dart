import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/api/workflow_inbox_cache.dart';
import 'package:hrms_plaridel/features/dtr/management/approvals/pages/workflow_approval_inbox_page.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/token_storage.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    WorkflowInboxCache.instance.clearSession();
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
  });

  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  final rows = [
    {'id': 'leave-request', 'kind': 'leave', 'can_review': true},
    {'id': 'locator-request', 'kind': 'locator', 'can_review': true},
  ];

  test(
    'simultaneous Leave and Locator loads share one inbox request',
    () async {
      final release = Completer<void>();
      var calls = 0;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            calls++;
            await release.future;
            handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: rows),
            );
          },
        ),
      );

      final leave = loadAssignedWorkflowRequests('leave');
      final locator = loadAssignedWorkflowRequests('locator');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      release.complete();

      expect((await leave).keys, ['leave-request']);
      expect((await locator).keys, ['locator-request']);
      expect(calls, 1);
    },
  );

  test('switching modules reuses the recent shared inbox response', () async {
    var calls = 0;
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls++;
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: rows),
          );
        },
      ),
    );

    expect((await loadAssignedWorkflowRequests('leave')).length, 1);
    expect((await loadAssignedWorkflowRequests('locator')).length, 1);
    expect(calls, 1);
  });

  test('explicit refresh bypasses a recent response', () async {
    var calls = 0;
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls++;
          handler.resolve(
            Response(
              requestOptions: options,
              data: calls == 1 ? rows : <dynamic>[],
            ),
          );
        },
      ),
    );
    expect(await loadAssignedWorkflowRequests('leave'), isNotEmpty);
    expect(
      await loadAssignedWorkflowRequests('leave', forceRefresh: true),
      isEmpty,
    );
    expect(await loadAssignedWorkflowRequests('locator'), isEmpty);
    expect(calls, 2);
  });

  test('concurrent explicit refreshes share the same new request', () async {
    final cache = WorkflowInboxCache();
    await cache.get('leave', () async => rows);
    final release = Completer<List<dynamic>>();
    var calls = 0;
    Future<List<dynamic>> load() {
      calls++;
      return release.future;
    }

    final leave = cache.get('leave', load, forceRefresh: true);
    final locator = cache.get('locator', load, forceRefresh: true);
    release.complete(rows);
    await Future.wait([leave, locator]);
    expect(calls, 1);
  });

  test('expired entries reload using a deterministic clock', () async {
    var now = DateTime(2026, 10, 23);
    final cache = WorkflowInboxCache(now: () => now);
    var calls = 0;
    Future<List<dynamic>> load() async {
      calls++;
      return rows;
    }

    await cache.get('leave', load);
    now = now.add(const Duration(seconds: 14));
    await cache.get('locator', load);
    expect(calls, 1);
    now = now.add(const Duration(seconds: 1));
    await cache.get('leave', load);
    expect(calls, 2);
  });

  test('cache returns independent nested workflow data', () async {
    final cache = WorkflowInboxCache();
    final data = <dynamic>[
      {
        'id': 'request',
        'kind': 'leave',
        'request_data': {
          'workflow_snapshot': {
            'steps': [
              {'label': 'Original'},
            ],
          },
        },
      },
    ];
    Future<List<dynamic>> load() async => data;
    final first = await cache.get('leave', load);
    final snapshot = first['request']!['request_data']['workflow_snapshot'];
    snapshot['steps'][0]['label'] = 'Changed by a screen';
    final second = await cache.get('leave', load);
    expect(
      second['request']!['request_data']['workflow_snapshot']['steps'][0]['label'],
      'Original',
    );
  });

  test(
    'failed requests are shared and can be retried without cached failure',
    () async {
      final cache = WorkflowInboxCache();
      final failure = Completer<List<dynamic>>();
      var calls = 0;
      Future<List<dynamic>> load() {
        calls++;
        return failure.future;
      }

      final leave = cache.get('leave', load);
      final locator = cache.get('locator', load);
      final leaveError = expectLater(leave, throwsStateError);
      final locatorError = expectLater(locator, throwsStateError);
      failure.completeError(StateError('Server unavailable'));
      await Future.wait([leaveError, locatorError]);
      expect(calls, 1);
      expect(await cache.get('leave', () async => rows), isNotEmpty);
    },
  );

  for (final obsoleteFails in [false, true]) {
    test(
      'invalidation supersedes an in-flight ${obsoleteFails ? 'failure' : 'response'}',
      () async {
        final cache = WorkflowInboxCache();
        final first = Completer<List<dynamic>>();
        final second = Completer<List<dynamic>>();
        var calls = 0;
        Future<List<dynamic>> load() =>
            ++calls == 1 ? first.future : second.future;
        final oldReader = cache.get('leave', load);
        cache.invalidate();
        final newReader = cache.get('locator', load);
        if (obsoleteFails) {
          first.completeError(StateError('Obsolete request failed'));
        } else {
          first.complete(rows);
        }
        second.complete(<dynamic>[]);
        expect(await oldReader, isEmpty);
        expect(await newReader, isEmpty);
        expect(calls, 2);
        expect(await cache.get('leave', load), isEmpty);
        expect(calls, 2);
      },
    );
  }

  test(
    'account changes terminate old readers and do not expose their response',
    () async {
      final cache = WorkflowInboxCache();
      final oldResponse = Completer<List<dynamic>>();
      final oldReader = cache.get('leave', () => oldResponse.future);
      final error = expectLater(oldReader, throwsStateError);
      cache.clearSession();
      expect(await cache.get('leave', () async => <dynamic>[]), isEmpty);
      oldResponse.complete(rows);
      await error;
      expect(await cache.get('leave', () async => rows), isEmpty);
    },
  );

  for (final next in [
    const AppUser(id: 'other', email: 'other@test.invalid', role: 'admin'),
    const AppUser(id: 'reviewer', email: 'reviewer@test.invalid', role: 'hr'),
  ]) {
    test(
      'AuthProvider clears inbox on identity/role change to ${next.id}/${next.role}',
      () async {
        final auth = AuthProvider()
          ..replaceUser(
            const AppUser(
              id: 'reviewer',
              email: 'reviewer@test.invalid',
              role: 'admin',
            ),
          );
        addTearDown(auth.dispose);
        final cache = WorkflowInboxCache.instance;
        await cache.get('leave', () async => rows);
        auth.replaceUser(next);
        expect(await cache.get('leave', () async => <dynamic>[]), isEmpty);
      },
    );
  }

  for (final path in [
    '/api/approval-workflows/requests/leave/request/approve',
    '/api/approval-workflows/workflow',
    '/api/leave/request/revoke',
    '/api/locator-slips/request/return-for-correction',
    '/api/leave-final-reviewers',
    '/api/departments/department/reviewers',
    '/api/dtr-access/reviewer',
    '/api/docutracker/official-signatories',
  ]) {
    test(
      'successful workflow mutation invalidates shared inbox: $path',
      () async {
        final cache = WorkflowInboxCache();
        await cache.get('leave', () async => rows);
        cache.invalidateAfterResponse('PATCH', path, 200);
        expect(await cache.get('leave', () async => <dynamic>[]), isEmpty);
      },
    );
  }

  test(
    'a conflict invalidates the inbox but reads and validation failures do not',
    () async {
      final cache = WorkflowInboxCache();
      await cache.get('leave', () async => rows);
      for (final (method, path, status) in [
        ('GET', '/api/leave/request', 200),
        ('POST', '/api/leave/request/approve', 400),
        ('POST', '/api/contact', 200),
      ]) {
        cache.invalidateAfterResponse(method, path, status);
        expect(await cache.get('leave', () async => <dynamic>[]), isNotEmpty);
      }
      cache.invalidateAfterResponse('POST', '/api/leave/request/approve', 409);
      expect(await cache.get('leave', () async => <dynamic>[]), isEmpty);
    },
  );

  for (final status in [200, 409]) {
    test(
      'API client invalidates inbox after an actual $status mutation response',
      () async {
        final cache = WorkflowInboxCache.instance;
        await cache.get('leave', () async => rows);
        final dio = Dio()..httpClientAdapter = _ResponseAdapter(status);
        final client = ApiClient.forTesting(dio: dio, refreshDio: Dio())
          ..init();
        addTearDown(dio.close);
        try {
          await client.post('/api/leave/request/revoke');
        } on DioException catch (error) {
          expect(error.response?.statusCode, 409);
        }
        expect(await cache.get('leave', () async => <dynamic>[]), isEmpty);
      },
    );
  }

  test(
    'clearing expired or signed-out credentials removes cached approvals',
    () async {
      final cache = WorkflowInboxCache.instance;
      await cache.get('leave', () async => rows);
      await TokenStorage.instance.clearAllTokens();
      expect(await cache.get('leave', () async => <dynamic>[]), isEmpty);
    },
  );
}

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter(this.status);
  final int status;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({'status': 'revoked'}),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
