import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/providers/leave_provider.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/data/repositories/mock_leave_repository.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_request.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type.dart';

void main() {
  for (final departmentHead in [false, true]) {
    test(
      '${departmentHead ? 'head' : 'HR'} queue reaches request 251',
      () async {
        final repository = _ReviewPagingRepository();
        final provider = LeaveProvider(repository: repository);
        addTearDown(provider.dispose);
        provider.onAuthUserChanged('reviewer');
        const query = LeaveRequestQuery(limit: 200);

        Future<void> refresh() => departmentHead
            ? provider.loadDepartmentHeadRequests(query: query)
            : provider.loadRequests(query: query);
        List<LeaveRequest> rows() => departmentHead
            ? provider.departmentHeadRequests
            : provider.requests;

        await refresh();
        expect(rows(), hasLength(200));
        expect(provider.reviewTotal(departmentHead: departmentHead), 251);
        expect(provider.reviewHasMore(departmentHead: departmentHead), isTrue);

        await provider.loadMoreReviewRequests(
          query: query,
          departmentHead: departmentHead,
        );
        expect(rows(), hasLength(251));
        expect(rows().last.id, 'request-250');
        expect(provider.reviewHasMore(departmentHead: departmentHead), isFalse);

        await refresh();
        expect(rows(), hasLength(251));

        const filtered = LeaveRequestQuery(
          userId: 'employee-250',
          department: 'Records',
          limit: 200,
        );
        if (departmentHead) {
          await provider.loadDepartmentHeadRequests(query: filtered);
        } else {
          await provider.loadRequests(query: filtered);
        }
        expect(rows().map((request) => request.id), ['request-250']);
        expect(provider.reviewTotal(departmentHead: departmentHead), 1);
      },
    );
  }
}

class _ReviewPagingRepository extends MockLeaveRepository {
  final List<LeaveRequest> all = List.generate(
    251,
    (index) => LeaveRequest(
      id: 'request-$index',
      userId: 'employee-$index',
      employeeName: 'Employee $index',
      officeDepartment: index == 250 ? 'Records' : 'Finance',
      leaveType: LeaveType.vacationLeave,
      startDate: DateTime(2026, 9, 21),
      endDate: DateTime(2026, 9, 21),
      workingDaysApplied: 1,
      status: LeaveRequestStatus.pendingHr,
    ),
  );

  @override
  Future<List<LeaveRequest>> listRequests({
    LeaveRequestQuery query = const LeaveRequestQuery(),
  }) async => all
      .where(
        (request) =>
            (query.userId == null || request.userId == query.userId) &&
            (query.department == null ||
                request.officeDepartment == query.department),
      )
      .toList();

  @override
  Future<List<LeaveRequest>> listDepartmentHeadRequests({
    LeaveRequestQuery query = const LeaveRequestQuery(),
  }) => listRequests(query: query);
}
