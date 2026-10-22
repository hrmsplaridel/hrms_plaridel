'use strict';
module.exports = function createDtrComponent({
  calculateAttendancePolicyPenalties,
  getAttendancePolicyCache,
  normalizeAttendancePolicy,
  pool,
  setAttendancePolicyCache,
}) {
  function _normalizePolicy(row) {
    return normalizeAttendancePolicy(row);
  }

  async function getActiveDefaultAttendancePolicy() {
    const cached = getAttendancePolicyCache('dtr', 'default');
    if (cached.found) return cached.value;
    const result = await pool.query(
      `SELECT id, work_hours_per_day, use_equivalent_day_conversion, deduct_late,
            convert_late_to_equivalent_day, deduct_undertime, convert_undertime_to_equivalent_day,
            absent_equals_full_day_deduction, combine_late_and_undertime, deduction_multiplier
     FROM attendance_policies
     WHERE is_default = true
       AND (is_active IS NULL OR is_active = true)
     LIMIT 1`
    );
    return setAttendancePolicyCache('dtr', 'default', _normalizePolicy(result.rows[0]), {
      isDefault: true,
    });
  }

  async function getAttendancePolicyForEmployeeDate(employeeId, dateStr) {
    if (!employeeId || !dateStr) return getActiveDefaultAttendancePolicy();
    const cacheKey = `${employeeId}|${dateStr}`;
    const cached = getAttendancePolicyCache('dtr', cacheKey);
    if (cached.found) return cached.value;

    const result = await pool.query(
      `WITH eff AS (
       SELECT a.department_id, a.shift_id
       FROM assignments a
       WHERE a.employee_id = $1::uuid
         AND a.effective_from <= $2::date
         AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
       ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC
       LIMIT 1
     )
     SELECT p.id, p.work_hours_per_day, p.use_equivalent_day_conversion, p.deduct_late,
            p.convert_late_to_equivalent_day, p.deduct_undertime, p.convert_undertime_to_equivalent_day,
            p.absent_equals_full_day_deduction, p.combine_late_and_undertime, p.deduction_multiplier
     FROM policy_assignments pa
     JOIN attendance_policies p ON p.id = pa.attendance_policy_id
     LEFT JOIN eff e ON true
     WHERE (pa.is_active IS NULL OR pa.is_active = true)
       AND pa.effective_from <= $2::date
       AND (pa.effective_to IS NULL OR pa.effective_to >= $2::date)
       AND (
         pa.employee_id = $1::uuid
         OR (pa.department_id IS NOT NULL AND pa.department_id = e.department_id)
         OR (pa.shift_id IS NOT NULL AND pa.shift_id = e.shift_id)
       )
     ORDER BY CASE
                WHEN pa.employee_id = $1::uuid THEN 1
                WHEN pa.department_id IS NOT NULL AND pa.department_id = e.department_id THEN 2
                WHEN pa.shift_id IS NOT NULL AND pa.shift_id = e.shift_id THEN 3
                ELSE 4
              END,
              pa.effective_from DESC,
              pa.created_at DESC
     LIMIT 1`,
      [employeeId, dateStr]
    );
    const resolved = result.rows[0]
      ? _normalizePolicy(result.rows[0])
      : await getActiveDefaultAttendancePolicy();
    return setAttendancePolicyCache('dtr', cacheKey, resolved, {
      employeeId,
      date: dateStr,
    });
  }

  async function applyAttendancePolicyPenalties(
    employeeId,
    dateStr,
    rawLateMinutes,
    rawUndertimeMinutes
  ) {
    const policy = await getAttendancePolicyForEmployeeDate(employeeId, dateStr);
    return {
      ...calculateAttendancePolicyPenalties(policy, rawLateMinutes, rawUndertimeMinutes),
      policy,
    };
  }
  return {
    _normalizePolicy,
    getActiveDefaultAttendancePolicy,
    getAttendancePolicyForEmployeeDate,
    applyAttendancePolicyPenalties,
  };
};
