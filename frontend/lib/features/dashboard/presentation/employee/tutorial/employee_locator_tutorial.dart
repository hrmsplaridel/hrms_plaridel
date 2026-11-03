import 'package:flutter/widgets.dart';

import 'employee_tutorial_controller.dart';

class EmployeeLocatorTutorial {
  EmployeeLocatorTutorial._();

  static List<EmployeeTutorialTarget> targets({
    required bool isDepartmentHead,
    required GlobalKey headerKey,
    required GlobalKey requestsKey,
    GlobalKey? tabsKey,
    GlobalKey? approvalFiltersKey,
    VoidCallback? showMyRequests,
    VoidCallback? showApprovals,
  }) => [
    EmployeeTutorialTarget(
      key: headerKey,
      title: 'Locator Requests',
      body:
          'Select File Request to file your own locator, pass-slip, or work-from-home request with its destination, purpose, schedule, and required trip details.',
    ),
    if (isDepartmentHead && tabsKey != null)
      EmployeeTutorialTarget(
        key: tabsKey,
        title: 'My Requests and Approvals / History',
        body:
            'My Requests contains your own filings. Approvals / History contains requests assigned to you for review and their approval history. Approval access depends on your assigned workflow role.',
      ),
    EmployeeTutorialTarget(
      key: requestsKey,
      title: 'Find and track your requests',
      body:
          'Use the status, date, and search filters to find your own filings. Open a request to view its approval progress, remarks, and available correction or cancellation actions.',
      onFocus: showMyRequests,
    ),
    if (isDepartmentHead && approvalFiltersKey != null)
      EmployeeTutorialTarget(
        key: approvalFiltersKey,
        title: 'Filter Approvals / History',
        body:
            'Search by employee or request details and use From and To to narrow the dates. Pending finds requests awaiting action; Returned and Forwarded show workflow progress. Approved, Revoked, Rejected, and Cancelled show their recorded outcomes. Clear resets the filters.',
        onFocus: showApprovals,
      ),
    if (isDepartmentHead)
      EmployeeTutorialTarget(
        key: requestsKey,
        title: 'Review a request and its history',
        body:
            'Open a request row or card to inspect its purpose, destination, time coverage, attachment, and workflow history. Approve, return for correction, reject, or forward only when that action is available to your assigned review step. Completed or revoked records remain available for history and may have no review actions.',
        onFocus: showApprovals,
      ),
  ];
}
