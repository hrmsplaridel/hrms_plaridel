-- DocuTracker AI summaries v1.
-- Stores generated summaries separately from workflow/runtime document state.

CREATE TABLE IF NOT EXISTS docutracker_ai_summaries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  summary_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  generated_by UUID REFERENCES users(id) ON DELETE SET NULL,
  provider TEXT NOT NULL DEFAULT 'ollama',
  model TEXT,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_docutracker_ai_summaries_document_generated
  ON docutracker_ai_summaries(document_id, generated_at DESC);
