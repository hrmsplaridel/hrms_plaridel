# October 12 merge: migration checklist

Reviewed merge `72eb9b53` against pre-merge `0b62f1b4`.
This is an upgrade checklist for an existing HRMS database, not a fresh install.
Do not run `init-schema.sql` on the existing database.

## Applied locally

Target: `localhost:5433/hrms_plaridel`.
The merge introduced four RSP migration files and no changed/new DocuTracker SQL.
The three gate schemas and the vacancy age backfill were missing locally.
An additional standalone date-of-birth migration was added because the merged
initializer and runtime setup included that field but no upgrade file did.

Applied together in one transaction, with a 5-second lock timeout and 60-second
statement timeout, in this order (paths relative to this directory):

1. `20261006_rsp_issued_form_gate.sql`
2. `20261007_rsp_pre_deliberation_gate.sql`
3. `20261008_rsp_final_hiring_gate.sql`
4. `20261010_vacancy_age_requirements.sql`
5. `20261012_rsp_applicant_date_of_birth.sql`

Backup: `.backups/20261012-post-merge-1791738017106/before-migrations.dump`
(relative to repository root), 1,509,675 bytes. `pg_restore --list` succeeded;
a full restore rehearsal was not performed. Keep this private archive local.

Verification: existing applicant count/status preserved; existing applicant gates
remain false; all five unique form/application indexes and seven gate status/type
checks exist; checks are validated. No vacancy objects remain without a numeric
minimum age. `date_of_birth` is DATE and existing dates were not inferred from age.
All three RSP service schema guards passed against the local database.
Local PM2 `hrms-backend` restarted; health and database health returned HTTP 200.

RSP regression tests: 66 passed, 1 failed. The merged
`rspTurnAroundTimeCreate.test.js:187` assumes the first UPDATE's first argument is
the null position, but receives a UUID. The route returned 200. This test/query
ordering mismatch needs separate investigation; migrations cannot establish that
the entire merged feature is regression-free. No unrelated application fix made.

## Server execution list

Production was not accessed or modified. Its installed schema is unverified.
Back up that database, check prerequisites and already-installed objects, and
apply only missing upgrades. The five files above are the new merge upgrade list;
include the new date-of-birth file in the deployment commit.

The RSP gates require existing `recruitment_applications`, `bi_form_entries`,
`ojt_work_immersion_evaluation_entries`, `work_experience_sheet_entries`,
`applicants_profile_entries`, and `selection_lineup_entries` tables.
The age backfill requires `job_vacancy_announcement.vacancies` JSONB. Check that
array elements are objects and any existing application links are unique before
creating the unique indexes. Gate migrations preserve existing applicants' stage
progress; the age backfill sets missing/non-numeric minimum ages to 18 and retains
numeric ages and vacancy order. The DOB migration leaves old applicants NULL.

Run these five SQL files using `psql -X -v ON_ERROR_STOP=1 --single-transaction`
with one `-f` argument per file in the order above, using the approved server
connection. Do not put credentials into this document. On failure the transaction
must roll back; inspect the error before retrying. Deploy matching application
code, restart the server's actual service, and check health plus RSP workflows.

## Earlier leave/locator upgrades, if absent on the server

These were already installed locally and were not reapplied. Local inspection
confirmed the reviewer table, leave eligibility/routing/template fields,
JO/COS default trigger, and leave/locator template snapshot triggers and tables.
For a server that has not received the earlier leave work, use this order after
checking the earlier baseline prerequisites in the linked guides:

1. `20261009_employee_employment_types.sql`
2. `dtr/20261009_employee_primary_reviewers.sql`
3. `dtr/20261010_leave_type_employment_eligibility.sql`
4. `dtr/20261010_jo_cos_leave_defaults.sql`
5. `dtr/20261010_leave_print_templates.sql`
6. `dtr/20261010_leave_approval_routing.sql`
7. `dtr/20261010_locator_print_templates.sql`

See [leave deployment](dtr/LEAVE_CHANGES_DEPLOYMENT.md) and
[locator deployment](dtr/LOCATOR_PRINT_DEPLOYMENT.md). These files contain their
own transaction blocks; execute individually with stop-on-error. The removed
manual-Mayor migration is already consolidated into approval routing.
Letterhead uploads and local settings are not copied by these migrations.

No new DocuTracker migration is required by this merge. Do not rerun its full
installer on an existing database merely because it is present in the repository.
There is no general local migration-history table; installed state was checked
from schema/data, not inferred from filenames. This checklist does not certify
every historical migration on an uninspected production database.
