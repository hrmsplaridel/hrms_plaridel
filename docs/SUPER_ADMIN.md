# Separate Super-Admin Account

The `super_admin` login is a system identity, not an employee. It has no employee
number, assignment, leave credits, or DTR. It is not created from Create Account.

## Set Up an Existing Database

1. Apply `backend/scripts/migrations/20261003_super_admin_account.sql` before
   starting the updated backend. Do not rerun `init-schema.sql` on an existing
   database.
2. Set `HRMS_SUPER_ADMIN_USERNAME=superadmin` (or
   `HRMS_SUPER_ADMIN_EMAIL`) and `HRMS_SUPER_ADMIN_PASSWORD` (at least 12
   characters) in the shell or a secret manager. Optionally set
   `HRMS_SUPER_ADMIN_NAME`.
3. From `backend`, run `npm run admin:bootstrap` once. Remove the password from
   the shell environment after the script finishes. The script refuses to
   overwrite an existing super-admin account.
4. Sign in using `superadmin` in the "Email or username" field on the normal
   login page on a desktop computer.

Fresh databases get the role constraint from `init-schema.sql`, but still need
the one-time bootstrap script. Do not place the super-admin password in the
repository or share it with employee/admin accounts.

The super-admin dashboard provides Create Account, Account Access, and the
read-only system Audit Log. The super-admin is the only role allowed to view that log;
each view is audited. Existing admins retain employee/admin account creation
during this transition.

## Account Creation Access

Apply `backend/scripts/migrations/20261003_account_creation_access.sql` to
existing databases before deploying the matching backend. The migration grants
existing administrators account creation; administrators created afterward are
denied until Super Admin enables them under **Account Access**. Super Admin can
always create employee/admin accounts. Changes are recorded in the system audit
log. The backend checks access on Create Account and DTR biometric user import;
the unused public `/auth/register` endpoint no longer creates accounts.

This does not change access to RSP, L&D, DocuTracker, or other admin features.

## DTR Admin Access

Apply `backend/scripts/migrations/20261003_dtr_admin_access.sql` to existing
databases. Existing administrators keep DTR reports and management access;
new administrators start without either permission. Super Admin can manage
both switches in **Account Access > DTR Access**.

**View reports** controls the DTR report card and bulk report generation.
**Manage DTR** controls the Time Logs, Workforce Setup, and Biometric Devices
cards, plus DTR-specific time-log, schedule, assignment, shift, holiday,
attendance-policy, and biometric management endpoints. The two grants are
independent and audited on change. Admins may still view their own attendance.
Employee profiles, leave/locator workflows, correction reviewer decisions,
and other groups' modules retain their existing authorization rules.

## Audit identity snapshots

Apply `backend/scripts/migrations/20261004_audit_identity_snapshots.sql` before
deploying the matching audit API. For a configured PostgreSQL connection, run
`psql -v ON_ERROR_STOP=1 --single-transaction -f scripts/migrations/20261004_audit_identity_snapshots.sql`
from `backend`. Fresh installations include this migration in `init-schema.sql`.

An insert trigger captures the actor's ID, name, and email for every new system
audit event. Events targeting `user`, `system_account`, `employee_account`, or
`auth` also capture the affected account. Snapshots remain when accounts are
renamed or deleted; they follow audit-log retention, independently of account
deletion. No passwords, tokens, or other profile fields are captured. Existing
entries are not backfilled: the UI labels their current account information or
unavailable historical identity. Actor filters use captured identities when
available. Roll back the application before removing these columns/trigger;
dropping snapshot columns would permanently lose captured historical identities.
