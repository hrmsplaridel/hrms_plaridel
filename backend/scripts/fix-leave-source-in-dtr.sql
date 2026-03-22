-- Fix source for leave-based and holiday-based DTR records that incorrectly have source = 'system'.
-- Leave-based and holiday/work-suspension records should have source = 'adjusted'.
-- Run once: psql -d hrms_plaridel -f backend/scripts/fix-leave-source-in-dtr.sql

UPDATE dtr_daily_summary
SET source = 'adjusted', updated_at = now()
WHERE (leave_request_id IS NOT NULL OR holiday_id IS NOT NULL)
  AND source != 'adjusted';
