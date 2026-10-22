'use strict';
module.exports = function createLeaveComponent({
  ANNUAL_QUOTA_LEAVE_USAGE_STATUSES,
  ENTITLEMENT_BASES,
  annualAllowance,
  buildAnnualEntitlementYearSummary,
  calendarYearsForDateRange,
  countedDatesForCalendarYear,
  formatDayCount,
  normalizeEntitlementBasis,
  systemLeaveTypeDisplayName,
  toIsoDateStr,
  workingDaysWithinYear,
}) {
  function annualQuotaLimitErrorMessage(label, yearSummary) {
    return (
      `${label} is limited to ${formatDayCount(yearSummary.limit_days)} days per calendar year. ` +
      `You only have ${formatDayCount(yearSummary.remaining_before_request)} day(s) remaining for ${yearSummary.year}; ` +
      `this request needs ${formatDayCount(yearSummary.requested_days)} day(s).`
    );
  }

  async function computeAnnualQuotaLeavePreview(
    client,
    { userId, leaveTypeName, startStr, endStr, excludeId = null, requestedCountedDates = null },
  ) {
    const leaveTypeKey = String(leaveTypeName || '').trim();
    if (!client || !userId || !leaveTypeKey || !startStr || !endStr) return null;

    const typeQ = await client.query(
      `SELECT COALESCE(display_name, description, name) AS display_name,
            max_days,
            first_year_allowance,
            entitlement_basis
     FROM leave_types
     WHERE name = $1
     LIMIT 1`,
      [leaveTypeKey],
    );
    const typeRow = typeQ.rows[0];
    if (
      !typeRow ||
      normalizeEntitlementBasis(typeRow.entitlement_basis, leaveTypeKey) !==
        ENTITLEMENT_BASES.ANNUAL
    ) {
      return null;
    }
    const limit = Number(typeRow.max_days);
    if (!Number.isFinite(limit) || limit <= 0) return null;
    const label = typeRow.display_name || systemLeaveTypeDisplayName(leaveTypeKey);

    let hireDate = null;
    if (typeRow.first_year_allowance === 'prorated') {
      const employee = await client.query(
        'SELECT date_hired::text AS date_hired FROM users WHERE id = $1::uuid LIMIT 1',
        [userId],
      );
      hireDate = employee.rows[0]?.date_hired;
    }
    const years = calendarYearsForDateRange(startStr, endStr);
    if (years.length === 0) return null;

    const queryFrom = `${Math.min(...years)}-01-01`;
    const queryTo = `${Math.max(...years)}-12-31`;
    const existing = await client.query(
      `SELECT lr.id, lr.start_date, lr.end_date, lr.status
     FROM leave_requests lr
     INNER JOIN leave_types lt ON lt.id = lr.leave_type_id
     WHERE (lr.user_id = $1::uuid OR lr.employee_id = $1::uuid)
       AND lt.name = $2
       AND lr.status = ANY($3::text[])
       AND lr.start_date <= $5::date
       AND lr.end_date >= $4::date
       AND ($6::text IS NULL OR lr.id::text <> $6::text)`,
      [userId, leaveTypeKey, ANNUAL_QUOTA_LEAVE_USAGE_STATUSES, queryFrom, queryTo, excludeId],
    );

    const normalizedRequestedDates = Array.isArray(requestedCountedDates)
      ? requestedCountedDates.map(toIsoDateStr).filter(Boolean)
      : null;
    const yearSummaries = [];
    for (const year of years) {
      const requestedDatesForYear =
        normalizedRequestedDates == null
          ? null
          : countedDatesForCalendarYear(normalizedRequestedDates, year);
      const requestedDays =
        requestedDatesForYear == null
          ? await workingDaysWithinYear(client, userId, startStr, endStr, year)
          : requestedDatesForYear.length;
      if (requestedDays <= 0) continue;

      let approvedDays = 0;
      let pendingDays = 0;
      for (const row of existing.rows) {
        const existingStart = toIsoDateStr(row.start_date);
        const existingEnd = toIsoDateStr(row.end_date);
        const days = await workingDaysWithinYear(client, userId, existingStart, existingEnd, year);
        if (row.status === 'approved') approvedDays += days;
        else pendingDays += days;
      }

      const allowance = annualAllowance(typeRow, hireDate, year);
      const summary = buildAnnualEntitlementYearSummary({
        year,
        limitDays: allowance.limit_days,
        approvedDays,
        pendingDays,
        requestedDays,
        requestedCountedDates: requestedDatesForYear || [],
      });
      Object.assign(summary, {
        full_limit_days: allowance.full_limit_days,
        calculated_days: allowance.calculated_days,
        prorated: allowance.prorated,
      });
      summary.allowed = summary.allowed && !allowance.error_message;
      summary.error_message =
        allowance.error_message ||
        (summary.allowed ? null : annualQuotaLimitErrorMessage(label, summary));
      yearSummaries.push(summary);
    }

    return {
      leave_type: leaveTypeKey,
      display_name: label,
      entitlement_basis: ENTITLEMENT_BASES.ANNUAL,
      limit_days: limit,
      allowed: yearSummaries.every((summary) => summary.allowed),
      years: yearSummaries,
    };
  }

  async function assertAnnualQuotaLeaveLimit(
    client,
    { userId, leaveTypeName, startStr, endStr, excludeId = null },
  ) {
    const preview = await computeAnnualQuotaLeavePreview(client, {
      userId,
      leaveTypeName,
      startStr,
      endStr,
      excludeId,
    });
    const rejectedYear = preview?.years?.find((summary) => !summary.allowed);
    if (!rejectedYear) return;
    const err = new Error(
      rejectedYear.error_message ||
        annualQuotaLimitErrorMessage(preview.display_name, rejectedYear),
    );
    err.statusCode = 400;
    throw err;
  }
  return {
    annualQuotaLimitErrorMessage,
    computeAnnualQuotaLeavePreview,
    assertAnnualQuotaLeaveLimit,
  };
};
