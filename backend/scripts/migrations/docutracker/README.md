# DocuTracker SQL

This directory contains only DocuTracker-owned PostgreSQL schemas, migrations,
seeds, verification scripts, fixes, and generated installers.

The shared HRMS schema remains at `backend/scripts/init-schema.sql` and must be
installed first. A fresh database receives `primary_reviewer_designations` from
that file. An older database must apply the DTR migration
`backend/scripts/migrations/dtr/20261009_employee_primary_reviewers.sql` manually.
DocuTracker reads that table and does not create it. Before deployment or
testing, run the read-only check (it does not apply SQL):

```powershell
node backend/scripts/check-docutracker-schema.js
```

To install all DocuTracker phases in their required order, run:

```powershell
psql -d hrms_plaridel -v ON_ERROR_STOP=1 -f backend/scripts/migrations/docutracker/docutracker-install-all-in-order.sql
```

Regenerate the combined DocuTracker installers after changing an individual
SQL file:

```powershell
node backend/scripts/build-docutracker-all.js
```

The combined installers are generated files. Make changes in the individual
source migration or SQL file, then regenerate the installers.
