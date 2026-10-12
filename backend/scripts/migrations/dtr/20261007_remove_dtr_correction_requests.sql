-- Remove the retired employee correction-request workflow.
-- Apply after older DTR migrations. Deploy matching backend code before restart.
-- Existing requests, evidence, reviewer configurations and their notifications are deleted.
-- Direct HR attendance records, biometric punches and generic audit history are retained.
BEGIN;
SET LOCAL lock_timeout = '5s';
DROP TABLE IF EXISTS dtr_correction_attachments;
DROP TABLE IF EXISTS dtr_corrections;
DROP TABLE IF EXISTS dtr_correction_reviewer_configs;
ALTER TABLE IF EXISTS dtr_admin_access DROP COLUMN IF EXISTS corrections_allowed;
DELETE FROM user_notifications WHERE left(type, 15) = 'dtr_correction_';
COMMIT;
