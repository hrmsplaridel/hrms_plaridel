# Migrations from the 2026-10-04 pull

Compared pre-pull `e546ffad` with pulled commit `cd63177e`.

## Local execution record

Target: `localhost:5433/hrms_plaridel`. All five files below were missing locally and applied successfully in this order. PostgreSQL error-stop was enabled. Files without their own transaction were run with `--single-transaction`.

1. `backend/scripts/migrate-add-exam-question-images.sql`
2. `backend/scripts/migrations/docutracker/migrate-docutracker-submitter-department-reviewers-v1.sql`
3. `backend/scripts/migrations/docutracker/migrate-docutracker-hide-test-types-from-employees-v1.sql`
4. `backend/scripts/migrations/docutracker/migrate-docutracker-purchase-request-authorized-creators-v1.sql`
5. `backend/scripts/migrations/docutracker/migrate-docutracker-memo-authorized-preparers-v1.sql`

Pre-migration database/uploads backup: `backend/.backups/132a89dc-10b6-4d43-aec5-c8b5ad068e19` (21,926,991 bytes).

Verified three exam-image columns, originating department column/index, submitter-department routing constraint, and all 12 create/submit denial baselines for employee/HR/supervisor across Memo and Purchase Request. User-specific permission exceptions and existing documents were preserved. 64 focused exam-image, DocuTracker permissions, and workflow tests passed.

## Already present / not rerun

- `backend/scripts/migrations/docutracker/migrate-docutracker-source-signature-assignment-source-v1.sql`: only whitespace changed in the pull; its assignment-source/recovery columns and constraints already exist locally.
- New-install schema and generated installation bundles changed too. Their new operational changes are covered by the files above; other consolidated hardening/leave-signature objects already exist locally. Do not rerun the entire init schema or installation bundles over the existing database just because those files changed.

## Server upgrade checklist

These have NOT been executed on the server. Confirm the server database, back it up, and inspect its existing schema first. The list assumes the server already has the pre-pull schema; an older server may need additional prerequisites, including the source-signature assignment migration above. Check `docutracker_permissions` role uniqueness and the existing workflow `assignee_source` column before applying.

From the repository root, using psql connection options for the confirmed server database:

```bash
psql -X -h <host> -p <port> -U <db-user> -d <database> -v ON_ERROR_STOP=1 --single-transaction -f backend/scripts/migrate-add-exam-question-images.sql
psql -X -h <host> -p <port> -U <db-user> -d <database> -v ON_ERROR_STOP=1 -f backend/scripts/migrations/docutracker/migrate-docutracker-submitter-department-reviewers-v1.sql
psql -X -h <host> -p <port> -U <db-user> -d <database> -v ON_ERROR_STOP=1 --single-transaction -f backend/scripts/migrations/docutracker/migrate-docutracker-hide-test-types-from-employees-v1.sql
psql -X -h <host> -p <port> -U <db-user> -d <database> -v ON_ERROR_STOP=1 --single-transaction -f backend/scripts/migrations/docutracker/migrate-docutracker-purchase-request-authorized-creators-v1.sql
psql -X -h <host> -p <port> -U <db-user> -d <database> -v ON_ERROR_STOP=1 --single-transaction -f backend/scripts/migrations/docutracker/migrate-docutracker-memo-authorized-preparers-v1.sql
```

Run one command at a time and stop on any error. The submitter-department migration includes its own BEGIN/COMMIT. Permission migrations deliberately apply deny-by-default role rules; administrators authorize specific preparers/creators in System Access. After deployment, restart the existing backend service and verify `/health`, `/health/db`, and the affected features.
