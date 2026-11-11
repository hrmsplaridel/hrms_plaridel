# Backup reviewer printing

Approval workflow settings have two separate print controls for Leave and Locator:

- **When a primary reviewer files their own request** keeps its existing Mayor, blank, or actual-reviewer choices.
- **When a backup reviewer approves** defaults to **Keep primary reviewer’s name**. The other choice is **Show approving backup’s name and signature**.

The default keeps the primary's name and position on the form. A backup's approval does not put either the backup's ink or ink from another workflow step above the primary's name. If the primary signs and approves that same step, their own confirmed signature may print.

The actual-reviewer option prints the person who approves the step, with their valid signature for that request and revision. Reviewer permissions, stage progression, and audit identities are unchanged. The setting does not detect absences or appoint backups; backups still need to be configured.

The selected rule is versioned in `approval_workflow_versions.backup_signatory_policy` and copied into the request's workflow snapshot. Under the default, primary identities are also saved in `primary_signatories`, so later organization changes do not replace the printed names. Corrections retain the saved policy and identities. Requests filed before this feature retain their earlier print behavior.

Standard form blocks and custom `workflow_step_N` signature elements honor the policy. HR credit certification and manual Mayor signing continue to follow their separate role/signing rules. When the applicant is themselves the primary, the existing self-filing rule takes precedence.

## Deployment

Existing databases require [20261111_workflow_backup_signatories.sql](../backend/scripts/migrations/dtr/20261111_workflow_backup_signatories.sql). Fresh databases use the updated [init-schema.sql](../backend/scripts/init-schema.sql).

Apply the migration before deploying the matching backend and rebuilt frontend. It adds a constrained column with default `keep_primary`; it does not update Leave or Locator request snapshots. Follow the [Ubuntu migration procedure](private/UBUNTU_SERVER_APPLY_MIGRATIONS.md) for the production database, then restart `hrms-api` and verify both health endpoints. The local development database and production database are separate deployment targets.

Publishing an edited workflow affects future filings. Existing filed requests keep their saved workflow version and printing behavior.
