'use strict';

const DEFAULT_TIME_ZONE = 'Asia/Manila';
const DEFAULT_QUEUE_LIMIT = 12;

function dateOnly(value) {
  if (value == null) return null;
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    const year = value.getFullYear();
    const month = String(value.getMonth() + 1).padStart(2, '0');
    const day = String(value.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
  const match = String(value).match(/^(\d{4})-(\d{2})-(\d{2})/);
  return match ? match[0] : null;
}

function serviceMonthForDate(value) {
  const date = dateOnly(value);
  return date ? `${date.slice(0, 7)}-01` : null;
}

function monthsInRange(dateFrom, dateTo) {
  const start = dateOnly(dateFrom);
  const end = dateOnly(dateTo);
  if (!start || !end || start > end) return [];
  const cursor = new Date(`${start.slice(0, 7)}-01T12:00:00Z`);
  const last = new Date(`${end.slice(0, 7)}-01T12:00:00Z`);
  const months = [];
  while (cursor <= last && months.length < 1200) {
    months.push(cursor.getUTCMonth() + 1);
    cursor.setUTCMonth(cursor.getUTCMonth() + 1);
  }
  return [...new Set(months)];
}

async function ensureDtrMonthEndReconciliationTable(db) {
  await db.query(`
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
    )
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_dtr_reconciliation_pending_month
      ON dtr_month_end_reconciliation_queue(service_month, required_at)
      WHERE status = 'pending'
  `);
}

function holidayQueueFilter({ recurring, dateFrom, dateTo }) {
  if (recurring === true) {
    const months = monthsInRange(dateFrom, dateTo);
    return {
      sql: 'EXTRACT(MONTH FROM lad.service_month)::int = ANY($1::int[])',
      params: [months],
    };
  }
  return {
    sql: `lad.service_month <= date_trunc('month', $2::date)::date
          AND (lad.service_month + INTERVAL '1 month - 1 day')::date >= $1::date`,
    params: [dateOnly(dateFrom), dateOnly(dateTo)],
  };
}

async function enqueueHolidayReconciliation(
  db,
  {
    dateFrom,
    dateTo,
    recurring = false,
    reason = 'holiday_changed',
    metadata = null,
    timeZone = DEFAULT_TIME_ZONE,
  } = {}
) {
  const start = dateOnly(dateFrom);
  const end = dateOnly(dateTo);
  if (!start || !end || start > end) return 0;
  const filter = holidayQueueFilter({ recurring, dateFrom: start, dateTo: end });
  if (recurring === true && filter.params[0].length === 0) return 0;

  await ensureDtrMonthEndReconciliationTable(db);
  const params = [
    ...filter.params,
    reason,
    metadata == null ? null : JSON.stringify(metadata),
    timeZone,
  ];
  const reasonIndex = filter.params.length + 1;
  const metadataIndex = reasonIndex + 1;
  const timeZoneIndex = metadataIndex + 1;
  const result = await db.query(
    `INSERT INTO dtr_month_end_reconciliation_queue (
       employee_id, service_month, status, reason, metadata_json,
       required_at, reconciled_at, updated_at
     )
     SELECT DISTINCT lad.user_id, lad.service_month, 'pending',
            $${reasonIndex}::text, $${metadataIndex}::jsonb, now(), NULL, now()
       FROM leave_attendance_deductions lad
      WHERE lad.service_month <
            date_trunc('month', CURRENT_TIMESTAMP AT TIME ZONE $${timeZoneIndex})::date
        AND ${filter.sql}
     ON CONFLICT (employee_id, service_month) DO UPDATE
       SET status = 'pending',
           reason = EXCLUDED.reason,
           metadata_json = EXCLUDED.metadata_json,
           required_at = now(),
           last_error = NULL,
           reconciled_at = NULL,
           updated_at = now()`,
    params
  );
  return result.rowCount || 0;
}

async function enqueueEmployeeRangeReconciliation(
  db,
  {
    employeeId,
    dateFrom,
    dateTo,
    reason = 'historical_employee_configuration_changed',
    metadata = null,
    timeZone = DEFAULT_TIME_ZONE,
  } = {}
) {
  const employee = String(employeeId || '').trim();
  const start = dateOnly(dateFrom);
  const end = dateOnly(dateTo);
  if (!employee || !start || !end || start > end) {
    return { count: 0, months: [] };
  }

  await ensureDtrMonthEndReconciliationTable(db);
  const result = await db.query(
    `WITH completed_months AS (
       SELECT generate_series(
                date_trunc('month', $2::date),
                date_trunc(
                  'month',
                  LEAST(
                    $3::date,
                    date_trunc(
                      'month',
                      CURRENT_TIMESTAMP AT TIME ZONE $6
                    )::date - 1
                  )
                ),
                INTERVAL '1 month'
              )::date AS service_month
     )
     INSERT INTO dtr_month_end_reconciliation_queue (
       employee_id, service_month, status, reason, metadata_json,
       required_at, reconciled_at, updated_at
     )
     SELECT $1::uuid, service_month, 'pending', $4::text, $5::jsonb,
            now(), NULL, now()
       FROM completed_months
      WHERE service_month <= $3::date
     ON CONFLICT (employee_id, service_month) DO UPDATE
       SET status = 'pending',
           reason = EXCLUDED.reason,
           metadata_json = EXCLUDED.metadata_json,
           required_at = now(),
           last_error = NULL,
           reconciled_at = NULL,
           updated_at = now()
     RETURNING service_month::text AS service_month`,
    [
      employee,
      start,
      end,
      reason,
      metadata == null ? null : JSON.stringify(metadata),
      timeZone,
    ]
  );
  const months = result.rows
    .map((row) => dateOnly(row.service_month))
    .filter(Boolean);
  return { count: months.length, months };
}

async function listPendingReconciliationMonths(
  db,
  { excludeServiceMonth = null, limit = DEFAULT_QUEUE_LIMIT, timeZone = DEFAULT_TIME_ZONE } = {}
) {
  await ensureDtrMonthEndReconciliationTable(db);
  const safeLimit = Math.max(1, Math.min(120, Number.parseInt(limit, 10) || DEFAULT_QUEUE_LIMIT));
  const result = await db.query(
    `SELECT service_month::text AS service_month,
            COUNT(*)::int AS employee_count,
            array_agg(employee_id::text ORDER BY employee_id::text) AS employee_ids,
            MAX(required_at) AS cutoff
       FROM dtr_month_end_reconciliation_queue
      WHERE status = 'pending'
        AND service_month <
            date_trunc('month', CURRENT_TIMESTAMP AT TIME ZONE $1)::date
        AND ($2::date IS NULL OR service_month <> $2::date)
      GROUP BY service_month
      ORDER BY service_month ASC
      LIMIT $3::int`,
    [timeZone, excludeServiceMonth, safeLimit]
  );
  return result.rows.map((row) => ({
    serviceMonth: dateOnly(row.service_month),
    targetMonth: dateOnly(row.service_month)?.slice(0, 7),
    employeeCount: Number(row.employee_count || 0),
    employeeIds: Array.isArray(row.employee_ids) ? row.employee_ids.map(String) : [],
    cutoff: row.cutoff,
  }));
}

async function listPendingReconciliationEmployees(
  db,
  { serviceMonth, cutoff = new Date(), timeZone = DEFAULT_TIME_ZONE } = {}
) {
  const month = serviceMonthForDate(serviceMonth);
  if (!month) return [];
  await ensureDtrMonthEndReconciliationTable(db);
  const result = await db.query(
    `SELECT employee_id::text AS employee_id
       FROM dtr_month_end_reconciliation_queue
      WHERE status = 'pending'
        AND service_month = $1::date
        AND service_month <
            date_trunc('month', CURRENT_TIMESTAMP AT TIME ZONE $3)::date
        AND required_at <= $2::timestamptz
      ORDER BY employee_id::text`,
    [month, cutoff, timeZone]
  );
  return result.rows.map((row) => String(row.employee_id)).filter(Boolean);
}

async function resolveReconciliationMonth(
  db,
  { serviceMonth, cutoff = new Date() } = {}
) {
  const month = serviceMonthForDate(serviceMonth);
  if (!month) return 0;
  const result = await db.query(
    `UPDATE dtr_month_end_reconciliation_queue
        SET status = 'reconciled',
            last_attempt_at = now(),
            attempt_count = attempt_count + 1,
            last_error = NULL,
            reconciled_at = now(),
            updated_at = now()
      WHERE service_month = $1::date
        AND status = 'pending'
        AND required_at <= $2::timestamptz`,
    [month, cutoff]
  );
  return result.rowCount || 0;
}

async function recordReconciliationFailure(
  db,
  { serviceMonth, cutoff = new Date(), error } = {}
) {
  const month = serviceMonthForDate(serviceMonth);
  if (!month) return 0;
  const result = await db.query(
    `UPDATE dtr_month_end_reconciliation_queue
        SET last_attempt_at = now(),
            attempt_count = attempt_count + 1,
            last_error = LEFT($3::text, 2000),
            updated_at = now()
      WHERE service_month = $1::date
        AND status = 'pending'
        AND required_at <= $2::timestamptz`,
    [month, cutoff, String(error?.message || error || 'Unknown reconciliation error')]
  );
  return result.rowCount || 0;
}

module.exports = {
  DEFAULT_QUEUE_LIMIT,
  DEFAULT_TIME_ZONE,
  dateOnly,
  serviceMonthForDate,
  monthsInRange,
  ensureDtrMonthEndReconciliationTable,
  enqueueEmployeeRangeReconciliation,
  enqueueHolidayReconciliation,
  listPendingReconciliationEmployees,
  listPendingReconciliationMonths,
  resolveReconciliationMonth,
  recordReconciliationFailure,
};
