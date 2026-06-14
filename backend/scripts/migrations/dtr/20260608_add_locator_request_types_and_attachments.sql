CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS locator_request_types (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  code TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL,
  short_label TEXT NOT NULL,
  location_label TEXT NOT NULL DEFAULT 'Office / Destination',
  location_hint TEXT NOT NULL DEFAULT 'Enter office or destination',
  dtr_slot_label TEXT NOT NULL DEFAULT 'On Field',
  dtr_print_label TEXT NOT NULL DEFAULT 'ON FIELD',
  requires_attachment BOOLEAN NOT NULL DEFAULT false,
  coverage_mode TEXT NOT NULL DEFAULT 'manual'
    CONSTRAINT locator_request_types_coverage_mode_check
    CHECK (coverage_mode IN ('manual', 'wfh')),
  is_active BOOLEAN NOT NULL DEFAULT true,
  is_system BOOLEAN NOT NULL DEFAULT false,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO locator_request_types (
  code, label, short_label, location_label, location_hint,
  dtr_slot_label, dtr_print_label, requires_attachment,
  coverage_mode, is_active, is_system, sort_order
) VALUES
  (
    'locator', 'Locator / Official Business', 'Locator',
    'Office / Destination', 'Enter office or destination',
    'On Field', 'ON FIELD', false, 'manual', true, true, 10
  ),
  (
    'pass_slip', 'Pass Slip', 'Pass Slip',
    'Destination / Location', 'Enter destination or location',
    'Pass Slip', 'PASS SLIP', false, 'manual', true, true, 20
  ),
  (
    'work_from_home', 'Work From Home', 'WFH',
    'Work Location', 'Enter work location',
    'WFH', 'WFH', false, 'wfh', true, true, 30
  )
ON CONFLICT (code) DO UPDATE SET
  is_system = true,
  updated_at = now();

ALTER TABLE locator_slips
  DROP CONSTRAINT IF EXISTS locator_slips_request_type_check;

ALTER TABLE locator_slips
  ADD COLUMN IF NOT EXISTS attachment_name TEXT,
  ADD COLUMN IF NOT EXISTS attachment_path TEXT,
  ADD COLUMN IF NOT EXISTS attachment_mime_type TEXT,
  ADD COLUMN IF NOT EXISTS attachment_uploaded_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_locator_request_types_active
  ON locator_request_types(is_active, sort_order, label);
