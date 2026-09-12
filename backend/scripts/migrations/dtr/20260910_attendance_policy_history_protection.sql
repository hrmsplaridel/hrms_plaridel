-- Preserve attendance-policy assignment and DTR history when policies are deleted.
BEGIN;

ALTER TABLE policy_assignments
  DROP CONSTRAINT IF EXISTS policy_assignments_attendance_policy_id_fkey;
ALTER TABLE policy_assignments
  ADD CONSTRAINT policy_assignments_attendance_policy_id_fkey
  FOREIGN KEY (attendance_policy_id)
  REFERENCES attendance_policies(id)
  ON DELETE RESTRICT;

ALTER TABLE dtr_daily_summary
  DROP CONSTRAINT IF EXISTS dtr_daily_summary_attendance_policy_id_fkey;
ALTER TABLE dtr_daily_summary
  ADD CONSTRAINT dtr_daily_summary_attendance_policy_id_fkey
  FOREIGN KEY (attendance_policy_id)
  REFERENCES attendance_policies(id)
  ON DELETE RESTRICT;

COMMIT;
