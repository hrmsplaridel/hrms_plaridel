-- Migration: Authoritative employee additional-position schema
-- Purpose: Move employee_other_positions ownership out of runtime API routes.

BEGIN;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS employee_other_positions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  position_id UUID NOT NULL REFERENCES positions(id) ON DELETE RESTRICT,
  effective_from DATE NOT NULL,
  effective_to DATE,
  is_active BOOLEAN NOT NULL DEFAULT true,
  remarks TEXT,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

UPDATE employee_other_positions eop
SET department_id = p.department_id
FROM positions p
WHERE eop.department_id IS NULL
  AND p.id = eop.position_id
  AND p.department_id IS NOT NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM employee_other_positions
    WHERE department_id IS NULL
  ) THEN
    RAISE EXCEPTION
      'Cannot require employee_other_positions.department_id: unresolved rows remain';
  END IF;
END $$;

ALTER TABLE employee_other_positions
  ALTER COLUMN department_id SET NOT NULL;

ALTER TABLE employee_other_positions
  DROP CONSTRAINT IF EXISTS employee_other_positions_department_id_fkey;

ALTER TABLE employee_other_positions
  ADD CONSTRAINT employee_other_positions_department_id_fkey
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT;

ALTER TABLE employee_other_positions
  DROP CONSTRAINT IF EXISTS chk_employee_other_position_dates;

ALTER TABLE employee_other_positions
  ADD CONSTRAINT chk_employee_other_position_dates
  CHECK (effective_to IS NULL OR effective_to >= effective_from);

CREATE INDEX IF NOT EXISTS idx_employee_other_positions_employee
  ON employee_other_positions (employee_id, effective_from DESC);

CREATE INDEX IF NOT EXISTS idx_employee_other_positions_position
  ON employee_other_positions (position_id);

CREATE INDEX IF NOT EXISTS idx_employee_other_positions_duplicate_lookup
  ON employee_other_positions (
    employee_id,
    department_id,
    position_id,
    effective_from,
    effective_to
  )
  WHERE is_active = true;

COMMIT;
