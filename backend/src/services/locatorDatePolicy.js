const HRMS_TIMEZONE = process.env.HRMS_TIMEZONE || 'Asia/Manila';

function currentHrmsDate(now = new Date(), timeZone = HRMS_TIMEZONE) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const get = (type) => parts.find((part) => part.type === type)?.value || '';
  return `${get('year')}-${get('month')}-${get('day')}`;
}

function evaluateEmployeeLocatorDateWindow({ slipDate, now = new Date() }) {
  const date = String(slipDate || '').slice(0, 10);
  if (!date) {
    return {
      ok: false,
      code: 'locator_date_required',
      error: 'Locator date is required.',
    };
  }
  if (date < currentHrmsDate(now)) {
    return {
      ok: false,
      code: 'locator_past_date_not_allowed',
      error:
        'Employees cannot file locator requests for a past date. Contact HR for a documented correction.',
    };
  }
  return { ok: true };
}

function normalizeCorrectionReason(value) {
  const reason = String(value || '').trim();
  return reason.length >= 10 && reason.length <= 1000 ? reason : null;
}

module.exports = {
  HRMS_TIMEZONE,
  currentHrmsDate,
  evaluateEmployeeLocatorDateWindow,
  normalizeCorrectionReason,
};
