const DTR_POLICY_SECTIONS = [
  {
    key: 'daily_logs',
    title: 'Daily DTR Logs',
    aliases: [
      'dtr',
      'daily time',
      'attendance',
      'logs',
      'punch',
      'time in',
      'time out',
      'required logs',
      'missing logs',
      'kulang',
      'kuwang',
    ],
    points: [
      'Required DTR logs are based on the employee schedule for the selected date.',
      'A normal working day usually expects AM in, AM out, PM in, and PM out logs unless the schedule or holiday setup says otherwise.',
      'If a scheduled workday has no saved DTR row, HRMS treats it as a possible absent/no-record day for assistant review.',
    ],
  },
  {
    key: 'schedule_late_undertime',
    title: 'Schedule, Late, and Undertime',
    aliases: [
      'schedule',
      'shift',
      'late',
      'grace',
      'undertime',
      'overtime',
      'office hours',
      'duty',
      'pasok',
    ],
    points: [
      'Shift start, break times, shift end, and grace period come from the assigned schedule.',
      'Late minutes are checked against the scheduled start/break return plus the configured grace period.',
      'Undertime usually means the worked minutes or final time-out did not satisfy the scheduled duty requirement.',
    ],
  },
  {
    key: 'coverage',
    title: 'DTR Coverage',
    aliases: [
      'coverage',
      'cover',
      'covered',
      'leave',
      'locator',
      'holiday',
      'absent',
      'on leave',
      'on field',
    ],
    points: [
      'Approved leave, approved locator slips, holidays, and schedule/rest-day setup can explain why DTR logs are missing or marked differently.',
      'Pending leave or locator requests are not final DTR coverage until the required approvers finish the workflow.',
      'Locator coverage should match the exact missing slot, such as AM in, AM out, PM in, or PM out.',
    ],
  },
  {
    key: 'correction',
    title: 'DTR Correction',
    aliases: [
      'correction',
      'correct',
      'adjust',
      'manual',
      'fix',
      'proof',
      'evidence',
      'unsa buhaton',
      'ano gagawin',
    ],
    points: [
      'For missed punches, prepare the date, missing slot, actual work details, and proof or remarks for HR/Admin review.',
      'If the issue happened because of official business, WFH, or field work, check or file the matching locator slip instead of a manual punch correction.',
      'If the issue is caused by wrong schedule or holiday setup, HR/Admin should review the schedule or holiday calendar configuration.',
    ],
  },
  {
    key: 'export_review',
    title: 'DTR Export and Review',
    aliases: ['export', 'download', 'print', 'excel', 'pdf', 'report', 'review'],
    points: [
      'The assistant export can include saved DTR rows plus generated no-record scheduled workdays for review.',
      'Generated no-record workdays are assistant findings, not newly saved DTR rows.',
      'Final payroll or official DTR posting still depends on HR/Admin validation and the actual HRMS records.',
    ],
  },
];

const LOCATOR_POLICY_SECTIONS = [
  {
    key: 'types',
    title: 'Locator Types',
    aliases: [
      'type',
      'types',
      'kind',
      'kinds',
      'official business',
      'ob',
      'wfh',
      'work from home',
      'pass slip',
      'fieldwork',
    ],
    points: [
      'Available locator types come from the active HRMS locator type setup.',
      'Official Business or Locator is normally used for approved work outside the office or field duty.',
      'WFH and Pass Slip may have different labels, destination fields, attachment rules, and DTR coverage behavior depending on HRMS setup.',
    ],
  },
  {
    key: 'filing_requirements',
    title: 'Locator Filing Requirements',
    aliases: [
      'requirement',
      'requirements',
      'need',
      'needed',
      'kinahanglan',
      'kailangan',
      'how to file',
      'unsaon',
      'paano',
      'file',
      'filing',
      'attachment',
      'document',
      'docs',
    ],
    points: [
      'A locator slip needs a slip date, locator type, covered DTR slot or slots, destination/location, and reason.',
      'Attachment is required only when the selected locator type is configured to require it.',
      'The selected date should normally be a scheduled working day with required logs unless HR/Admin policy allows otherwise.',
    ],
  },
  {
    key: 'dtr_coverage',
    title: 'Locator DTR Coverage',
    aliases: [
      'coverage',
      'cover',
      'covered',
      'sakop',
      'am in',
      'am out',
      'pm in',
      'pm out',
      'missing log',
      'dtr',
    ],
    points: [
      'A locator slip helps DTR only after approval and only for the covered slots saved on the slip.',
      'For a missing PM out, the approved locator should cover PM out; for missing AM in, it should cover AM in.',
      'A pending, rejected, or cancelled locator is not final DTR coverage.',
    ],
  },
  {
    key: 'approval_workflow',
    title: 'Locator Approval Workflow',
    aliases: [
      'approval',
      'approve',
      'approved',
      'pending',
      'waiting',
      'holding',
      'review',
      'remarks',
      'reject',
      'rejected',
    ],
    points: [
      'Locator slips may pass through department head review and HR review before final approval.',
      'Reviewer remarks explain why a slip was returned or rejected when remarks were saved.',
      'If a slip is pending for a long time, follow up with the current reviewer shown in HRMS.',
    ],
  },
  {
    key: 'filing_checks',
    title: 'Locator Filing Checks',
    aliases: [
      'allowed',
      'eligible',
      'pwede',
      'puwede',
      'can i file',
      'duplicate',
      'overlap',
      'holiday',
      'rest day',
      'schedule',
    ],
    points: [
      'Before filing, check if the date is a working day, holiday, rest day, or already covered by another approved request.',
      'Choose the locator type that matches what actually happened: official business, WFH, pass slip, or another active type.',
      'The assistant can do an initial check, but final approval still follows the normal HRMS workflow.',
    ],
  },
];

function lower(value) {
  return String(value || '').toLowerCase();
}

function cleanSection(section) {
  return {
    key: section.key,
    title: section.title,
    aliases: [...section.aliases],
    points: [...section.points],
  };
}

function sectionsForMessage(sections, message, fallbackKeys = []) {
  const text = lower(message);
  const selected = sections.filter((section) => {
    return section.aliases.some((alias) => text.includes(alias));
  });
  if (selected.length > 0) return selected.map(cleanSection);
  const fallback = sections.filter((section) => fallbackKeys.includes(section.key));
  return fallback.map(cleanSection);
}

function policyPointLines(sections, { maxPointsPerSection = 2 } = {}) {
  return (sections || []).flatMap((section) => {
    return section.points
      .slice(0, maxPointsPerSection)
      .map((point) => `${section.title}: ${point}`);
  });
}

function getDtrPolicySectionsForMessage(message, options = {}) {
  return sectionsForMessage(
    DTR_POLICY_SECTIONS,
    message,
    options.fallbackKeys || ['daily_logs', 'coverage', 'correction']
  );
}

function getLocatorPolicySectionsForMessage(message, options = {}) {
  return sectionsForMessage(
    LOCATOR_POLICY_SECTIONS,
    message,
    options.fallbackKeys || ['filing_requirements', 'dtr_coverage', 'approval_workflow']
  );
}

function buildDtrPolicyKnowledge() {
  return DTR_POLICY_SECTIONS.map(cleanSection);
}

function buildLocatorPolicyKnowledge() {
  return LOCATOR_POLICY_SECTIONS.map(cleanSection);
}

module.exports = {
  buildDtrPolicyKnowledge,
  buildLocatorPolicyKnowledge,
  getDtrPolicySectionsForMessage,
  getLocatorPolicySectionsForMessage,
  policyPointLines,
};
