const {
  LOCATOR_SLOTS,
  locatorSlotLabel,
  normalizeLocatorCoverage,
} = require('./locatorCoverage');

const ACTIVE_LOCATOR_STATUSES = Object.freeze([
  'pending',
  'pending_department_head',
  'pending_hr',
  'approved',
]);
const APPROVED_LOCATOR_STATUSES = Object.freeze(['approved']);
const DTR_SLOT_FIELDS = Object.freeze({
  am_in: 'time_in',
  am_out: 'break_out',
  pm_in: 'break_in',
  pm_out: 'time_out',
});

function locatorCoverageFromInput(input = {}) {
  return normalizeLocatorCoverage({
    am_in: input.am_in ?? input.amIn,
    am_out: input.am_out ?? input.amOut,
    pm_in: input.pm_in ?? input.pmIn,
    pm_out: input.pm_out ?? input.pmOut,
  });
}

function overlappingLocatorSlots(requested, existing) {
  const requestedCoverage = locatorCoverageFromInput(requested);
  const existingCoverage = locatorCoverageFromInput(existing);
  return LOCATOR_SLOTS.filter(
    (slot) => requestedCoverage[slot] && existingCoverage[slot]
  );
}

function conflictingDtrPunchSlots(requested, dtrRecord) {
  const requestedCoverage = locatorCoverageFromInput(requested);
  return LOCATOR_SLOTS.filter((slot) => {
    const dtrField = DTR_SLOT_FIELDS[slot];
    return requestedCoverage[slot] && dtrRecord?.[dtrField] != null;
  });
}

function conflictMessage({ locatorConflicts, leaveConflicts, attendanceConflicts }) {
  if (locatorConflicts.length > 0) {
    const slots = [...new Set(locatorConflicts.flatMap((item) => item.slots))]
      .map(locatorSlotLabel)
      .join(', ');
    return `Another active locator request already covers ${slots}. Use only non-overlapping slots or resolve the existing request first.`;
  }
  if (leaveConflicts.length > 0) {
    const leave = leaveConflicts[0];
    return `Approved ${leave.leave_type || 'leave'} already covers this date. Resolve the leave and locator conflict before continuing.`;
  }
  if (attendanceConflicts.length > 0) {
    const slots = attendanceConflicts[0].slots.map(locatorSlotLabel).join(', ');
    return `DTR punches already exist for ${slots}. HR must resolve the attendance record or return the locator request before approval.`;
  }
  return null;
}

async function lockEmployeeAttendanceDate(client, employeeId, attendanceDate) {
  await client.query(
    `SELECT pg_advisory_xact_lock(
       hashtext($1::text),
       hashtext($2::text)
     )`,
    [String(employeeId), String(attendanceDate).slice(0, 10)]
  );
}

async function findLocatorRequestConflicts(
  client,
  {
    employeeId,
    slipDate,
    slots,
    excludeSlipId = null,
    phase = 'submission',
    checkLeave = true,
    checkAttendance = true,
    acquireLock = true,
  }
) {
  const date = String(slipDate || '').slice(0, 10);
  if (!client || !employeeId || !date) {
    throw new Error('Employee and locator date are required for conflict checking.');
  }
  if (acquireLock) await lockEmployeeAttendanceDate(client, employeeId, date);

  const statuses = phase === 'submission'
    ? ACTIVE_LOCATOR_STATUSES
    : APPROVED_LOCATOR_STATUSES;
  const locatorResult = await client.query(
    `SELECT id, status, request_type, am_in, am_out, pm_in, pm_out
     FROM locator_slips
     WHERE employee_id = $1::uuid
       AND slip_date = $2::date
       AND status = ANY($4::text[])
       AND ($3::uuid IS NULL OR id <> $3::uuid)
     ORDER BY created_at ASC`,
    [employeeId, date, excludeSlipId, statuses]
  );
  const locatorConflicts = locatorResult.rows
    .map((row) => ({
      id: row.id,
      status: row.status,
      request_type: row.request_type,
      slots: overlappingLocatorSlots(slots, row),
    }))
    .filter((item) => item.slots.length > 0);

  let leaveConflicts = [];
  if (checkLeave) {
    const leaveResult = await client.query(
      `SELECT lr.id,
              COALESCE(NULLIF(lt.display_name, ''), NULLIF(lt.description, ''), lt.name) AS leave_type
       FROM dtr_leave_coverage dlc
       JOIN leave_requests lr ON lr.id = dlc.leave_request_id
       LEFT JOIN leave_types lt ON lt.id = lr.leave_type_id
       WHERE dlc.employee_id = $1::uuid
         AND dlc.attendance_date = $2::date
         AND lr.status = 'approved'
         AND COALESCE(lt.affects_dtr_normally, true) = true
       ORDER BY lr.approved_at DESC NULLS LAST, lr.updated_at DESC
       LIMIT 5`,
      [employeeId, date]
    );
    leaveConflicts = leaveResult.rows.map((row) => ({
      id: row.id,
      leave_type: row.leave_type || 'leave',
    }));
  }

  let attendanceConflicts = [];
  if (checkAttendance) {
    const dtrResult = await client.query(
      `SELECT id, status, time_in, break_out, break_in, time_out,
              late_minutes, undertime_minutes
       FROM dtr_daily_summary
       WHERE employee_id = $1::uuid
         AND attendance_date = $2::date
       LIMIT 1`,
      [employeeId, date]
    );
    attendanceConflicts = dtrResult.rows
      .map((row) => ({
        id: row.id,
        status: row.status,
        slots: conflictingDtrPunchSlots(slots, row),
        late_minutes: Number(row.late_minutes || 0),
        undertime_minutes: Number(row.undertime_minutes || 0),
      }))
      .filter((item) => item.slots.length > 0);
  }

  const conflicts = {
    locator: locatorConflicts,
    leave: leaveConflicts,
    attendance: attendanceConflicts,
  };
  const message = conflictMessage({
    locatorConflicts,
    leaveConflicts,
    attendanceConflicts,
  });
  return {
    ok: !message,
    code: locatorConflicts.length > 0
      ? 'locator_slot_conflict'
      : leaveConflicts.length > 0
        ? 'approved_leave_conflict'
        : attendanceConflicts.length > 0
          ? 'dtr_punch_conflict'
          : null,
    message,
    conflicts,
  };
}

async function findApprovedLocatorConflictsForDates(
  client,
  { employeeId, dates, acquireLocks = true }
) {
  const normalizedDates = [...new Set(
    (Array.isArray(dates) ? dates : [])
      .map((date) => String(date || '').slice(0, 10))
      .filter(Boolean)
  )].sort();
  if (acquireLocks) {
    for (const date of normalizedDates) {
      await lockEmployeeAttendanceDate(client, employeeId, date);
    }
  }
  if (normalizedDates.length === 0) return [];

  const result = await client.query(
    `SELECT id, slip_date::text AS slip_date, request_type,
            am_in, am_out, pm_in, pm_out
     FROM locator_slips
     WHERE employee_id = $1::uuid
       AND status = 'approved'
       AND slip_date = ANY($2::date[])
     ORDER BY slip_date, created_at`,
    [employeeId, normalizedDates]
  );
  return result.rows.map((row) => ({
    id: row.id,
    slip_date: String(row.slip_date).slice(0, 10),
    request_type: row.request_type,
    slots: LOCATOR_SLOTS.filter((slot) => locatorCoverageFromInput(row)[slot]),
  }));
}

module.exports = {
  ACTIVE_LOCATOR_STATUSES,
  APPROVED_LOCATOR_STATUSES,
  conflictingDtrPunchSlots,
  findApprovedLocatorConflictsForDates,
  findLocatorRequestConflicts,
  locatorCoverageFromInput,
  lockEmployeeAttendanceDate,
  overlappingLocatorSlots,
};
