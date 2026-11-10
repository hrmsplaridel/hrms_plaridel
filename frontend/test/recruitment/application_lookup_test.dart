import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/pages/application_flow_page.dart';
import 'package:hrms_plaridel/features/recruitment/presentation/applicant/pages/track_application_page.dart';

const _applicationId = '11111111-1111-4111-8111-111111111111';
const _applicantNumber = 'PLR-TEST2345';

class _StatusApi {
  int status = 200;
  bool connectionFailure = false;
  bool malformed = false;
  bool legacySubmitResponse = false;
  bool gateRequired = false;
  String applicationId = _applicationId;
  final requests = <RequestOptions>[];

  Map<String, dynamic> get payload => {
    'application': {
      'id': applicationId,
      'applicant_number': _applicantNumber,
      'full_name': 'Test Applicant',
      'email': 'reused@example.com',
      'position_applied_for': 'IT Programmer',
      'status': 'passed',
      'step4_gate_required': gateRequired,
      'wes_status': 'waiting_for_work_experience_sheet',
      'applicants_profile_status': 'waiting',
      'selection_lineup_status': 'waiting',
    },
    'examResult': {
      'id': '22222222-2222-4222-8222-222222222222',
      'application_id': applicationId,
      'score_percent': 92,
      'passed': true,
      'bei_grading_complete': false,
    },
  };

  Interceptor get interceptor => InterceptorsWrapper(
    onRequest: (options, handler) {
      requests.add(options);
      if (connectionFailure || status != 200) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: connectionFailure
                ? DioExceptionType.connectionError
                : DioExceptionType.badResponse,
            response: connectionFailure
                ? null
                : Response(
                    requestOptions: options,
                    statusCode: status,
                    data: {'error': 'Status temporarily unavailable'},
                  ),
          ),
        );
        return;
      }
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: malformed || (legacySubmitResponse && options.method == 'POST')
              ? {'ok': true}
              : payload,
        ),
      );
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _StatusApi api;

  setUpAll(() => ApiClient.instance.init());
  setUp(() {
    api = _StatusApi();
    ApiClient.instance.dio.interceptors
      ..clear()
      ..add(api.interceptor);
  });

  for (final query in ['reused@example.com', _applicantNumber]) {
    test(
      '$query returns null only when the application is not found',
      () async {
        api.status = 404;
        expect(
          await RecruitmentRepo.instance.getApplicationByEmailOrApplicantNumber(
            query,
          ),
          isNull,
        );
        for (final status in [429, 500, 503]) {
          api.status = status;
          await expectLater(
            RecruitmentRepo.instance.getApplicationByEmailOrApplicantNumber(
              query,
            ),
            throwsA(
              isA<DioException>().having(
                (error) => error.response?.statusCode,
                'status',
                status,
              ),
            ),
          );
        }
        api.connectionFailure = true;
        await expectLater(
          RecruitmentRepo.instance.getApplicationByEmailOrApplicantNumber(
            query,
          ),
          throwsA(isA<DioException>()),
        );
      },
    );
  }

  test(
    'an invalid status response is not treated as a missing application',
    () async {
      api.malformed = true;
      await expectLater(
        RecruitmentRepo.instance.getApplicationByEmail('reused@example.com'),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Could not read application status'),
          ),
        ),
      );
    },
  );

  test(
    'exam submission supplies Step 4 state without another lookup',
    () async {
      api.gateRequired = true;
      final saved = await RecruitmentRepo.instance.submitExamResult(
        applicationId: _applicationId,
        scorePercent: 92,
        passed: true,
      );
      expect(saved!.application.step4GateRequired, isTrue);
      expect(saved.examResult!.passed, isTrue);
      expect(api.requests, hasLength(1));
      expect(api.requests.single.method, 'POST');
    },
  );

  test('older submission responses allow a status refresh', () async {
    api.legacySubmitResponse = true;
    expect(
      await RecruitmentRepo.instance.submitExamResult(
        applicationId: _applicationId,
        scorePercent: 92,
        passed: true,
      ),
      isNull,
    );
  });

  testWidgets('one status poll recovers Step 4 while BEI is still pending', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: ApplicationFlowPage(resumeEmail: 'reused@example.com'),
      ),
    );
    await tester.pumpAndSettle();
    final initialCount = api.requests.length;

    api.status = 429;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(api.requests.length, initialCount + 1);
    expect(api.requests.last.queryParameters, {'number': _applicantNumber});
    expect(find.text('Could not refresh application status'), findsOneWidget);
    expect(find.text('Waiting for deliberation result'), findsNothing);
    expect(find.textContaining('No application found'), findsNothing);

    api.status = 200;
    api.gateRequired = true;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(api.requests.length, initialCount + 2);
    expect(find.text('Step 4 — Deliberation Preparation'), findsOneWidget);
    expect(find.text('Could not refresh application status'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'an existing session does not switch to another application using the same email',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: ApplicationFlowPage(resumeEmail: 'reused@example.com'),
        ),
      );
      await tester.pumpAndSettle();
      api.applicationId = '33333333-3333-4333-8333-333333333333';
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('This application is no longer available'),
        findsOneWidget,
      );
      expect(api.requests.last.queryParameters, {'number': _applicantNumber});
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final page in <Widget>[
    const ApplicationFlowPage(),
    const TrackApplicationPage(),
  ]) {
    testWidgets(
      '${page.runtimeType} distinguishes a failed lookup from a missing application',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(home: page));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).first,
          'reused@example.com',
        );
        await tester.pump();
        api.status = 429;
        final checkButton = find.byType(FilledButton).first;
        await tester.ensureVisible(checkButton);
        await tester.tap(checkButton);
        await tester.pumpAndSettle();
        expect(find.text('Status temporarily unavailable'), findsOneWidget);
        expect(find.textContaining('No application found'), findsNothing);

        api.status = 404;
        await tester.tap(checkButton);
        await tester.pumpAndSettle();
        expect(find.textContaining('No application found'), findsOneWidget);
        expect(find.text('Status temporarily unavailable'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
