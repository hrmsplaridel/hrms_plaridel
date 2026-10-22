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

  test('an expired first page supersedes a delayed older page', () async {
    var now = DateTime(2026);
    final cache = WorkflowInboxCache(now: () => now);
    await cache.get(
      'leave',
      () async => {
        'items': rows,
        'has_more': {'leave': true},
        'next_cursor': {'leave': 'old-cursor'},
      },
    );
    final response = Completer<dynamic>();
    final oldPage = cache.loadMore('leave', (_) => response.future);
    final failure = expectLater(oldPage, throwsStateError);
    now = now.add(const Duration(seconds: 15));
    await cache.get('leave', () async => <dynamic>[]);
    response.complete(<dynamic>[
      {'id': 'obsolete', 'kind': 'leave'},
    ]);
    await failure;
    expect(await cache.get('leave', () async => rows), isEmpty);
  });

  test(
    'load more waits for a first-page refresh and uses the refreshed cursor',
    () async {
      final cache = WorkflowInboxCache();
      dynamic responsePage(String? cursor) => {
        'items': rows,
        'has_more': {'leave': cursor != null},
        'next_cursor': {'leave': cursor},
      };
      await cache.get('leave', () async => responsePage('old-cursor'));
      final response = Completer<dynamic>();
      final refresh = cache.get(
        'leave',
        () => response.future,
        forceRefresh: true,
      );
      final more = cache.loadMore('leave', (cursor) async {
        expect(cursor, 'new-cursor');
        return responsePage(null);
      });
      response.complete(responsePage('new-cursor'));
      await refresh;
      expect((await more).length, 1);
    },
  );

  test(
    'client requests bounded pages and accepts module continuation metadata',
    () async {
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.queryParameters['paginated'], true);
            expect(options.queryParameters['limit'], 50);
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'items': rows,
                  'has_more': {'leave': true, 'locator': false},
                  'next_cursor': {'leave': 'next-leave-page', 'locator': null},
                },
              ),
            );
          },
        ),
      );
      expect((await loadAssignedWorkflowRequests('leave')).keys, [
        'leave-request',
      ]);
    },
  );

  dynamic page(List<dynamic> items, {String? cursor}) => {
    'items': items,
    'has_more': {'leave': cursor != null, 'locator': false},
    'next_cursor': {'leave': cursor, 'locator': null},
  };

  test(
    'loading the next module page appends rows without dropping the other module',
    () async {
      var now = DateTime(2026);
      final cache = WorkflowInboxCache(now: () => now);
      await cache.get('leave', () async => page(rows, cursor: 'page-2'));
      now = now.add(const Duration(seconds: 30));
      final result = await cache.loadMore('leave', (cursor) async {
        expect(cursor, 'page-2');
        return page([
          {'id': 'older-leave', 'kind': 'leave'},
        ]);
      });
      expect(result.keys, ['leave-request', 'older-leave']);
      expect(cache.hasMore('leave'), false);
      // No forced refresh: inspect the other module while the initial page is fresh.
      now = now.subtract(const Duration(seconds: 30));
      final locator = await cache.get(
        'locator',
        () async => throw StateError('Unexpected fetch'),
      );
      expect(locator.keys, ['locator-request']);
    },
  );

  test(
    'simultaneous load-more calls share one request and failure retains its cursor',
    () async {
      final cache = WorkflowInboxCache();
      await cache.get('leave', () async => page(rows, cursor: 'page-2'));
      final pending = Completer<dynamic>();
      var calls = 0;
      Future<dynamic> load(String cursor) {
        calls++;
        return pending.future;
      }

      final first = cache.loadMore('leave', load),
          second = cache.loadMore('leave', load);
      final firstError = expectLater(first, throwsStateError);
      final secondError = expectLater(second, throwsStateError);
      pending.completeError(StateError('Unavailable'));
      await Future.wait([firstError, secondError]);
      expect(calls, 1);
      expect(cache.hasMore('leave'), true);
      final retry = await cache.loadMore(
        'leave',
        (_) async => page([
          {'id': 'older', 'kind': 'leave'},
        ]),
      );
      expect(retry.length, 2);
    },
  );

  for (final change in ['event', 'account', 'refresh']) {
    test(
      '$change prevents a delayed page from repopulating the inbox',
      () async {
        final cache = WorkflowInboxCache();
        await cache.get('leave', () async => page(rows, cursor: 'page-2'));
        final response = Completer<dynamic>();
        final pending = cache.loadMore('leave', (_) => response.future);
        final failure = expectLater(pending, throwsStateError);
        if (change == 'event') cache.invalidate();
        if (change == 'account') cache.clearSession();
        await cache.get(
          'leave',
          () async => page([]),
          forceRefresh: change == 'refresh',
        );
        response.complete(
          page([
            {'id': 'obsolete', 'kind': 'leave'},
          ]),
        );
        await failure;
        expect(
          await cache.get(
            'leave',
            () async => throw StateError('Unexpected fetch'),
          ),
          isEmpty,
        );
        expect(cache.hasMore('leave'), false);
      },
    );
  }

  test(
    'a repeated cursor is rejected without losing loaded rows or retry state',
    () async {
      final cache = WorkflowInboxCache();
      await cache.get('leave', () async => page(rows, cursor: 'page-2'));
      await expectLater(
        cache.loadMore('leave', (_) async => page([], cursor: 'page-2')),
        throwsFormatException,
      );
      expect(cache.hasMore('leave'), true);
      expect(
        (await cache.get(
          'leave',
          () async => throw StateError('Unexpected fetch'),
        )).length,
        1,
      );
    },
  );

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
