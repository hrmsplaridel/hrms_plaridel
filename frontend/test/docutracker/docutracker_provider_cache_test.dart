import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingApi api;
  late DateTime now;
  late DocuTrackerProvider provider;

  setUpAll(() => ApiClient.instance.init());

  setUp(() {
    ApiClient.instance.dio.interceptors.clear();
    api = _CountingApi();
    ApiClient.instance.dio.interceptors.add(api.interceptor);
    DocuTrackerRepository.instance.clearSessionCaches();
    now = DateTime(2026, 10, 1, 12);
    provider = DocuTrackerProvider(clock: () => now);
    provider.onAuthUserChanged('user-1');
  });

  tearDown(() => provider.dispose());

  Future<void> loadDocs({bool forceRefresh = false}) =>
      provider.loadDocumentsForUser(
        userId: 'user-1',
        isAdmin: true,
        forceRefresh: forceRefresh,
      );

  test('revisiting within the TTL reuses cached documents', () async {
    await loadDocs();
    expect(api.count('/api/docutracker/documents'), 1);

    now = now.add(const Duration(seconds: 10));
    await loadDocs();
    expect(api.count('/api/docutracker/documents'), 1);
    expect(provider.documents.single.title, 'Document 1');
  });

  test('stale revisit refreshes quietly without the loading state', () async {
    await loadDocs();
    final loadingStates = <bool>[];
    provider.addListener(() => loadingStates.add(provider.loading));

    now = now.add(DocuTrackerProvider.documentsTtl);
    await loadDocs();

    expect(api.count('/api/docutracker/documents'), 2);
    expect(loadingStates, isNot(contains(true)));
    expect(provider.documents.single.title, 'Document 2');
  });

  test('invalidated documents refresh quietly on the next visit', () async {
    await loadDocs();
    provider.invalidateDocuments();
    final loadingStates = <bool>[];
    provider.addListener(() => loadingStates.add(provider.loading));

    await loadDocs();

    expect(api.count('/api/docutracker/documents'), 2);
    expect(loadingStates, isNot(contains(true)));
  });

  test('concurrent loads for the same scope share one request', () async {
    await Future.wait([loadDocs(), loadDocs(), loadDocs()]);
    expect(api.count('/api/docutracker/documents'), 1);
  });

  test('forceRefresh bypasses a fresh cache', () async {
    await loadDocs();
    await loadDocs(forceRefresh: true);
    expect(api.count('/api/docutracker/documents'), 2);
  });

  test('an older response cannot overwrite a newer forced refresh', () async {
    final gate = Completer<void>();
    api.firstDocumentsGate = gate;
    final slow = loadDocs();
    await Future<void>.delayed(Duration.zero);
    await loadDocs(forceRefresh: true);
    expect(provider.documents.single.title, 'Document 2');

    gate.complete();
    await slow;
    expect(provider.documents.single.title, 'Document 2');
    expect(provider.loading, isFalse);
  });

  test('routing configs are cached and never toggle loading', () async {
    final loadingStates = <bool>[];
    provider.addListener(() => loadingStates.add(provider.loading));
    await Future.wait([
      provider.loadRoutingConfigs(),
      provider.loadRoutingConfigs(),
    ]);
    await provider.loadRoutingConfigs();
    expect(api.count('/api/docutracker/routing-configs'), 1);
    expect(loadingStates, isNot(contains(true)));

    await provider.loadRoutingConfigs(forceRefresh: true);
    expect(api.count('/api/docutracker/routing-configs'), 2);
  });

  test('source signature requests dedupe and respect the TTL', () async {
    await Future.wait([
      provider.loadSourceSignatureRequests(),
      provider.loadSourceSignatureRequests(),
    ]);
    expect(api.signatureRequests, 2);

    await provider.loadSourceSignatureRequests();
    expect(api.signatureRequests, 2);

    now = now.add(DocuTrackerProvider.sourceSignatureRequestsTtl);
    final loadingStates = <bool>[];
    provider.addListener(
      () => loadingStates.add(provider.sourceSignatureRequestsLoading),
    );
    await provider.loadSourceSignatureRequests();
    expect(api.signatureRequests, 4);
    expect(loadingStates, isNot(contains(true)));
  });

  test(
    'form_signature notifications refetch loaded signature requests',
    () async {
      provider.handleSourceModuleNotification('form_signature');
      await Future<void>.delayed(Duration.zero);
      expect(api.signatureRequests, 0);

      await provider.loadSourceSignatureRequests();
      expect(api.signatureRequests, 2);

      final loadingStates = <bool>[];
      provider.addListener(
        () => loadingStates.add(provider.sourceSignatureRequestsLoading),
      );
      provider.handleSourceModuleNotification('form_signature');
      await provider.loadSourceSignatureRequests();
      expect(api.signatureRequests, 4);
      expect(loadingStates, isNot(contains(true)));
    },
  );

  test('only training notifications mark documents stale', () async {
    await loadDocs();
    // Recruitment records are not DocuTracker documents.
    provider.handleSourceModuleNotification('recruitment');
    await loadDocs();
    expect(api.count('/api/docutracker/documents'), 1);

    provider.handleSourceModuleNotification('training');
    await loadDocs();
    expect(api.count('/api/docutracker/documents'), 2);

    provider.handleSourceModuleNotification('leave');
    await loadDocs();
    expect(api.count('/api/docutracker/documents'), 2);
  });

  test('cached notifications do not notify listeners again', () async {
    await provider.loadNotifications(forceRefresh: true);
    var notified = 0;
    provider.addListener(() => notified++);
    await provider.loadNotifications();
    expect(notified, 0);
    expect(api.count('/api/docutracker/notifications'), 1);
  });

  test('account change clears cached data and saved screen state', () async {
    await loadDocs();
    await provider.loadRoutingConfigs();
    provider.viewState('documents:true')['search'] = 'memo';

    provider.onAuthUserChanged('user-2');
    expect(provider.documents, isEmpty);
    expect(provider.viewState('documents:true'), isEmpty);

    await provider.loadDocumentsForUser(userId: 'user-2', isAdmin: true);
    await provider.loadRoutingConfigs();
    expect(api.count('/api/docutracker/documents'), 2);
    expect(api.count('/api/docutracker/routing-configs'), 2);
  });

  test('admin permissions are cached and refresh quietly', () async {
    Future<void> loadPermissions({bool forceRefresh = false}) =>
        provider.loadPermissions(userOnly: true, forceRefresh: forceRefresh);

    await Future.wait([loadPermissions(), loadPermissions()]);
    await loadPermissions();
    expect(api.count('/api/docutracker/permission-records'), 1);

    final loadingStates = <bool>[];
    provider.addListener(() => loadingStates.add(provider.loading));
    now = now.add(DocuTrackerProvider.permissionsTtl);
    await loadPermissions();
    await loadPermissions(forceRefresh: true);
    expect(api.count('/api/docutracker/permission-records'), 3);
    expect(loadingStates, isNot(contains(true)));
  });

  test('employee directory loads once and is cleared on sign-out', () async {
    await Future.wait([
      provider.loadEmployeeDirectory(),
      provider.loadEmployeeDirectory(),
    ]);
    await provider.loadEmployeeDirectory();
    expect(api.count('/api/employees'), 1);

    provider.onAuthUserChanged(null);
    provider.onAuthUserChanged('user-1');
    await provider.loadEmployeeDirectory();
    expect(api.count('/api/employees'), 2);
  });

  test(
    'creatable document types are cached until permissions change',
    () async {
      final repo = DocuTrackerRepository.instance;
      await repo.creatableDocumentTypes();
      await repo.creatableDocumentTypes();
      expect(api.count('/api/docutracker/routing-configs'), 1);

      await repo.savePermissionPolicy(documentType: '*', changes: const []);
      await repo.creatableDocumentTypes();
      expect(api.count('/api/docutracker/routing-configs'), 2);
    },
  );
}

class _CountingApi {
  final Map<String, int> _counts = {};
  Completer<void>? firstDocumentsGate;
  var _documentResponses = 0;

  int count(String path) => _counts[path] ?? 0;

  int get signatureRequests =>
      count('/api/docutracker/sources/rsp/signature-requests') +
      count('/api/docutracker/sources/ld/signature-requests');

  late final Interceptor interceptor = InterceptorsWrapper(
    onRequest: (options, handler) {
      final path = options.path;
      _counts[path] = count(path) + 1;
      if (path == '/api/docutracker/documents') {
        final response = ++_documentResponses;
        final gate = firstDocumentsGate;
        final data = [
          {
            'id': '11111111-1111-4111-8111-11111111111$response',
            'document_type': 'memo',
            'title': 'Document $response',
            'status': 'pending',
            'created_by': 'user-1',
          },
        ];
        if (response == 1 && gate != null) {
          unawaited(gate.future.then((_) => _resolve(options, handler, data)));
          return;
        }
        _resolve(options, handler, data);
        return;
      }
      final data = switch (path) {
        '/api/docutracker/permission-policy' => <String, dynamic>{},
        '/api/docutracker/notifications' => <dynamic>[
          {
            'id': '55555555-5555-4555-8555-555555555555',
            'document_id': 'doc-1',
            'user_id': 'user-1',
            'type': 'assigned',
            'title': 'Notice',
          },
        ],
        _ => <dynamic>[],
      };
      _resolve(options, handler, data);
    },
  );

  void _resolve(
    RequestOptions options,
    RequestInterceptorHandler handler,
    Object data,
  ) {
    handler.resolve(
      Response<dynamic>(requestOptions: options, statusCode: 200, data: data),
    );
  }
}
