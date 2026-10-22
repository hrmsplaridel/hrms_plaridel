-- Add custom leave layouts without rewriting existing versions or request pointers.
BEGIN;
ALTER TABLE leave_print_template_versions ADD COLUMN IF NOT EXISTS print_layout JSONB;
ALTER TABLE leave_print_template_versions DROP CONSTRAINT IF EXISTS leave_print_template_versions_layout_check;
ALTER TABLE leave_print_template_versions ADD CONSTRAINT leave_print_template_versions_layout_check CHECK (layout IN ('csc','wellness','custom'));
ALTER TABLE leave_print_template_versions DROP CONSTRAINT IF EXISTS chk_leave_print_layout;
ALTER TABLE leave_print_template_versions ADD CONSTRAINT chk_leave_print_layout CHECK (
 (layout <> 'custom' AND print_layout IS NULL) OR
 (layout = 'custom' AND print_layout IS NOT NULL AND jsonb_typeof(print_layout) = 'object' AND octet_length(print_layout::text) <= 100000)
);
COMMIT;
