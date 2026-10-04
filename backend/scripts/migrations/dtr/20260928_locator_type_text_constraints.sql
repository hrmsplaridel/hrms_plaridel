-- Enforce locator-type code and display-text integrity without truncating data.
-- Run: psql -v ON_ERROR_STOP=1 -d hrms_plaridel -f backend/scripts/migrations/dtr/20260928_locator_type_text_constraints.sql

BEGIN;

DO $$
DECLARE
  invalid_rows INTEGER;
BEGIN
  SELECT COUNT(*)::integer
  INTO invalid_rows
  FROM locator_request_types
  WHERE code !~ '^[a-z0-9_][a-z0-9_-]{1,63}$'
     OR label <> btrim(label)
     OR char_length(label) NOT BETWEEN 1 AND 100
     OR short_label <> btrim(short_label)
     OR char_length(short_label) NOT BETWEEN 1 AND 40
     OR location_label <> btrim(location_label)
     OR char_length(location_label) NOT BETWEEN 1 AND 100
     OR location_hint <> btrim(location_hint)
     OR char_length(location_hint) NOT BETWEEN 1 AND 200
     OR dtr_slot_label <> btrim(dtr_slot_label)
     OR char_length(dtr_slot_label) NOT BETWEEN 1 AND 40
     OR dtr_print_label <> btrim(dtr_print_label)
     OR char_length(dtr_print_label) NOT BETWEEN 1 AND 40;

  IF invalid_rows > 0 THEN
    RAISE EXCEPTION
      'Cannot add locator type text constraints: % row(s) violate the required format or length limits.',
      invalid_rows
      USING HINT = 'Correct the reported locator_request_types rows before rerunning this migration.';
  END IF;
END
$$;

ALTER TABLE locator_request_types
  DROP CONSTRAINT IF EXISTS chk_locator_request_types_code_format,
  DROP CONSTRAINT IF EXISTS chk_locator_request_types_label_length,
  DROP CONSTRAINT IF EXISTS chk_locator_request_types_short_label_length,
  DROP CONSTRAINT IF EXISTS chk_locator_request_types_location_label_length,
  DROP CONSTRAINT IF EXISTS chk_locator_request_types_location_hint_length,
  DROP CONSTRAINT IF EXISTS chk_locator_request_types_dtr_slot_label_length,
  DROP CONSTRAINT IF EXISTS chk_locator_request_types_dtr_print_label_length;

ALTER TABLE locator_request_types
  ADD CONSTRAINT chk_locator_request_types_code_format
    CHECK (code ~ '^[a-z0-9_][a-z0-9_-]{1,63}$'),
  ADD CONSTRAINT chk_locator_request_types_label_length
    CHECK (label = btrim(label) AND char_length(label) BETWEEN 1 AND 100),
  ADD CONSTRAINT chk_locator_request_types_short_label_length
    CHECK (short_label = btrim(short_label) AND char_length(short_label) BETWEEN 1 AND 40),
  ADD CONSTRAINT chk_locator_request_types_location_label_length
    CHECK (location_label = btrim(location_label) AND char_length(location_label) BETWEEN 1 AND 100),
  ADD CONSTRAINT chk_locator_request_types_location_hint_length
    CHECK (location_hint = btrim(location_hint) AND char_length(location_hint) BETWEEN 1 AND 200),
  ADD CONSTRAINT chk_locator_request_types_dtr_slot_label_length
    CHECK (dtr_slot_label = btrim(dtr_slot_label) AND char_length(dtr_slot_label) BETWEEN 1 AND 40),
  ADD CONSTRAINT chk_locator_request_types_dtr_print_label_length
    CHECK (dtr_print_label = btrim(dtr_print_label) AND char_length(dtr_print_label) BETWEEN 1 AND 40);

COMMIT;
