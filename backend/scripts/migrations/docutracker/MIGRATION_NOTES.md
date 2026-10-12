# DocuTracker migration notes

One entry per migration file added under this folder. Newest first.

---

## migrate-docutracker-signature-identity-snapshot-v1.sql

- **Date:** 2026-10-12
- **Purpose:** Freezes the printed signer identity of a signed builder field (official
  Memo *Prepared by* / *Approved by*). `signer_name_snapshot` already existed; this adds
  the position and role held **at signing**, so a later promotion, transfer, rename,
  deactivation or a new Mayor never changes an already signed document. Unsigned fields
  keep showing the live directory identity (`assigned_signer_name/_position/_role`).
- **Affected tables / columns:** `docutracker_signature_fields`: new nullable
  `signer_position_snapshot TEXT` and `signer_role_snapshot TEXT`. Written only by
  `signLockedField` (sign, re-sign and add-own-signature), from the same current-assignment
  rule as the live signatory line (the Mayor falls back to "Municipal Mayor").
- **Constraints:** `docutracker_signature_fields_identity_snapshot_check_v1`: snapshots are
  NULL or non-blank, and only a signed row (`signed_at IS NOT NULL`) may carry them.
  Added `NOT VALID`, then validated.
- **Indexes:** none.
- **Triggers:** none.
- **Seed data:** none.
- **Backfill:** none, on purpose. Fields signed before this migration keep NULL snapshots:
  the historical position is unknown and is not fabricated from today's directory. The
  Memo prints their stored signer name with no position line and no "HON." prefix.
- **Required for existing databases:** yes. Without it signing fails (the UPDATE writes
  the new columns). Reading builders works either way (`SELECT f.*`).
- **init-schema.sql updated:** yes (both columns and the named CHECK on the
  `docutracker_signature_fields` CREATE TABLE).
- **Rollup regenerated:** yes, `node backend/scripts/build-docutracker-all.js`
  (section 33 "SIGNER IDENTITY SNAPSHOT" in `post-production-hardening.sql` and
  `install-all-in-order.sql`; phase 3 headers now read 10-33).
- **Tests run:** `node --test` over `backend/test/docutracker*.test.js` (fake pools);
  Flutter `test/docutracker test/shared`. Also verified on throwaway databases (dropped
  afterwards): fresh `init-schema.sql` install then this migration twice, and this
  migration twice on a `pg_dump --schema-only` copy of the dev schema. Applied once to
  the dev database (5 existing signed fields left with NULL snapshots), and the real
  signing SQL was exercised there inside a rolled-back transaction.
- **Compatibility:** additive and idempotent (single transaction, `ADD COLUMN IF NOT
  EXISTS`, constraint drop/re-create). API responses gain `signer_position_snapshot` and
  `signer_role_snapshot`; older clients ignore them.
- **Rollback notes:** drop the CHECK, then the two columns. Signed Memos would then fall
  back to printing no position (the client never substitutes live data for a signed field).

---

## migrate-docutracker-document-release-v1.sql

- **Date:** 2026-10-07
- **Purpose:** Adds a generic, per-document-type Release / Distribution stage for
  native DocuTracker documents. A document whose type requires release stays
  `status = 'approved'` after final approval and is tracked as *Awaiting release*
  until an authorized user releases it to one HRMS department. Active members of
  that department can then open it (view only), like other relationship-based
  access: role-level `view` rows do not gate it, a user-specific view deny does.
- **Affected tables / columns:**
  - `docutracker_document_types`: new `requires_release BOOLEAN NOT NULL DEFAULT false`.
    The `memo` row is inserted if missing and set to `true` only when the column is
    first created (re-runs do not override an admin's later choice).
  - `docutracker_documents`: new columns `release_required BOOLEAN NOT NULL DEFAULT false`,
    `released_to_department_id UUID REFERENCES departments(id) ON DELETE SET NULL`,
    `released_to_department_name TEXT`, `released_by UUID REFERENCES users(id) ON DELETE SET NULL`,
    `released_by_name TEXT`, `released_at TIMESTAMPTZ`, `release_remarks TEXT`.
  - `docutracker_document_history`: new `metadata JSONB NOT NULL DEFAULT '{}'`.
- **Constraints:**
  - `docutracker_documents_release_native_check_v1`: `NOT release_required OR source_module IS NULL`
    (DTR / RSP / L&D source records can never enter the release stage).
  - `docutracker_documents_release_state_check_v1`: a released row must be release-required
    and carry a non-blank department name snapshot.
  - `chk_docutracker_history_action`: adds `'released'`.
  - `docutracker_notifications_type_check`: adds `'released'`.
  - `docutracker_permissions_action_check_prod_v1`: adds `'release'`.
- **Indexes:** `idx_docutracker_documents_released_to_department`
  on `(released_to_department_id, released_at DESC) WHERE released_at IS NOT NULL`.
- **Triggers:** none.
- **Seed data:** role permission `('hr', 'memo', 'release', true)` (ON CONFLICT DO NOTHING).
  This row is part of the default role policy in
  `backend/src/services/docutrackerPermissionDefaults.js`, so resetting HR's Memo
  settings restores it (a test keeps that module identical to the init-schema seed).
- **Backfill:** none. Existing documents keep `release_required = false`, so documents
  already approved do **not** become *Awaiting release*. Memos still in review when the
  migration runs become release-required when they reach final approval afterwards.
- **Required for existing databases:** yes. Without it the backend release queries and the
  final-approval snapshot reference missing columns.
- **init-schema.sql updated:** yes (final shape of every column, constraint, index, type
  seed `requires_release`, and the `hr / memo / release` permission row). The release
  row is inserted **after** the `\ir` DocuTracker rollup: earlier rollup sections re-create
  narrower permission action checks, so seeding it in the baseline block before the rollup
  made a fresh install fail.
- **Rollup regenerated:** yes, `node backend/scripts/build-docutracker-all.js`
  (section 32 "DOCUMENT RELEASE / DISTRIBUTION" in `post-production-hardening.sql` and
  `install-all-in-order.sql`). Re-running it after the final changes produced no diff.
- **Tests run:** `node --test` over `backend/test/docutracker*.test.js` (fake pools only,
  including `docutrackerDocumentRelease.test.js`, `docutrackerPermissionDefaults.test.js`,
  `docutrackerDocumentListPagination.test.js`); Flutter `test/docutracker test/shared`.
  Also verified on throwaway databases (dropped afterwards, dev untouched): a fresh
  `psql -v ON_ERROR_STOP=1 -f init-schema.sql` install followed by this migration twice,
  and this migration applied twice to a `pg_dump --schema-only` copy of the dev schema.
- **Compatibility:** additive and idempotent (single transaction; `IF NOT EXISTS`, constraint
  drop/re-create with the widened lists, new checks added `NOT VALID` then validated).
  Types other than `memo` are unaffected unless an admin enables release for them.
- **Rollback notes:** set `requires_release = false` on the types to disable the feature
  without dropping data. A full rollback would drop the new columns/index/checks and restore
  the previous CHECK lists, but only after deleting `released` history/notification rows and
  `release` permission rows, which would otherwise violate the narrowed checks.
