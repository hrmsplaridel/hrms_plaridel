-- Optional: align DB with ON CONFLICT-friendly schema (one row per document_type).
-- Safe to run multiple times.

CREATE UNIQUE INDEX IF NOT EXISTS docutracker_routing_configs_document_type_key
  ON docutracker_routing_configs (document_type);
