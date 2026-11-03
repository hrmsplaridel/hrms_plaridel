# October 23 merge review and upgrade inventory

Reviewed `663a40b6` against `00fa6d61` (140 changed files). The merge brings
Mayor Office endorsement isolation, RSP/L&D changes, account-role changes and
shared UI/branding updates. Existing Leave, Locator and DTR fixes are retained.

Subsequent local application is recorded in [LOCAL_20261023_APPLIED.md](LOCAL_20261023_APPLIED.md).
The pending-state statements below describe the earlier review, before that application.

## Upgrade inventory

Paths in this table are relative to `backend/scripts/migrations/`.

| Order | Script | Purpose |
| --- | --- | --- |
| 1 | `20261020_mayor_isolation_m1_prep.sql` | Add endorsement identity, reference, decision and meeting lifecycle fields/checks/indexes. |
| 2 | `20261020_mayor_isolation_m2_backfill.sql` | Fill existing applicant names, references and endorsement dates; add unique reference index. |
| 3 | `20261020_mayor_isolation_m3_decouple_fk.sql` | Make the recruitment link optional and remove recruitment foreign keys that could delete endorsement history. Requires a verified backup and coordinated deployment. |
| 4 | `20261020_mayor_isolation_m4_staff_role.sql` | Permit `mayor_office_staff` without changing the single-active-Mayor rule. |
| 5 | `20261020_mayor_endorsement_is_test.sql` | Add the test-record flag/index and mark three explicitly identified disposable validation records. |
| Independent | `20261020_ojt_interviewer_signature.sql` | Add the OJT interviewer's signature field. |
| Independent, added during review | `20261023_rsp_hired_account_sync.sql` | Add the one-time synchronization marker and mirror the merged account-link backfill. Later manual choices remain unchanged on rerun. |
| Independent, added during review | `20261023_ld_multiple_training_records.sql` | Remove one-training-per-employee uniqueness, retaining existing rows and adding a lookup index. |

The last two upgrades existed only in runtime table-initialization code in the
merge. Dedicated scripts were added so operators can inspect and apply them
without triggering an application request.

Read-only inspection of `localhost:5433/hrms_plaridel` found the original
non-null recruitment FK and old role check, missing Mayor isolation fields and
OJT signature, and the L&D employee unique constraint. These upgrade scripts
were **not applied to the existing database during this review**. Running the
fresh initializer on that database is not an upgrade procedure.

Before deployment, back up the actual target, inspect installed state, apply
only missing upgrades in the order above, and verify schema and existing data.
M3 changes deletion behavior and permits independent records; do not infer
production authorization from this local review.

## Relocated scripts, not new upgrades

The merge moved these existing scripts into module folders:

- `rsp/20261006_rsp_issued_form_gate.sql`
- `rsp/20261007_rsp_pre_deliberation_gate.sql`
- `rsp/20261008_rsp_final_hiring_gate.sql`
- `rsp/20261010_vacancy_age_requirements.sql`
- `rsp/init-schema-rsp.sql`
- `rsp/migrate-rsp-hire-email-sent.sql`
- `rsp/rsp-storage-attachment-policy.sql`
- `ld/init-schema-ld.sql`
- `ld/migrate-20260917-rspld-merge.sql`

They must not be rerun merely because their paths changed. The RSP service
schema-error messages and storage script instructions now point to these paths.

## Findings resolved

- Fresh schema omitted `mayor_endorsement_requests.is_test`, three Mayor
  monitoring indexes, and `recruitment_applications.hr_account_setup_linked_sync`.
  These are now declared directly; the merged staff role, optional recruitment
  links, OJT signature and multi-training definitions are retained.
- The Memo preview/PDF still referenced the renamed `Plaridel Logo.jpg` asset.
  Both now use the bundled `PlaridelLogo.jpg` via the shared layout constant.
- Mayor custom-report dates accepted impossible/reversed dates and could throw
  on an invalid month. They now fail validation before report execution.
- Invalid RSP status updates invoked schema setup and account backfills before
  rejecting the input. They now return 400 before any database query.
- The new RSP credential resend route replaced passwords without invalidating
  sessions and could roll back a password after the email was sent. Password
  writes now increment `auth_version` and compare the prior hash; failed sends
  restore only their own write, while post-delivery metadata failures preserve
  the delivered password. Tests use mocked mail; no emails were sent.
- A TAT regression mock mistook `SELECT ... FOR UPDATE` for an update, and its
  assertion selected the wrong query. The fixture now distinguishes reads from
  writes and checks the actual form update. Obsolete login assertions now match
  the intentionally restored Remember me control.

## Verification and limits

The complete initializer and both added upgrade scripts were executed against a
uniquely named temporary local database, then that database was removed. Tests
cover repeated upgrades, retained manual choices, independent endorsements,
multiple training records, and existing workflow/signature rules. Existing
application records were not used for write tests. Backend source parsing and
startup imports, targeted RSP/Mayor/DocuTracker checks, DTR/Leave/Locator suites,
and selected Flutter screen tests provide regression coverage; they are not a
full browser/device acceptance test of every merged feature.

Full frontend library analysis found no compile errors, with seven existing
warnings/informational findings left outside the functional fixes. The prior
acceptance/phase scripts committed by the team were not run: some create test
accounts, endorsement requests or other records and require their own staging
setup. No external messages, emails, production migrations or deployments were
performed.

Final checks: 404 Leave, 358 Locator, 131 DTR, 129 focused backend tests, six
fresh-schema/upgrade checks, and 62 selected Flutter tests passed. Edited Dart
files have no analyzer findings; backend preflight parsed 352 source files and
loaded 66 startup modules. The verified local PM2 `hrms-backend` process was
restarted and both `/health` and `/health/db` returned HTTP 200 with `ok: true`.
The error log did not grow. A final read-only check confirmed no temporary test
databases remained and the listed upgrades were still absent on the existing
application database. Healthy API/database probes do not mean the pending
Mayor/OJT upgrades have been installed.
