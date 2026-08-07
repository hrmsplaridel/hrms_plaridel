function coverageError(message, details = null) {
  const error = new Error(message);
  error.statusCode = 400;
  if (details) error.details = details;
  return error;
}

function normalizeCoverageDates(dates) {
  const normalized = [];
  const seen = new Set();
  for (const raw of Array.isArray(dates) ? dates : []) {
    const match = String(raw || '').match(/^(\d{4}-\d{2}-\d{2})/);
    if (!match || seen.has(match[1])) continue;
    seen.add(match[1]);
    normalized.push(match[1]);
  }
  return normalized.sort();
}

function attendanceConflictMessage(conflicts) {
  const dates = conflicts.map((row) => String(row.attendance_date).slice(0, 10));
  const preview = dates.slice(0, 5).join(', ');
  const suffix = dates.length > 5 ? ` and ${dates.length - 5} more` : '';
  return `Cannot approve leave because attendance already exists on ${preview}${suffix}. Resolve the DTR record first.`;
}

function assertCoverageMatchesRequestedDays(dates, requestedDays) {
  const coverageDates = normalizeCoverageDates(dates);
  const requested = Number(requestedDays);
  if (coverageDates.length === 0) {
    throw coverageError(
      'This request no longer contains any scheduled working dates. Return it for correction before approval.'
    );
  }
  if (
    !Number.isFinite(requested) ||
    Math.abs(requested - coverageDates.length) > 0.0001
  ) {
    throw coverageError(
      `The server now counts ${coverageDates.length} working day(s), but this request reserved ${Number.isFinite(requested) ? requested : 0}. Return the request for correction before approval.`
    );
  }
  return {
    dates: coverageDates,
    days: coverageDates.length,
  };
}

async function findAttendanceConflicts(client, employeeId, dates) {
  const coverageDates = normalizeCoverageDates(dates);
  if (!client || !employeeId || coverageDates.length === 0) return [];

  const result = await client.query(
    `SELECT attendance_date::text AS attendance_date,
            status,
            time_in IS NOT NULL AS has_time_in,
            break_out IS NOT NULL AS has_break_out,
            break_in IS NOT NULL AS has_break_in,
            time_out IS NOT NULL AS has_time_out
     FROM dtr_daily_summary
     WHERE employee_id = $1::uuid
       AND attendance_date = ANY($2::date[])
       AND (
         time_in IS NOT NULL
         OR break_out IS NOT NULL
         OR break_in IS NOT NULL
         OR time_out IS NOT NULL
         OR status IN ('present', 'late', 'incomplete')
       )
     ORDER BY attendance_date
     FOR UPDATE`,
    [employeeId, coverageDates]
  );
  return result.rows;
}

async function replaceApprovedLeaveCoverage(
  client,
  { employeeId, leaveRequestId, dates, actorUserId = null }
) {
  const coverageDates = normalizeCoverageDates(dates);
  if (!client || !employeeId || !leaveRequestId || coverageDates.length === 0) {
    throw coverageError('Approved leave must contain at least one scheduled working date.');
  }

  const attendanceConflicts = await findAttendanceConflicts(
    client,
    employeeId,
    coverageDates
  );
  if (attendanceConflicts.length > 0) {
    throw coverageError(attendanceConflictMessage(attendanceConflicts), {
      conflict_dates: attendanceConflicts.map((row) =>
        String(row.attendance_date).slice(0, 10)
      ),
    });
  }

  const coverageConflicts = await client.query(
    `SELECT attendance_date::text AS attendance_date, leave_request_id
     FROM dtr_leave_coverage
     WHERE employee_id = $1::uuid
       AND attendance_date = ANY($2::date[])
       AND leave_request_id <> $3::uuid
     ORDER BY attendance_date
     FOR UPDATE`,
    [employeeId, coverageDates, leaveRequestId]
  );
  if (coverageConflicts.rows.length > 0) {
    const datesText = coverageConflicts.rows
      .map((row) => String(row.attendance_date).slice(0, 10))
      .join(', ');
    throw coverageError(
      `Cannot approve leave because another approved leave already covers ${datesText}.`
    );
  }

  await client.query(
    'DELETE FROM dtr_leave_coverage WHERE leave_request_id = $1::uuid',
    [leaveRequestId]
  );
  let inserted;
  try {
    inserted = await client.query(
      `INSERT INTO dtr_leave_coverage (
         leave_request_id,
         employee_id,
         attendance_date,
         created_by,
         created_at
       )
       SELECT $1::uuid, $2::uuid, covered_date, $4::uuid, now()
       FROM unnest($3::date[]) AS covered_date
       RETURNING attendance_date::text AS attendance_date`,
      [leaveRequestId, employeeId, coverageDates, actorUserId]
    );
  } catch (error) {
    if (error?.code === '23505') {
      throw coverageError(
        'Another approved leave was recorded for one of these dates. Refresh and review the request again.'
      );
    }
    throw error;
  }

  return inserted.rows.map((row) => String(row.attendance_date).slice(0, 10));
}

async function removeApprovedLeaveCoverage(client, leaveRequestId) {
  if (!client || !leaveRequestId) return 0;
  const result = await client.query(
    'DELETE FROM dtr_leave_coverage WHERE leave_request_id = $1::uuid',
    [leaveRequestId]
  );
  return result.rowCount || 0;
}

module.exports = {
  assertCoverageMatchesRequestedDays,
  findAttendanceConflicts,
  normalizeCoverageDates,
  removeApprovedLeaveCoverage,
  replaceApprovedLeaveCoverage,
};
