-- Named, versioned DTR workflows. Existing filed requests retain legacy routing.
BEGIN;
CREATE TABLE IF NOT EXISTS approval_workflows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 100),
  current_version INTEGER NOT NULL DEFAULT 1 CHECK (current_version > 0),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS approval_workflows_name_unique ON approval_workflows (lower(name));
CREATE TABLE IF NOT EXISTS approval_workflow_versions (
  workflow_id UUID NOT NULL REFERENCES approval_workflows(id),
  version INTEGER NOT NULL CHECK (version > 0),
  steps JSONB NOT NULL CHECK (jsonb_typeof(steps)='array' AND jsonb_array_length(steps) BETWEEN 1 AND 3),
  employment_types TEXT[],
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (workflow_id, version)
);
ALTER TABLE leave_types ADD COLUMN IF NOT EXISTS approval_workflow_id UUID REFERENCES approval_workflows(id);
ALTER TABLE locator_request_types ADD COLUMN IF NOT EXISTS approval_workflow_id UUID REFERENCES approval_workflows(id);
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS workflow_snapshot JSONB;
ALTER TABLE locator_slips ADD COLUMN IF NOT EXISTS workflow_snapshot JSONB;

-- Convert existing type settings, including employment exceptions, without
-- modifying any request's status, reviewer, signature or historical workflow.
DO $$
DECLARE item RECORD; workflow UUID; title TEXT; route_steps JSONB;
BEGIN
 FOR item IN
   SELECT DISTINCT approval_route, mayor_employment_types FROM leave_types WHERE approval_workflow_id IS NULL
   UNION SELECT DISTINCT approval_route, mayor_employment_types FROM locator_request_types WHERE approval_workflow_id IS NULL
 LOOP
   title := CASE item.approval_route WHEN 'mayor' THEN 'Department approval - Manual Mayor signing'
     WHEN 'mayor_direct' THEN 'Direct Mayor approval' ELSE 'Department - Final HR' END;
   IF item.mayor_employment_types IS NOT NULL THEN
     title := left(title,45) || ' (' || array_to_string(item.mayor_employment_types,',') || ')';
     IF length(title)>100 THEN title:=left(title,65)||' '||md5(array_to_string(item.mayor_employment_types,',')); END IF;
   END IF;
   route_steps := CASE item.approval_route WHEN 'mayor' THEN '["department","manual_mayor"]'::jsonb
     WHEN 'mayor_direct' THEN '["mayor"]'::jsonb ELSE '["department","hr"]'::jsonb END;
   INSERT INTO approval_workflows(name) VALUES(title) ON CONFLICT DO NOTHING;
   SELECT id INTO workflow FROM approval_workflows WHERE lower(name)=lower(title);
   INSERT INTO approval_workflow_versions(workflow_id,version,steps,employment_types)
     VALUES(workflow,1,route_steps,item.mayor_employment_types) ON CONFLICT DO NOTHING;
   UPDATE leave_types SET approval_workflow_id=workflow WHERE approval_workflow_id IS NULL
     AND approval_route=item.approval_route AND mayor_employment_types IS NOT DISTINCT FROM item.mayor_employment_types;
   UPDATE locator_request_types SET approval_workflow_id=workflow WHERE approval_workflow_id IS NULL
     AND approval_route=item.approval_route AND mayor_employment_types IS NOT DISTINCT FROM item.mayor_employment_types;
 END LOOP;
END $$;

-- Preserve the legacy trigger for historical requests, but allow the shared
-- engine to project the status of requests with a saved workflow.
DO $$
DECLARE definition TEXT; constraint_row RECORD;
BEGIN
 SELECT pg_get_functiondef('snapshot_leave_approval_route()'::regprocedure) INTO definition;
 IF position('NEW.workflow_snapshot IS NOT NULL' IN definition)=0 THEN
   definition:=regexp_replace(definition, 'BEGIN[[:space:]]*', E'BEGIN\n IF NEW.workflow_snapshot IS NOT NULL THEN RETURN NEW; END IF;\n');
   EXECUTE definition;
 END IF;
 FOR constraint_row IN SELECT conname FROM pg_constraint
   WHERE conrelid='leave_requests'::regclass AND contype='c'
     AND pg_get_constraintdef(oid) LIKE '%final_review_route%'
 LOOP EXECUTE format('ALTER TABLE leave_requests DROP CONSTRAINT %I',constraint_row.conname); END LOOP;
 ALTER TABLE leave_requests ADD CONSTRAINT leave_requests_final_review_route_check CHECK(final_review_route IN ('hr','mayor','mayor_direct'));
END $$;
COMMIT;
