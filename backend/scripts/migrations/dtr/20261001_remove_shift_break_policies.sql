BEGIN;
SET LOCAL lock_timeout = '5s';

ALTER TABLE shifts DROP COLUMN IF EXISTS break_mode;
ALTER TABLE shifts DROP COLUMN IF EXISTS unpaid_break_minutes;

-- Remove retired options from schedule metadata without recalculating DTR totals.
UPDATE dtr_daily_summary
SET shift_snapshot = shift_snapshot - ARRAY[
  'breakMode', 'unpaidBreakMinutes', 'break_mode', 'unpaid_break_minutes'
]
WHERE jsonb_typeof(shift_snapshot) = 'object'
  AND shift_snapshot ?| ARRAY[
    'breakMode', 'unpaidBreakMinutes', 'break_mode', 'unpaid_break_minutes'
  ];

COMMENT ON COLUMN dtr_daily_summary.shift_snapshot IS 'Effective attendance schedule used to process this attendance date.';
COMMIT;
