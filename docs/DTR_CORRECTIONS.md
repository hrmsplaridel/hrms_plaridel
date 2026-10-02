# DTR Correction Requests

Apply `backend/scripts/migrations/dtr/20261002_dtr_correction_audit.sql` to existing databases before deploying. Fresh databases include these columns in `init-schema.sql`.

- Employees: My Attendance > DTR Corrections > Request correction.
- Enter only changed punches. Unselected punches retain their existing values. Select +1 day for next-day overnight punches. Deleting an existing punch is not supported by this request flow.
- A reason is required; supporting references can be included in the reason. File attachments are not included in this version.
- HR/admin: Time Logs menu > Review DTR corrections. Open a request to compare original and requested timestamps. Review notes are required for approval and rejection.
- Self-review is prohibited. Employees cannot submit on behalf of others or read another employee's requests.
- Only one pending request per employee/date is permitted through the API. Already-reviewed requests cannot be reviewed again. If attendance changes after submission, reject and request a fresh submission.
- Approval applies the existing attendance calculations, preserves raw biometric logs, marks the summary Adjusted, saves before/after evidence, and queues closed-period reconciliation in one transaction. Rejection leaves attendance unchanged.
- Month-End reconciliation follows the existing scheduler/manual rerun timing; it is not an immediate deduction adjustment.
- Existing direct HR manual-entry access is unchanged.

Backend tests: `node --test test/dtrCorrections.test.js`

Flutter tests: `flutter test --no-pub test/dtr/attendance/dtr_corrections_dialog_test.dart`
