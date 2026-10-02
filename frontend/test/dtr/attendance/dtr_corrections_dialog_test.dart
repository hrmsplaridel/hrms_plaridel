import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/attendance/presentation/widgets/dtr_corrections_dialog.dart';

void main() {
  final paths = <String>[];
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    paths.clear();
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          paths.add(options.path);
          handler.resolve(
            Response(
              requestOptions: options,
              data: options.path.contains('/original/')
                  ? {
                      'time_in': '2026-10-02T00:00:00Z',
                      'status': 'present',
                      'shift_punch_mode': 'full_day',
                    }
                  : <dynamic>[],
            ),
          );
        },
      ),
    );
  });
  for (final width in [390.0, 1200.0]) {
    testWidgets(
      'employee request form fits $width and validates empty submission',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: DtrCorrectionsDialog())),
        );
        await tester.pumpAndSettle();
        expect(find.text('No correction requests'), findsOneWidget);
        expect(paths, ['/api/dtr-corrections']);
        await tester.tap(find.text('Request correction'));
        await tester.pumpAndSettle();
        expect(find.text('AM In'), findsOneWidget);
        expect(find.text('PM Out'), findsOneWidget);
        expect(find.textContaining('Original: 8:00'), findsOneWidget);
        expect(find.text('Supporting document (optional)'), findsOneWidget);
        expect(find.text('Attach PDF / JPG / PNG (max 5 MB)'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('My DTR Corrections'), findsNothing);
        expect(find.byType(InputDecorator), findsWidgets);
        await tester.tap(find.text('Submit request'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Choose at least one punch'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('My DTR Corrections'), findsOneWidget);
      },
    );
  }
  testWidgets('single-session shift shows only Time In and Time Out', (
    tester,
  ) async {
    final day = DateTime.now().toUtc().add(const Duration(hours: 8));
    final timeIn = DateTime.utc(day.year, day.month, day.day, 14);
    final nextDayOut = DateTime.utc(day.year, day.month, day.day, 23);
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(
            requestOptions: options,
            data: options.path.contains('/original/')
                ? {
                    'time_in': timeIn.toIso8601String(),
                    'time_out': nextDayOut.toIso8601String(),
                    'shift_punch_mode': 'single_session',
                  }
                : <dynamic>[],
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DtrCorrectionsDialog())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request correction'));
    await tester.pumpAndSettle();
    expect(find.text('Time In'), findsOneWidget);
    expect(find.text('Time Out'), findsOneWidget);
    expect(find.text('AM Out'), findsNothing);
    expect(find.text('PM In'), findsNothing);
    expect(find.textContaining('(+1 day)'), findsOneWidget);
  });
  testWidgets('review list does not offer employee submission', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DtrCorrectionsDialog(review: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Review DTR Corrections'), findsOneWidget);
    expect(find.text('Request correction'), findsNothing);
  });
  testWidgets('failed load offers retry and disables new requests', (
    tester,
  ) async {
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(
                requestOptions: options,
                statusCode: 404,
                data: {'error': 'Resource not found.'},
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DtrCorrectionsDialog())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No correction requests'), findsNothing);
    await tester.tap(find.text('Request correction'));
    await tester.pumpAndSettle();
    expect(find.text('Request DTR Correction'), findsNothing);
  });
}
