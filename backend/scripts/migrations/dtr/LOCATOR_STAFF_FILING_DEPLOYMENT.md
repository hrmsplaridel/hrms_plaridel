# Locator staff filing

Apply `20261012_locator_staff_filing.sql` to an existing database before deploying
the matching backend/frontend. Requires the existing locator type, request,
history, reviewer and signature schema. Fresh installs include the new type
columns and constraint in `init-schema.sql`; do not rerun that initializer on an
existing database.

The migration adds `filing_access` (`employee`, `admin`, `both`) and
`auto_approve_admin`. Existing types remain employee-only with auto
approval off. Existing request status, balances and attendance rows are unchanged.

Configure these fields in Create/Edit Locator Type → Filing Requirements.
For example, create a No electricity type, set Who can file to HR/admin only,
and enable Auto approve HR/admin filing if that is the intended policy. Choose
the labels and DTR coverage wording appropriate to that type.

Locator Management → More actions → File for employees supports one or up to
100 selected employees. Search employee or department; load further employee
pages as needed. Full-shift coverage adapts to each employee's shift; selected
manual slots are validated for each shift. Today/future filing retains the
existing date policy. Past dates still use Record Correction individually.

Each employee is processed sequentially in a separate transaction. Active
employment, date-effective assignment, working day, attachment and attendance/
leave/locator overlap checks still apply. Attachment files are copied per saved
request so deleting one request's attachment cannot remove another's attachment.
Results identify successes and failures; successfully saved employees are removed
from the selection. No automatic request replay occurs. After an interrupted
connection, check history before retrying.

Auto approval requires the type option AND a currently assigned final HR reviewer
who is not the employee. The server checks eligibility, and the existing signature
service rechecks the reviewer before saving their signature and approval in the
same transaction. Other authorized staff can file, with normal approval routing.
This designated staff-filing path intentionally skips department endorsement when
auto approval is authorized; history records submission by staff and HR approval.
HR does not electronically sign as the employee. Printed employee and department
signature areas remain blank where those people have not signed.

History records the actual filing actor and `filed_for_employee` metadata. Auto
approvals record the HR reviewer, signature and approval timestamp. Employees
receive a filing/approval notification; pending submissions notify their normal
reviewers. Existing employee endpoints still use the authenticated employee's ID
and enforce employee filing eligibility. Staff endpoints require HR/admin role;
administrators also need `locator_allowed` access. Self filing uses My Requests.

Local target: localhost:5433/hrms_plaridel. Migration applied October 12, 2026.
Backup: `.backups/20261012-locator-staff-1791814693271/before-migration.dump`
relative to repository root; archive list verified. All three existing type rules
were preserved except the first version accidentally granted staff filing by
default. This was corrected at the owner's request: Locator, Pass Slip and Work
From Home restored to employee-only, auto approval off, and the database/code/UI
defaults changed to employee-only. Future staff filing is explicitly enabled per
type by HR. Database CHECK rejected employee-only plus auto approval (23514)
inside a rolled-back test transaction.

Production is unchanged. Back up the production database, apply this migration
with stop-on-error, deploy matching code, restart the API and rebuild the HRMS
client. Uploaded letterheads/settings are not copied from the local database.
