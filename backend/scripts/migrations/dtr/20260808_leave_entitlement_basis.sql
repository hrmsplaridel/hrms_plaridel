-- Separate real credit wallets from annual, event, request, and compliance limits.
-- Run: psql -d hrms_plaridel -f backend/scripts/migrations/dtr/20260808_leave_entitlement_basis.sql

ALTER TABLE leave_types
  ADD COLUMN IF NOT EXISTS entitlement_basis TEXT NOT NULL DEFAULT 'per_request';

UPDATE leave_types
SET entitlement_basis = CASE
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
  ELSE COALESCE(NULLIF(entitlement_basis, ''), 'per_request')
END;

UPDATE leave_types
SET entitlement_basis = 'per_request'
WHERE entitlement_basis NOT IN (
  'accrual',
  'annual',
  'per_event',
  'per_request',
  'compliance'
);

ALTER TABLE leave_types
  DROP CONSTRAINT IF EXISTS chk_leave_type_entitlement_basis;

ALTER TABLE leave_types
  ADD CONSTRAINT chk_leave_type_entitlement_basis
  CHECK (
    entitlement_basis IN ('accrual', 'annual', 'per_event', 'per_request', 'compliance')
  );

COMMENT ON COLUMN leave_types.entitlement_basis IS
  'How max_days is interpreted: accrued credits, annual quota, qualifying event, individual request, or compliance requirement.';
