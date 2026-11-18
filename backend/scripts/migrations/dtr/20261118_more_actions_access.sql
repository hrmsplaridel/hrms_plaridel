-- Per-tool administrator grants for the existing Leave and Locator More actions menus.
-- Existing grants are copied only when a column is first introduced.
BEGIN;
LOCK TABLE dtr_admin_access IN SHARE ROW EXCLUSIVE MODE;
DO $$
DECLARE
  tool RECORD;
  added BOOLEAN := false;
BEGIN
  FOR tool IN SELECT * FROM (VALUES
      ('leave_paper_allowed', 'leave_allowed'),
      ('leave_types_allowed', 'leave_allowed'),
      ('leave_ledger_allowed', 'leave_allowed'),
      ('leave_card_allowed', 'leave_allowed'),
      ('leave_balances_allowed', 'leave_allowed'),
      ('leave_month_end_allowed', 'leave_allowed'),
      ('leave_year_end_allowed', 'leave_allowed'),
      ('locator_file_allowed', 'locator_allowed'),
      ('locator_corrections_allowed', 'locator_allowed'),
      ('locator_paper_allowed', 'locator_allowed'),
      ('locator_types_allowed', 'locator_allowed')
  ) AS tools(field_name, parent_name)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_attribute
      WHERE attrelid = 'dtr_admin_access'::regclass
        AND attname = tool.field_name AND NOT attisdropped
    ) THEN
      EXECUTE format('ALTER TABLE dtr_admin_access ADD COLUMN %I BOOLEAN NOT NULL DEFAULT false', tool.field_name);
      EXECUTE format('UPDATE dtr_admin_access SET %I = %I', tool.field_name, tool.parent_name);
      added := true;
    END IF;
  END LOOP;
  IF added THEN
    -- Invalidate stale Manage Access drafts opened before these grants existed.
    UPDATE dtr_admin_access SET updated_at = GREATEST(clock_timestamp(), updated_at + interval '1 microsecond');
  END IF;
END $$;
COMMIT;
