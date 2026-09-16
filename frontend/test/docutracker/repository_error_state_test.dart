import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/data/repositories/docutracker_repository.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/admin/pages/docutracker_setup_permissions_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _DocuTrackerApiStub api;

  setUpAll(() {
    ApiClient.instance.init();
  });

  setUp(() {
    ApiClient.instance.dio.interceptors.clear();
    api = _DocuTrackerApiStub();
    ApiClient.instance.dio.interceptors.add(api.interceptor);
  });

  test(
    'repository propagates load failures instead of returning empty lists',
    () async {
      api.fail = true;
      final repository = DocuTrackerRepository.instance;

      await expectLater(
        repository.listDocumentHistory('document-1'),
        throwsA(predicate((error) => error.toString() == api.errorMessage)),
      );
      await expectLater(
        repository.listMyNotifications(),
        throwsA(predicate((error) => error.toString() == api.errorMessage)),
      );
      await expectLater(
        repository.listPermissions(),
        throwsA(predicate((error) => error.toString() == api.errorMessage)),
      );
      await expectLater(
        repository.getWorkflowSteps(documentType: 'memo', workflowVersion: 1),
        throwsA(predicate((error) => error.toString() == api.errorMessage)),
      );
      await expectLater(
        repository.getRoutingConfigs(),
        throwsA(predicate((error) => error.toString() == api.errorMessage)),
      );
    },
  );

  test('provider preserves valid state when refreshes fail', () async {
    final provider = DocuTrackerProvider();
    addTearDown(provider.dispose);

    await provider.loadRoutingConfigs();
    await provider.loadDocumentsForUser(userId: 'user-1', isAdmin: true);
    await provider.loadPermissions(roleId: 'admin', documentType: '*');
    await provider.loadDocumentHistory('document-1');
    await provider.loadNotifications(forceRefresh: true);

    expect(provider.routingConfigs, isNotEmpty);
    expect(provider.documents.single.title, 'Existing document');
    expect(provider.permissions.single.documentType, '*');
    expect(provider.documentHistory.single.action, 'created');
    expect(provider.notifications.single.title, 'Existing notification');

    final routingCount = provider.routingConfigs.length;
    api.fail = true;

    await provider.loadRoutingConfigs();
    expect(provider.routingConfigs, hasLength(routingCount));

    await provider.loadDocumentsForUser(userId: 'user-1', isAdmin: true);
    expect(provider.documents.single.title, 'Existing document');

    await provider.loadPermissions(roleId: 'admin', documentType: '*');
    expect(provider.permissions.single.documentType, '*');

    await provider.loadDocumentHistory('document-1');
    expect(provider.documentHistory.single.action, 'created');

    await provider.loadNotifications(forceRefresh: true);
    expect(provider.notifications.single.title, 'Existing notification');
    expect(provider.error, api.errorMessage);
  });

  test(
    'provider does not retain documents when a different user load fails',
    () async {
      final provider = DocuTrackerProvider();
      addTearDown(provider.dispose);

      await provider.loadDocumentsForUser(userId: 'user-1', isAdmin: true);
      expect(provider.documents, hasLength(1));

      api.fail = true;
      await provider.loadDocumentsForUser(userId: 'user-2', isAdmin: false);

      expect(provider.documents, isEmpty);
      expect(provider.error, api.errorMessage);
    },
  );

  testWidgets('preselected employee resolves its role and loads permissions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DocuTrackerSetupPermissionsScreen(
          initialUserId: _DocuTrackerApiStub._userId,
          initialDocumentType: '*',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Employee'), findsOneWidget);
    expect(api.requestedPaths, contains('/api/docutracker/permission-records'));
    expect(find.text('Submit drafts'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });
}

class _DocuTrackerApiStub {
  static const _documentId = '11111111-1111-4111-8111-111111111111';
  static const _userId = '22222222-2222-4222-8222-222222222222';

  bool fail = false;
  final String errorMessage = 'DocuTracker data is temporarily unavailable.';
  final List<String> requestedPaths = <String>[];

  late final Interceptor interceptor = InterceptorsWrapper(
    onRequest: (options, handler) {
      requestedPaths.add(options.path);
      if (fail) {
        handler.reject(
          DioException(
            requestOptions: options,
            response: Response<dynamic>(
              requestOptions: options,
              statusCode: 503,
              data: <String, dynamic>{'error': errorMessage},
            ),
            type: DioExceptionType.badResponse,
          ),
        );
        return;
      }

      final data = switch (options.path) {
        '/api/employees' => <dynamic>[
          <String, dynamic>{
            'id': _userId,
            'full_name': 'Test Employee',
            'role': 'employee',
          },
        ],
        '/api/docutracker/permission-explain' => <String, dynamic>{
          'final_decision': true,
        },
        '/api/docutracker/routing-configs' => <dynamic>[],
        '/api/docutracker/documents' => <dynamic>[
          <String, dynamic>{
            'id': _documentId,
            'document_type': 'memo',
            'title': 'Existing document',
            'status': 'pending',
            'created_by': _userId,
          },
        ],
        '/api/docutracker/permission-records' => <dynamic>[
          <String, dynamic>{
            'id': '33333333-3333-4333-8333-333333333333',
            'role_id': 'admin',
            'document_type': '*',
            'action': 'view',
            'granted': true,
          },
        ],
        '/api/docutracker/documents/document-1/history' => <dynamic>[
          <String, dynamic>{
            'id': '44444444-4444-4444-8444-444444444444',
            'document_id': 'document-1',
            'action': 'created',
          },
        ],
        '/api/docutracker/notifications' => <dynamic>[
          <String, dynamic>{
            'id': '55555555-5555-4555-8555-555555555555',
            'document_id': _documentId,
            'user_id': _userId,
            'type': 'assigned',
            'title': 'Existing notification',
          },
        ],
        '/api/docutracker/workflow-steps' => <dynamic>[],
        _ => <dynamic>[],
      };
      handler.resolve(
        Response<dynamic>(requestOptions: options, statusCode: 200, data: data),
      );
    },
  );
}
