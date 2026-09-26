-- Allow employees to file Mandatory/Forced Leave through the normal workflow.

BEGIN;

UPDATE leave_types
SET employee_can_file = true,
    admin_only = false,
    updated_at = now()
WHERE name = 'mandatoryForcedLeave';

COMMIT;
