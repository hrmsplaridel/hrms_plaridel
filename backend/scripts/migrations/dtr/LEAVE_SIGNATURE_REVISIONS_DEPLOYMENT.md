# Leave signature revisions (2026-10-15)

Apply `20261015_leave_signature_revisions.sql` to an existing database after the
Leave routing/print-template and DocuTracker Leave signature migrations. Deploy
the matching backend code and restart the backend after applying the upgrade.
The shared initializer includes it for new databases; do not rerun the initializer
against an existing database.

From `backend`, use the project's SQL migration procedure:

```powershell
psql -v ON_ERROR_STOP=1 -d "$env:DATABASE_URL" -f scripts/migrations/dtr/20261015_leave_signature_revisions.sql
```

The upgrade adds request/signature revision columns, replaces signature slot
uniqueness with request/revision/slot uniqueness, and installs a trigger. It does
not rewrite request content, statuses, reviewer assignments, balances, saved
images, or historical signature timestamps. Existing records start at revision 1;
past revisions are not inferred retroactively. Approved historical forms keep their
existing signatures. Future edits, returns/rejections/cancellations, and
resubmissions invalidate earlier confirmations while retaining their rows.

Employee fields, additional details, attachments, official identity/schema
snapshots, printed template, and routing/assigned reviewer changes advance the
revision. Ordinary department endorsement and final approval do not. The trigger
runs after the routing and print-template snapshot triggers so it compares the
final stored version. Repeating the upgrade is safe and does not reset revisions.

Signature reads used by request details and printed forms return only the current
revision. Department/final approval requires that actor's current-revision
signature. Reviewers use the existing signature chooser to select the same saved
image again; they need not redraw it. Signature history records the revision and
asset, and approval history records the confirmed revision. Earlier signatures
remain database audit records; this change does not add a historical-ink browser.

Before a production upgrade, confirm the target database, take a backup, and get
operator approval. This upgrade and the matching code must be deployed together.
For rollback, restore the pre-upgrade backup: reverting slot uniqueness alone can
fail once multiple revisions of a slot have been stored.

Regression test, against an explicitly selected test database:

```powershell
$env:LEAVE_SIGNATURE_TEST_DATABASE_URL = $env:DATABASE_URL
node --test test/leaveSignatureRevisionPostgres.integration.test.js
```

This test uses only temporary tables and a temporary trigger function, and rolls
back its transaction. It verifies stale approval rejection, current-only reads,
archived rows, signature ownership, department and final HR saved-image reuse,
revision increments, no-op edits, and preservation of ink during approval.

## Local installation

Applied on 2026-10-15 to the verified local target
`localhost:5433/hrms_plaridel`. Before/after hashes confirmed unchanged existing
contents for 23 requests, 27 signatures, 19 saved assets, and 98 history entries,
excluding the added revision columns. The `zz_leave_signature_revision` trigger
was verified, the local PM2 `hrms-backend` process restarted, and both `/health`
and `/health/db` returned HTTP 200. This does not establish production migration
status.
