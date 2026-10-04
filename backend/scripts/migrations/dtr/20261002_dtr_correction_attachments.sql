BEGIN;
CREATE TABLE IF NOT EXISTS dtr_correction_attachments (
  correction_id UUID PRIMARY KEY REFERENCES dtr_corrections(id) ON DELETE CASCADE,
  file_name TEXT NOT NULL,
  mime_type TEXT NOT NULL CHECK (mime_type IN ('application/pdf', 'image/jpeg', 'image/png')),
  content BYTEA NOT NULL CHECK (octet_length(content) BETWEEN 1 AND 5242880),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMIT;
