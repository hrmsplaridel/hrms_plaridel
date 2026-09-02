-- Bind assistant feedback to server-issued responses and remove stored chat text.
BEGIN;

ALTER TABLE dtr_assistant_feedback
  ADD COLUMN IF NOT EXISTS response_hash TEXT;

CREATE INDEX IF NOT EXISTS idx_dtr_assistant_feedback_created
  ON dtr_assistant_feedback(created_at);

UPDATE dtr_assistant_feedback
SET prompt_preview = NULL,
    content_preview = NULL
WHERE prompt_preview IS NOT NULL
   OR content_preview IS NOT NULL;

DELETE FROM dtr_assistant_feedback
WHERE created_at < now() - interval '180 days';

COMMIT;
