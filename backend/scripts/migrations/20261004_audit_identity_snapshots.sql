-- New events only: current user data cannot reconstruct historical identities.
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS actor_snapshot JSONB;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS target_snapshot JSONB;

CREATE OR REPLACE FUNCTION capture_audit_identities()
RETURNS trigger LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
BEGIN
  SELECT jsonb_build_object('id', u.id, 'name', u.full_name, 'email', u.email)
    INTO NEW.actor_snapshot FROM users u WHERE u.id = NEW.user_id;
  NEW.actor_snapshot := COALESCE(NEW.actor_snapshot,
    jsonb_build_object('id', NEW.user_id, 'name', NULL, 'email', NULL));
  NEW.target_snapshot := NULL;
  IF NEW.entity_type IN ('user', 'system_account', 'employee_account', 'auth') THEN
    SELECT jsonb_build_object('id', u.id, 'name', u.full_name, 'email', u.email)
      INTO NEW.target_snapshot FROM users u WHERE u.id = NEW.entity_id;
    NEW.target_snapshot := COALESCE(NEW.target_snapshot,
      jsonb_build_object('id', NEW.entity_id, 'name', NULL, 'email', NULL));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS audit_identity_capture ON audit_logs;
CREATE TRIGGER audit_identity_capture BEFORE INSERT ON audit_logs
FOR EACH ROW EXECUTE FUNCTION capture_audit_identities();
