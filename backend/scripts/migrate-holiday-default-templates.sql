-- DB-backed Philippine holiday templates.
-- Enables admins to add future-year templates on deployed systems without code changes.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS holiday_default_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  country_code TEXT NOT NULL DEFAULT 'PH',
  year INTEGER NOT NULL,
  label TEXT NOT NULL,
  source TEXT,
  note TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT uq_holiday_default_templates_country_year UNIQUE (country_code, year)
);

CREATE TABLE IF NOT EXISTS holiday_default_template_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  template_id UUID NOT NULL REFERENCES holiday_default_templates(id) ON DELETE CASCADE,
  date_from DATE NOT NULL,
  date_to DATE NOT NULL,
  name TEXT NOT NULL,
  holiday_type TEXT NOT NULL DEFAULT 'regular'
    CHECK (holiday_type IN ('regular', 'special', 'local', 'work_suspension')),
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  recurring BOOLEAN NOT NULL DEFAULT false,
  coverage TEXT NOT NULL DEFAULT 'whole_day'
    CHECK (coverage IN ('whole_day', 'am_only', 'pm_only')),
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_holiday_default_template_items_date_range CHECK (date_to >= date_from),
  CONSTRAINT uq_holiday_default_template_items_row UNIQUE (template_id, name, date_from, date_to)
);

CREATE INDEX IF NOT EXISTS idx_holiday_default_template_items_template
ON holiday_default_template_items(template_id, sort_order, date_from);
