import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/core/api/app_user.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/shared/pages/dtr_time_logs_content.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/features/dtr/attendance/models/time_record.dart';
import 'package:hrms_plaridel/providers/auth_provider.dart';

void main() {
  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.instance.init();
  });

  late DtrProvider provider;
  late List<Map<String, dynamic>> recordRequests;
  late List<Map<String, dynamic>> rows;
  String? failure;

  setUp(() {
    provider = DtrProvider();
    addTearDown(provider.dispose);
    recordRequests = [];
    rows = [];
    failure = null;
    final dio = ApiClient.instance.dio;
    dio.interceptors.clear();
    addTearDown(dio.interceptors.clear);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          dynamic data = <dynamic>[];
          if (options.path == '/api/employees') {
            data = [
              {'id': 'saved-employee', 'full_name': 'Saved Employee'},
            ];
          } else if (options.path == '/api/dtr-daily-summary') {
            if (options.method == 'POST') {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionError,
                ),
              );
              return;
            }
            recordRequests.add(Map.of(options.queryParameters));
            if (failure != null) {
              final missing = failure == 'missing';
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: missing
                      ? DioExceptionType.badResponse
                      : DioExceptionType.connectionError,
                  message: missing
                      ? 'PGRST205: Could not find the table public.time_records'
                      : 'Connection failed with internal network details',
                  response: missing
                      ? Response(
                          requestOptions: options,
                          statusCode: 500,
                          data: {
                            'error':
                                'Could not find the table public.time_records',
                          },
                        )
                      : null,
                ),
              );
              return;
            }
            data = rows;
          }
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data),
          );
        },
      ),
    );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(
    WidgetTester tester, {
    double width = 1280,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthProvider()
      ..replaceUser(
        const AppUser(id: 'admin', email: 'admin@test.local', role: 'admin'),
      );
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: provider),
        ],
        child: MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const Scaffold(
            body: SingleChildScrollView(child: DtrTimeLogsContent()),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  for (final width in [360.0, 768.0, 1280.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('missing attendance shows an error and Retry at $width '
          'in $brightness', (tester) async {
        failure = 'missing';
        await open(tester, width: width, brightness: brightness);
        expect(find.text("Time logs couldn't be loaded."), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(
          find.textContaining('contact your system administrator'),
          findsOneWidget,
        );
        expect(find.textContaining('sample data'), findsNothing);
        expect(find.textContaining('DioException'), findsNothing);
        expect(find.textContaining('PGRST205'), findsNothing);
        expect(find.text('No time records match your filters.'), findsNothing);
        expect(tester.takeException(), isNull);

        final failedQuery = Map.of(recordRequests.last);
        failure = null;
        final now = DateTime.now();
        rows = [
          {
            'id': 'saved-record',
            'user_id': 'saved-employee',
            'employee_name': 'Saved Employee',
            'record_date': now.toIso8601String().split('T').first,
            'status': 'present',
          },
        ];
        await tester.ensureVisible(find.text('Retry'));
        await tester.tap(find.text('Retry'));
        await settle(tester);
        expect(recordRequests, hasLength(2));
        expect(recordRequests.last, failedQuery);
        expect(find.text("Time logs couldn't be loaded."), findsNothing);
        expect(find.text('Saved Employee'), findsWidgets);
        expect(provider.error, isNull);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('network failures stay distinct from successful empty results', (
    tester,
  ) async {
    failure = 'network';
    await open(tester);
    expect(find.text("Time logs couldn't be loaded."), findsOneWidget);
    expect(
      find.text('No internet connection or the server is unreachable.'),
      findsOneWidget,
    );
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.text('No time records match your filters.'), findsNothing);

    failure = null;
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(find.text("Time logs couldn't be loaded."), findsNothing);
    expect(find.text('No time records match your filters.'), findsOneWidget);
    expect(find.textContaining('sample data'), findsNothing);
    expect(find.text('Juan Dela Cruz'), findsNothing);
  });

  test(
    'a successful silent record refresh clears the previous error',
    () async {
      final now = DateTime.now();
      failure = 'network';
      await provider.loadTimeRecordsForAdmin(startDate: now, endDate: now);
      expect(provider.error, isNotNull);
      expect(provider.timeRecordsError, isNotNull);

      failure = null;
      await provider.loadTimeRecordsForAdmin(
        startDate: now,
        endDate: now,
        silent: true,
        forceRefresh: true,
      );
      expect(provider.error, isNull);
      expect(provider.timeRecordsError, isNull);
    },
  );

  test('sign out clears record-load errors', () async {
    provider.onAuthUserChanged('account-a');
    failure = 'network';
    final now = DateTime.now();
    await provider.loadTimeRecordsForAdmin(startDate: now, endDate: now);
    expect(provider.timeRecordsError, isNotNull);

    provider.onAuthUserChanged(null);
    expect(provider.timeRecordsError, isNull);
    expect(provider.error, isNull);
  });

  testWidgets('a failed manual save is not presented as a failed record load', (
    tester,
  ) async {
    await open(tester);
    final saved = provider.addManualEntry(
      TimeRecord(userId: 'saved-employee', recordDate: DateTime.now()),
    );
    await settle(tester);
    expect(await saved, isFalse);
    expect(provider.error, isNotNull);
    expect(find.text("Time logs couldn't be loaded."), findsNothing);
    expect(find.text('No time records match your filters.'), findsOneWidget);
  });
}
