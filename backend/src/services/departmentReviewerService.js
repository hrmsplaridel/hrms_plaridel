'use strict';

const { todayInHrmsTimezone } = require('../utils/dateRangeParser');

function cleanDate(value) {
  const text = String(value || '').trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) {
    throw new TypeError('effectiveDate must use YYYY-MM-DD');
  }
  return text;
}

async function getEmployeeDepartmentForDate(client, employeeUserId, effectiveDate) {
  const date = cleanDate(effectiveDate);
  const result = await client.query(
    `SELECT a.department_id, d.name AS department_name
     FROM assignments a
     LEFT JOIN departments d ON d.id = a.department_id
     WHERE a.employee_id = $1::uuid
       AND a.department_id IS NOT NULL
       AND a.effective_from <= $2::date
       AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
     ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC
     LIMIT 1`,
    [employeeUserId, date]
  );
  if (!result.rows[0]) return null;
  return {
    departmentId: result.rows[0].department_id,
    departmentName: result.rows[0].department_name || null,
  };
}

async function resolveDepartmentReviewers(
  client,
  { departmentId, effectiveDate = todayInHrmsTimezone(), excludeUserId = null }
) {
  const date = cleanDate(effectiveDate);
  if (!departmentId) {
    return { departmentId: null, effectiveDate: date, primary: null, backups: [], reviewers: [] };
  }

  const primaryResult = await client.query(
    `SELECT u.id AS reviewer_id,
            COALESCE(NULLIF(btrim(u.full_name), ''), u.email, u.id::text) AS reviewer_name,
            head_period.id AS designation_id, head_period.position_title_snapshot AS position_title,
            head_period.effective_from::text AS effective_from, head_period.effective_to::text AS effective_to
     FROM primary_reviewer_designations head_period
     JOIN users u ON u.id = head_period.employee_id
     WHERE head_period.scope_key = 'department:' || $1::uuid::text
       AND head_period.department_id = $1::uuid
       AND head_period.is_active = true
       AND head_period.effective_from <= $2::date
       AND (head_period.effective_to IS NULL OR head_period.effective_to >= $2::date)
       AND u.is_active = true
       AND ($3::uuid IS NULL OR u.id <> $3::uuid)
     LIMIT 1`,
    [departmentId, date, excludeUserId]
  );

  const backupResult = await client.query(
    `SELECT b.employee_id AS reviewer_id,
            COALESCE(NULLIF(btrim(u.full_name), ''), u.email, u.id::text) AS reviewer_name,
            b.backup_rank
     FROM department_reviewer_backups b
     JOIN users u ON u.id = b.employee_id
     WHERE b.department_id = $1::uuid
       AND b.is_active = true
       AND b.effective_from <= $2::date
       AND (b.effective_to IS NULL OR b.effective_to >= $2::date)
       AND (u.is_active IS NULL OR u.is_active = true)
       AND ($3::uuid IS NULL OR u.id <> $3::uuid)
     ORDER BY b.backup_rank, b.effective_from DESC, b.created_at, b.id`,
    [departmentId, date, excludeUserId]
  );

  const primaryRow = primaryResult.rows[0] || null;
  const primary = primaryRow
    ? {
        reviewerId: primaryRow.reviewer_id,
        reviewerName: primaryRow.reviewer_name,
        position_title: primaryRow.position_title || null,
        designation_id: primaryRow.designation_id || null,
        effective_from: primaryRow.effective_from || null,
        effective_to: primaryRow.effective_to || null,
        reviewerRole: 'primary',
        backupRank: null,
      }
    : null;
  const seen = new Set(primary ? [String(primary.reviewerId)] : []);
  const backups = [];
  for (const row of backupResult.rows || []) {
    const id = String(row.reviewer_id);
    if (seen.has(id)) continue;
    seen.add(id);
    backups.push({
      reviewerId: row.reviewer_id,
      reviewerName: row.reviewer_name,
      reviewerRole: 'backup',
      backupRank: Number(row.backup_rank),
    });
  }

  return {
    departmentId,
    effectiveDate: date,
    primary,
    backups,
    reviewers: [...(primary ? [primary] : []), ...backups],
  };
}

/**
 * Per active department: who reviews documents routed to "the submitter's
 * Department Head" on [effectiveDate].
 *
 * status:
 *  - no_staff    : nobody is assigned, nothing can be blocked
 *  - no_reviewer : staff exist but no Head and no backup, so staff submissions fail
 *  - head_only   : a Head exists but no backup, so the Head's own submissions fail
 *  - ready       : a Head or backup can review staff, and someone else can review the Head
 */
async function listDepartmentReviewerReadiness(
  client,
  { effectiveDate = todayInHrmsTimezone() } = {}
) {
  const date = cleanDate(effectiveDate);
  const departments = await client.query(
    `SELECT d.id, d.name,
            COUNT(DISTINCT u.id)::int AS staff_count
     FROM departments d
     LEFT JOIN assignments a
       ON a.department_id = d.id
      AND a.is_active = true
      AND a.effective_from <= $1::date
      AND (a.effective_to IS NULL OR a.effective_to >= $1::date)
     LEFT JOIN users u
       ON u.id = a.employee_id
      AND (u.is_active IS NULL OR u.is_active = true)
     WHERE d.is_active IS NULL OR d.is_active = true
     GROUP BY d.id, d.name
     ORDER BY d.name`,
    [date]
  );

  const rows = [];
  for (const department of departments.rows) {
    const resolved = await resolveDepartmentReviewers(client, {
      departmentId: department.id,
      effectiveDate: date,
    });
    const staffCount = Number(department.staff_count) || 0;
    let status = 'ready';
    if (staffCount === 0) status = 'no_staff';
    else if (resolved.reviewers.length === 0) status = 'no_reviewer';
    else if (resolved.primary && resolved.backups.length === 0) status = 'head_only';
    rows.push({
      department_id: department.id,
      department_name: department.name,
      staff_count: staffCount,
      primary: resolved.primary,
      backup_count: resolved.backups.length,
      status,
    });
  }
  return { effective_date: date, departments: rows };
}

async function getEmployeeReviewSnapshot(
  client,
  { employeeUserId, effectiveDate = todayInHrmsTimezone() }
) {
  const department = await getEmployeeDepartmentForDate(
    client,
    employeeUserId,
    effectiveDate
  );
  if (!department) return null;
  const resolved = await resolveDepartmentReviewers(client, {
    departmentId: department.departmentId,
    effectiveDate,
    excludeUserId: employeeUserId,
  });
  const routingPrimary = resolved.primary || resolved.backups[0] || null;
  return {
    departmentId: department.departmentId,
    departmentName: department.departmentName,
    departmentHeadUserId: routingPrimary?.reviewerId || null,
    reviewerUserIds: resolved.reviewers.map((reviewer) => reviewer.reviewerId),
    reviewers: resolved.reviewers,
  };
}

async function replaceRequestReviewerSnapshot(
  client,
  { requestType, requestId, departmentId, reviewers }
) {
  const config = requestType === 'leave'
    ? {
        table: 'leave_request_department_reviewers',
        requestColumn: 'leave_request_id',
      }
    : requestType === 'locator'
      ? {
          table: 'locator_slip_department_reviewers',
          requestColumn: 'locator_slip_id',
        }
      : null;
  if (!config) throw new TypeError('requestType must be leave or locator');

  await client.query(
    `DELETE FROM ${config.table} WHERE ${config.requestColumn} = $1::uuid`,
    [requestId]
  );
  for (const reviewer of reviewers || []) {
    await client.query(
      `INSERT INTO ${config.table} (
         ${config.requestColumn}, department_id, reviewer_id,
         reviewer_name_snapshot, reviewer_role, backup_rank
       ) VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $5, $6)`,
      [
        requestId,
        departmentId || null,
        reviewer.reviewerId,
        reviewer.reviewerName,
        reviewer.reviewerRole,
        reviewer.backupRank,
      ]
    );
  }
}

module.exports = {
  getEmployeeDepartmentForDate,
  getEmployeeReviewSnapshot,
  listDepartmentReviewerReadiness,
  replaceRequestReviewerSnapshot,
  resolveDepartmentReviewers,
};
