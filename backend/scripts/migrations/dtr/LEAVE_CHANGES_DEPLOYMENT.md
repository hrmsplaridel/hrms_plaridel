# Leave changes: migration order

This guide covers the employment eligibility, Wellness form, and manual Mayor
signing changes made on October 9–10, 2026. It assumes an existing HRMS database
with the earlier leave, credit, and reviewer schema already installed.

## Which migration do I need?

For approval routing, deploy the combined migration:

`20261010_leave_approval_routing.sql`

It creates the routing fields and makes the Mayor route finish at department
approval in one migration. Existing requests
waiting for electronic Mayor approval return to the department queue so the
approval API can complete accounting. It does not directly deduct balances.

## Full order for these features

Run the missing migrations in this order, from the backend directory:

| Order | File relative to backend | Purpose |
| --- | --- | --- |
| 1 | `scripts/migrations/20261009_employee_employment_types.sql` | Seven employment types, keeping legacy `regular` values. |
| 2 | `scripts/migrations/dtr/20261009_employee_primary_reviewers.sql` | Employee-based primary reviewer assignments. |
| 3 | `scripts/migrations/dtr/20261010_leave_type_employment_eligibility.sql` | Eligible employment types for each leave type. |
| 4 | `scripts/migrations/dtr/20261010_jo_cos_leave_defaults.sql` | JO/COS credit defaults and protected leave eligibility defaults. |
| 5 | `scripts/migrations/dtr/20261010_leave_print_templates.sql` | Versioned printed layouts and uploaded backgrounds. |
| 6 | `scripts/migrations/dtr/20261010_leave_approval_routing.sql` | Conditional routing, request snapshots, and department approval with manual Mayor signing. |

Migration 5 should precede migration 6 because routing updates the print-template
snapshot function. The separate manual-signing migration was folded into routing
before server deployment and removed. Do not look for or run a seventh migration.

For a new database use the updated `scripts/init-schema.sql`. For an existing
database use the upgrade migrations above instead of rerunning the initializer.
The initializer also contains account seed statements.

## Local database status

All six features above are already installed in the local database:

`localhost:5433/hrms_plaridel`

The original routing and manual signing migrations were applied locally on
October 10, 2026 before consolidation. At that time,
all 20 existing requests and their balances remained unchanged; none were
waiting for electronic Mayor approval. This does not establish the migration
status of the production server.

The combined routing migration was subsequently applied locally and verified:
all 20 requests, balances, and saved routing settings remained unchanged.

## Wellness settings are separate from migrations

The migrations create the capabilities. They do not copy local configuration
or uploaded files to another database. On the server, configure Wellness in
Leave Type Settings:

1. Printed form: **Wellness Leave form**; upload the approved A4 background.
2. Approval route: **Department approval → Manual Mayor signing**.
3. Apply that route to **Job Order (JO)** and **Contract of Service (COS)**.
4. Keep an active Mayor account for the printed name and assign department
   reviewers through Approvals & Signatories.

Other employment types use the CSC layout and retain the HR route when they are
not selected for the manual route. Filing eligibility and monthly credit
eligibility are independent settings.

Deploy the corresponding backend and Flutter changes as well as the migrations.
Restart the backend and rebuild/restart the frontend after deployment. A SQL
migration by itself does not deploy the application code.
