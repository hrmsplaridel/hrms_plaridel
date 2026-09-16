-- DocuTracker document builder and e-signature persistence.
-- Apply after the DocuTracker core and workflow migrations.

BEGIN;

CREATE TABLE IF NOT EXISTS docutracker_document_contents (
  document_id UUID PRIMARY KEY
    REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  format_version INT NOT NULL DEFAULT 1,
  pages JSONB NOT NULL DEFAULT '[]'::jsonb,
  page_size TEXT NOT NULL DEFAULT 'A4',
  margins JSONB NOT NULL DEFAULT
    '{"top":0.08,"right":0.08,"bottom":0.08,"left":0.08}'::jsonb,
  revision INT NOT NULL DEFAULT 1,
  updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT docutracker_document_contents_pages_array_check
    CHECK (jsonb_typeof(pages) = 'array'),
  CONSTRAINT docutracker_document_contents_margins_object_check
    CHECK (jsonb_typeof(margins) = 'object'),
  CONSTRAINT docutracker_document_contents_format_version_check
    CHECK (format_version > 0),
  CONSTRAINT docutracker_document_contents_revision_check
    CHECK (revision > 0),
  CONSTRAINT docutracker_document_contents_page_size_check
    CHECK (page_size = 'A4')
);

CREATE TABLE IF NOT EXISTS docutracker_signature_assets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  image_bytes BYTEA NOT NULL,
  mime_type TEXT NOT NULL,
  source_type TEXT NOT NULL,
  display_name TEXT,
  is_saved BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT docutracker_signature_assets_mime_check
    CHECK (mime_type IN ('image/png', 'image/jpeg')),
  CONSTRAINT docutracker_signature_assets_source_check
    CHECK (source_type IN ('drawn', 'uploaded')),
  CONSTRAINT docutracker_signature_assets_size_check
    CHECK (octet_length(image_bytes) BETWEEN 1 AND 2097152)
);

CREATE INDEX IF NOT EXISTS idx_docutracker_signature_assets_owner_saved
  ON docutracker_signature_assets(owner_user_id, is_saved, created_at DESC);

CREATE TABLE IF NOT EXISTS docutracker_signature_fields (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL
    REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  page_number INT NOT NULL,
  position_x DOUBLE PRECISION NOT NULL,
  position_y DOUBLE PRECISION NOT NULL,
  width DOUBLE PRECISION NOT NULL,
  height DOUBLE PRECISION NOT NULL,
  assigned_signer_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  label TEXT NOT NULL DEFAULT 'Sign Here',
  signature_asset_id UUID REFERENCES docutracker_signature_assets(id) ON DELETE RESTRICT,
  signed_by UUID REFERENCES users(id) ON DELETE RESTRICT,
  signer_name_snapshot TEXT,
  signed_at TIMESTAMPTZ,
  locked_at TIMESTAMPTZ,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT docutracker_signature_fields_page_check
    CHECK (page_number > 0),
  CONSTRAINT docutracker_signature_fields_position_x_check
    CHECK (position_x >= 0 AND position_x <= 1),
  CONSTRAINT docutracker_signature_fields_position_y_check
    CHECK (position_y >= 0 AND position_y <= 1),
  CONSTRAINT docutracker_signature_fields_width_check
    CHECK (width > 0 AND width <= 1 AND position_x + width <= 1),
  CONSTRAINT docutracker_signature_fields_height_check
    CHECK (height > 0 AND height <= 1 AND position_y + height <= 1),
  CONSTRAINT docutracker_signature_fields_label_check
    CHECK (length(btrim(label)) BETWEEN 1 AND 80),
  CONSTRAINT docutracker_signature_fields_signed_state_check CHECK (
    (signature_asset_id IS NULL AND signed_by IS NULL AND signed_at IS NULL
      AND locked_at IS NULL AND signer_name_snapshot IS NULL)
    OR
    (signature_asset_id IS NOT NULL AND signed_by IS NOT NULL AND signed_at IS NOT NULL
      AND locked_at IS NOT NULL AND signer_name_snapshot IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_docutracker_signature_fields_document_page
  ON docutracker_signature_fields(document_id, page_number, created_at);

CREATE INDEX IF NOT EXISTS idx_docutracker_signature_fields_signer_pending
  ON docutracker_signature_fields(assigned_signer_id, document_id)
  WHERE signed_at IS NULL;

COMMIT;
