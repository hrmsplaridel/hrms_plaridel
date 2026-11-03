-- Enable untouched legacy built-in CSC paper-recording defaults.
-- Run after 20261026_leave_approved_paper_recording.sql.
-- The feature was introduced on 2026-10-26 (Asia/Manila). Conservatively
-- preserve any type saved since that day, including explicit disabled choices.
-- Custom types and types without HR filing permission are unchanged.
BEGIN;
SET LOCAL lock_timeout = '5s';
UPDATE public.leave_types
SET allow_approved_paper_filing = true, updated_at = now()
WHERE name IN (
  'vacationLeave',
  'mandatoryForcedLeave',
  'sickLeave',
  'maternityLeave',
  'paternityLeave',
  'specialPrivilegeLeave',
  'soloParentLeave',
  'studyLeave',
  'tenDayVawcLeave',
  'rehabilitationPrivilege',
  'specialLeaveBenefitsForWomen',
  'specialEmergencyCalamityLeave',
  'adoptionLeave',
  'others'
)
  AND admin_can_file = true
  AND allow_approved_paper_filing = false
  AND updated_at < TIMESTAMPTZ '2026-10-26 00:00:00+08';
COMMIT;
