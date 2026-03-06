-- DocuTracker module tables (Steps 1-5)
-- Run this in Supabase SQL Editor to create the required tables.

-- Documents table
CREATE TABLE IF NOT EXISTS docutracker_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_type TEXT NOT NULL DEFAULT 'memo',
  title TEXT NOT NULL,
  description TEXT,
  file_path TEXT,
  file_name TEXT,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  current_step INT DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'pending',
  sent_time TIMESTAMPTZ,
  deadline_time TIMESTAMPTZ,
  reviewed_time TIMESTAMPTZ
);

-- Routing records (per-step tracking: sent_time, deadline_time, reviewed_time, status)
CREATE TABLE IF NOT EXISTS docutracker_routing_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id UUID NOT NULL REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  step_order INT NOT NULL,
  assignee_id UUID REFERENCES auth.users(id),
  sent_time TIMESTAMPTZ,
  deadline_time TIMESTAMPTZ,
  reviewed_time TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending',
  remarks TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Permissions (Step 4: Admin Privilege Management)
CREATE TABLE IF NOT EXISTS docutracker_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role_id TEXT,
  user_id UUID REFERENCES auth.users(id),
  document_type TEXT NOT NULL DEFAULT '*',
  action TEXT NOT NULL,
  granted BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Routing configs (workflow definitions per document type)
CREATE TABLE IF NOT EXISTS docutracker_routing_configs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_type TEXT NOT NULL UNIQUE,
  steps JSONB NOT NULL DEFAULT '[]',
  review_deadline_hours INT DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- RLS policies (basic - adjust for your auth)
ALTER TABLE docutracker_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE docutracker_routing_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE docutracker_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE docutracker_routing_configs ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to read documents (refine for Step 2: Role-Based Visibility)
CREATE POLICY "docutracker_documents_select" ON docutracker_documents
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "docutracker_documents_insert" ON docutracker_documents
  FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "docutracker_documents_update" ON docutracker_documents
  FOR UPDATE TO authenticated USING (true);

-- Similar for other tables - customize based on your role/department logic
CREATE POLICY "docutracker_routing_records_all" ON docutracker_routing_records
  FOR ALL TO authenticated USING (true);

CREATE POLICY "docutracker_permissions_all" ON docutracker_permissions
  FOR ALL TO authenticated USING (true);

CREATE POLICY "docutracker_routing_configs_select" ON docutracker_routing_configs
  FOR SELECT TO authenticated USING (true);
