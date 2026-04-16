-- Add index for leave_request_id lookups in DTR daily summary
-- Run:
--   psql -U postgres -d hrms_plaridel -f backend/scripts/migrate-add-dtr-leave-request-index.sql

CREATE INDEX IF NOT EXISTS idx_dtr_leave_request
ON dtr_daily_summary(leave_request_id);

