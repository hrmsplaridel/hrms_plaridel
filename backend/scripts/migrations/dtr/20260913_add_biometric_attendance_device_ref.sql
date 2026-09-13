-- Preserve the registered device that produced each live biometric punch.
BEGIN;

ALTER TABLE biometric_attendance_logs
  ADD COLUMN IF NOT EXISTS device_ref_id UUID;

ALTER TABLE biometric_attendance_logs
  DROP CONSTRAINT IF EXISTS biometric_attendance_logs_device_ref_id_fkey;
ALTER TABLE biometric_attendance_logs
  ADD CONSTRAINT biometric_attendance_logs_device_ref_id_fkey
  FOREIGN KEY (device_ref_id)
  REFERENCES biometric_devices(id)
  ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_biometric_attendance_logs_device_ref_id
  ON biometric_attendance_logs(device_ref_id);

COMMIT;
