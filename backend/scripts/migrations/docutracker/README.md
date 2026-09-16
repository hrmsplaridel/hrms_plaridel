# DocuTracker SQL

This directory contains only DocuTracker-owned PostgreSQL schemas, migrations,
seeds, verification scripts, fixes, and generated installers.

The shared HRMS schema remains at `backend/scripts/init-schema.sql` and must be
installed first. To install all DocuTracker phases in their required order, run:

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
