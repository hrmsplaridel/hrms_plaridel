import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/admin/admin_my_leave_entry.dart';
import 'package:hrms_plaridel/features/dtr/leave/presentation/shared/pages/leave_main.dart';

class _Repository extends MockLeaveRepository {
  _Repository(this.assigned);
  final bool assigned;
  @override
  Future<Map<String, dynamic>> checkIsDepartmentHead() async => {
    'isDeptHead': assigned,
    'canReviewPending': assigned,
  };
}

void main() {
  setUp(() {
    ApiClient.instance.init();
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          h.resolve(
            Response(requestOptions: o, statusCode: 200, data: <dynamic>[]),
          );
        },
      ),
    );
  });
  tearDown(() => ApiClient.instance.dio.interceptors.clear());
  testWidgets('failed workflow lookup does not create an approval tab', (
    tester,
  ) async {
    ApiClient.instance.dio.interceptors.clear();
    ApiClient.instance.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) => h.reject(DioException(requestOptions: o)),
      ),
    );
    final provider = LeaveProvider(repository: _Repository(false));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(
            body: AdminMyLeaveEntry(
              requestsContent: Text('Personal requests'),
              approvalsContent: Text('Reviewer queue'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Personal requests'), findsOneWidget);
    expect(find.text('Approvals'), findsNothing);
    expect(find.byType(LeaveMain), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });
  testWidgets(
    'My Leave exposes assigned custom approvals without a department designation',
    (tester) async {
      ApiClient.instance.init();
      ApiClient.instance.dio.interceptors.clear();
      ApiClient.instance.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: [
                  {'id': 'assigned', 'kind': 'leave'},
                ],
              ),
            );
          },
        ),
      );
      addTearDown(() => ApiClient.instance.dio.interceptors.clear());
      final provider = LeaveProvider(repository: _Repository(false));
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(
              body: AdminMyLeaveEntry(
                requestsContent: Text('Personal requests'),
                approvalsContent: Text('Custom queue'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Approvals'), findsOneWidget);
      await tester.tap(find.text('Approvals'));
      await tester.pumpAndSettle();
      expect(find.text('Custom queue'), findsOneWidget);
      expect(
        tester.widget<LeaveMain>(find.byType(LeaveMain)).isDepartmentHead,
        false,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    },
  );
  for (final assigned in [true, false]) {
    testWidgets('admin department approvals visibility: assigned=$assigned', (
      tester,
    ) async {
      final provider = LeaveProvider(repository: _Repository(assigned));
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(
              body: AdminMyLeaveEntry(
                requestsContent: Text('Personal requests'),
                approvalsContent: Text('Department queue'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Personal requests'), findsOneWidget);
      expect(find.text('Approvals'), assigned ? findsOneWidget : findsNothing);
      if (assigned) {
        expect(find.byType(LeaveMain), findsOneWidget);
        expect(find.byType(ChoiceChip), findsNothing);
        await tester.tap(find.text('Approvals'));
        await tester.pumpAndSettle();
        expect(find.text('Department queue'), findsOneWidget);
      }
    });
  }
}
