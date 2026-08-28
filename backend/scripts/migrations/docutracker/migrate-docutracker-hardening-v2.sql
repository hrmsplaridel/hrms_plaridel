-- DocuTracker hardening v2
-- Safe to run repeatedly.

-- 1) Routing / escalation numeric guards
ALTER TABLE docutracker_routing_configs
  DROP CONSTRAINT IF EXISTS docutracker_routing_configs_review_deadline_hours_check;
ALTER TABLE docutracker_routing_configs
  ADD CONSTRAINT docutracker_routing_configs_review_deadline_hours_check
  CHECK (review_deadline_hours > 0);

ALTER TABLE docutracker_escalation_configs
  DROP CONSTRAINT IF EXISTS docutracker_escalation_configs_escalation_delay_minutes_check;
ALTER TABLE docutracker_escalation_configs
  ADD CONSTRAINT docutracker_escalation_configs_escalation_delay_minutes_check
  CHECK (escalation_delay_minutes > 0);

ALTER TABLE docutracker_escalation_configs
  DROP CONSTRAINT IF EXISTS docutracker_escalation_configs_max_escalation_level_check;
ALTER TABLE docutracker_escalation_configs
  ADD CONSTRAINT docutracker_escalation_configs_max_escalation_level_check
  CHECK (max_escalation_level >= 1);

-- 2) Notification event key for deterministic idempotency
ALTER TABLE docutracker_notifications
  ADD COLUMN IF NOT EXISTS event_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_notifications_event_key_unique
  ON docutracker_notifications(document_id, user_id, type, event_key)
  WHERE event_key IS NOT NULL;

-- 3) Permission row hygiene and uniqueness
DELETE FROM docutracker_permissions
WHERE user_id IS NULL
  AND role_id IS NULL;

WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY user_id, role_id, document_type, action
           ORDER BY updated_at DESC NULLS LAST, created_at DESC, id DESC
         ) AS rn
  FROM docutracker_permissions
)
DELETE FROM docutracker_permissions p
USING ranked r
WHERE p.id = r.id
  AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_permissions_user_unique
  ON docutracker_permissions(user_id, document_type, action)
  WHERE user_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_permissions_role_unique
  ON docutracker_permissions(role_id, document_type, action)
  WHERE role_id IS NOT NULL;

ALTER TABLE docutracker_permissions
  DROP CONSTRAINT IF EXISTS docutracker_permissions_scope_check_v1;
ALTER TABLE docutracker_permissions
  ADD CONSTRAINT docutracker_permissions_scope_check_v1
  CHECK ((user_id IS NOT NULL) <> (role_id IS NOT NULL));

-- 4) Query-performance indexes for list/history access patterns
CREATE INDEX IF NOT EXISTS idx_docutracker_documents_type_status_created
  ON docutracker_documents(document_type, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_holder_status_deadline
  ON docutracker_documents(current_holder_id, status, deadline_time);

CREATE INDEX IF NOT EXISTS idx_docutracker_history_document_created_desc
  ON docutracker_document_history(document_id, created_at DESC);

-- 5) Transition idempotency storage
CREATE TABLE IF NOT EXISTS docutracker_transition_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
  response_payload JSONB,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (document_id, action, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_docutracker_transition_requests_lookup
  ON docutracker_transition_requests(document_id, action, idempotency_key);
