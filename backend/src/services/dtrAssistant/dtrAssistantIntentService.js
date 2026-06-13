function lower(value) {
  return String(value || '').toLowerCase();
}

function normalizeIntent(value) {
  const intent = String(value || '').trim().toLowerCase();
  return [
    'today_dtr',
    'missing_logs',
    'leave_balance',
    'latest_leave_request',
    'latest_locator_request',
  ].includes(intent)
    ? intent
    : null;
}

function detectEmployeeAssistantIntent(message, explicitIntent) {
  const forcedIntent = normalizeIntent(explicitIntent);
  if (forcedIntent) return forcedIntent;

  const text = lower(message);

  if (
    /\b(missing|incomplete|kulang|kuwang|wala|absent|no log|nolog|logs?|entries)\b/.test(
      text
    ) &&
    /\b(logs?|dtr|attendance|time[\s-]?in|time[\s-]?out|this week|week|semanaha|semana|karon|ngayon)\b/.test(
      text
    )
  ) {
    return 'missing_logs';
  }

  if (
    /\b(leave balance|leave balances|leave credit|leave credits|credits|balance|available leave|remaining leave|pila.*leave|ilan.*leave)\b/.test(
      text
    )
  ) {
    return 'leave_balance';
  }

  if (
    /\b(leave request|latest leave|last leave|leave status|status.*leave|ano status.*leave|na-approve.*leave|approved.*leave)\b/.test(
      text
    )
  ) {
    return 'latest_leave_request';
  }

  if (
    /\b(locator|pass slip|locator slip|wfh|work from home|official business|ob request|na-approve|approved.*locator|status.*locator)\b/.test(
      text
    )
  ) {
    return 'latest_locator_request';
  }

  if (
    /\b(dtr|attendance|late|time[\s-]?in|time[\s-]?out|status)\b/.test(text) &&
    /\b(today|karon|ngayon|karong adlawa|this day|late|status|time[\s-]?in|time[\s-]?out)\b/.test(
      text
    )
  ) {
    return 'today_dtr';
  }

  return null;
}

module.exports = {
  detectEmployeeAssistantIntent,
  normalizeIntent,
};
