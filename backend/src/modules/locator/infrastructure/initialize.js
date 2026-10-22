'use strict';
// Retain the existing startup initializer without adding new migration behavior.
module.exports = function initializeLocatorCompatibility({ DEFAULT_LOCATOR_TYPES, pool }) {
  pool
    .query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`)
    .then(() =>
      pool.query(`
      CREATE TABLE IF NOT EXISTS locator_request_types (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        code TEXT NOT NULL UNIQUE,
        label TEXT NOT NULL,
        short_label TEXT NOT NULL,
        location_label TEXT NOT NULL DEFAULT 'Office / Destination',
        location_hint TEXT NOT NULL DEFAULT 'Enter office or destination',
        dtr_slot_label TEXT NOT NULL DEFAULT 'On Field',
        dtr_print_label TEXT NOT NULL DEFAULT 'ON FIELD',
        requires_attachment BOOLEAN NOT NULL DEFAULT false,
        coverage_mode TEXT NOT NULL DEFAULT 'manual'
          CONSTRAINT locator_request_types_coverage_mode_check
          CHECK (coverage_mode IN ('manual', 'wfh')),
        is_active BOOLEAN NOT NULL DEFAULT true,
        is_system BOOLEAN NOT NULL DEFAULT false,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
      );

      CREATE TABLE IF NOT EXISTS locator_slips (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
        assigned_department_head_id UUID REFERENCES users(id) ON DELETE SET NULL,
        slip_date DATE NOT NULL,
        am_in BOOLEAN NOT NULL DEFAULT false,
        am_out BOOLEAN NOT NULL DEFAULT false,
        pm_in BOOLEAN NOT NULL DEFAULT false,
        pm_out BOOLEAN NOT NULL DEFAULT false,
        request_type TEXT NOT NULL DEFAULT 'locator',
        request_type_label_snapshot TEXT,
        request_type_short_label_snapshot TEXT,
        request_type_location_label_snapshot TEXT,
        request_type_location_hint_snapshot TEXT,
        request_type_dtr_slot_label_snapshot TEXT,
        request_type_dtr_print_label_snapshot TEXT,
        request_type_requires_attachment_snapshot BOOLEAN,
        request_type_coverage_mode_snapshot TEXT
          CONSTRAINT chk_locator_type_coverage_snapshot
          CHECK (
            request_type_coverage_mode_snapshot IS NULL
            OR request_type_coverage_mode_snapshot IN ('manual', 'wfh')
          ),
        request_type_snapshot_at TIMESTAMPTZ,
        office TEXT NOT NULL,
        reason TEXT NOT NULL,
        attachment_name TEXT,
        attachment_path TEXT,
        attachment_mime_type TEXT,
        attachment_uploaded_at TIMESTAMPTZ,
        status TEXT NOT NULL DEFAULT 'pending_department_head'
          CONSTRAINT locator_slips_status_check
          CHECK (status IN (
            'pending',
            'pending_department_head',
            'pending_hr',
            'pending_mayor',
            'returned_for_correction',
            'approved',
            'revoked',
            'rejected_by_department_head',
            'rejected_by_hr',
            'cancelled'
          )),
        dept_head_reviewer_id UUID REFERENCES users(id) ON DELETE SET NULL,
        dept_head_reviewed_at TIMESTAMPTZ,
        dept_head_remarks TEXT,
        hr_reviewer_id UUID REFERENCES users(id) ON DELETE SET NULL,
        hr_reviewed_at TIMESTAMPTZ,
        hr_remarks TEXT,
        is_retroactive_correction BOOLEAN NOT NULL DEFAULT false,
        retroactive_correction_reason TEXT,
        retroactive_corrected_by UUID REFERENCES users(id) ON DELETE SET NULL,
        retroactive_corrected_at TIMESTAMPTZ,
        revoked_by UUID REFERENCES users(id) ON DELETE SET NULL,
        revoked_at TIMESTAMPTZ,
        revocation_reason TEXT,
        month_end_reconciliation_required BOOLEAN NOT NULL DEFAULT false,
        month_end_reconciled_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        CONSTRAINT chk_locator_correction_audit CHECK (
          is_retroactive_correction = false
          OR (
            retroactive_correction_reason IS NOT NULL
            AND char_length(btrim(retroactive_correction_reason)) BETWEEN 10 AND 1000
            AND retroactive_corrected_by IS NOT NULL
            AND retroactive_corrected_at IS NOT NULL
          )
        ),
        CONSTRAINT chk_locator_revocation_audit CHECK (
          status <> 'revoked'
          OR (
            revoked_by IS NOT NULL
            AND revoked_at IS NOT NULL
            AND revocation_reason IS NOT NULL
            AND char_length(btrim(revocation_reason)) BETWEEN 10 AND 1000
          )
        )
      );

      CREATE INDEX IF NOT EXISTS idx_locator_slips_employee
        ON locator_slips(employee_id, updated_at DESC);
      CREATE INDEX IF NOT EXISTS idx_locator_slips_status
        ON locator_slips(status, updated_at DESC);
      CREATE INDEX IF NOT EXISTS idx_locator_slips_department
        ON locator_slips(department_id, updated_at DESC);
      CREATE INDEX IF NOT EXISTS idx_locator_slips_date
        ON locator_slips(slip_date DESC);

      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type TEXT NOT NULL DEFAULT 'locator';
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type_label_snapshot TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type_short_label_snapshot TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type_location_label_snapshot TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type_location_hint_snapshot TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type_dtr_slot_label_snapshot TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type_dtr_print_label_snapshot TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type_requires_attachment_snapshot BOOLEAN;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type_coverage_mode_snapshot TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type_snapshot_at TIMESTAMPTZ;
      ALTER TABLE locator_slips
        DROP CONSTRAINT IF EXISTS chk_locator_type_coverage_snapshot;
      ALTER TABLE locator_slips
        DROP CONSTRAINT IF EXISTS locator_slips_request_type_coverage_mode_snapshot_check;
      ALTER TABLE locator_slips
        ADD CONSTRAINT chk_locator_type_coverage_snapshot CHECK (
          request_type_coverage_mode_snapshot IS NULL
          OR request_type_coverage_mode_snapshot IN ('manual', 'wfh')
        );
      ALTER TABLE locator_slips
        DROP CONSTRAINT IF EXISTS locator_slips_request_type_check;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS attachment_name TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS attachment_path TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS attachment_mime_type TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS attachment_uploaded_at TIMESTAMPTZ;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS assigned_department_head_id UUID
          REFERENCES users(id) ON DELETE SET NULL;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS is_retroactive_correction BOOLEAN NOT NULL DEFAULT false;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS retroactive_correction_reason TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS retroactive_corrected_by UUID
          REFERENCES users(id) ON DELETE SET NULL;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS retroactive_corrected_at TIMESTAMPTZ;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS revoked_by UUID
          REFERENCES users(id) ON DELETE SET NULL;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS revocation_reason TEXT;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS month_end_reconciliation_required BOOLEAN NOT NULL DEFAULT false;
      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS month_end_reconciled_at TIMESTAMPTZ;
      ALTER TABLE locator_slips
        DROP CONSTRAINT IF EXISTS locator_slips_status_check;
      ALTER TABLE locator_slips
        ADD CONSTRAINT locator_slips_status_check CHECK (status IN (
          'pending', 'pending_department_head', 'pending_hr', 'pending_mayor',
          'returned_for_correction', 'approved', 'revoked',
          'rejected_by_department_head', 'rejected_by_hr', 'cancelled'
        ));
      ALTER TABLE locator_slips
        DROP CONSTRAINT IF EXISTS chk_locator_revocation_audit;
      ALTER TABLE locator_slips
        ADD CONSTRAINT chk_locator_revocation_audit CHECK (
          status <> 'revoked'
          OR (
            revoked_by IS NOT NULL
            AND revoked_at IS NOT NULL
            AND revocation_reason IS NOT NULL
            AND char_length(btrim(revocation_reason)) BETWEEN 10 AND 1000
          )
        );
      CREATE INDEX IF NOT EXISTS idx_locator_request_types_active
        ON locator_request_types(is_active, sort_order, label);
      CREATE INDEX IF NOT EXISTS idx_locator_slips_request_type
        ON locator_slips(request_type);
      CREATE INDEX IF NOT EXISTS idx_locator_slips_assigned_department_head
        ON locator_slips(assigned_department_head_id, status, updated_at DESC);
      CREATE TABLE IF NOT EXISTS locator_slip_history (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        locator_slip_id UUID NOT NULL REFERENCES locator_slips(id) ON DELETE RESTRICT,
        action TEXT NOT NULL CHECK (char_length(btrim(action)) > 0),
        from_status TEXT,
        to_status TEXT,
        actor_id UUID,
        actor_name_snapshot TEXT,
        actor_role TEXT,
        remarks TEXT,
        metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
      );
      CREATE INDEX IF NOT EXISTS idx_locator_slip_history_request_time
        ON locator_slip_history(locator_slip_id, created_at, id);
      CREATE OR REPLACE FUNCTION prevent_locator_slip_history_mutation()
      RETURNS trigger AS $history$
      BEGIN
        RAISE EXCEPTION 'locator_slip_history is append-only';
      END;
      $history$ LANGUAGE plpgsql;
      DROP TRIGGER IF EXISTS trg_prevent_locator_slip_history_mutation
        ON locator_slip_history;
      CREATE TRIGGER trg_prevent_locator_slip_history_mutation
      BEFORE UPDATE OR DELETE ON locator_slip_history
      FOR EACH ROW EXECUTE FUNCTION prevent_locator_slip_history_mutation();
    `)
    )
    .then(async () => {
      for (const type of DEFAULT_LOCATOR_TYPES) {
        await pool.query(
          `INSERT INTO locator_request_types (
           code, label, short_label, location_label, location_hint,
           dtr_slot_label, dtr_print_label, requires_attachment,
           coverage_mode, is_active, is_system, sort_order
         ) VALUES (
           $1::text, $2::text, $3::text, $4::text, $5::text,
           $6::text, $7::text, $8::boolean, $9::text, true, true, $10::integer
         )
         ON CONFLICT (code) DO UPDATE SET
           is_system = true,
           updated_at = now()`,
          [
            type.code,
            type.label,
            type.short_label,
            type.location_label,
            type.location_hint,
            type.dtr_slot_label,
            type.dtr_print_label,
            type.requires_attachment,
            type.coverage_mode,
            type.sort_order,
          ]
        );
      }
      await pool.query(
        `UPDATE locator_slips AS slip
       SET request_type_label_snapshot = COALESCE(slip.request_type_label_snapshot, locator_type.label),
           request_type_short_label_snapshot = COALESCE(slip.request_type_short_label_snapshot, locator_type.short_label),
           request_type_location_label_snapshot = COALESCE(slip.request_type_location_label_snapshot, locator_type.location_label),
           request_type_location_hint_snapshot = COALESCE(slip.request_type_location_hint_snapshot, locator_type.location_hint),
           request_type_dtr_slot_label_snapshot = COALESCE(slip.request_type_dtr_slot_label_snapshot, locator_type.dtr_slot_label),
           request_type_dtr_print_label_snapshot = COALESCE(slip.request_type_dtr_print_label_snapshot, locator_type.dtr_print_label),
           request_type_requires_attachment_snapshot = COALESCE(slip.request_type_requires_attachment_snapshot, locator_type.requires_attachment),
           request_type_coverage_mode_snapshot = COALESCE(slip.request_type_coverage_mode_snapshot, locator_type.coverage_mode),
           request_type_snapshot_at = COALESCE(slip.request_type_snapshot_at, now())
       FROM locator_request_types AS locator_type
       WHERE locator_type.code = slip.request_type
         AND (
           slip.request_type_label_snapshot IS NULL
           OR slip.request_type_short_label_snapshot IS NULL
           OR slip.request_type_location_label_snapshot IS NULL
           OR slip.request_type_location_hint_snapshot IS NULL
           OR slip.request_type_dtr_slot_label_snapshot IS NULL
           OR slip.request_type_dtr_print_label_snapshot IS NULL
           OR slip.request_type_requires_attachment_snapshot IS NULL
           OR slip.request_type_coverage_mode_snapshot IS NULL
           OR slip.request_type_snapshot_at IS NULL
         )`
      );
    })
    .catch((err) => console.error('[locator] failed to ensure locator_slips table', err));
};
