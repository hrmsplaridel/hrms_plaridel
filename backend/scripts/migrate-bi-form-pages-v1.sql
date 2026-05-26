-- BI form pages 2–3 fields (functional areas, performance, other relevant info).
-- Run: psql -d hrms_plaridel -f scripts/migrate-bi-form-pages-v1.sql

ALTER TABLE bi_form_entries ADD COLUMN IF NOT EXISTS functional_areas JSONB DEFAULT '[]'::JSONB;
ALTER TABLE bi_form_entries ADD COLUMN IF NOT EXISTS other_functional_area TEXT;
ALTER TABLE bi_form_entries ADD COLUMN IF NOT EXISTS performance_3_years TEXT;
ALTER TABLE bi_form_entries ADD COLUMN IF NOT EXISTS challenges_coping TEXT;
ALTER TABLE bi_form_entries ADD COLUMN IF NOT EXISTS compliance_attendance TEXT;
ALTER TABLE bi_form_entries ADD COLUMN IF NOT EXISTS other_relevant_information TEXT;
