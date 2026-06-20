ALTER TABLE dtr_assistant_feedback
  ADD COLUMN IF NOT EXISTS prompt_preview TEXT,
  ADD COLUMN IF NOT EXISTS prompt_hash TEXT,
  ADD COLUMN IF NOT EXISTS intent_confidence NUMERIC(5,4),
  ADD COLUMN IF NOT EXISTS intent_source TEXT;

CREATE INDEX IF NOT EXISTS idx_dtr_assistant_feedback_prompt_hash
  ON dtr_assistant_feedback(prompt_hash)
  WHERE prompt_hash IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_dtr_assistant_feedback_intent_source_created
  ON dtr_assistant_feedback(intent, intent_source, created_at DESC);
