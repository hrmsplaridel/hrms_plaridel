BEGIN;

CREATE TABLE IF NOT EXISTS dtr_month_end_reconciliation_queue (
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  service_month DATE NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'reconciled')),
  reason TEXT NOT NULL,
  metadata_json JSONB,
  required_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_attempt_at TIMESTAMPTZ,
  attempt_count INT NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  last_error TEXT,
  reconciled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (employee_id, service_month),
  CONSTRAINT chk_dtr_reconciliation_service_month
    CHECK (EXTRACT(DAY FROM service_month) = 1)
);

CREATE INDEX IF NOT EXISTS idx_dtr_reconciliation_pending_month
  ON dtr_month_end_reconciliation_queue(service_month, required_at)
  WHERE status = 'pending';

CREATE OR REPLACE FUNCTION queue_completed_month_dtr_reconciliation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  affected_employee UUID;
  affected_date DATE;
  operation_reason TEXT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    affected_employee := OLD.employee_id;
    affected_date := OLD.attendance_date;
  ELSE
    affected_employee := NEW.employee_id;
    affected_date := NEW.attendance_date;
  END IF;
  operation_reason := 'dtr_' || lower(TG_OP);

  IF affected_date <
     date_trunc('month', CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date THEN
    INSERT INTO dtr_month_end_reconciliation_queue (
      employee_id, service_month, status, reason, metadata_json,
      required_at, reconciled_at, updated_at
    ) VALUES (
      affected_employee,
      date_trunc('month', affected_date)::date,
      'pending',
      operation_reason,
      jsonb_build_object('attendance_date', affected_date, 'operation', TG_OP),
      now(),
      NULL,
      now()
    )
    ON CONFLICT (employee_id, service_month) DO UPDATE
      SET status = 'pending',
          reason = EXCLUDED.reason,
          metadata_json = EXCLUDED.metadata_json,
          required_at = now(),
          last_error = NULL,
          reconciled_at = NULL,
          updated_at = now();
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF (OLD.employee_id, OLD.attendance_date)
       IS DISTINCT FROM (NEW.employee_id, NEW.attendance_date)
       AND OLD.attendance_date <
           date_trunc('month', CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Manila')::date THEN
      INSERT INTO dtr_month_end_reconciliation_queue (
        employee_id, service_month, status, reason, metadata_json,
        required_at, reconciled_at, updated_at
      ) VALUES (
        OLD.employee_id,
        date_trunc('month', OLD.attendance_date)::date,
        'pending',
        operation_reason,
        jsonb_build_object('attendance_date', OLD.attendance_date, 'operation', TG_OP),
        now(),
        NULL,
        now()
      )
      ON CONFLICT (employee_id, service_month) DO UPDATE
        SET status = 'pending',
            reason = EXCLUDED.reason,
            metadata_json = EXCLUDED.metadata_json,
            required_at = now(),
            last_error = NULL,
            reconciled_at = NULL,
            updated_at = now();
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_queue_completed_month_dtr_reconciliation
  ON dtr_daily_summary;

CREATE TRIGGER trg_queue_completed_month_dtr_reconciliation
AFTER INSERT OR UPDATE OR DELETE ON dtr_daily_summary
FOR EACH ROW
EXECUTE FUNCTION queue_completed_month_dtr_reconciliation();

COMMENT ON TABLE dtr_month_end_reconciliation_queue IS
  'Completed employee-month DTR changes waiting for idempotent leave-deduction reconciliation.';

COMMIT;
