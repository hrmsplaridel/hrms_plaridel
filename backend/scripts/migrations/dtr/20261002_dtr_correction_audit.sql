BEGIN;
ALTER TABLE dtr_corrections ADD COLUMN IF NOT EXISTS original_record JSONB;
ALTER TABLE dtr_corrections ADD COLUMN IF NOT EXISTS applied_record JSONB;
COMMIT;
