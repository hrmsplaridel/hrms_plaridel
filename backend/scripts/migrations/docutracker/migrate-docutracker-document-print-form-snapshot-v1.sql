-- DocuTracker: per-document Printed Form snapshot.
-- New documents freeze official vs custom version at create time.
-- Existing rows stay print_form_selection = 'unset' (legacy; not backfilled).

BEGIN;

ALTER TABLE docutracker_documents
  ADD COLUMN IF NOT EXISTS print_form_selection TEXT NOT NULL DEFAULT 'unset';

ALTER TABLE docutracker_documents
  ADD COLUMN IF NOT EXISTS print_template_version_id UUID;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'docutracker_documents_print_form_selection_check_v1'
  ) THEN
    ALTER TABLE docutracker_documents
      ADD CONSTRAINT docutracker_documents_print_form_selection_check_v1
      CHECK (print_form_selection IN ('unset', 'official', 'custom'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'docutracker_documents_print_form_snapshot_check_v1'
  ) THEN
    ALTER TABLE docutracker_documents
      ADD CONSTRAINT docutracker_documents_print_form_snapshot_check_v1
      CHECK (
        (print_form_selection = 'unset' AND print_template_version_id IS NULL)
        OR (print_form_selection = 'official' AND print_template_version_id IS NULL)
        OR (print_form_selection = 'custom' AND print_template_version_id IS NOT NULL)
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'docutracker_documents_print_template_version_fkey'
  ) THEN
    ALTER TABLE docutracker_documents
      ADD CONSTRAINT docutracker_documents_print_template_version_fkey
      FOREIGN KEY (print_template_version_id)
      REFERENCES docutracker_print_template_versions(id)
      ON DELETE RESTRICT;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_print_template_version
  ON docutracker_documents (print_template_version_id)
  WHERE print_template_version_id IS NOT NULL;

CREATE OR REPLACE FUNCTION docutracker_stamp_print_form_snapshot()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  type_version_id UUID;
  type_layout JSONB;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.print_form_selection IS DISTINCT FROM OLD.print_form_selection
      OR NEW.print_template_version_id IS DISTINCT FROM OLD.print_template_version_id THEN
      RAISE EXCEPTION 'DocuTracker print form snapshot is immutable';
    END IF;
    RETURN NEW;
  END IF;

  -- INSERT: stamp only when still legacy-unset (app may already set official/custom).
  IF NEW.print_form_selection IS NULL OR NEW.print_form_selection = 'unset' THEN
    SELECT dt.print_template_version_id, v.print_layout
      INTO type_version_id, type_layout
    FROM docutracker_document_types dt
    LEFT JOIN docutracker_print_template_versions v
      ON v.id = dt.print_template_version_id
    WHERE dt.document_type = NEW.document_type;

    IF type_version_id IS NOT NULL
      AND type_layout IS NOT NULL
      AND jsonb_typeof(type_layout) = 'object' THEN
      NEW.print_form_selection := 'custom';
      NEW.print_template_version_id := type_version_id;
    ELSE
      NEW.print_form_selection := 'official';
      NEW.print_template_version_id := NULL;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_docutracker_stamp_print_form_snapshot
  ON docutracker_documents;
CREATE TRIGGER trg_docutracker_stamp_print_form_snapshot
  BEFORE INSERT OR UPDATE OF print_form_selection, print_template_version_id
  ON docutracker_documents
  FOR EACH ROW
  EXECUTE FUNCTION docutracker_stamp_print_form_snapshot();

COMMIT;
