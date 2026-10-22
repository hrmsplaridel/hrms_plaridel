import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_plaridel/features/mayor/presentation/pages/mayor_dashboard_page.dart';

void main() {
  test('MayorDashboardData parses Phase 4 dashboard payload', () {
    final data = MayorDashboardData.fromJson({
      'timezone': 'Asia/Manila',
      'week_boundary': 'monday',
      'summary': {
        'total_requests': 10,
        'pending_count': 3,
        'mayor_approved_count': 1,
        'endorsed_count': 4,
        'rejected_count': 2,
        'endorsed_today': 1,
        'endorsed_this_week': 2,
        'endorsed_this_month': 3,
        'pending_meeting_approvals': 2,
        'pending_final_decisions': 1,
        'pending_attendance': 1,
        'reschedule_requested_count': 0,
        'approved_meetings_count': 5,
        'completed_meetings_count': 4,
        'meetings_today': 1,
        'upcoming_meetings': 2,
        'requests_today': 1,
        'requests_this_week': 4,
        'requests_this_month': 6,
        'rejected_today': 0,
        'rejected_this_week': 1,
        'rejected_this_month': 2,
        'meetings_on_today': 1,
        'meetings_this_week': 2,
        'meetings_this_month': 3,
        'legacy_scheduled_without_meeting_approval': 0,
      },
      'monthly_trends': [
        {'month': '2026-09', 'endorsed_count': 1},
        {'month': '2026-10', 'endorsed_count': 3},
      ],
      'office_statistics': [
        {'office_name': 'HRMO', 'total': 2},
      ],
      'recent_endorsements': [
        {
          'id': 'a1111111-1111-1111-1111-111111111111',
          'applicant_name': 'Jane Doe',
          'office_name': 'HRMO',
          'status': 'endorsed',
          'reference_number': 'MER-20261020-ABC',
        },
      ],
      'pending_mayor_actions': [
        {
          'id': 'b2222222-2222-2222-2222-222222222222',
          'applicant_name': 'John Smith',
          'office_name': 'Accounting',
          'status': 'pending',
          'meeting_request_status': 'submitted',
        },
      ],
      'meeting_queue': [],
      'upcoming_meetings': [],
      'recent_requests': [],
    });

    expect(data.totalRequests, 10);
    expect(data.endorsedToday, 1);
    expect(data.endorsedThisWeek, 2);
    expect(data.pendingMeetingApprovals, 2);
    expect(data.monthlyTrends.length, 2);
    expect(data.monthlyTrends.last.endorsedCount, 3);
    expect(data.recentEndorsements.single.referenceNumber, 'MER-20261020-ABC');
    expect(data.pendingMayorActions.single.meetingRequestStatus, 'submitted');

    final summary = data.toMonitoringSummary();
    expect(summary.endorsedThisMonth, 3);
    expect(summary.requestsThisMonth, 6);
    expect(summary.rejectedThisMonth, 2);
    expect(summary.meetingsThisMonth, 3);
    expect(summary.meetingsToday, 1);
    expect(summary.legacyScheduledWithoutMeetingApproval, 0);
  });

  test('empty Phase 4 payload yields zeros', () {
    final data = MayorDashboardData.fromJson({});
    expect(data.totalRequests, 0);
    expect(data.endorsedCount, 0);
    expect(data.monthlyTrends, isEmpty);
    expect(data.recentEndorsements, isEmpty);
  });
}
