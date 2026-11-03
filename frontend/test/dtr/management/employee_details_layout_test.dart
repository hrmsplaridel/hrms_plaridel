import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/features/dtr/management/employees/widgets/employee_details_view.dart';
import 'package:hrms_plaridel/shared/widgets/skeleton_bone.dart';

const _summary = ValueKey('employee-details-summary');
const _footer = ValueKey('employee-details-footer');
const _scroll = ValueKey('employee-details-scroll');

void main() {
  final calls = <RequestOptions>[];
  Completer<void>? fetchGate;
  late Map<String, dynamic> profile;
  setUp(() {
    calls.clear();
    fetchGate = null;
    profile = {
      'full_name': 'Edgar Cruz Ramos Jr.',
      'first_name': 'Edgar',
      'middle_name': 'Cruz',
      'last_name': 'Ramos',
      'suffix': 'Jr.',
      'employee_number': 12,
      'current_position_name': 'Administrative Assistant',
      'current_department_name': 'Human Resources',
      'employment_type': 'permanent',
      'employment_status': 'active',
      'is_active': false,
      'salary_grade': 'SG-12',
      'date_of_birth': '2004-03-01',
      'date_hired': '2026-01-15',
      'contact_number': '09903355853',
      'email': 'edgar@example.test',
      'role': 'employee',
      'address': 'Purok 2|Bato|Plaridel|Misamis Occidental',
      'leave_credit_eligible': true,
      'credit_balances': [
        {
          'user_id': 'employee',
          'leave_type': 'vacationLeave',
          'earned_days': '10',
          'used_days': '2',
          'pending_days': '1',
          'adjusted_days': '.5',
        },
      ],
      'assignment_history': [
        {
          'department_name': 'Human Resources',
          'position_name': 'Administrative Assistant',
          'shift_name': 'Regular shift',
          'effective_from': '2026-01-15',
          'effective_to': null,
          'status': 'Current',
          'remarks': 'Initial assignment',
        },
      ],
    };
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) async {
          calls.add(request);
          if (fetchGate != null) await fetchGate!.future;
          handler.resolve(
            Response(requestOptions: request, statusCode: 200, data: profile),
          );
        },
      ),
    );
  });
  tearDown(() => ApiClient.instance.dio.interceptors.clear());

  Future<void> mount(
    WidgetTester tester, {
    double width = 760,
    bool dark = false,
    double scale = 1,
    VoidCallback? onEdit,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? ThemeData.dark() : ThemeData.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: EmployeeDetailsView(employeeId: 'employee', onEdit: onEdit),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [360.0, 520.0, 760.0, 1100.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'employee profile groups fields and pins summary/footer at $width, dark=$dark',
        (tester) async {
          await mount(tester, width: width, dark: dark);
          expect(find.byKey(_summary), findsOneWidget);
          expect(find.byKey(_footer), findsOneWidget);
          expect(find.text('ER'), findsOneWidget);
          expect(find.text('Edgar Cruz Ramos Jr.'), findsOneWidget);
          final first = tester.getRect(
            find.byKey(const ValueKey('employee-detail-first-name')),
          );
          final middle = tester.getRect(
            find.byKey(const ValueKey('employee-detail-middle-name')),
          );
          if (width >= 640) {
            expect(first.top, closeTo(middle.top, .1));
            expect(middle.left, greaterThan(first.right));
          } else {
            expect(middle.top, greaterThan(first.bottom));
          }
          final employment = tester
              .getTopLeft(
                find.byKey(const ValueKey('employee-details-employment')),
              )
              .dy;
          final personal = tester
              .getTopLeft(
                find.byKey(
                  const ValueKey('employee-details-personal-information'),
                ),
              )
              .dy;
          final contact = tester
              .getTopLeft(
                find.byKey(const ValueKey('employee-details-contact')),
              )
              .dy;
          expect(personal, greaterThan(employment));
          expect(contact, greaterThan(personal));
          expect(find.text('March 1, 2004'), findsOneWidget);
          expect(find.text('SG-12'), findsOneWidget);
          expect(find.text('7.50 days'), findsOneWidget);
          expect(find.byType(TextFormField), findsNothing);
          expect(find.text('Edit employee'), findsNothing);

          final headerBefore = tester.getRect(find.byKey(_summary));
          final footerBefore = tester.getRect(find.byKey(_footer));
          await tester.drag(find.byKey(_scroll), const Offset(0, -1400));
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byKey(_summary)), headerBefore);
          expect(tester.getRect(find.byKey(_footer)), footerBefore);
          expect(
            find.widgetWithText(OutlinedButton, 'Close').hitTestable(),
            findsOneWidget,
          );
          expect(calls.every((request) => request.method == 'GET'), isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('long identity and larger text remain usable on mobile', (
    tester,
  ) async {
    profile['full_name'] = 'Maria Cristina De Los Santos Villanueva';
    profile['current_position_name'] =
        'Human Resource Management and Development Officer';
    profile['current_department_name'] =
        'Human Resource Management and Development Office';
    await mount(tester, width: 360, dark: true, scale: 1.5);
    expect(find.byKey(_summary), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Close').hitTestable(),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('SG-12'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Edit uses the host capability without writing from details', (
    tester,
  ) async {
    var edited = false;
    await mount(tester, onEdit: () => edited = true);
    await tester.tap(find.widgetWithText(FilledButton, 'Edit employee'));
    expect(edited, isTrue);
    expect(find.byType(TextFormField), findsNothing);
    expect(calls.every((request) => request.method == 'GET'), isTrue);
  });

  testWidgets(
    'salary grade remains verbatim and login is distinct from employment',
    (tester) async {
      profile['salary_grade'] = '50000';
      await mount(tester);
      expect(find.text('50000'), findsOneWidget);
      expect(find.text('Salary grade'), findsOneWidget);
      expect(find.text('₱50,000.00'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(_summary),
          matching: find.text('Active'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('employee-detail-login-status')),
          matching: find.text('Disabled'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('loading uses shared skeletons and keeps Close available', (
    tester,
  ) async {
    fetchGate = Completer<void>();
    await tester.pumpWidget(
      const MaterialApp(home: EmployeeDetailsView(employeeId: 'employee')),
    );
    await tester.pump();
    expect(find.byType(SkeletonBone), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Close').hitTestable(),
      findsOneWidget,
    );
    fetchGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(_summary), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
