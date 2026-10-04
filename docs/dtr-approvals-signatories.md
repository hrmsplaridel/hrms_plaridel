# DTR Approvals & Signatories

Open DTR > Approvals & Signatories. The Leave Workflow and Locator Workflow
tabs edit the same existing department-head and final-HR configuration.
Separate Locator assignments and approval-stage bypasses are not introduced.
The DocuTracker workflow mirrors continue to read these records.

Choose a department to view its primary reviewer and up to five ordered backups.
The searchable left list shows departments and a separate office-wide Final HR
Review entry. On wide screens the selected settings appear alongside the list;
on narrow screens selection opens the details with a Back to list action.
Unsaved backup edits prevent changing the selected entry until saved or discarded.
Report Signatories uses the same layout, with roles on the left and the selected
official and designation history on the right.
Use Position designations to designate the Department Head position with its
effective period, or the office-wide final reviewer position. The employee
assigned to that position remains the primary reviewer. Final reviewers must
meet the existing HR/admin eligibility rules. Final position designations are
current settings; backup lists and department-head periods support effective dates.
Removing a designation does not disable the corresponding approval stage.

Report Signatories assigns the Office-hours Verifier, HR Report Officer, and
shared Leave Credit Certifier. These are effective-dated, audited records in
the existing official-signatory registry. They do not grant approval permissions.
DTR printing uses today's effective officials and their stored title snapshots.
Until a DTR role is explicitly configured, its legacy position lookup remains
available. Once a designation exists, an expired/future-only period leaves that
role unconfigured rather than substituting a legacy employee.

## Deployment

After pulling the backend, apply
`backend/scripts/migrations/dtr/20260930_dtr_report_signatories.sql` to the target
database (after the existing DocuTracker signatory migrations), then restart
`hrms-api`. The migration only expands allowed role keys; it does not assign
people or modify existing reviewer records. Rebuild the Flutter client for the UI.

## Verification

From `backend`:

```sh
node --test test/officialSignatoryService.test.js test/dtrReportSignatoriesAccess.test.js test/leaveFinalReviewerService.test.js
```

From `frontend`:

```sh
flutter test --no-pub test/dtr/approvals/approvals_signatories_page_test.dart test/dtr/reports/dtr_report_signatories_test.dart
```

Configure each DTR signatory, reload Reports, and verify both names and titles in
the preview. Change a backup and check that both workflow tabs and DocuTracker's
read-only mirror show the saved reviewer configuration.
# Configuration Ownership

Department and Position forms now edit basic details and status only. Configure
department-head designations, final reviewers, effective dates, and backups in
DTR > Approvals & Signatories. Ordinary position updates omit designation fields
so existing reviewer settings and designation periods are preserved. No database
migration is required for removing these duplicate controls.
