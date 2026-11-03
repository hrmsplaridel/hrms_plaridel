# Employee attendance tracking start

Configure this in the existing **Assignments** page. Select an employee, add or edit a primary assignment, choose **Attendance tracking starts**, and save the assignment. No environment variable or separate setup page is required.

For example, an employee hired and assigned on **2025-01-01** can start attendance tracking on **2026-11-01**. Keep the real hire and assignment dates. Missing scheduled days before November are shown as **Not tracked**, rather than Absent, and do not generate attendance deductions. November onward follows the normal assignment, schedule, holiday, leave, locator, and attendance policy rules.

The date belongs to the employee, so transfers and later shifts preserve it. Leaving it blank retains the existing assignment-based behavior. **Use assignment schedule** clears the date, subject to the same validation as other changes. Existing employees are not assigned a tracking date automatically.

Imported historical punches and approved leave/locator records remain visible. Official report deductions and month-end attendance deductions exclude dates before tracking starts; missing historical days are excluded from absence counts. This date does not import balances, erase historical attendance, or change monthly leave accrual eligibility. Continue using opening balances and opening usage for historical leave data.

Tracking changes are audited and saved in the same transaction as the assignment. Invalid dates and dates before hire are rejected. Changes affecting an existing month-end attendance deduction record are rejected with HTTP 409; the system does not silently reverse previously posted deductions. HR must reconcile affected postings before changing that boundary.

## Database

- Additive migration: `backend/scripts/migrations/dtr/20261101_employee_attendance_tracking.sql`.
- Fresh installations: the nullable `users.attendance_tracking_start_date DATE` column is included in `backend/scripts/init-schema.sql`.
- Existing databases: apply the migration before deploying the backend. It does not backfill employee dates.
- Applied and verified locally against `hrms_plaridel` on loopback PostgreSQL port 5433. Server deployment remains separate.

## Verification

- `npm run test:employee-attendance-tracking`: service, assignment transaction, report overlays, and month-end regressions.
- `EMPLOYEE_TRACKING_DB_TEST=1 node --test test/employeeAttendanceTrackingPostgres.integration.test.js`: PostgreSQL integration test; temporary users and postings are rolled back.
- `npm run test:dtr-management` and `npm run test:leave-management`.
- Flutter assignment, attendance, report, and export tests, plus Dart analysis of changed files.

## Complete change inventory (23 files)

Database and backend:

1. `backend/package.json`
2. `backend/scripts/init-schema.sql`
3. `backend/scripts/migrations/dtr/20261101_employee_attendance_tracking.sql`
4. `backend/src/services/employeeAttendanceTracking.js`
5. `backend/src/routes/assignments.js`
6. `backend/src/services/leaveAttendanceDeduction.js`
7. `backend/src/modules/dtr/use-cases/completeReport.js`
8. `backend/src/modules/dtr/services/reportAbsences.js`
9. `backend/src/modules/dtr/services/reportPolicies.js`

Frontend:

10. `frontend/lib/features/dtr/management/assignments/pages/manage_assignment.dart`
11. `frontend/lib/features/dtr/management/assignments/widgets/assignment_forms.dart`
12. `frontend/lib/features/dtr/attendance/presentation/widgets/attendance_display.dart`
13. `frontend/lib/features/dtr/attendance/presentation/shared/pages/dtr_time_logs_content.dart`
14. `frontend/lib/features/dtr/reports/presentation/pages/dtr_reports.dart`
15. `frontend/lib/features/dtr/reports/data/dtr_export.dart`

Tests and documentation:

16. `backend/test/employeeAttendanceTracking.test.js`
17. `backend/test/employeeAttendanceTrackingPostgres.integration.test.js`
18. `backend/test/assignmentRoutesTransaction.test.js`
19. `backend/test/dtrReportOverlays.test.js`
20. `backend/test/leaveAttendanceDeduction.test.js`
21. `frontend/test/dtr/management/assignment_upcoming_empty_state_test.dart`
22. `frontend/test/dtr/reports/employee_tracking_export_test.dart`
23. `docs/employee-attendance-tracking.md`
