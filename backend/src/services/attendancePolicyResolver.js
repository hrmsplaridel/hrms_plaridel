function normalizeAttendancePolicy(row) {
  return {
    id: row?.id || null,
    workHoursPerDay: row?.work_hours_per_day != null ? parseFloat(row.work_hours_per_day) : 8,
    useEquivalentDayConversion: row?.use_equivalent_day_conversion ?? true,
    deductLate: row?.deduct_late ?? true,
    convertLateToEquivalentDay: row?.convert_late_to_equivalent_day ?? false,
    deductUndertime: row?.deduct_undertime ?? true,
    convertUndertimeToEquivalentDay: row?.convert_undertime_to_equivalent_day ?? false,
    absentEqualsFullDayDeduction: row?.absent_equals_full_day_deduction ?? true,
    combineLateAndUndertime: row?.combine_late_and_undertime ?? false,
    deductionMultiplier: row?.deduction_multiplier != null ? parseFloat(row.deduction_multiplier) : 1,
  };
}

function round3(value) {
  return Math.round((Number(value) || 0) * 1000) / 1000;
}

function attendancePolicyPayload(policy) {
  const normalized = policy || normalizeAttendancePolicy(null);
  return {
    id: normalized.id || null,
    work_hours_per_day: normalized.workHoursPerDay,
    use_equivalent_day_conversion: normalized.useEquivalentDayConversion,
    deduct_late: normalized.deductLate,
    convert_late_to_equivalent_day: normalized.convertLateToEquivalentDay,
    deduct_undertime: normalized.deductUndertime,
    convert_undertime_to_equivalent_day: normalized.convertUndertimeToEquivalentDay,
    absent_equals_full_day_deduction: normalized.absentEqualsFullDayDeduction,
    combine_late_and_undertime: normalized.combineLateAndUndertime,
    deduction_multiplier: normalized.deductionMultiplier,
  };
}

/**
 * Build the official report contribution from already policy-processed DTR
 * minutes. This mirrors month-end treatment without applying the multiplier a
 * second time.
 */
function calculateAttendanceReportDeduction({
  policy,
  lateMinutes,
  undertimeMinutes,
  status,
  expectedWorkMinutes,
  holidayCoverage,
}) {
  const normalized = policy || normalizeAttendancePolicy(null);
  const normalizedStatus = String(status || '').trim().toLowerCase();
  const normalizedCoverage = String(holidayCoverage || '').trim().toLowerCase();
  const isWholeDayHoliday =
    normalizedStatus === 'holiday' &&
    (!normalizedCoverage || normalizedCoverage === 'whole_day');
  const excluded = new Set(['on_leave', 'rest_day', 'on_field']);
  if (
    !normalized.useEquivalentDayConversion ||
    excluded.has(normalizedStatus) ||
    isWholeDayHoliday
  ) {
    return {
      late_minutes: 0,
      undertime_minutes: 0,
      absence_minutes: 0,
      total_minutes: 0,
      equivalent_day: 0,
    };
  }

  let appliedLate = normalized.deductLate
    ? Math.max(0, parseInt(lateMinutes, 10) || 0)
    : 0;
  let appliedUndertime = normalized.deductUndertime
    ? Math.max(0, parseInt(undertimeMinutes, 10) || 0)
    : 0;
  let appliedAbsence = 0;

  if (
    normalizedStatus === 'absent' &&
    normalized.deductUndertime &&
    normalized.absentEqualsFullDayDeduction
  ) {
    const expected = Math.max(0, Number(expectedWorkMinutes) || 0);
    appliedAbsence = appliedUndertime > 0
      ? appliedUndertime
      : Math.round(expected * Math.max(0, normalized.deductionMultiplier || 1));
    appliedUndertime = 0;
  }

  const total = appliedLate + appliedUndertime + appliedAbsence;
  const workMinutes = Math.max(
    1,
    Math.round(
      (Number.isFinite(normalized.workHoursPerDay) && normalized.workHoursPerDay > 0
        ? normalized.workHoursPerDay
        : 8) * 60
    )
  );

  return {
    late_minutes: appliedLate,
    undertime_minutes: appliedUndertime,
    absence_minutes: appliedAbsence,
    total_minutes: total,
    equivalent_day: total > 0 ? round3(total / workMinutes) : 0,
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
  const late = policy?.deductLate ? Math.max(0, Number(rawLateMinutes) || 0) : 0;
  const undertime = policy?.deductUndertime
    ? Math.max(0, Number(rawUndertimeMinutes) || 0)
    : 0;

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

  const policyColumns = `p.id, p.work_hours_per_day, p.use_equivalent_day_conversion,
    p.deduct_late,
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
  attendancePolicyPayload,
  calculateAttendanceReportDeduction,
  calculateAttendancePolicyPenalties,
  loadAttendancePolicyContext,
  normalizeAttendancePolicy,
  resolveAttendancePolicy,
};
