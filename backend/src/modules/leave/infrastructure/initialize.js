'use strict';
// Preserve legacy startup compatibility during this behavior-preserving extraction.
module.exports = function initializeLeaveCompatibility({
  SYSTEM_LEAVE_TYPE_NAMES,
  initLeaveAttachmentAccessLog,
  initLeaveBalanceLedger,
  initLeaveRequestHistory,
  pool,
}) {
  initLeaveRequestHistory(pool);
  initLeaveBalanceLedger(pool);
  initLeaveAttachmentAccessLog(pool);
  pool
    .query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`)
    .then(async () => {
      await pool.query(`
      ALTER TABLE leave_types
        ADD COLUMN IF NOT EXISTS display_name TEXT,
        ADD COLUMN IF NOT EXISTS employee_can_file BOOLEAN NOT NULL DEFAULT true,
        ADD COLUMN IF NOT EXISTS admin_only BOOLEAN NOT NULL DEFAULT false,
        ADD COLUMN IF NOT EXISTS admin_can_file BOOLEAN NOT NULL DEFAULT true,
        ADD COLUMN IF NOT EXISTS allows_past_dates BOOLEAN NOT NULL DEFAULT true,
        ADD COLUMN IF NOT EXISTS requires_attachment BOOLEAN NOT NULL DEFAULT false,
        ADD COLUMN IF NOT EXISTS requires_attachment_when_over_days NUMERIC,
        ADD COLUMN IF NOT EXISTS max_days NUMERIC,
        ADD COLUMN IF NOT EXISTS minimum_advance_days INTEGER,
        ADD COLUMN IF NOT EXISTS affects_dtr_normally BOOLEAN NOT NULL DEFAULT true,
        ADD COLUMN IF NOT EXISTS balance_ledger_type TEXT NOT NULL DEFAULT 'none',
        ADD COLUMN IF NOT EXISTS entitlement_basis TEXT NOT NULL DEFAULT 'per_request',
        ADD COLUMN IF NOT EXISTS sex_eligibility TEXT NOT NULL DEFAULT 'any',
        ADD COLUMN IF NOT EXISTS eligible_employment_types TEXT[],
        ADD COLUMN IF NOT EXISTS employee_detail_schema JSONB NOT NULL DEFAULT '[]'::jsonb,
        ADD COLUMN IF NOT EXISTS is_system BOOLEAN NOT NULL DEFAULT false,
        ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
    `);

      await pool.query(`
      ALTER TABLE leave_types
        ALTER COLUMN balance_ledger_type SET DEFAULT 'none';
    `);

      await pool.query(`
      UPDATE leave_types
      SET balance_ledger_type = 'none',
          updated_at = COALESCE(updated_at, now())
      WHERE COALESCE(NULLIF(balance_ledger_type, ''), 'none') = 'others';
    `);

      await pool.query(`
      UPDATE leave_types
      SET sex_eligibility = 'any',
          updated_at = COALESCE(updated_at, now())
      WHERE sex_eligibility IS NULL
         OR sex_eligibility NOT IN ('any', 'female', 'male');
    `);

      await pool.query(
        `
      UPDATE leave_types
      SET display_name = COALESCE(NULLIF(display_name, ''), description, name),
          is_system = CASE
            WHEN name = ANY($1::text[]) THEN true
            ELSE is_system
          END,
          updated_at = COALESCE(updated_at, now());
    `,
        [SYSTEM_LEAVE_TYPE_NAMES],
      );

      await pool.query(
        `
      UPDATE leave_types
      SET employee_can_file = true,
          admin_only = false,
          allows_past_dates = CASE WHEN name IN ('vacationLeave', 'specialPrivilegeLeave') THEN false ELSE true END,
          requires_attachment = CASE
            WHEN name IN (
              'maternityLeave',
              'paternityLeave',
              'soloParentLeave',
              'studyLeave',
              'tenDayVawcLeave',
              'rehabilitationPrivilege',
              'specialLeaveBenefitsForWomen',
              'specialEmergencyCalamityLeave',
              'adoptionLeave',
              'others'
            ) THEN true
            ELSE false
          END,
          requires_attachment_when_over_days = CASE WHEN name = 'sickLeave' THEN 5 ELSE NULL END,
          max_days = CASE
            WHEN name = 'mandatoryForcedLeave' THEN 5
            WHEN name = 'maternityLeave' THEN 105
            WHEN name = 'paternityLeave' THEN 7
            WHEN name = 'specialPrivilegeLeave' THEN 3
            WHEN name = 'soloParentLeave' THEN 7
            WHEN name = 'studyLeave' THEN 180
            WHEN name = 'tenDayVawcLeave' THEN 10
            WHEN name = 'rehabilitationPrivilege' THEN 180
            WHEN name = 'specialLeaveBenefitsForWomen' THEN 60
            WHEN name = 'specialEmergencyCalamityLeave' THEN 5
            ELSE NULL
          END,
          minimum_advance_days = CASE
            WHEN name IN ('vacationLeave', 'soloParentLeave', 'specialLeaveBenefitsForWomen') THEN 5
            WHEN name = 'specialPrivilegeLeave' THEN 7
            ELSE NULL
          END,
          affects_dtr_normally = true,
          balance_ledger_type = CASE
            WHEN name = 'mandatoryForcedLeave' THEN 'vacationLeave'
            WHEN name IN ('vacationLeave', 'sickLeave') THEN name
            ELSE 'none'
          END,
          entitlement_basis = CASE
            WHEN name IN ('vacationLeave', 'sickLeave') THEN 'accrual'
            WHEN name IN ('specialPrivilegeLeave', 'soloParentLeave', 'tenDayVawcLeave') THEN 'annual'
            WHEN name = 'mandatoryForcedLeave' THEN 'compliance'
            WHEN name IN (
              'maternityLeave',
              'paternityLeave',
              'rehabilitationPrivilege',
              'specialLeaveBenefitsForWomen',
              'specialEmergencyCalamityLeave',
              'adoptionLeave'
            ) THEN 'per_event'
            ELSE 'per_request'
          END,
          sex_eligibility = CASE
            WHEN name IN ('maternityLeave', 'tenDayVawcLeave', 'specialLeaveBenefitsForWomen') THEN 'female'
            WHEN name = 'paternityLeave' THEN 'male'
            ELSE 'any'
          END,
          is_active = true
      WHERE name = ANY($1::text[]);
    `,
        [SYSTEM_LEAVE_TYPE_NAMES],
      );

      await pool.query(`
      CREATE TABLE IF NOT EXISTS leave_balance_deduction_history (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        leave_type TEXT NOT NULL,
        deducted_days NUMERIC NOT NULL,
        remaining_days NUMERIC,
        remarks TEXT,
        applied_by UUID REFERENCES users(id) ON DELETE SET NULL,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        metadata_json JSONB
      );
    `);

      await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_leave_balance_deduction_history_user_applied
        ON leave_balance_deduction_history(user_id, applied_at DESC);
    `);
    })
    .catch((err) =>
      console.error('[leave] failed to ensure leave_balance_deduction_history table', err),
    );
};
