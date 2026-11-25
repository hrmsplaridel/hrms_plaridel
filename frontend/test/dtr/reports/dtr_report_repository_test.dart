import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/dtr_provider.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_report_assignments.dart';
import 'package:hrms_plaridel/features/dtr/reports/data/dtr_report_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
  });
  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  test(
    'one failed report source preserves the other verified results',
    () async {
      final requests = <String>[];
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            requests.add(o.path);
            if (o.path == '/api/dtr-daily-summary') {
              h.reject(
                DioException(
                  requestOptions: o,
                  type: DioExceptionType.connectionError,
                ),
              );
            } else {
              h.resolve(
                Response(
                  requestOptions: o,
                  data: o.path == '/api/assignments'
                      ? [
                          {
                            'effective_from': '2026-02-01',
                            'start_time': '08:00',
                            'end_time': '17:00',
                          },
                        ]
                      : {
                          'roles': {
                            for (final role in [
                              'dtr_office_hours_verifier',
                              'dtr_hr_officer',
                            ])
                              role: {
                                'configured': true,
                                'current': {
                                  'name': role,
                                  'position_title': 'Officer',
                                },
                              },
                          },
                        },
                ),
              );
            }
          },
        ),
      );
      final report = await DtrReportRepository().fetchEmployeeReport(
        'a',
        year: 2026,
        month: 2,
      );
      expect(report.records.succeeded, isFalse);
      expect(report.assignments.value, hasLength(1));
      expect(report.signatories.value!.isConfigured, isTrue);
      expect(requests.toSet(), {
        '/api/dtr-daily-summary',
        '/api/assignments',
        '/api/dtr-report-signatories',
      });
    },
  );

  test(
    'employee request keeps status, department and inclusive historical dates',
    () async {
      late RequestOptions request;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            request = o;
            h.resolve(
              Response(
                requestOptions: o,
                data: [
                  {
                    'id': 'old',
                    'full_name': 'Former Employee',
                    'employee_number': '7',
                    'is_active': false,
                    'employment_status': 'resigned',
                    'current_shift_punch_mode': 'single_session',
                  },
                  {'id': '', 'full_name': 'Invalid'},
                ],
              ),
            );
          },
        ),
      );
      final employees = await DtrReportRepository().fetchReportEmployees(
        departmentId: ' finance ',
        employeeStatus: 'All',
        startDate: DateTime(2026, 2),
        endDate: DateTime(2026, 2, 28),
      );
      expect(request.path, '/api/employees');
      expect(request.queryParameters, {
        'status': 'All',
        'role': 'All',
        'start_date': '2026-02-01',
        'end_date': '2026-02-28',
        'department_id': 'finance',
      });
      expect(employees.single.employeeNumber, 7);
      expect(employees.single.isActive, isFalse);
      expect(employees.single.shiftPunchMode, 'single_session');
    },
  );

  test(
    'assignment parsing retains overrides, overnight hours and month boundaries',
    () {
      final timeline = parseDtrAssignmentTimeline(
        [
          {'effective_from': '2026-01-01', 'effective_to': '2026-01-31'},
          {
            'effective_from': '2026-02-01',
            'effective_to': '2026-02-14',
            'start_time': '08:00',
            'end_time': '17:00',
            'break_end': '13:00',
            'working_days': [1, '2', 3, 4, 5, 8],
            'punch_mode': 'full_day',
            'schedule_overrides': [
              {'date': '2026-02-07', 'is_working_day': true},
              {'date': '2026-02-09', 'is_working_day': false},
            ],
          },
          {
            'effective_from': '2026-02-15',
            'effective_to': null,
            'start_time': '22:00',
            'end_time': '06:00',
            'working_days': [1, 2, 3, 4, 5],
          },
          {'effective_from': '2026-03-01'},
        ],
        year: 2026,
        month: 2,
      );
      expect(timeline, hasLength(2));
      expect(timeline.first.workingDays, [1, 2, 3, 4, 5]);
      expect(timeline.first.workHoursPerDay, 8);
      expect(isDtrScheduledWorkDay(DateTime(2026, 2, 7), timeline), isTrue);
      expect(isDtrScheduledWorkDay(DateTime(2026, 2, 9), timeline), isFalse);
      expect(timeline.last.overnight, isTrue);
      expect(timeline.last.punchMode, 'single_session');
      expect(timeline.last.workHoursPerDay, 8);
      expect(timeline.last.officialHours, contains('(+1 day)'));
    },
  );

  test(
    'bulk loading preserves returned records, cutoff, assignments and per-employee errors',
    () async {
      late RequestOptions request;
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            request = o;
            h.resolve(
              Response(
                requestOptions: o,
                data: {
                  'employees': [
                    {
                      'employee_id': 'a',
                      'reportable_through': '2026-02-20',
                      'records': [
                        {
                          'id': 'r',
                          'employee_id': 'a',
                          'attendance_date': '2026-02-01',
                          'status': 'present',
                        },
                      ],
                      'assignments': [
                        {
                          'effective_from': '2026-02-01',
                          'start_time': '08:00',
                          'end_time': '17:00',
                        },
                      ],
                    },
                  ],
                  'errors': [
                    {'employee_id': 'b', 'error': 'Missing policy'},
                  ],
                },
              ),
            );
          },
        ),
      );
      final batch = await DtrReportRepository().fetchBulkReportBatch(
        [
          const EmployeeOption(id: 'a', fullName: 'A'),
          const EmployeeOption(id: 'b', fullName: 'B'),
        ],
        year: 2026,
        month: 2,
      );
      expect(request.path, '/api/dtr-daily-summary/bulk-report');
      expect(request.data, {
        'employee_ids': ['a', 'b'],
        'start_date': '2026-02-01',
        'end_date': '2026-02-28',
      });
      expect(request.receiveTimeout, const Duration(minutes: 2));
      expect(batch.employees['a']!.recordsPage.items, hasLength(1));
      expect(
        batch.employees['a']!.recordsPage.reportableThrough,
        DateTime(2026, 2, 20),
      );
      expect(batch.employees['a']!.assignmentTimeline, hasLength(1));
      expect(batch.errors, {'b': 'Missing policy'});
    },
  );
}
