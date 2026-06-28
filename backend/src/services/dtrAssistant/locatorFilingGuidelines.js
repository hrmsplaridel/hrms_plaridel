const LOCATOR_GENERIC_FIELD_HELP_PATTERN =
  /\b(what (?:do|should|can) i (?:put|enter|write|select|type)|what to (?:put|enter|write|select|type)|example inputs?|sample inputs?|sample reason|example reason|give (?:me )?(?:an? )?example|help (?:me )?(?:with )?(?:this )?field|confused.*field|unsa(?:y| akong)? ibutang|unsay ibutang|ano(?:ng| ang)? ilalagay|paano fill|paunsa fill)\b/i;

const LOCATOR_TOPIC_PATTERN =
  /\b(locator|locator slip|pass slip|wfh|work from home|official business|ob request|ob|on field|field work|fieldwork|out of office|outside office|travel order)\b/i;

const LOCATOR_FORM_FIELDS = {
  slip_date: {
    title: 'Slip Date',
    aliases: [
      'slip date',
      'locator date',
      'date field',
      'request date',
      'what date',
      'unsa nga date',
      'unsa date',
      'ano date',
      'kanus-a',
    ],
    explanation:
      'Choose the workday the locator slip should cover. It must match a valid scheduled working day.',
    examples: ['Today if the activity is today', 'The exact workday you were out or on field'],
    note: 'Do not pick a rest day or holiday unless HR policy allows it for your case.',
  },
  locator_type: {
    title: 'Locator Type',
    aliases: [
      'locator type',
      'request type',
      'type field',
      'what locator type',
      'which locator type',
      'unsa nga locator type',
      'unsa nga type',
      'ano nga locator type',
      'unsay type',
    ],
    explanation:
      'Select the locator category that matches your actual activity, such as Official Business, Pass Slip, or Work From Home.',
    examples: [],
    note: 'Each type has different coverage and attachment rules. Pick the one that matches your real purpose.',
  },
  covered_slots: {
    title: 'Covered DTR Slots',
    aliases: [
      'covered slots',
      'covered slot',
      'dtr slots',
      'am in',
      'am out',
      'pm in',
      'pm out',
      'time in slot',
      'time out slot',
      'unsa slots',
      'unsa slot',
      'ano slots',
      'which slots',
    ],
    explanation:
      'Select the exact AM/PM time-in or time-out slots that the approved locator should cover in your DTR.',
    examples: ['AM In and AM Out only', 'PM In and PM Out for an afternoon activity'],
    note: 'Choose only the slots that truly need coverage. Do not select slots you actually logged on time.',
  },
  destination: {
    title: 'Office / Destination',
    aliases: [
      'destination field',
      'destination',
      'office field',
      'office',
      'location field',
      'location',
      'work location',
      'where field',
      'unsa ibutang sa destination',
      'unsay ibutang sa destination',
      'unsa ibutang sa office',
      'unsay ibutang sa location',
      'ano ilalagay sa destination',
      'ano ilalagay sa location',
      'asa ibutang',
      'saan ilalagay',
    ],
    explanation:
      'Enter the actual office, agency, client site, or work location related to the request.',
    examples: [],
    note: 'Use a real and specific place. Replace any sample text with your actual destination.',
  },
  reason: {
    title: 'Reason / Remarks',
    aliases: [
      'reason field',
      'locator reason',
      'remarks field',
      'remarks',
      'general reason',
      'what reason',
      'sample reason',
      'example reason',
      'sample locator reason',
      'example locator reason',
      'unsa ibutang sa reason',
      'unsay ibutang sa reason',
      'unsa isulat sa reason',
      'ano ilalagay sa reason',
      'ano isulat sa reason',
      'rason',
    ],
    explanation:
      'Write a short, clear official purpose that helps the reviewer understand why the locator is needed.',
    examples: [],
    note: 'Keep it truthful and work-related. Do not copy an example if it is not true for your request.',
  },
  attachment: {
    title: 'Attachment',
    aliases: [
      'attachment field',
      'attachment',
      'document field',
      'supporting document',
      'required attachment',
      'unsa attachment',
      'ano attachment',
      'sample attachment',
    ],
    explanation:
      'Upload the supporting document required by the selected locator type, if any.',
    examples: ['Official travel order', 'Meeting invitation or office memorandum'],
    note: 'Some locator types do not require an attachment. Check the selected type rule first.',
  },
};

function getLocatorFormFieldKey(message) {
  const text = String(message || '').toLowerCase();
  let best = null;
  let bestLength = 0;
  for (const [key, field] of Object.entries(LOCATOR_FORM_FIELDS)) {
    for (const alias of field.aliases) {
      if (!text.includes(alias) || alias.length <= bestLength) continue;
      best = key;
      bestLength = alias.length;
    }
  }
  return best;
}

function isLocatorFormFieldHelpQuestion(message) {
  const text = String(message || '');
  const hasLocatorTopic = LOCATOR_TOPIC_PATTERN.test(text);
  if (LOCATOR_GENERIC_FIELD_HELP_PATTERN.test(text) && hasLocatorTopic) return true;
  const fieldKey = getLocatorFormFieldKey(text);
  if (!fieldKey) return false;
  if (!hasLocatorTopic) {
    return /\b(locator|pass slip|wfh|official business|field work|fieldwork)\b/i.test(text);
  }
  return /\b(field|form|input|example|sample|put|enter|write|select|choose|fill|upload|attach|meaning|mean|confused|help|ibutang|ilalagay|isulat|sulat)\b/i.test(
    text
  );
}

function reasonExamplesForLocatorType(locatorTypeValue) {
  const examples = {
    locator: [
      'Attend coordination meeting at the Municipal Treasurer\'s Office',
      'Follow up payroll documents at the provincial office',
    ],
    work_from_home: [
      'Work-from-home due to approved office arrangement',
      'Remote work for assigned project tasks during inclement weather',
    ],
    pass_slip: [
      'Pass slip to attend an urgent personal matter for 2 hours',
      'Short official errand outside the office during work hours',
    ],
  };
  return examples[locatorTypeValue] || examples.locator;
}

function destinationExamplesForLocatorType(locatorTypeValue) {
  const examples = {
    locator: [
      'Municipal Engineering Office, Plaridel',
      'Provincial Capitol, Malolos',
    ],
    work_from_home: ['Home work location - Poblacion, Plaridel'],
    pass_slip: ['Municipal Health Office, Plaridel'],
  };
  return examples[locatorTypeValue] || examples.locator;
}

function getLocatorFormFieldGuidance(message, locatorTypeValue) {
  const key = getLocatorFormFieldKey(message);
  if (!key) return null;
  const field = LOCATOR_FORM_FIELDS[key];
  let examples = [...field.examples];
  if (key === 'reason') {
    examples = reasonExamplesForLocatorType(locatorTypeValue);
  } else if (key === 'destination') {
    examples = destinationExamplesForLocatorType(locatorTypeValue);
  }
  return {
    key,
    title: field.title,
    explanation: field.explanation,
    examples,
    note: field.note,
  };
}

module.exports = {
  getLocatorFormFieldGuidance,
  getLocatorFormFieldKey,
  isLocatorFormFieldHelpQuestion,
  LOCATOR_FORM_FIELDS,
  LOCATOR_TOPIC_PATTERN,
};
