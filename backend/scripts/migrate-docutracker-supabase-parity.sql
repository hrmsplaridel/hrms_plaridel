-- Align existing PostgreSQL DocuTracker tables with standalone HRMS schema
-- (migrated from Supabase). Safe to run multiple times.
-- Run: psql -d hrms_plaridel -f scripts/migrate-docutracker-supabase-parity.sql

ALTER TABLE docutracker_document_history
  ADD COLUMN IF NOT EXISTS actor_name TEXT;

ALTER TABLE docutracker_routing_records
  ALTER COLUMN assignee_id DROP NOT NULL;

ALTER TABLE docutracker_documents DROP CONSTRAINT IF EXISTS docutracker_documents_status_check;

-- Former Supabase RLS policies used role `authenticated` with broad access.
-- This app enforces access via Express + JWT. Optional RLS for a future
-- restricted DB role (uncomment and create role `hrms_app` if needed):
--
-- ALTER TABLE docutracker_documents ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY docutracker_documents_service ON docutracker_documents
--   FOR ALL TO hrms_app USING (true) WITH CHECK (true);
