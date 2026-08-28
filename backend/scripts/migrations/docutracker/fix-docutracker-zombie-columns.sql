-- Fix DocuTracker out-of-sync columns that are causing crashes during document creation.
-- These columns are legacy fields that are no longer used in the codebase.

ALTER TABLE docutracker_documents
  DROP COLUMN IF EXISTS workflow_flow_id;

ALTER TABLE docutracker_workflow_steps
  DROP COLUMN IF EXISTS flow_id;

ALTER TABLE docutracker_routing_configs
  DROP COLUMN IF EXISTS flow_id;

-- Also check docutracker_routing_config_versions just in case
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'docutracker_routing_config_versions' AND column_name = 'flow_id'
  ) THEN
    ALTER TABLE docutracker_routing_config_versions DROP COLUMN IF EXISTS flow_id;
  END IF;
END $$;
