'use strict';

const { addDays, todayInHrmsTimezone } = require('../utils/dateRangeParser');
const { PositionLifecycleError } = require('./positionLifecycle');

function cleanDate(value, label, { required = false } = {}) {
  if (value === null || value === undefined || value === '') {
    if (required) {
      throw new PositionLifecycleError(`${label} is required`, 400);
    }
    return null;
  }
  const text = String(value).trim();
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!match) {
    throw new PositionLifecycleError(`${label} must use YYYY-MM-DD`, 400);
  }
  const parsed = new Date(Date.UTC(
    Number(match[1]),
    Number(match[2]) - 1,
    Number(match[3])
  ));
  if (
    parsed.getUTCFullYear() !== Number(match[1]) ||
    parsed.getUTCMonth() !== Number(match[2]) - 1 ||
    parsed.getUTCDate() !== Number(match[3])
  ) {
    throw new PositionLifecycleError(`${label} is invalid`, 400);
  }
  return text;
}

function assertRange(from, to) {
  if (to && to < from) {
    throw new PositionLifecycleError(
      'Department Head effective_to must be on or after effective_from',
      400
    );
  }
}

async function refreshLegacyDepartmentHeadFlag(db, positionId, effectiveDate) {
  await db.query(
    `UPDATE positions p
        SET is_department_head = EXISTS (
              SELECT 1
              FROM position_department_head_periods period
              WHERE period.position_id = p.id
                AND period.is_active = true
                AND (period.effective_to IS NULL OR period.effective_to >= $2::date)
            ),
            updated_at = now()
      WHERE p.id = $1::uuid`,
    [positionId, effectiveDate]
  );
}

async function getManagedDepartmentHeadPeriod(
  db,
  positionId,
  effectiveDate = todayInHrmsTimezone()
) {
  const result = await db.query(
    `SELECT id, position_id, department_id,
            effective_from::text AS effective_from,
            effective_to::text AS effective_to, is_active
       FROM position_department_head_periods
      WHERE position_id = $1::uuid
        AND is_active = true
        AND (effective_to IS NULL OR effective_to >= $2::date)
      ORDER BY (effective_from <= $2::date) DESC, effective_from
      LIMIT 1`,
    [positionId, effectiveDate]
  );
  return result.rows[0] || null;
}

async function saveDepartmentHeadPeriod(
  db,
  {
    actorId,
    positionId,
    departmentId,
    periodId = null,
    effectiveFrom = null,
    effectiveTo = null,
  }
) {
  if (!departmentId) {
    throw new PositionLifecycleError(
      'An official Department Head position must belong to a department',
      400
    );
  }
  const from = cleanDate(
    effectiveFrom || todayInHrmsTimezone(),
    'Department Head effective_from',
    { required: true }
  );
  const to = cleanDate(effectiveTo, 'Department Head effective_to');
  assertRange(from, to);

  await db.query(
    'SELECT id FROM departments WHERE id = $1::uuid FOR UPDATE',
    [departmentId]
  );

  let result;
  if (periodId) {
    result = await db.query(
      `UPDATE position_department_head_periods
          SET department_id = $3::uuid,
              effective_from = $4::date,
              effective_to = $5::date,
              is_active = true,
              updated_at = now()
        WHERE id = $1::uuid
          AND position_id = $2::uuid
      RETURNING id, position_id, department_id,
                effective_from::text AS effective_from,
                effective_to::text AS effective_to, is_active`,
      [periodId, positionId, departmentId, from, to]
    );
    if (result.rowCount === 0) {
      throw new PositionLifecycleError(
        'Department Head designation period was not found',
        404
      );
    }
  } else {
    result = await db.query(
      `INSERT INTO position_department_head_periods (
         position_id, department_id, effective_from, effective_to,
         is_active, created_by
       ) VALUES ($1::uuid, $2::uuid, $3::date, $4::date, true, $5::uuid)
       RETURNING id, position_id, department_id,
                 effective_from::text AS effective_from,
                 effective_to::text AS effective_to, is_active`,
      [positionId, departmentId, from, to, actorId || null]
    );
  }

  await refreshLegacyDepartmentHeadFlag(db, positionId, todayInHrmsTimezone());
  return result.rows[0];
}

async function endDepartmentHeadPeriod(
  db,
  { positionId, periodId = null, effectiveDate = todayInHrmsTimezone() }
) {
  const date = cleanDate(effectiveDate, 'Department Head end date', {
    required: true,
  });
  const result = await db.query(
    `SELECT id, effective_from::text AS effective_from
       FROM position_department_head_periods
      WHERE position_id = $1::uuid
        AND is_active = true
        AND ($2::uuid IS NULL OR id = $2::uuid)
        AND (effective_to IS NULL OR effective_to >= $3::date)
      ORDER BY (effective_from <= $3::date) DESC, effective_from
      LIMIT 1
      FOR UPDATE`,
    [positionId, periodId, date]
  );
  const period = result.rows[0];
  if (period) {
    if (period.effective_from >= date) {
      await db.query(
        `UPDATE position_department_head_periods
            SET is_active = false, updated_at = now()
          WHERE id = $1::uuid`,
        [period.id]
      );
    } else {
      await db.query(
        `UPDATE position_department_head_periods
            SET effective_to = $2::date, updated_at = now()
          WHERE id = $1::uuid`,
        [period.id, addDays(date, -1)]
      );
    }
  }
  await refreshLegacyDepartmentHeadFlag(db, positionId, date);
  return period || null;
}

module.exports = {
  cleanDate,
  endDepartmentHeadPeriod,
  getManagedDepartmentHeadPeriod,
  refreshLegacyDepartmentHeadFlag,
  saveDepartmentHeadPeriod,
};
