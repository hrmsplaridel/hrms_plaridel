-- DocuTracker printed-form templates (background + designed layout), per document type.
-- Official Memo / Purchase Request keep built-in templates unless a custom layout is saved.

CREATE TABLE IF NOT EXISTS docutracker_print_template_versions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_type TEXT NOT NULL
    REFERENCES docutracker_document_types(document_type) ON DELETE CASCADE,
  background_pdf BYTEA,
  background_name TEXT,
  print_layout JSONB,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT docutracker_print_template_versions_layout_object_check
    CHECK (print_layout IS NULL OR jsonb_typeof(print_layout) = 'object')
);

CREATE INDEX IF NOT EXISTS idx_docutracker_print_template_versions_type
  ON docutracker_print_template_versions (document_type, created_at DESC);

ALTER TABLE docutracker_document_types
  ADD COLUMN IF NOT EXISTS print_template_version_id UUID;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'docutracker_document_types_print_template_version_fkey'
  ) THEN
    ALTER TABLE docutracker_document_types
      ADD CONSTRAINT docutracker_document_types_print_template_version_fkey
      FOREIGN KEY (print_template_version_id)
      REFERENCES docutracker_print_template_versions(id)
      ON DELETE SET NULL;
  END IF;
END $$;
