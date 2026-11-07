import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/pages/manage_employee.dart';

class _PendingRequest {
  _PendingRequest(this.options, this.handler);
  final RequestOptions options;
  final RequestInterceptorHandler handler;

  void succeed(List<dynamic> rows) => handler.resolve(
    Response(requestOptions: options, statusCode: 200, data: rows),
  );

  void fail() => handler.reject(
    DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: options,
        statusCode: 500,
        data: {'error': 'Device connection timed out.'},
      ),
    ),
  );
}

List<Map<String, dynamic>> roster(String name, String bioId) => [
  {'full_name': name, 'biometric_user_id': bioId},
];

Future<void> flushUi(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final requests = <_PendingRequest>[];
  final duplicateRequests = <_PendingRequest>[];
  var delayDuplicates = false;

  setUpAll(() => ApiClient.instance.init());
  setUp(() {
    requests.clear();
    duplicateRequests.clear();
    delayDuplicates = false;
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.endsWith('/users')) {
            requests.add(_PendingRequest(options, handler));
            return;
          }
          if (options.queryParameters.containsKey('biometric_user_ids') &&
              delayDuplicates) {
            duplicateRequests.add(_PendingRequest(options, handler));
            return;
          }
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: options.path == '/api/biometric-devices'
                  ? [
                      {
                        'id': 'offline',
                        'name': 'Offline clock',
                        'vendor': 'zkteco',
                      },
                      {'id': 'online', 'name': 'Testing', 'vendor': 'zkteco'},
                    ]
                  : <dynamic>[],
            ),
          );
        },
      ),
    );
  });
  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  Future<void> openDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ManageEmployee(canCreateAccount: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import from Device'));
    await flushUi(tester);
    expect(
      requests.single.options.path,
      '/api/biometric-devices/offline/users',
    );
  }

  Future<void> selectDevice(WidgetTester tester, String name) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await flushUi(tester);
    await tester.tap(find.text(name).last);
    await flushUi(tester);
  }

  testWidgets(
    'old offline failure cannot show an error after selecting a working device',
    (tester) async {
      await openDialog(tester);
      await selectDevice(tester, 'Testing');
      requests[1].succeed(roster('Current employee', '2'));
      await flushUi(tester);
      requests[0].fail();
      await flushUi(tester);
      expect(find.text('Current employee'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('Device connection timed out.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late success from another device cannot overwrite the current roster',
    (tester) async {
      await openDialog(tester);
      await selectDevice(tester, 'Testing');
      requests[1].succeed(roster('Current employee', '2'));
      await flushUi(tester);
      requests[0].succeed(roster('Old employee', '1'));
      await flushUi(tester);
      expect(find.text('Current employee'), findsOneWidget);
      expect(find.text('Old employee'), findsNothing);
    },
  );

  testWidgets('old request cannot stop the new device loading indicator', (
    tester,
  ) async {
    await openDialog(tester);
    await selectDevice(tester, 'Testing');
    requests[0].fail();
    await flushUi(tester);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Fetch Users'),
          )
          .onPressed,
      isNull,
    );
    requests[1].succeed(roster('Current employee', '2'));
    await flushUi(tester);
    expect(find.text('Current employee'), findsOneWidget);
  });

  testWidgets('switching A to B to A still ignores the original A response', (
    tester,
  ) async {
    await openDialog(tester);
    await selectDevice(tester, 'Testing');
    await selectDevice(tester, 'Offline clock');
    requests[2].succeed(roster('New A employee', '3'));
    await flushUi(tester);
    requests[0].succeed(roster('Old A employee', '1'));
    requests[1].fail();
    await flushUi(tester);
    expect(find.text('New A employee'), findsOneWidget);
    expect(find.text('Old A employee'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'current failure is concise, names the device, and clears on retry',
    (tester) async {
      await openDialog(tester);
      requests[0].fail();
      await flushUi(tester);
      expect(find.textContaining('Offline clock'), findsWidgets);
      expect(
        find.textContaining('Device connection timed out.'),
        findsOneWidget,
      );
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Fetch Users'));
      await flushUi(tester);
      expect(find.textContaining('Device connection timed out.'), findsNothing);
      requests[1].succeed(roster('Recovered employee', '1'));
      await flushUi(tester);
      expect(find.text('Recovered employee'), findsOneWidget);
    },
  );

  testWidgets(
    'duplicate lookup from a previous device cannot mark current users as duplicates',
    (tester) async {
      delayDuplicates = true;
      await openDialog(tester);
      requests[0].succeed(roster('Old employee', '1'));
      await flushUi(tester);
      expect(duplicateRequests, hasLength(1));
      await selectDevice(tester, 'Testing');
      requests[1].succeed(roster('Current employee', '1'));
      await flushUi(tester);
      duplicateRequests[1].succeed([]);
      await flushUi(tester);
      duplicateRequests[0].succeed([
        {'id': 'linked', 'full_name': 'Old employee', 'biometric_user_id': '1'},
      ]);
      await flushUi(tester);
      expect(find.text('Current employee'), findsOneWidget);
      expect(find.text('Duplicate'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Import'), findsOneWidget);
    },
  );

  testWidgets(
    'imports wait for the current duplicate check and linked users remain blocked',
    (tester) async {
      delayDuplicates = true;
      await openDialog(tester);
      requests[0].succeed(roster('Linked employee', '1'));
      await flushUi(tester);
      expect(find.widgetWithText(FilledButton, 'Import'), findsNothing);
      duplicateRequests.single.succeed([
        {
          'id': 'linked',
          'full_name': 'Linked employee',
          'biometric_user_id': '1',
        },
      ]);
      await flushUi(tester);
      expect(find.text('Linked employee'), findsOneWidget);
      expect(find.text('Duplicate'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Import'), findsNothing);
    },
  );

  testWidgets(
    'failed duplicate checks show a retryable error instead of enabling unchecked imports',
    (tester) async {
      delayDuplicates = true;
      await openDialog(tester);
      requests[0].succeed(roster('Unchecked employee', '1'));
      await flushUi(tester);
      duplicateRequests.single.fail();
      await flushUi(tester);
      expect(
        find.textContaining(
          'Could not check existing employee links for Offline clock.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Import'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Fetch Users'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('closing the dialog ignores outstanding failures', (
    tester,
  ) async {
    await openDialog(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await flushUi(tester);
    requests[0].fail();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
