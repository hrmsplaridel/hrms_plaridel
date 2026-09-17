BEGIN;

CREATE TABLE IF NOT EXISTS docutracker_official_signatories (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  role_key TEXT NOT NULL,
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  employee_name_snapshot TEXT NOT NULL,
  position_title_snapshot TEXT,
  department_name_snapshot TEXT,
  effective_from DATE NOT NULL,
  effective_to DATE,
  remarks TEXT,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT docutracker_official_signatories_role_check
    CHECK (role_key IN ('leave_credit_certifier')),
  CONSTRAINT docutracker_official_signatories_period_check
    CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CONSTRAINT docutracker_official_signatories_name_check
    CHECK (length(btrim(employee_name_snapshot)) BETWEEN 1 AND 200),
  CONSTRAINT docutracker_official_signatories_role_start_unique
    UNIQUE (role_key, effective_from)
);

CREATE INDEX IF NOT EXISTS idx_docutracker_official_signatories_effective
  ON docutracker_official_signatories(role_key, effective_from DESC, effective_to);

CREATE INDEX IF NOT EXISTS idx_docutracker_official_signatories_employee
  ON docutracker_official_signatories(employee_id, effective_from DESC);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'docutracker_official_signatories_no_overlap'
      AND conrelid = 'docutracker_official_signatories'::regclass
  ) THEN
    ALTER TABLE docutracker_official_signatories
      ADD CONSTRAINT docutracker_official_signatories_no_overlap
      EXCLUDE USING gist (
        role_key WITH =,
        daterange(effective_from, COALESCE(effective_to, 'infinity'::date), '[]') WITH &&
      );
  END IF;
END $$;

COMMIT;
