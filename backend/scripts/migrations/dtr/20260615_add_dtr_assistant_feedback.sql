CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS dtr_assistant_feedback (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL,
  message_id UUID NOT NULL,
  rating TEXT NOT NULL
    CONSTRAINT dtr_assistant_feedback_rating_check
    CHECK (rating IN ('up', 'down')),
  intent TEXT,
  provider TEXT,
  model TEXT,
  model_profile TEXT,
  content_preview TEXT,
  comment TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, message_id)
);

CREATE INDEX IF NOT EXISTS idx_dtr_assistant_feedback_user_created
  ON dtr_assistant_feedback(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_dtr_assistant_feedback_rating_created
  ON dtr_assistant_feedback(rating, created_at DESC);
