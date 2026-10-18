'use strict';
module.exports = function createDtrComponent({
  locatorCoverageSegments,
  mergeLocatorCoverages,
  normalizeLocatorRequestType,
  pool,
}) {
  /** Get approved leave dates in [startStr, endStr] for employees. Returns Set of "employeeId|YYYY-MM-DD". */
  async function getApprovedLeaveKeysInRange(employeeIds, startStr, endStr) {
    if (!startStr || !endStr) return new Set();
    if (!employeeIds || employeeIds.length === 0) return new Set();
    const res = await pool.query(
      `SELECT lr.employee_id, lr.start_date::text AS start_str, lr.end_date::text AS end_str
     FROM leave_requests lr
     LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
     WHERE lr.status = 'approved'
       AND COALESCE(lt.affects_dtr_normally, true) = true
       AND lr.employee_id = ANY($1::uuid[])
       AND lr.start_date <= $3::date
       AND lr.end_date >= $2::date
       AND NOT EXISTS (
         SELECT 1 FROM dtr_leave_coverage c
         WHERE c.leave_request_id = lr.id
       )`,
      [employeeIds, startStr, endStr]
    );
    const out = new Set();
    for (const r of res.rows) {
      const empId = r.employee_id;
      const s = String(r.start_str).slice(0, 10);
      const e = String(r.end_str).slice(0, 10);
      let cur = new Date(`${s}T00:00:00`);
      const end = new Date(`${e}T00:00:00`);
      while (cur <= end) {
        const dStr = cur.toISOString().slice(0, 10);
        if (dStr >= startStr && dStr <= endStr) out.add(`${empId}|${dStr}`);
        cur.setDate(cur.getDate() + 1);
      }
    }
    return out;
  }

  /** Exact server-approved leave coverage keyed by "employeeId|YYYY-MM-DD". */
  async function getApprovedLeaveCoverageInRange(employeeIds, startStr, endStr) {
    const out = new Map();
    if (!startStr || !endStr || !employeeIds || employeeIds.length === 0) {
      return out;
    }
    const result = await pool.query(
      `SELECT c.id AS leave_coverage_id,
            c.employee_id,
            c.attendance_date::text AS attendance_date,
            c.leave_request_id,
            COALESCE(NULLIF(lt.display_name, ''), NULLIF(lt.description, ''), lt.name) AS leave_type_name
     FROM dtr_leave_coverage c
     JOIN leave_requests lr ON lr.id = c.leave_request_id AND lr.status = 'approved'
     LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
     WHERE c.employee_id = ANY($1::uuid[])
       AND c.attendance_date >= $2::date
       AND c.attendance_date <= $3::date
     ORDER BY c.attendance_date`,
      [employeeIds, startStr, endStr]
    );
    for (const row of result.rows) {
      const dateStr = String(row.attendance_date).slice(0, 10);
      out.set(`${row.employee_id}|${dateStr}`, {
        ...row,
        attendance_date: dateStr,
      });
    }
    return out;
  }

  async function getApprovedLeaveCoverageForDate(employeeId, dateStr, db = pool) {
    if (!employeeId || !dateStr) return null;
    const result = await db.query(
      `SELECT active_coverage.id, active_coverage.leave_request_id
     FROM (
       SELECT c.id, c.leave_request_id, 0 AS source_priority
       FROM dtr_leave_coverage c
       JOIN leave_requests lr ON lr.id = c.leave_request_id
       WHERE c.employee_id = $1::uuid
         AND c.attendance_date = $2::date
         AND lr.status = 'approved'

       UNION ALL

       SELECT NULL::uuid AS id, d.leave_request_id, 1 AS source_priority
       FROM dtr_daily_summary d
       JOIN leave_requests lr ON lr.id = d.leave_request_id
       WHERE d.employee_id = $1::uuid
         AND d.attendance_date = $2::date
         AND lr.status = 'approved'
     ) active_coverage
     ORDER BY active_coverage.source_priority
     LIMIT 1`,
      [employeeId, dateStr]
    );
    return result.rows[0] || null;
  }

  /**
   * Get approved locator slips in [startStr, endStr] for employees.
   * Returns Map key "employeeId|YYYY-MM-DD" -> metadata object.
   */
  async function getApprovedLocatorByDateInRange(employeeIds, startStr, endStr) {
    const out = new Map();
    if (!startStr || !endStr) return out;
    if (!employeeIds || employeeIds.length === 0) return out;
    const res = await pool.query(
      `SELECT ls.id, ls.employee_id, ls.slip_date::text AS slip_date_str,
            ls.am_in, ls.am_out, ls.pm_in, ls.pm_out,
            ls.request_type, ls.office, ls.reason,
            COALESCE(ls.request_type_label_snapshot, lrt.label) AS request_type_label,
            COALESCE(ls.request_type_dtr_slot_label_snapshot, lrt.dtr_slot_label) AS dtr_slot_label,
            COALESCE(ls.request_type_dtr_print_label_snapshot, lrt.dtr_print_label) AS dtr_print_label,
            COALESCE(ls.request_type_coverage_mode_snapshot, lrt.coverage_mode) AS coverage_mode
     FROM locator_slips ls
     LEFT JOIN locator_request_types lrt ON lrt.code = ls.request_type
     WHERE ls.status = 'approved'
       AND ls.employee_id = ANY($1::uuid[])
       AND ls.slip_date >= $2::date
       AND ls.slip_date <= $3::date
     ORDER BY ls.updated_at DESC, ls.created_at DESC`,
      [employeeIds, startStr, endStr]
    );
    for (const r of res.rows) {
      const dateStr = String(r.slip_date_str).slice(0, 10);
      const key = `${r.employee_id}|${dateStr}`;
      const existing = out.get(key);
      const coverage = mergeLocatorCoverages([existing?.coverage, r]);
      if (existing) {
        existing.coverage = coverage;
        existing.segments = locatorCoverageSegments(coverage).map((slot) => slot.toUpperCase());
        continue;
      }
      out.set(key, {
        id: r.id,
        request_type: normalizeLocatorRequestType(r.request_type),
        request_type_label: r.request_type_label || null,
        dtr_slot_label: r.dtr_slot_label || null,
        dtr_print_label: r.dtr_print_label || null,
        coverage_mode: r.coverage_mode || null,
        office: r.office || null,
        reason: r.reason || null,
        coverage,
        segments: locatorCoverageSegments(coverage).map((slot) => slot.toUpperCase()),
      });
    }
    return out;
  }
  return {
    getApprovedLeaveKeysInRange,
    getApprovedLeaveCoverageInRange,
    getApprovedLeaveCoverageForDate,
    getApprovedLocatorByDateInRange,
  };
};
