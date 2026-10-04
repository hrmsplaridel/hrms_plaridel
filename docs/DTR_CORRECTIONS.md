# DTR Correction Requests

Apply `backend/scripts/migrations/dtr/20261002_dtr_correction_audit.sql` to existing databases before deploying. Fresh databases include these columns in `init-schema.sql`.

Apply `backend/scripts/migrations/dtr/20261003_dtr_correction_reviewers.sql` to existing databases. Before accepting new requests, an admin must configure a primary under DTR > Approvals & Signatories > DTR Corrections. A backup is required when a second active admin/HR account exists. There is no default all-admin reviewer fallback. The configuration is office-wide and effective-dated; the current configured reviewers handle pending requests, including requests submitted before a configuration change. Each save adds an audit revision, even for the same effective date.

- Employees: My Attendance > DTR Corrections > Request correction.
- Enter only changed punches. Unselected punches retain their existing values. Select +1 day for next-day overnight punches. Deleting an existing punch is not supported by this request flow.
- Submission includes the original attendance revision from the preview. If the record changes while the form is open, the request is blocked until the employee loads and reviews the updated attendance. The form retains the draft punches, reason, and attachment. Reload the frontend after deploying this change; older clients without a revision cannot submit corrections.
- A reason is required. One optional PDF, JPG/JPEG or PNG up to 5 MB may be previewed and removed before submission. Apply `20261002_dtr_correction_attachments.sql` for existing databases. Evidence is stored in a private table in the same transaction as the request and accessed only by its owner or an assigned reviewer. File extension and signature checks do not replace malware scanning.
- Assigned HR/admin reviewers: DTR > DTR Corrections. Filter the request queue by status or employee, then open a request to compare original and requested timestamps. Review notes are required for approval and rejection. Only current assigned reviewers can view the shared queue, request evidence, or decide requests; the employee retains access to their own requests.
- Self-review is prohibited. Employees cannot submit on behalf of others or read another employee's requests.
- Assigned admin reviewers must retain DTR Corrections access. Submission availability and notifications exclude admins whose access has been revoked; reviewer options and backup requirements count only eligible accounts. Active HR reviewers retain their role-based access. A request requires at least one eligible configured reviewer other than its requester.
- Only one pending request per employee/date is permitted through the API. Already-reviewed requests cannot be reviewed again. If attendance changes after submission, reject and request a fresh submission.
- Approval applies the existing attendance calculations, preserves raw biometric logs, marks the summary Adjusted, saves before/after evidence, and queues closed-period reconciliation in one transaction. Rejection leaves attendance unchanged.
- Month-End reconciliation follows the existing scheduler/manual rerun timing; it is not an immediate deduction adjustment.
- Existing direct HR manual-entry access is unchanged.
- Correction queues use creation-time/ID cursors with a creation cutoff, so approvals do not shift unseen requests past the next page. All requests are ordered newest first; use Pending to focus on outstanding work. Refresh or changing filters starts a new traversal and includes new submissions. Status membership is live, so refresh to discover requests that enter a filter behind your current position. Failed navigation keeps the last successful page index.

Backend tests: `node --test test/dtrCorrections.test.js`

Flutter tests: `flutter test --no-pub test/dtr/approvals/approvals_signatories_page_test.dart test/dtr/attendance/admin_dtr_corrections_page_test.dart test/dtr/attendance/dtr_corrections_dialog_test.dart`
