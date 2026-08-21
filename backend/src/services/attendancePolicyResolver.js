function normalizeAttendancePolicy(row) {
  return {
    id: row?.id || null,
    workHoursPerDay: row?.work_hours_per_day != null ? parseFloat(row.work_hours_per_day) : 8,
    deductLate: row?.deduct_late ?? true,
    convertLateToEquivalentDay: row?.convert_late_to_equivalent_day ?? false,
    deductUndertime: row?.deduct_undertime ?? true,
    convertUndertimeToEquivalentDay: row?.convert_undertime_to_equivalent_day ?? false,
    absentEqualsFullDayDeduction: row?.absent_equals_full_day_deduction ?? true,
    combineLateAndUndertime: row?.combine_late_and_undertime ?? false,
    deductionMultiplier: row?.deduction_multiplier != null ? parseFloat(row.deduction_multiplier) : 1,
  };
}

function applyPolicyConversion(minutes, convertToEquivalentDay, workHoursPerDay, multiplier) {
  if (!Number.isFinite(minutes) || minutes <= 0) return 0;
  const appliedMultiplier = Number.isFinite(multiplier) && multiplier > 0 ? multiplier : 1;
  if (!convertToEquivalentDay) return Math.round(minutes * appliedMultiplier);
  const workMinutes = Math.max(
    1,
    Math.round((Number.isFinite(workHoursPerDay) ? workHoursPerDay : 8) * 60)
  );
  return Math.round((minutes / workMinutes) * appliedMultiplier * workMinutes);
}

function calculateAttendancePolicyPenalties(policy, rawLateMinutes, rawUndertimeMinutes) {
  let late = policy?.deductLate ? Math.max(0, Number(rawLateMinutes) || 0) : 0;
  let undertime = policy?.deductUndertime
    ? Math.max(0, Number(rawUndertimeMinutes) || 0)
    : 0;

  if (policy?.combineLateAndUndertime) {
    undertime += late;
    late = 0;
  }

  return {
    lateMinutes: applyPolicyConversion(
      late,
      policy?.convertLateToEquivalentDay,
      policy?.workHoursPerDay,
      policy?.deductionMultiplier
    ),
    undertimeMinutes: applyPolicyConversion(
      undertime,
      policy?.convertUndertimeToEquivalentDay,
      policy?.workHoursPerDay,
      policy?.deductionMultiplier
    ),
  };
}

function normalizeDate(value) {
  return value == null ? null : String(value).slice(0, 10);
}

function comparePolicyAssignments(left, right) {
  const effectiveCompare = String(right.effectiveFrom || '').localeCompare(
    String(left.effectiveFrom || '')
  );
  if (effectiveCompare !== 0) return effectiveCompare;
  const createdCompare = String(right.createdAt || '').localeCompare(String(left.createdAt || ''));
  if (createdCompare !== 0) return createdCompare;
  return String(right.assignmentId || '').localeCompare(String(left.assignmentId || ''));
}

function addTargetPolicy(targetMap, targetId, policyAssignment) {
  if (!targetId) return;
  const key = String(targetId);
  const existing = targetMap.get(key) || [];
  existing.push(policyAssignment);
  targetMap.set(key, existing);
}

function firstEffectivePolicy(items, dateStr) {
  if (!items) return null;
  return items.find(
    (item) =>
      item.effectiveFrom <= dateStr && (!item.effectiveTo || item.effectiveTo >= dateStr)
  ) || null;
}

async function loadAttendancePolicyContext(
  db,
  employeeIds,
  startDate,
  endDate,
  assignmentsByEmployee
) {
  const ids = Array.from(new Set((employeeIds || []).filter(Boolean).map(String)));
  const departmentIds = new Set();
  const shiftIds = new Set();
  for (const assignments of assignmentsByEmployee?.values?.() || []) {
    for (const assignment of assignments || []) {
      if (assignment.departmentId) departmentIds.add(String(assignment.departmentId));
      if (assignment.shiftId) shiftIds.add(String(assignment.shiftId));
    }
  }

  const policyColumns = `p.id, p.work_hours_per_day, p.deduct_late,
    p.convert_late_to_equivalent_day,
    p.deduct_undertime, p.convert_undertime_to_equivalent_day,
    p.absent_equals_full_day_deduction, p.combine_late_and_undertime,
    p.deduction_multiplier`;

  const [defaultResult, assignedResult] = await Promise.all([
    db.query(
      `SELECT ${policyColumns}
       FROM attendance_policies p
       WHERE (p.is_active IS NULL OR p.is_active = true)
       ORDER BY p.is_default DESC, p.updated_at DESC, p.created_at DESC
       LIMIT 1`
    ),
    ids.length === 0
      ? Promise.resolve({ rows: [] })
      : db.query(
          `SELECT pa.id AS policy_assignment_id,
                  pa.employee_id, pa.department_id, pa.shift_id,
                  pa.effective_from::text AS effective_from,
                  pa.effective_to::text AS effective_to,
                  pa.created_at,
                  ${policyColumns}
           FROM policy_assignments pa
           JOIN attendance_policies p ON p.id = pa.attendance_policy_id
           WHERE (pa.is_active IS NULL OR pa.is_active = true)
             AND (p.is_active IS NULL OR p.is_active = true)
             AND pa.effective_from <= $5::date
             AND (pa.effective_to IS NULL OR pa.effective_to >= $4::date)
             AND (
               pa.employee_id = ANY($1::uuid[])
               OR pa.department_id = ANY($2::uuid[])
               OR pa.shift_id = ANY($3::uuid[])
             )
           ORDER BY pa.effective_from DESC, pa.created_at DESC, pa.id DESC`,
          [ids, Array.from(departmentIds), Array.from(shiftIds), startDate, endDate]
        ),
  ]);

  const context = {
    defaultPolicy: normalizeAttendancePolicy(defaultResult.rows[0]),
    byEmployee: new Map(),
    byDepartment: new Map(),
    byShift: new Map(),
  };

  for (const row of assignedResult.rows) {
    const item = {
      assignmentId: row.policy_assignment_id,
      effectiveFrom: normalizeDate(row.effective_from),
      effectiveTo: normalizeDate(row.effective_to),
      createdAt: row.created_at,
      policy: normalizeAttendancePolicy(row),
    };
    addTargetPolicy(context.byEmployee, row.employee_id, item);
    addTargetPolicy(context.byDepartment, row.department_id, item);
    addTargetPolicy(context.byShift, row.shift_id, item);
  }

  for (const targetMap of [context.byEmployee, context.byDepartment, context.byShift]) {
    for (const policies of targetMap.values()) policies.sort(comparePolicyAssignments);
  }

  return context;
}

function resolveAttendancePolicy(context, employeeId, dateStr, assignment) {
  const employeePolicy = firstEffectivePolicy(
    context?.byEmployee?.get(String(employeeId)),
    dateStr
  );
  if (employeePolicy) return employeePolicy.policy;

  const departmentPolicy = assignment?.departmentId
    ? firstEffectivePolicy(context?.byDepartment?.get(String(assignment.departmentId)), dateStr)
    : null;
  if (departmentPolicy) return departmentPolicy.policy;

  const shiftPolicy = assignment?.shiftId
    ? firstEffectivePolicy(context?.byShift?.get(String(assignment.shiftId)), dateStr)
    : null;
  return shiftPolicy?.policy || context?.defaultPolicy || normalizeAttendancePolicy(null);
}

module.exports = {
  calculateAttendancePolicyPenalties,
  loadAttendancePolicyContext,
  normalizeAttendancePolicy,
  resolveAttendancePolicy,
};
