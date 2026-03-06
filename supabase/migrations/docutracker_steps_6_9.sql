-- DocuTracker Steps 6-9: Escalation, Notifications, Audit Trail
-- Run after docutracker_tables.sql

-- Add new columns to docutracker_documents
ALTER TABLE docutracker_documents
  ADD COLUMN IF NOT EXISTS document_number TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS current_holder_id UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS escalation_level INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS needs_admin_intervention BOOLEAN DEFAULT false;

-- Document history / audit trail (Step 6 & 9)
CREATE TABLE IF NOT EXISTS docutracker_document_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id UUID NOT NULL REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  action TEXT,
  actor_id UUID REFERENCES auth.users(id),
  actor_name TEXT,
  from_step INT,
  to_step INT,
  from_status TEXT,
  to_status TEXT,
  remarks TEXT,
  is_overdue_log BOOLEAN DEFAULT false,
  is_escalation_log BOOLEAN DEFAULT false,
  escalation_level INT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Notifications (Step 7)
CREATE TABLE IF NOT EXISTS docutracker_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id UUID NOT NULL REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  type TEXT NOT NULL,
  title TEXT,
  body TEXT,
  read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Escalation configs (Step 6)
CREATE TABLE IF NOT EXISTS docutracker_escalation_configs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_type TEXT NOT NULL,
  department_id TEXT,
  escalation_target_role TEXT,
  escalation_delay_minutes INT DEFAULT 60,
  max_escalation_level INT DEFAULT 3,
  notify_original_sender BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- RLS
ALTER TABLE docutracker_document_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE docutracker_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE docutracker_escalation_configs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "docutracker_history_all" ON docutracker_document_history
  FOR ALL TO authenticated USING (true);

CREATE POLICY "docutracker_notifications_select" ON docutracker_notifications
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE POLICY "docutracker_notifications_insert" ON docutracker_notifications
  FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "docutracker_escalation_select" ON docutracker_escalation_configs
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "docutracker_escalation_all_admin" ON docutracker_escalation_configs
  FOR ALL TO authenticated USING (true);
