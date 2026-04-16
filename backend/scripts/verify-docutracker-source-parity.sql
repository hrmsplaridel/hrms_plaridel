-- DocuTracker source-schema parity verifier
-- Usage:
--   psql -d hrms_plaridel -f backend/scripts/verify-docutracker-source-parity.sql
--
-- Purpose:
--   Fail fast if DocuTracker required source/core tables are missing.
--   This should be part of pre-release validation.

DO $$
DECLARE
  missing_tables text[];
BEGIN
  SELECT ARRAY(
    SELECT t.required_table
    FROM (
      VALUES
        -- Source module tables consumed by DocuTracker source feed
        ('public.training_daily_reports'),
        ('public.leave_requests'),
        ('public.dtr_corrections'),
        ('public.overtime_requests'),
        ('public.recruitment_applications'),
        -- DocuTracker core tables
        ('public.docutracker_documents'),
        ('public.docutracker_permissions'),
        ('public.docutracker_routing_configs'),
        ('public.docutracker_routing_records'),
        ('public.docutracker_document_history'),
        ('public.docutracker_notifications')
    ) AS t(required_table)
    WHERE to_regclass(t.required_table) IS NULL
  ) INTO missing_tables;

  IF array_length(missing_tables, 1) IS NOT NULL THEN
    RAISE EXCEPTION
      'DocuTracker schema parity check failed. Missing tables: %',
      array_to_string(missing_tables, ', ');
  END IF;

  RAISE NOTICE 'DocuTracker schema parity check passed. All required tables are present.';
END $$;
