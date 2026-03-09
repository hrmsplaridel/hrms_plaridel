-- HRMS Plaridel - DocuTracker Module
-- Run AFTER init-schema.sql (requires: users, departments)
-- Run: psql -d hrms_plaridel -f scripts/init-schema-docutracker.sql

-- =========================
-- DOCUTRACKER - DOCUMENTS
-- =========================
CREATE TABLE IF NOT EXISTS docutracker_documents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_number TEXT UNIQUE,
  document_type TEXT NOT NULL DEFAULT 'memo',
  title TEXT NOT NULL,
  description TEXT,
  file_path TEXT,
  file_name TEXT,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  current_holder_id UUID REFERENCES users(id) ON DELETE SET NULL,
  current_step INT DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'in_review', 'approved', 'rejected', 'returned', 'cancelled')),
  sent_time TIMESTAMPTZ,
  deadline_time TIMESTAMPTZ,
  reviewed_time TIMESTAMPTZ,
  escalation_level INT DEFAULT 0,
  needs_admin_intervention BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS docutracker_routing_configs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_type TEXT NOT NULL UNIQUE,
  steps JSONB NOT NULL DEFAULT '[]',
  review_deadline_hours INT DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS docutracker_document_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  action TEXT,
  actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
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

CREATE TABLE IF NOT EXISTS docutracker_routing_records (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  step_order INT NOT NULL,
  assignee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sent_time TIMESTAMPTZ,
  deadline_time TIMESTAMPTZ,
  reviewed_time TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending',
  remarks TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS docutracker_notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL
    CHECK (type IN ('assigned', 'deadline_near', 'overdue', 'escalated', 'returned', 'rejected')),
  title TEXT,
  body TEXT,
  read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS docutracker_permissions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  role_id TEXT,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  document_type TEXT NOT NULL DEFAULT '*',
  action TEXT NOT NULL,
  granted BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS docutracker_escalation_configs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_type TEXT NOT NULL,
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  escalation_target_role TEXT,
  escalation_delay_minutes INT DEFAULT 60,
  max_escalation_level INT DEFAULT 3,
  notify_original_sender BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_docutracker_documents_created_by ON docutracker_documents(created_by);
CREATE INDEX IF NOT EXISTS idx_docutracker_documents_current_holder ON docutracker_documents(current_holder_id);
CREATE INDEX IF NOT EXISTS idx_docutracker_documents_status ON docutracker_documents(status);
CREATE INDEX IF NOT EXISTS idx_docutracker_history_document_id ON docutracker_document_history(document_id);
CREATE INDEX IF NOT EXISTS idx_docutracker_notifications_user_id ON docutracker_notifications(user_id);
