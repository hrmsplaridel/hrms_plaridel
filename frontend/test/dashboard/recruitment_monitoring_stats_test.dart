import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/dashboard/presentation/admin/desktop/widgets/recruitment_monitoring_stats.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';

RecruitmentApplication _app({
  required String id,
  required String status,
  DateTime? createdAt,
  bool finalRequirementsApproved = false,
  DateTime? orientationAt,
  bool? orientationAttended,
  bool? finalInterviewPassed,
  String? hiredUserId,
  bool hrAccountSetupDone = false,
}) {
  return RecruitmentApplication(
    id: id,
    fullName: 'Applicant $id',
    email: '$id@example.com',
    status: status,
    createdAt: createdAt,
    finalRequirementsApproved: finalRequirementsApproved,
    orientationAt: orientationAt,
    orientationAttended: orientationAttended,
    finalInterviewPassed: finalInterviewPassed,
    hiredUserId: hiredUserId,
    hrAccountSetupDone: hrAccountSetupDone,
  );
}

void main() {
  test('KPI counts match the existing dashboard status rules', () {
    final stats = RecruitmentMonitoringStats.fromApps([
      _app(id: '1', status: 'submitted'),
      _app(id: '2', status: 'document_approved'),
      _app(id: '3', status: 'exam_taken'),
      _app(id: '4', status: 'passed'),
      _app(id: '5', status: 'registered'),
      _app(id: '6', status: 'failed'),
    ]);

    expect(stats.total, 6);
    expect(stats.pending, 1);
    expect(stats.inProgress, 3);
    expect(stats.hired, 1);
    expect(stats.closed, 1);
  });

  test('pipeline assigns each applicant to the furthest existing stage', () {
    final stats = RecruitmentMonitoringStats.fromApps([
      _app(id: 'a', status: 'submitted'),
      _app(id: 'b', status: 'document_approved'),
      _app(id: 'c', status: 'exam_taken'),
      _app(id: 'd', status: 'passed'),
      _app(id: 'e', status: 'passed', finalInterviewPassed: true),
      _app(
        id: 'f',
        status: 'passed',
        finalInterviewPassed: true,
        finalRequirementsApproved: true,
      ),
      _app(id: 'g', status: 'passed', orientationAt: DateTime(2026, 9, 1)),
      _app(id: 'h', status: 'passed', hrAccountSetupDone: true),
      _app(id: 'i', status: 'registered'),
      _app(id: 'j', status: 'failed'),
    ]);

    Map<String, int> counts() => {
      for (final s in stats.pipeline) s.key: s.count,
    };

    expect(counts(), {
      'applied': 1,
      'review': 1,
      'exam': 1,
      'interview': 2,
      'requirements': 1,
      'orientation': 1,
      'account': 1,
      'hired': 1,
    });
  });

  test('attention items use existing statuses only', () {
    final items = RecruitmentMonitoringStats.attentionItems([
      _app(id: '1', status: 'submitted'),
      _app(id: '2', status: 'submitted'),
      _app(id: '3', status: 'exam_taken'),
      _app(id: '4', status: 'passed'),
      _app(id: '5', status: 'passed', finalInterviewPassed: true),
      _app(id: '6', status: 'registered'),
    ]);

    expect(items.map((e) => '${e.label}:${e.count}').toList(), [
      'Pending document review:2',
      'Pending exam review:1',
      'Pending interview:1',
      'Incomplete final requirements:1',
    ]);
  });

  test('monthly submissions use createdAt within the last 6 months', () {
    final now = DateTime(2026, 9, 15);
    final stats = RecruitmentMonitoringStats.fromApps([
      _app(id: '1', status: 'submitted', createdAt: DateTime(2026, 9, 6)),
      _app(id: '2', status: 'passed', createdAt: DateTime(2026, 9, 1)),
      _app(id: '3', status: 'submitted', createdAt: DateTime(2026, 4, 2)),
      _app(id: '4', status: 'submitted', createdAt: DateTime(2025, 12, 1)),
    ], now: now);

    expect(stats.monthlySubmissions.map((m) => m.label).toList(), [
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
    ]);
    expect(stats.monthlySubmissions.map((m) => m.count).toList(), [
      1,
      0,
      0,
      0,
      0,
      2,
    ]);
  });
}
