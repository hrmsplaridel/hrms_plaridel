-- Existing template versions keep their original fixed locator-slip layout.
BEGIN;
ALTER TABLE locator_print_template_versions
  ADD COLUMN IF NOT EXISTS print_layout JSONB;
ALTER TABLE locator_print_template_versions
  DROP CONSTRAINT IF EXISTS chk_locator_print_layout;
ALTER TABLE locator_print_template_versions
  ADD CONSTRAINT chk_locator_print_layout CHECK (
    print_layout IS NULL OR (
      jsonb_typeof(print_layout) = 'object'
      AND octet_length(print_layout::text) <= 100000
    )
  );
COMMIT;
