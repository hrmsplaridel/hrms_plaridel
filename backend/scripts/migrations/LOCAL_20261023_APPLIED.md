# Local database upgrade — October 23, 2026

Target: **localhost:5433/hrms_plaridel**, PostgreSQL 18.3.
The user explicitly authorized applying the discussed upgrades and checking for
missing local schema objects. No server or production database was changed.

## Applied

The following scripts were applied once to the local application database in
one transaction, in order (paths relative to this directory):

1. `20261020_mayor_isolation_m1_prep.sql`
2. `20261020_mayor_isolation_m2_backfill.sql`
3. `20261020_mayor_isolation_m3_decouple_fk.sql`
4. `20261020_mayor_isolation_m4_staff_role.sql`
5. `20261020_mayor_endorsement_is_test.sql`
6. `20261020_ojt_interviewer_signature.sql`
7. `20261023_rsp_hired_account_sync.sql`
8. `20261023_ld_multiple_training_records.sql`
9. `rsp/rsp-storage-attachment-policy.sql`
10. `20261023_schema_support_parity.sql`

The last two address older gaps discovered during the schema comparison:
the RSP attachment lookup function, push-token updated-at trigger, Leave owner
non-null constraint and non-blank DTR restoration-reason constraint. Existing
records already satisfied the added constraints; no corrective data backfill
was needed for these repairs.

The four discussed DocuTracker migrations were already represented in the
database and were not rerun. In particular, the current step-assignee constraint
also permits `final_hr_reviewers` and `active_mayor`; running an older narrower
constraint migration would unnecessarily remove support for those sources.

## Backup and rehearsal

Private backup directory, relative to `backend/`:
`.backups/20261023-local-merge-upgrade-950a67aa91/`.

- `before.dump`: rehearsal backup.
- `before-apply.dump`: final backup taken after stopping the local backend;
  2,492,758 bytes. Archive listing and SHA-256 verification passed.
- `upgrade-report.json`: private application record, hashes, scripts and counts.

The rehearsal backup was fully restored into a disposable database, and the
upgrades were exercised there before the real database was changed. A second
disposable database received the complete `init-schema.sql` as SQL, with no
installer includes. All disposable databases were removed afterward.

## Verification

- No missing application tables, columns, functions or non-internal triggers
  compared with the complete fresh schema after the targeted repairs.
- Older equivalent names for indexes and constraints were retained. Their
  uniqueness, foreign-key, JSON, signature-state and bounds rules were inspected;
  duplicate constraints were not added merely to rename them.
- Counts and protected-data fingerprints across all 111 existing public tables
  were preserved. Expected migration backfills and newly introduced columns
  were excluded from fingerprint comparisons; the RSP account-link backfill
  was separately checked for completion.
- Mayor isolation columns, validated meeting checks, partial unique indexes,
  optional recruitment links and staff-role eligibility were verified.
- DocuTracker schema preflight passed. Backend preflight parsed 352 source
  files and loaded 66 startup modules.
- Six fresh-schema/upgrade tests and 136 targeted backend regression tests passed.
  The support migration was also tested twice in a disposable database.
- Local PM2 `hrms-backend` was restarted. Health, database health, Leave balances,
  Locator availability, shared approval inbox, Mayor dashboard and monthly
  endorsement report endpoints returned HTTP 200.
- PM2's backend error log did not grow during final checks.

`init-schema.sql` was not rerun against the existing database. It already
contained the final definitions restored by the support repairs. This record
does not authorize or certify the installed state of a separate server; inspect
and back up that target before applying only its missing scripts.
