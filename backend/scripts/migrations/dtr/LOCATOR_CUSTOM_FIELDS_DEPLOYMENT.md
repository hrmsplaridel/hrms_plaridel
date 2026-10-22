# Locator additional fields

Apply `20261013_locator_custom_fields.sql` to an existing database before
deploying the updated API. Deploy the frontend build as well. The migration
adds empty JSON defaults; existing type policies and request statuses are
preserved. Do not run `init-schema.sql` against an existing database.

Each locator type can define up to 20 fields: text, long text, date, number,
Yes/No, or dropdown. Fields can be required. Dropdown choices are configured
one per line. Existing types have no additional fields until HR adds them.

Employee filing, HR/admin bulk filing, record correction, and employee
resubmission validate answers against the selected type. Bulk filing applies
the same answers to all selected employees. Resubmission uses the current
type definitions; ordinary type edits do not rewrite filed request snapshots.

Saved labels and answers appear in request details and supplemental PDF
pages. The locator slip retains its existing signature layout. A saved
letterhead applies to the first page; supplemental pages retain their size.

Local verification: migration applied to `localhost:5433/hrms_plaridel` after
a validated PostgreSQL backup. Four existing types and 15 request statuses
were unchanged. Backup: `.backups/20261013-locator-custom-fields-1791875277628/before-migration.dump`.
Production deployment has not been performed.
