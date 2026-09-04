-- Enforce the Shift Management API's working-day and grace-period rules.

BEGIN;

CREATE OR REPLACE FUNCTION public.is_valid_shift_working_days(days INTEGER[])
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
STRICT
AS $$
  SELECT cardinality(days) BETWEEN 1 AND 7
     AND days <@ ARRAY[1,2,3,4,5,6,7]::INTEGER[]
     AND cardinality(days) = (
       SELECT COUNT(DISTINCT day)::INTEGER
       FROM unnest(days) AS day
     );
$$;

ALTER TABLE shifts
  DROP CONSTRAINT IF EXISTS shifts_working_days_check;

ALTER TABLE shifts
  ADD CONSTRAINT shifts_working_days_check
  CHECK (public.is_valid_shift_working_days(working_days));

ALTER TABLE shifts
  DROP CONSTRAINT IF EXISTS shifts_grace_period_range_check;

ALTER TABLE shifts
  ADD CONSTRAINT shifts_grace_period_range_check
  CHECK (grace_period_minutes BETWEEN 0 AND 240);

COMMIT;
