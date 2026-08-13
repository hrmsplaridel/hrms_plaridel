'use strict';

/**
 * Month-end Vacation Leave deductions derived from finalized DTR values.
 *
 * DTR late/undertime minutes are converted to day equivalents on the backend,
 * then posted as a separate used-days movement. A monthly posting row keeps
 * retries idempotent and lets a later DTR correction post only the difference.
 */

const {
  expandNonRecurringToWindow,
  expandRecurringToWindow,
} = require('./holidayRangeUtils');
const {
  getExpectedWorkMinutes,
  getShiftType,
} = require('./shiftAttendance');
const {
  expectedLocatorSlotsForShift,
  locatorCoversExpectedShiftSlots,
} = require('./locatorCoverage');
const {
  initLeaveBalanceLedger,
  insertLeaveBalanceLedger,
} = require('./leaveBalanceLedger');
const {
  monthStartInTimeZone,
  parseTargetMonth,
  round3,
} = require('./leaveMonthlyAccrual');

const VACATION_LEAVE = 'vacationLeave';
const DEFAULT_TIME_ZONE = 'Asia/Manila';
const NOON_MINUTES = 12 * 60;

function addMonths(date, count) {
  const result = new Date(date.getTime());
  result.setMonth(result.getMonth() + count);
  return result;
}

function monthKey(date) {
  return date.getFullYear() * 12 + date.getMonth();
}

function endOfMonth(date) {
  return new Date(date.getFullYear(), date.getMonth() + 1, 0);
}

function toDateStr(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function dateOnly(value) {
  if (value == null) return null;
  return String(value).slice(0, 10);
}

function datesInRange(startStr, endStr) {
  const result = [];
  const current = new Date(`${startStr}T12:00:00`);
  const end = new Date(`${endStr}T12:00:00`);
  while (current <= end) {
    result.push(toDateStr(current));
    current.setDate(current.getDate() + 1);
  }
  return result;
}

function isoWeekday(dateStr) {
  const day = new Date(`${dateStr}T12:00:00`).getDay();
  return day === 0 ? 7 : day;
}

function timeToMinutes(value) {
  if (value == null) return null;
  const match = String(value).trim().match(/^(\d{1,2}):(\d{2})/);
  if (!match) return null;
  const hours = parseInt(match[1], 10);
  const minutes = parseInt(match[2], 10);
  if (!Number.isFinite(hours) || !Number.isFinite(minutes)) return null;
  return hours * 60 + minutes;
}

function normalizePolicy(row) {
  return {
    id: row?.id || row?.attendance_policy_id || null,
    workHoursPerDay:
      row?.work_hours_per_day != null ? parseFloat(row.work_hours_per_day) : 8,
    useEquivalentDayConversion: row?.use_equivalent_day_conversion ?? true,
    deductLate: row?.deduct_late ?? false,
    deductUndertime: row?.deduct_undertime ?? true,
    absentEqualsFullDayDeduction: row?.absent_equals_full_day_deduction ?? true,
    deductionMultiplier:
      row?.deduction_multiplier != null ? parseFloat(row.deduction_multiplier) : 1,
  };
}

function policyWorkMinutes(policy) {
  const hours =
    Number.isFinite(policy?.workHoursPerDay) && policy.workHoursPerDay > 0
      ? policy.workHoursPerDay
      : 8;
  return Math.max(1, Math.round(hours * 60));
}

/**
 * Convert already policy-filtered minutes to a leave day equivalent.
 * Stored DTR minutes already include the configured deduction multiplier.
 */
function equivalentDaysFromMinutes(minutes, workHoursPerDay = 8) {
  const total = Number(minutes);
  const hours = Number(workHoursPerDay);
  if (!Number.isFinite(total) || total <= 0) return 0;
  const divisor = Number.isFinite(hours) && hours > 0 ? hours * 60 : 8 * 60;
  return round3(total / divisor);
}

function assignmentForDate(assignmentsByEmployee, employeeId, dateStr) {
  const rows = assignmentsByEmployee.get(String(employeeId)) || [];
  return (
    rows.find(
      (row) =>
        row.effectiveFrom <= dateStr &&
        (!row.effectiveTo || row.effectiveTo >= dateStr)
    ) || null
  );
}

function policyForDate({
  policyAssignments,
  defaultPolicy,
  employeeId,
  dateStr,
  assignment,
}) {
  const matches = policyAssignments
    .filter((row) => {
      if (row.effectiveFrom > dateStr) return false;
      if (row.effectiveTo && row.effectiveTo < dateStr) return false;
      return (
        row.employeeId === String(employeeId) ||
        (row.departmentId &&
          assignment?.departmentId &&
          row.departmentId === assignment.departmentId) ||
        (row.shiftId && assignment?.shiftId && row.shiftId === assignment.shiftId)
      );
    })
    .map((row) => ({
      row,
      rank:
        row.employeeId === String(employeeId)
          ? 1
          : row.departmentId === assignment?.departmentId
            ? 2
            : 3,
    }))
    .sort((left, right) => {
      if (left.rank !== right.rank) return left.rank - right.rank;
      const effective = right.row.effectiveFrom.localeCompare(left.row.effectiveFrom);
      if (effective !== 0) return effective;
      return right.row.createdAt.localeCompare(left.row.createdAt);
    });
  return matches.length > 0 ? matches[0].row.policy : defaultPolicy;
}

function expectedMinutesForCoverage(assignment, coverage) {
  const full = getExpectedWorkMinutes(assignment);
  if (!coverage || coverage === 'none') return full;
  if (coverage === 'whole_day') return 0;

  const shiftType = getShiftType(assignment);
  if (coverage === 'am_only') {
    if (shiftType === 'am_only') return 0;
    if (shiftType === 'pm_only' || shiftType === 'single_session') return full;
    const pmStart = assignment.breakEndMinutes ?? NOON_MINUTES;
    return Math.max(0, (assignment.endMinutes ?? pmStart) - pmStart);
  }
  if (coverage === 'pm_only') {
    if (shiftType === 'pm_only') return 0;
    if (shiftType === 'am_only' || shiftType === 'single_session') return full;
    return Math.max(0, NOON_MINUTES - (assignment.startMinutes ?? NOON_MINUTES));
  }
  return full;
}

async function ensureLeaveAttendanceDeductionTable(db) {
  await db.query('CREATE EXTENSION IF NOT EXISTS "uuid-ossp";');
  await db.query(`
    CREATE TABLE IF NOT EXISTS leave_attendance_deductions (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      service_month DATE NOT NULL,
      leave_type TEXT NOT NULL DEFAULT 'vacationLeave',
      late_minutes INT NOT NULL DEFAULT 0 CHECK (late_minutes >= 0),
      undertime_minutes INT NOT NULL DEFAULT 0 CHECK (undertime_minutes >= 0),
      absence_minutes INT NOT NULL DEFAULT 0 CHECK (absence_minutes >= 0),
      computed_days NUMERIC(10,3) NOT NULL DEFAULT 0 CHECK (computed_days >= 0),
      deducted_days NUMERIC(10,3) NOT NULL DEFAULT 0 CHECK (deducted_days >= 0),
      without_pay_days NUMERIC(10,3) NOT NULL DEFAULT 0 CHECK (without_pay_days >= 0),
      source_record_count INT NOT NULL DEFAULT 0 CHECK (source_record_count >= 0),
      metadata_json JSONB,
      posted_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      CONSTRAINT uq_leave_attendance_deduction_month
        UNIQUE (user_id, service_month, leave_type),
      CONSTRAINT chk_leave_attendance_service_month
        CHECK (EXTRACT(DAY FROM service_month) = 1),
      CONSTRAINT chk_leave_attendance_vacation_only
        CHECK (leave_type = 'vacationLeave'),
      CONSTRAINT fk_leave_attendance_deduction_leave_type
        FOREIGN KEY (leave_type) REFERENCES leave_types(name)
        ON UPDATE CASCADE ON DELETE RESTRICT
    )
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_leave_attendance_deductions_month
      ON leave_attendance_deductions(service_month, user_id)
  `);
}

async function loadEmployees(client, startStr, endStr) {
  const result = await client.query(
    `SELECT DISTINCT u.id AS user_id, u.full_name
     FROM users u
     JOIN assignments a ON a.employee_id = u.id
     WHERE COALESCE(u.leave_credit_eligible, true) = true
       AND (u.date_hired IS NULL OR u.date_hired <= $2::date)
       AND (u.separation_date IS NULL OR u.separation_date >= $1::date)
       AND (
         (
           (u.is_active IS NULL OR u.is_active = true)
           AND COALESCE(u.employment_status, 'active') = 'active'
         )
         OR u.separation_date >= $1::date
       )
       AND a.effective_from <= $2::date
       AND (a.effective_to IS NULL OR a.effective_to >= $1::date)
     ORDER BY u.full_name`,
    [startStr, endStr]
  );
  return result.rows.map((row) => ({
    userId: String(row.user_id),
    employeeName: row.full_name || 'Unnamed employee',
  }));
}

async function loadAssignments(client, employeeIds, startStr, endStr) {
  const map = new Map();
  if (employeeIds.length === 0) return map;
  const result = await client.query(
    `SELECT a.employee_id, a.department_id, a.shift_id,
            a.effective_from::text AS effective_from,
            a.effective_to::text AS effective_to,
            COALESCE(a.override_start_time, s.start_time)::text AS start_time,
            COALESCE(a.override_end_time, s.end_time)::text AS end_time,
            COALESCE(a.override_break_end, s.break_end)::text AS break_end,
            s.punch_mode, s.working_days
     FROM assignments a
     LEFT JOIN shifts s ON s.id = a.shift_id
     WHERE a.employee_id = ANY($1::uuid[])
       AND a.effective_from <= $3::date
       AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
     ORDER BY a.employee_id, a.effective_from DESC, a.created_at DESC`,
    [employeeIds, startStr, endStr]
  );
  for (const row of result.rows) {
    const startMinutes = timeToMinutes(row.start_time);
    const endMinutes = timeToMinutes(row.end_time);
    if (startMinutes == null || endMinutes == null) continue;
    const employeeId = String(row.employee_id);
    const list = map.get(employeeId) || [];
    list.push({
      departmentId: row.department_id ? String(row.department_id) : null,
      shiftId: row.shift_id ? String(row.shift_id) : null,
      effectiveFrom: dateOnly(row.effective_from),
      effectiveTo: dateOnly(row.effective_to),
      startMinutes,
      endMinutes,
      breakEndMinutes: timeToMinutes(row.break_end),
      punchMode: row.punch_mode || 'auto',
      workingDays: Array.isArray(row.working_days)
        ? row.working_days.map((value) => parseInt(value, 10))
        : [],
    });
    map.set(employeeId, list);
  }
  return map;
}

async function loadPolicies(client, assignmentsByEmployee, employeeIds, startStr, endStr) {
  const defaultResult = await client.query(
    `SELECT id, work_hours_per_day, use_equivalent_day_conversion,
            deduct_late, deduct_undertime, absent_equals_full_day_deduction,
            deduction_multiplier
     FROM attendance_policies
     WHERE (is_active IS NULL OR is_active = true)
     ORDER BY is_default DESC, updated_at DESC, created_at DESC
     LIMIT 1`
  );
  const defaultPolicy = normalizePolicy(defaultResult.rows[0]);

  const departmentIds = new Set();
  const shiftIds = new Set();
  for (const rows of assignmentsByEmployee.values()) {
    for (const row of rows) {
      if (row.departmentId) departmentIds.add(row.departmentId);
      if (row.shiftId) shiftIds.add(row.shiftId);
    }
  }

  const result = await client.query(
    `SELECT pa.employee_id, pa.department_id, pa.shift_id,
            pa.effective_from::text AS effective_from,
            pa.effective_to::text AS effective_to,
            pa.created_at,
            p.id, p.work_hours_per_day, p.use_equivalent_day_conversion,
            p.deduct_late, p.deduct_undertime,
            p.absent_equals_full_day_deduction, p.deduction_multiplier
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
       )`,
    [
      employeeIds,
      [...departmentIds],
      [...shiftIds],
      startStr,
      endStr,
    ]
  );

  return {
    defaultPolicy,
    policyAssignments: result.rows.map((row) => ({
      employeeId: row.employee_id ? String(row.employee_id) : null,
      departmentId: row.department_id ? String(row.department_id) : null,
      shiftId: row.shift_id ? String(row.shift_id) : null,
      effectiveFrom: dateOnly(row.effective_from),
      effectiveTo: dateOnly(row.effective_to),
      createdAt:
        row.created_at instanceof Date
          ? row.created_at.toISOString()
          : String(row.created_at || ''),
      policy: normalizePolicy(row),
    })),
  };
}

async function loadDtrRows(client, employeeIds, startStr, endStr) {
  const map = new Map();
  if (employeeIds.length === 0) return map;
  const result = await client.query(
    `SELECT employee_id, attendance_date::text AS attendance_date,
            time_in, break_out, break_in, time_out,
            late_minutes, undertime_minutes, status, holiday_id, leave_request_id
     FROM dtr_daily_summary
     WHERE employee_id = ANY($1::uuid[])
       AND attendance_date >= $2::date
       AND attendance_date <= $3::date`,
    [employeeIds, startStr, endStr]
  );
  for (const row of result.rows) {
    const key = `${row.employee_id}|${dateOnly(row.attendance_date)}`;
    map.set(key, row);
  }
  return map;
}

function hasPhysicalDtrPunches(row) {
  return !!(row?.time_in || row?.break_out || row?.break_in || row?.time_out);
}

async function loadApprovedLeaveKeys(client, employeeIds, startStr, endStr) {
  const keys = new Set();
  if (employeeIds.length === 0) return keys;
  const result = await client.query(
    `SELECT c.employee_id,
            c.attendance_date::text AS attendance_date,
            NULL::text AS start_date,
            NULL::text AS end_date
     FROM dtr_leave_coverage c
     JOIN leave_requests lr ON lr.id = c.leave_request_id AND lr.status = 'approved'
     WHERE c.employee_id = ANY($1::uuid[])
       AND c.attendance_date >= $2::date
       AND c.attendance_date <= $3::date

     UNION ALL

     SELECT lr.employee_id,
            NULL::text AS attendance_date,
            lr.start_date::text AS start_date,
            lr.end_date::text AS end_date
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
  for (const row of result.rows) {
    const employeeId = String(row.employee_id);
    if (row.attendance_date) {
      keys.add(`${employeeId}|${dateOnly(row.attendance_date)}`);
      continue;
    }
    const rangeStart = dateOnly(row.start_date) < startStr ? startStr : dateOnly(row.start_date);
    const rangeEnd = dateOnly(row.end_date) > endStr ? endStr : dateOnly(row.end_date);
    for (const dateStr of datesInRange(rangeStart, rangeEnd)) {
      keys.add(`${employeeId}|${dateStr}`);
    }
  }
  return keys;
}

async function loadFullLocatorKeys(
  client,
  employeeIds,
  startStr,
  endStr,
  assignmentsByEmployee,
  holidayCoverageByDate = new Map()
) {
  const keys = new Set();
  if (employeeIds.length === 0) return keys;
  const result = await client.query(
    `SELECT employee_id, slip_date::text AS slip_date,
            am_in, am_out, pm_in, pm_out
     FROM locator_slips
     WHERE status = 'approved'
       AND employee_id = ANY($1::uuid[])
       AND slip_date >= $2::date
       AND slip_date <= $3::date`,
    [employeeIds, startStr, endStr]
  );

  const coverageByEmployeeDate = new Map();
  for (const row of result.rows) {
    const employeeId = String(row.employee_id);
    const dateStr = dateOnly(row.slip_date);
    const key = `${employeeId}|${dateStr}`;
    const coverage = coverageByEmployeeDate.get(key) || {
      employeeId,
      dateStr,
      am_in: false,
      am_out: false,
      pm_in: false,
      pm_out: false,
    };
    coverage.am_in ||= row.am_in === true;
    coverage.am_out ||= row.am_out === true;
    coverage.pm_in ||= row.pm_in === true;
    coverage.pm_out ||= row.pm_out === true;
    coverageByEmployeeDate.set(key, coverage);
  }

  for (const [key, coverage] of coverageByEmployeeDate.entries()) {
    const assignment = assignmentForDate(
      assignmentsByEmployee,
      coverage.employeeId,
      coverage.dateStr
    );
    const holidayCoverage = holidayCoverageByDate.get(coverage.dateStr) || null;
    const holidayInfo = holidayCoverage ? { coverage: holidayCoverage } : null;
    if (
      locatorCoversExpectedShiftSlots(
        coverage,
        assignment,
        holidayInfo,
        coverage.dateStr
      )
    ) {
      keys.add(key);
    }
  }
  return keys;
}

async function loadHolidayCoverage(client, startStr, endStr) {
  const result = await client.query(
    `SELECT id, date_from::text AS date_from, date_to::text AS date_to,
            recurring, coverage
     FROM holidays
     WHERE (is_active IS NULL OR is_active = true)
       AND (
         recurring = true
         OR (date_from <= $2::date AND date_to >= $1::date)
       )`,
    [startStr, endStr]
  );
  const byDate = new Map();
  for (const row of result.rows) {
    const dates = row.recurring
      ? expandRecurringToWindow(
          dateOnly(row.date_from),
          dateOnly(row.date_to),
          startStr,
          endStr
        )
      : expandNonRecurringToWindow(
          dateOnly(row.date_from),
          dateOnly(row.date_to),
          startStr,
          endStr
        );
    for (const dateStr of dates) {
      if (!byDate.has(dateStr)) {
        byDate.set(dateStr, row.coverage || 'whole_day');
      }
    }
  }
  return byDate;
}

async function calculateMonthlyAttendanceDeductions(
  client,
  targetMonth,
  options = {}
) {
  const startStr = toDateStr(targetMonth);
  const endStr = toDateStr(endOfMonth(targetMonth));
  const employees =
    options.employees ||
    (await loadEmployees(client, startStr, endStr));
  const employeeIds = employees.map((employee) => employee.userId);
  if (employeeIds.length === 0) return [];

  const assignmentsByEmployee = await loadAssignments(
    client,
    employeeIds,
    startStr,
    endStr
  );
  const {
    defaultPolicy,
    policyAssignments,
  } = await loadPolicies(
    client,
    assignmentsByEmployee,
    employeeIds,
    startStr,
    endStr
  );
  const holidayCoverage = await loadHolidayCoverage(client, startStr, endStr);
  // A checked-out pg client can execute only one query at a time. Keep these
  // transaction-scoped reads sequential so this remains compatible with pg 9.
  const dtrRows = await loadDtrRows(client, employeeIds, startStr, endStr);
  const approvedLeaveKeys = await loadApprovedLeaveKeys(
    client,
    employeeIds,
    startStr,
    endStr
  );
  const fullLocatorKeys = await loadFullLocatorKeys(
    client,
    employeeIds,
    startStr,
    endStr,
    assignmentsByEmployee,
    holidayCoverage
  );

  const monthDates = datesInRange(startStr, endStr);
  const summaries = [];

  for (const employee of employees) {
    let lateMinutes = 0;
    let undertimeMinutes = 0;
    let absenceMinutes = 0;
    let computedDaysRaw = 0;
    let sourceRecordCount = 0;
    let syntheticAbsenceCount = 0;

    for (const dateStr of monthDates) {
      const assignment = assignmentForDate(
        assignmentsByEmployee,
        employee.userId,
        dateStr
      );
      if (!assignment || !assignment.workingDays.includes(isoWeekday(dateStr))) {
        continue;
      }

      const key = `${employee.userId}|${dateStr}`;
      const holiday = holidayCoverage.get(dateStr) || null;
      const dtr = dtrRows.get(key);
      if (
        approvedLeaveKeys.has(key) ||
        (fullLocatorKeys.has(key) && !hasPhysicalDtrPunches(dtr)) ||
        holiday === 'whole_day'
      ) {
        continue;
      }

      const policy = policyForDate({
        policyAssignments,
        defaultPolicy,
        employeeId: employee.userId,
        dateStr,
        assignment,
      });
      if (!policy.useEquivalentDayConversion) continue;

      let dayLate = 0;
      let dayUndertime = 0;
      let dayAbsence = 0;

      if (dtr) {
        if (
          dtr.status === 'on_leave' ||
          dtr.status === 'holiday' ||
          dtr.status === 'rest_day'
        ) {
          continue;
        }
        sourceRecordCount += 1;
        dayLate = policy.deductLate
          ? Math.max(0, parseInt(dtr.late_minutes, 10) || 0)
          : 0;
        dayUndertime = policy.deductUndertime
          ? Math.max(0, parseInt(dtr.undertime_minutes, 10) || 0)
          : 0;
        if (
          dtr.status === 'absent' &&
          policy.deductUndertime &&
          policy.absentEqualsFullDayDeduction
        ) {
          const expected = expectedMinutesForCoverage(assignment, holiday);
          dayAbsence =
            dayUndertime > 0
              ? dayUndertime
              : Math.round(expected * Math.max(0, policy.deductionMultiplier || 1));
          dayUndertime = 0;
        }
      } else if (
        policy.deductUndertime &&
        policy.absentEqualsFullDayDeduction
      ) {
        const expected = expectedMinutesForCoverage(assignment, holiday);
        dayAbsence = Math.round(
          expected * Math.max(0, policy.deductionMultiplier || 1)
        );
        if (dayAbsence > 0) syntheticAbsenceCount += 1;
      }

      const dayTotal = dayLate + dayUndertime + dayAbsence;
      if (dayTotal <= 0) continue;

      lateMinutes += dayLate;
      undertimeMinutes += dayUndertime;
      absenceMinutes += dayAbsence;
      computedDaysRaw += dayTotal / policyWorkMinutes(policy);
    }

    summaries.push({
      user_id: employee.userId,
      employee_name: employee.employeeName,
      leave_type: VACATION_LEAVE,
      service_month: startStr,
      late_minutes: lateMinutes,
      undertime_minutes: undertimeMinutes,
      absence_minutes: absenceMinutes,
      total_deduction_minutes: lateMinutes + undertimeMinutes + absenceMinutes,
      computed_days: round3(computedDaysRaw),
      source_record_count: sourceRecordCount,
      synthetic_absence_count: syntheticAbsenceCount,
    });
  }

  return summaries;
}

async function fetchPosting(client, userId, serviceMonth, forUpdate = false) {
  const result = await client.query(
    `SELECT id, computed_days, deducted_days, without_pay_days
     FROM leave_attendance_deductions
     WHERE user_id = $1::uuid
       AND service_month = $2::date
       AND leave_type = $3::text
     ${forUpdate ? 'FOR UPDATE' : ''}`,
    [userId, serviceMonth, VACATION_LEAVE]
  );
  return result.rows[0] || null;
}

async function ensurePostingLock(client, summary) {
  const insertResult = await client.query(
    `INSERT INTO leave_attendance_deductions (
       user_id, service_month, leave_type
     ) VALUES ($1::uuid, $2::date, $3::text)
     ON CONFLICT (user_id, service_month, leave_type) DO NOTHING
     RETURNING id`,
    [summary.user_id, summary.service_month, VACATION_LEAVE]
  );
  return {
    posting: await fetchPosting(
      client,
      summary.user_id,
      summary.service_month,
      true
    ),
    created: insertResult.rowCount > 0,
  };
}

async function fetchVacationBalanceForUpdate(client, userId) {
  await client.query(
    `INSERT INTO leave_balances (
       user_id, leave_type, earned_days, used_days, pending_days,
       adjusted_days, as_of_date, created_at, updated_at
     ) VALUES ($1::uuid, $2::text, 0, 0, 0, 0, CURRENT_DATE, now(), now())
     ON CONFLICT (user_id, leave_type) DO NOTHING`,
    [userId, VACATION_LEAVE]
  );
  const result = await client.query(
    `SELECT earned_days, used_days, pending_days, adjusted_days
     FROM leave_balances
     WHERE user_id = $1::uuid AND leave_type = $2::text
     FOR UPDATE`,
    [userId, VACATION_LEAVE]
  );
  const row = result.rows[0] || {};
  return {
    earned: parseFloat(row.earned_days || 0),
    used: parseFloat(row.used_days || 0),
    pending: parseFloat(row.pending_days || 0),
    adjusted: parseFloat(row.adjusted_days || 0),
  };
}

function desiredPosting(summary, previous, balance) {
  const oldDeducted = round3(parseFloat(previous?.deducted_days || 0));
  const usedWithoutThisPosting = Math.max(0, round3(balance.used - oldDeducted));
  const available = Math.max(
    0,
    round3(balance.earned - usedWithoutThisPosting + balance.adjusted - balance.pending)
  );
  const computed = round3(summary.computed_days || 0);
  const deducted = Math.min(computed, available);
  return {
    computed,
    deducted: round3(deducted),
    withoutPay: round3(Math.max(0, computed - deducted)),
    delta: round3(deducted - oldDeducted),
    oldDeducted,
    availableBeforePosting: available,
    usedWithoutThisPosting,
  };
}

async function runMonthlyAttendanceDeductions(pgPool, options = {}) {
  const dryRun = options.dryRun === true;
  const timeZone = options.timeZone || DEFAULT_TIME_ZONE;
  const nowMonth = monthStartInTimeZone(
    options.now != null ? options.now : new Date(),
    timeZone
  );
  const targetMonth =
    options.targetMonth == null
      ? addMonths(nowMonth, -1)
      : parseTargetMonth(options.targetMonth);

  if (
    options.allowCurrentTargetMonth !== true &&
    monthKey(targetMonth) >= monthKey(nowMonth)
  ) {
    throw new Error(
      'targetMonth must be a completed month before the current month'
    );
  }

  const targetYearMonth = toDateStr(targetMonth).slice(0, 7);
  const serviceMonth = toDateStr(targetMonth);
  await ensureLeaveAttendanceDeductionTable(pgPool);
  initLeaveBalanceLedger(pgPool);

  const client = await pgPool.connect();
  let rowsUpdated = 0;
  let rowsSkipped = 0;
  let totalComputedDays = 0;
  let totalDeductedDays = 0;
  let totalWithoutPayDays = 0;
  let locatorReconciliationsCleared = 0;
  const details = [];

  try {
    if (!dryRun) await client.query('BEGIN');

    const summaries =
      options.summaries ||
      (await calculateMonthlyAttendanceDeductions(client, targetMonth, options));

    for (const summary of summaries) {
      let previous;
      let balance;
      let postingCreated = false;
      if (dryRun) {
        previous = await fetchPosting(
          client,
          summary.user_id,
          serviceMonth,
          false
        );
        const balanceResult = await client.query(
          `SELECT earned_days, used_days, pending_days, adjusted_days
           FROM leave_balances
           WHERE user_id = $1::uuid AND leave_type = $2::text`,
          [summary.user_id, VACATION_LEAVE]
        );
        const row = balanceResult.rows[0] || {};
        balance = {
          earned: parseFloat(row.earned_days || 0),
          used: parseFloat(row.used_days || 0),
          pending: parseFloat(row.pending_days || 0),
          adjusted: parseFloat(row.adjusted_days || 0),
        };
        const previewEarnedAdjustment =
          options.balanceEarnedAdjustmentsByUser instanceof Map
            ? options.balanceEarnedAdjustmentsByUser.get(String(summary.user_id))
            : options.balanceEarnedAdjustmentsByUser?.[String(summary.user_id)];
        if (
          previewEarnedAdjustment != null &&
          Number.isFinite(Number(previewEarnedAdjustment))
        ) {
          balance.earned = round3(
            balance.earned + Number(previewEarnedAdjustment)
          );
        }
      } else {
        const postingLock = await ensurePostingLock(client, summary);
        previous = postingLock.posting;
        postingCreated = postingLock.created;
        balance = await fetchVacationBalanceForUpdate(client, summary.user_id);
      }

      const desired = desiredPosting(summary, previous, balance);
      const previousComputed = round3(parseFloat(previous?.computed_days || 0));
      const previousWithoutPay = round3(
        parseFloat(previous?.without_pay_days || 0)
      );
      const isCorrection = previous != null && !postingCreated;
      const changed =
        desired.delta !== 0 ||
        desired.computed !== previousComputed ||
        desired.withoutPay !== previousWithoutPay;

      totalComputedDays = round3(totalComputedDays + desired.computed);
      totalDeductedDays = round3(totalDeductedDays + desired.deducted);
      totalWithoutPayDays = round3(totalWithoutPayDays + desired.withoutPay);

      const detail = {
        ...summary,
        computed_days: desired.computed,
        deducted_days: desired.deducted,
        without_pay_days: desired.withoutPay,
        balance_delta: desired.delta,
        available_before_posting: desired.availableBeforePosting,
      };

      if (!changed) {
        rowsSkipped += 1;
        details.push({ ...detail, action: 'skipped', reason: 'already_posted' });
        continue;
      }

      rowsUpdated += 1;
      if (dryRun) {
        details.push({ ...detail, action: 'would_apply' });
        continue;
      }

      const oldUsed = balance.used;
      const newUsed = Math.max(0, round3(oldUsed + desired.delta));
      if (desired.delta !== 0) {
        await client.query(
          `UPDATE leave_balances
           SET used_days = $3::numeric,
               as_of_date = CURRENT_DATE,
               updated_at = now()
           WHERE user_id = $1::uuid AND leave_type = $2::text`,
          [summary.user_id, VACATION_LEAVE, newUsed]
        );
      }

      const metadata = {
        service_month: targetYearMonth,
        late_minutes: summary.late_minutes,
        undertime_minutes: summary.undertime_minutes,
        absence_minutes: summary.absence_minutes,
        total_deduction_minutes: summary.total_deduction_minutes,
        computed_days: desired.computed,
        deducted_days: desired.deducted,
        without_pay_days: desired.withoutPay,
        source_record_count: summary.source_record_count,
        synthetic_absence_count: summary.synthetic_absence_count,
      };

      await client.query(
        `UPDATE leave_attendance_deductions
         SET late_minutes = $4::int,
             undertime_minutes = $5::int,
             absence_minutes = $6::int,
             computed_days = $7::numeric,
             deducted_days = $8::numeric,
             without_pay_days = $9::numeric,
             source_record_count = $10::int,
             metadata_json = $11::jsonb,
             posted_at = now(),
             updated_at = now()
         WHERE user_id = $1::uuid
           AND service_month = $2::date
           AND leave_type = $3::text`,
        [
          summary.user_id,
          serviceMonth,
          VACATION_LEAVE,
          summary.late_minutes,
          summary.undertime_minutes,
          summary.absence_minutes,
          desired.computed,
          desired.deducted,
          desired.withoutPay,
          summary.source_record_count,
          metadata,
        ]
      );

      if (desired.delta !== 0) {
        await insertLeaveBalanceLedger(client, {
          userId: summary.user_id,
          leaveType: VACATION_LEAVE,
          action:
            isCorrection
              ? 'attendance_deduction_adjusted'
              : 'attendance_deduction',
          affectedBucket: 'used',
          daysChanged: desired.delta,
          oldValue: oldUsed,
          newValue: newUsed,
          actorUserId: null,
          actorKind: 'system',
          remarks: `DTR late/undertime deduction for ${targetYearMonth}`,
          metadataJson: metadata,
        });
      }

      details.push({
        ...detail,
        action:
          isCorrection
            ? 'adjusted'
            : desired.delta > 0
              ? 'applied'
              : 'recorded',
      });
    }

    if (!dryRun) {
      const reconciledLocators = await client.query(
        `UPDATE locator_slips
         SET month_end_reconciliation_required = false,
             month_end_reconciled_at = now(),
             updated_at = now()
         WHERE status = 'revoked'
           AND month_end_reconciliation_required = true
           AND date_trunc('month', slip_date)::date = $1::date`,
        [serviceMonth]
      );
      locatorReconciliationsCleared = reconciledLocators.rowCount || 0;
      await client.query('COMMIT');
    }

    return {
      targetYearMonth,
      dryRun,
      rowsUpdated,
      rowsSkipped,
      totalComputedDays,
      totalDeductedDays,
      totalWithoutPayDays,
      locatorReconciliationsCleared,
      details,
    };
  } catch (error) {
    if (!dryRun) {
      try {
        await client.query('ROLLBACK');
      } catch (_) {
        // Preserve the original failure.
      }
    }
    throw error;
  } finally {
    client.release();
  }
}

module.exports = {
  runMonthlyAttendanceDeductions,
  calculateMonthlyAttendanceDeductions,
  ensureLeaveAttendanceDeductionTable,
  equivalentDaysFromMinutes,
  expectedMinutesForCoverage,
  desiredPosting,
  /** @internal exported for regression tests */
  assignmentForDate,
  hasPhysicalDtrPunches,
  expectedLocatorSlotsForAssignment: expectedLocatorSlotsForShift,
  locatorCoversExpectedShiftSlots,
  loadAssignments,
  loadEmployees,
  loadFullLocatorKeys,
};
