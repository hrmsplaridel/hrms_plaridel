const GUIDELINES = {
  vacationLeave: {
    description:
      'Granted to employees for personal recreation, rest, or travel. Must be applied for in advance and is subject to approval.',
    requirements:
      'No documentary requirement. Indicate location, whether within the Philippines or abroad.',
    advanceFiling: 'File at least 5 days before the intended leave date.',
  },
  mandatoryForcedLeave: {
    description:
      'All officials and employees are required to go on vacation leave for at least 5 working days annually.',
    requirements: 'No documentary requirement.',
    limits: 'Mandatory 5 working days per year.',
    notes:
      'If unused within the year, HR/Admin may apply a year-end deduction against vacation leave credits.',
  },
  sickLeave: {
    description:
      'Granted when an employee is unable to report due to personal illness, injury, or medical appointment.',
    requirements:
      'Medical certificate required if the absence is 5 or more consecutive days, or at the discretion of the head of office.',
    advanceFiling: 'Apply immediately upon return or during absence if possible.',
  },
  maternityLeave: {
    description:
      'Granted to female employees for childbirth or miscarriage, both married and unmarried.',
    requirements:
      'Medical certificate or birth/delivery record. Marriage certificate if applicable. Notify your agency before the expected delivery.',
    limits:
      'Normal delivery: up to 105 working days. Caesarean section: up to 115 working days.',
    advanceFiling:
      'Notify your supervisor at least 30 days before the expected delivery date.',
    notes: 'Covers normal delivery, caesarean section, and miscarriage.',
  },
  paternityLeave: {
    description:
      'Granted to married male employees upon the delivery/miscarriage of their legitimate spouse.',
    requirements:
      'Marriage certificate. Birth certificate or medical records showing delivery/miscarriage.',
    limits: '7 working days; must be availed within 60 days of delivery.',
    advanceFiling: 'Notify HR prior or immediately after the event.',
  },
  specialPrivilegeLeave: {
    description:
      'Granted for personal milestones and special occasions such as birthdays, weddings, or hospitalization of immediate family.',
    requirements: 'No documentary requirement. State location/occasion.',
    limits: '3 days per year, non-cumulative.',
    advanceFiling: 'File in advance when possible.',
  },
  soloParentLeave: {
    description:
      'Granted to solo parents as defined by RA 8972 for parental obligations.',
    requirements:
      'Solo Parent ID or DSWD-issued certificate. Submit to HR before or after availing the leave.',
    limits: '7 working days per year.',
  },
  studyLeave: {
    description:
      'Granted to pursue higher education or review for licensure exams, with prior approval and service obligation after completion.',
    requirements:
      'Written request citing the course/exam. School enrollment certificate or review program documents. Agency head approval required.',
    limits: 'Maximum 6 months or 180 working days. Service obligation applies after.',
    advanceFiling: 'Apply well in advance because agency head approval is required.',
  },
  tenDayVawcLeave: {
    description:
      'Granted to women employees who are victims of Violence Against Women and Children under RA 9262.',
    requirements:
      'Barangay Protection Order, Court order, or any certified government-issued document confirming the VAWC situation.',
    limits: '10 days per year; may be extended as deemed necessary by the agency.',
  },
  rehabilitationPrivilege: {
    description:
      'Granted to employees who suffered injuries while in the performance of official duties.',
    requirements:
      'Medical certificate showing the injury and its direct connection to official duties. Incident/accident report endorsed by the head of office.',
    limits: 'Up to 6 months or 180 working days.',
    notes: 'Available only for work-related injuries, not personal accidents.',
  },
  specialLeaveBenefitsForWomen: {
    description:
      'Granted to female employees who undergo surgery caused by gynecological disorders under RA 9710.',
    requirements:
      'Medical certificate from a licensed physician confirming the gynecological disorder and necessity of the operation.',
    limits: 'Maximum 60 days, non-cumulative.',
    advanceFiling: 'Apply before or immediately after the procedure.',
  },
  specialEmergencyCalamityLeave: {
    description:
      "Granted when an employee's residence is within a declared calamity area or the employee must attend to immediate family needs due to calamity.",
    requirements:
      'Certification from the Barangay/LDRRMO or NDRRMC that the area is under calamity. Proof of residency in the affected area.',
    limits: '5 working days per calamity incident.',
  },
  adoptionLeave: {
    description:
      'Granted to adoptive parents upon finalization of the adoption decree under RA 8552.',
    requirements:
      'Court order / Adoption decree. Certified copy of the Certificate of Finality.',
    limits: '60 working days for the adoptive mother; 7 working days for the adoptive father.',
  },
  others: {
    description:
      'Other leave types not covered by the standard categories. Include complete details in the reason/remarks field.',
    requirements:
      'Provide supporting documents as applicable to the specific circumstance.',
    notes: 'Your supervisor and HR will review and determine applicable rules.',
  },
};

const GUIDELINE_DISPLAY_NAMES = {
  vacationLeave: 'Vacation Leave',
  mandatoryForcedLeave: 'Mandatory/Forced Leave',
  sickLeave: 'Sick Leave',
  maternityLeave: 'Maternity Leave',
  paternityLeave: 'Paternity Leave',
  specialPrivilegeLeave: 'Special Privilege Leave',
  soloParentLeave: 'Solo Parent Leave',
  studyLeave: 'Study Leave',
  tenDayVawcLeave: '10-Day VAWC Leave',
  rehabilitationPrivilege: 'Rehabilitation Privilege',
  specialLeaveBenefitsForWomen: 'Special Leave Benefits for Women',
  specialEmergencyCalamityLeave: 'Special Emergency/Calamity Leave',
  adoptionLeave: 'Adoption Leave',
  others: 'Others',
};

const ALIASES = {
  vacationleave: 'vacationLeave',
  vacation: 'vacationLeave',
  vl: 'vacationLeave',
  mandatoryforcedleave: 'mandatoryForcedLeave',
  mandatoryleave: 'mandatoryForcedLeave',
  forcedleave: 'mandatoryForcedLeave',
  sickleave: 'sickLeave',
  sick: 'sickLeave',
  sl: 'sickLeave',
  maternityleave: 'maternityLeave',
  maternity: 'maternityLeave',
  paternityleave: 'paternityLeave',
  paternity: 'paternityLeave',
  specialprivilegeleave: 'specialPrivilegeLeave',
  specialprivilege: 'specialPrivilegeLeave',
  soloparentleave: 'soloParentLeave',
  soloparent: 'soloParentLeave',
  studyleave: 'studyLeave',
  study: 'studyLeave',
  tendayvawcleave: 'tenDayVawcLeave',
  vawcleave: 'tenDayVawcLeave',
  vawc: 'tenDayVawcLeave',
  rehabilitationprivilege: 'rehabilitationPrivilege',
  rehabilitation: 'rehabilitationPrivilege',
  specialleavebenefitsforwomen: 'specialLeaveBenefitsForWomen',
  specialleavewomen: 'specialLeaveBenefitsForWomen',
  specialemergencycalamityleave: 'specialEmergencyCalamityLeave',
  calamityleave: 'specialEmergencyCalamityLeave',
  calamity: 'specialEmergencyCalamityLeave',
  adoptionleave: 'adoptionLeave',
  adoption: 'adoptionLeave',
  others: 'others',
};

const GUIDELINE_SECTIONS = [
  {
    key: 'general_rules',
    title: 'General Rules',
    aliases: ['general', 'general rules', 'basic rules', 'filing rules'],
    points: [
      'Leave is subject to supervisor/department head and HR approval.',
      'Approved leave dates are used by HRMS when updating DTR and leave balances.',
      'Employees should provide accurate dates, number of days, reason, and required documents.',
    ],
  },
  {
    key: 'filing_deadlines',
    title: 'Filing Deadlines',
    aliases: ['deadline', 'deadlines', 'filing deadline', 'advance', 'before filing'],
    points: [
      'Vacation leave is normally filed in advance; HRMS leave type rules may require a minimum advance notice.',
      'Sick leave may be filed during the absence or immediately upon return when advance filing is not practical.',
      'Late or past-date filing depends on the configured leave type rule and HR review.',
    ],
  },
  {
    key: 'supporting_documents',
    title: 'Supporting Documents',
    aliases: ['supporting', 'supporting documents', 'attachments', 'attachment', 'documents', 'docs'],
    points: [
      'Sick leave normally needs a medical certificate for 5 or more consecutive days, or when required by the head of office.',
      'Maternity, paternity, solo parent, VAWC, calamity, rehabilitation, adoption, and special women leave commonly need supporting documents.',
      'The exact attachment requirement still follows the active HRMS leave type configuration.',
    ],
  },
  {
    key: 'credits_limits',
    title: 'Leave Credits & Limits',
    aliases: ['credits', 'leave credits', 'limits', 'maximum', 'max', 'balance'],
    points: [
      'Vacation and sick leave normally use earned leave credits and reduce available balance after approval/posting.',
      'Some special leave types have annual or per-incident limits and may not use the same balance ledger.',
      'Pending leave may reduce the available balance shown before final approval.',
    ],
  },
  {
    key: 'commutation_monetization',
    title: 'Commutation & Monetization',
    aliases: ['commutation', 'monetization', 'monetisation', 'terminal leave', 'cash'],
    points: [
      'Commutation, monetization, and terminal leave are handled by HR/Admin policies and are not the same as ordinary leave filing.',
      'The assistant can explain records shown in HRMS, but HR/Admin should confirm payout-related requests.',
    ],
  },
];

const FORM_FIELD_GUIDANCE = {
  vacationLeave: [
    'Select Vacation Leave.',
    'Enter start date, end date, and number of days.',
    'Indicate whether the leave is within the Philippines or abroad, then add the location/reason.',
  ],
  mandatoryForcedLeave: [
    'Select Mandatory/Forced Leave if available for employee filing.',
    'Enter the covered dates and number of days.',
    'Confirm with HR if the schedule is office-assigned or year-end compliance related.',
  ],
  sickLeave: [
    'Select Sick Leave.',
    'Enter the absence dates and number of days.',
    'State whether it is in-hospital, outpatient, medical appointment, or recovery.',
    'Attach a medical certificate when required, especially for 5 or more consecutive days.',
  ],
  maternityLeave: [
    'Select Maternity Leave.',
    'Enter expected/actual delivery or miscarriage date and covered leave dates.',
    'Indicate delivery classification when applicable, such as normal delivery or caesarean section.',
    'Attach medical certificate, birth/delivery record, or related documents required by HR.',
  ],
  paternityLeave: [
    'Select Paternity Leave.',
    'Enter the spouse delivery/miscarriage date and requested covered dates.',
    'Attach marriage certificate plus birth certificate or medical record when required.',
  ],
  specialPrivilegeLeave: [
    'Select Special Privilege Leave.',
    'Enter covered dates, number of days, and occasion/reason.',
    'State the location or occasion clearly.',
  ],
  soloParentLeave: [
    'Select Solo Parent Leave.',
    'Enter covered dates and reason related to parental obligation.',
    'Attach Solo Parent ID or DSWD-issued certificate when required.',
  ],
  studyLeave: [
    'Select Study Leave.',
    'Enter covered dates and purpose, such as course, review, or exam.',
    'Attach enrollment/review documents and secure required agency approval.',
  ],
  tenDayVawcLeave: [
    'Select 10-Day VAWC Leave.',
    'Enter covered dates and supporting reason.',
    'Attach a Barangay Protection Order, court order, or certified government document when required.',
  ],
  rehabilitationPrivilege: [
    'Select Rehabilitation Privilege.',
    'Enter injury/incident date and covered rehabilitation dates.',
    'Attach medical certificate and incident/accident report endorsed by the office.',
  ],
  specialLeaveBenefitsForWomen: [
    'Select Special Leave Benefits for Women.',
    'Enter surgery/procedure date and covered leave dates.',
    'Attach medical certificate confirming the gynecological disorder and operation.',
  ],
  specialEmergencyCalamityLeave: [
    'Select Special Emergency/Calamity Leave.',
    'Enter calamity date, covered dates, and affected location.',
    'Attach barangay/LDRRMO/NDRRMC certification or proof of residency when required.',
  ],
  adoptionLeave: [
    'Select Adoption Leave.',
    'Enter covered dates tied to adoption finalization.',
    'Attach court order/adoption decree and Certificate of Finality when required.',
  ],
  others: [
    'Select the applicable Other Leave type.',
    'Enter complete dates, number of days, and detailed reason.',
    'Attach supporting documents that match the circumstance.',
  ],
};

const LEAVE_FORM_FIELDS = {
  leave_type: {
    title: 'Leave Type',
    aliases: [
      'leave type',
      'type of leave',
      'select leave',
      'which leave',
      'unsa nga leave',
      'unsang leave',
      'anong leave',
    ],
    explanation:
      'Choose the leave category that matches the real purpose of your absence.',
    examples: ['Vacation Leave for planned personal travel', 'Sick Leave for illness or a medical appointment'],
    note: 'Do not choose a different type only because it has more available credits.',
  },
  custom_leave_type: {
    title: 'Specify Other Leave Type',
    aliases: [
      'custom leave type',
      'other leave type',
      'specify other',
      'others field',
      'other type',
    ],
    explanation:
      'Enter the exact authorized leave name when the correct category is not in the standard list.',
    examples: ['Other authorized leave - [name stated in the office memorandum]'],
    note: 'Use the official name from the applicable memo or ask HR before submitting.',
  },
  dates: {
    title: 'Start Date and End Date',
    aliases: [
      'start date',
      'end date',
      'date field',
      'dates field',
      'dates of leave',
      'covered dates',
      'leave dates',
      'petsa',
      'date sa leave',
    ],
    explanation:
      'Select the first and last calendar dates covered by your leave request.',
    examples: ['Start Date: July 6, 2026; End Date: July 7, 2026'],
    note: 'Use your actual intended dates. The system calculates applicable working days from the selected range.',
  },
  working_days: {
    title: 'Number of Working Days Applied For',
    aliases: [
      'working days',
      'number of days',
      'days applied',
      'pila ka adlaw',
      'ilang araw',
      'day count',
    ],
    explanation:
      'This is the number of scheduled working days covered by the selected dates.',
    examples: ['A Monday-to-Tuesday request may show 2 working days if both are scheduled workdays'],
    note: 'This field is computed by HRMS. Change the dates instead of manually guessing the value.',
  },
  reason: {
    title: 'General Reason / Remarks',
    aliases: [
      'reason field',
      'remarks field',
      'general reason',
      'reason or remarks',
      'what reason',
      'sample reason',
      'example reason',
      'unsa ibutang sa reason',
      'unsay ibutang sa reason',
      'ano ilalagay sa reason',
      'rason',
    ],
    explanation:
      'Write a short, truthful explanation that helps the reviewer understand why the leave is needed.',
    examples: [],
    note: 'Avoid unnecessary private medical details. Never copy an example if it is not true for your request.',
  },
  location_option: {
    title: 'Location Option',
    aliases: [
      'location option',
      'within philippines',
      'abroad option',
      'country option',
      'local or abroad',
    ],
    explanation:
      'Choose whether the leave destination is within the Philippines or abroad.',
    examples: ['Within Philippines for Cebu City', 'Abroad for Tokyo, Japan'],
    note: 'Choose the option that matches your actual destination.',
  },
  location_details: {
    title: 'Specify Location',
    aliases: [
      'location field',
      'location details',
      'specify location',
      'location sa leave form',
      'location ng leave form',
      'sample location',
      'example location',
      'destination field',
      'place field',
      'asa nga lugar',
      'unsay ibutang sa location',
      'ano ilalagay sa location',
    ],
    explanation:
      'Enter a clear city, municipality, province, or country for the planned leave.',
    examples: ['Cebu City, Cebu', 'Tokyo, Japan'],
    note: 'Use the actual destination; a complete home address is usually unnecessary unless HR specifically requires it.',
  },
  sick_nature: {
    title: 'Nature of Illness',
    aliases: [
      'nature of illness',
      'in hospital',
      'out patient',
      'outpatient',
      'sick nature',
      'illness option',
    ],
    explanation:
      'Choose In Hospital only for hospital confinement; otherwise choose Out Patient for consultation, treatment, or home recovery.',
    examples: ['Out Patient for a clinic consultation', 'In Hospital for admitted confinement'],
    note: 'Choose the option that matches what actually happened.',
  },
  illness_details: {
    title: 'Specify Illness Details',
    aliases: [
      'illness details',
      'illness field',
      'sickness details',
      'medical details',
      'diagnosis field',
      'unsa ibutang sa illness',
      'ano ilalagay sa illness',
    ],
    explanation:
      'Briefly state the illness, treatment, consultation, or recovery reason relevant to the absence.',
    examples: ['Fever and medical consultation', 'Recovery after an outpatient procedure'],
    note: 'Keep it accurate and concise. Attach a medical certificate when the configured rule requires one.',
  },
  expected_delivery_date: {
    title: 'Expected Delivery Date',
    aliases: ['expected delivery date', 'due date', 'maternity date', 'expected delivery'],
    explanation:
      'Enter the expected delivery date stated by your physician or medical record.',
    examples: ['Expected Delivery Date: August 20, 2026'],
    note: 'Use the date from your medical document, not an estimated date you made yourself.',
  },
  maternity_classification: {
    title: 'Maternity Leave Classification',
    aliases: [
      'maternity classification',
      'delivery classification',
      'normal delivery',
      'caesarean',
      'cesarean',
      'c section',
    ],
    explanation:
      'Select Normal Delivery or Caesarean Section based on the applicable medical record.',
    examples: ['Normal Delivery', 'Caesarean Section'],
    note: 'Choose the classification supported by your medical document.',
  },
  child_delivery_date: {
    title: 'Child Delivery / Miscarriage Date',
    aliases: [
      'child delivery date',
      'delivery miscarriage date',
      'miscarriage date',
      'paternity date',
      'spouse delivery date',
    ],
    explanation:
      'Enter the actual delivery or miscarriage date shown in the supporting record.',
    examples: ['Child Delivery Date: July 2, 2026'],
    note: 'Paternity leave timing is checked from this date.',
  },
  accident_date: {
    title: 'Accident Date',
    aliases: ['accident date', 'incident date', 'rehabilitation date', 'injury date'],
    explanation:
      'Enter the date of the work-related accident or injury covered by the rehabilitation request.',
    examples: ['Accident Date: June 24, 2026'],
    note: 'The incident should match the accident report and medical document.',
  },
  calamity_date: {
    title: 'Calamity / Disaster Occurrence Date',
    aliases: [
      'calamity date',
      'disaster date',
      'occurrence date',
      'emergency date',
    ],
    explanation:
      'Enter the date the calamity or disaster occurred and affected your residence or immediate family.',
    examples: ['Calamity Occurrence Date: June 23, 2026'],
    note: 'Use the date supported by the barangay or disaster-risk document when required.',
  },
  women_illness_details: {
    title: 'Special Leave Benefits for Women - Illness Details',
    aliases: [
      'women illness details',
      'gynecological details',
      'women leave illness',
      'special women details',
    ],
    explanation:
      'Briefly identify the gynecological condition or procedure relevant to the request.',
    examples: ['Recovery after a medically advised gynecological procedure'],
    note: 'Use wording consistent with the medical certificate and avoid unnecessary sensitive detail.',
  },
  study_purpose: {
    title: 'Purpose of Study Leave',
    aliases: [
      'study purpose',
      'purpose of study leave',
      'masters degree',
      'board examination',
      'bar examination',
      'study option',
    ],
    explanation:
      'Choose the option that matches the approved study activity.',
    examples: ["Completion of Master's Degree", 'BAR / Board Examination Review'],
    note: 'Your supporting school or review documents should match the selected purpose.',
  },
  study_details: {
    title: 'Specify Study Leave Details',
    aliases: [
      'study details',
      'study leave details',
      'school details',
      'review details',
      'course details',
    ],
    explanation:
      'Enter the school, degree, examination, or review program connected to the request.',
    examples: ['Master of Public Administration thesis completion at [school name]', 'Civil Service examination review at [review center]'],
    note: 'Replace bracketed text with your truthful details.',
  },
  attachment: {
    title: 'Supporting Attachment',
    aliases: [
      'attachment',
      'attachment field',
      'attachment to upload',
      'file to attach',
      'file i attach',
      'i attach',
      'upload field',
      'upload',
      'supporting attachment',
      'supporting document field',
      'what file',
      'unsa nga file',
      'anong file',
    ],
    explanation:
      'Upload the document required by the selected leave type and requested duration.',
    examples: ['Medical certificate for qualifying sick leave', 'Birth or delivery record for maternity leave'],
    note: 'Use a readable PDF, JPG, or PNG and make sure the document belongs to your actual request.',
  },
  commutation: {
    title: 'Requested Commutation of Leave',
    aliases: [
      'commutation',
      'commutation leave',
      'commutation field',
      'requested commutation',
      'commutation checkbox',
      'commute leave',
      'cash leave',
      'monetization field',
    ],
    explanation:
      'Checking this box marks the leave request as also asking HR/Admin to consider commutation under office policy.',
    examples: [
      'Leave it unchecked for an ordinary leave absence request',
      'Check it only when HR has instructed you to request commutation',
    ],
    note: 'It does not automatically approve the leave, convert credits to cash, or guarantee payment. HR/Admin still reviews the request and applicable policy.',
  },
};

const GENERIC_FIELD_HELP_PATTERN =
  /\b(what (?:do|should|can) i (?:put|enter|write|select|type)|what to (?:put|enter|write|select|type)|example inputs?|sample inputs?|sample reason|example reason|give (?:me )?(?:an? )?example|help (?:me )?(?:with )?(?:this )?field|confused.*field|unsa(?:y| akong)? ibutang|ano(?:ng| ang)? ilalagay|paano fill|paunsa fill)\b/i;

function normalize(value) {
  return String(value || '').toLowerCase().replace(/[^a-z0-9]+/g, '');
}

function guidelineKeyForType(typeRecordOrValue) {
  if (!typeRecordOrValue) return null;
  if (typeof typeRecordOrValue === 'string') {
    return ALIASES[normalize(typeRecordOrValue)] || null;
  }

  const candidates = [
    typeRecordOrValue.name,
    typeRecordOrValue.display_name,
    typeRecordOrValue.description,
  ];
  for (const candidate of candidates) {
    const key = ALIASES[normalize(candidate)];
    if (key) return key;
  }
  return null;
}

function getLeaveGuidanceForType(typeRecordOrValue) {
  const key = guidelineKeyForType(typeRecordOrValue);
  if (!key) return null;
  const guidance = GUIDELINES[key];
  return guidance ? { key, ...guidance } : null;
}

function summarizeLeaveGuidance(guidance, options = {}) {
  if (!guidance) return null;
  const parts = [];
  if (options.includeDescription !== false && guidance.description) {
    parts.push(guidance.description);
  }
  if (guidance.requirements) parts.push(`Guideline requirements: ${guidance.requirements}`);
  if (guidance.limits) parts.push(`Limit: ${guidance.limits}`);
  if (guidance.advanceFiling) parts.push(`Filing: ${guidance.advanceFiling}`);
  if (guidance.notes) parts.push(`Note: ${guidance.notes}`);
  return parts.join(' ');
}

function getGuidelineSectionsForMessage(message) {
  const text = String(message || '').toLowerCase();
  const selected = GUIDELINE_SECTIONS.filter((section) => {
    return section.aliases.some((alias) => text.includes(alias));
  });
  return selected.length > 0 ? selected : [];
}

function getFormGuidanceForType(typeRecordOrValue) {
  const key = guidelineKeyForType(typeRecordOrValue) || 'others';
  return {
    key,
    fields: FORM_FIELD_GUIDANCE[key] || FORM_FIELD_GUIDANCE.others,
  };
}

function getLeaveFormFieldKey(message) {
  const text = String(message || '').toLowerCase();
  let best = null;
  let bestLength = 0;
  for (const [key, field] of Object.entries(LEAVE_FORM_FIELDS)) {
    for (const alias of field.aliases) {
      if (!text.includes(alias) || alias.length <= bestLength) continue;
      best = key;
      bestLength = alias.length;
    }
  }
  return best;
}

function isLeaveFormFieldHelpQuestion(message) {
  const text = String(message || '');
  if (GENERIC_FIELD_HELP_PATTERN.test(text)) return true;
  const fieldKey = getLeaveFormFieldKey(text);
  if (!fieldKey) return false;
  if (
    fieldKey === 'commutation' &&
    /\b(what is|what's|what does|meaning|mean|happen|check|checked|checking|checkbox|tick|ticked|request|requested|enable|enabled|turn on|cash|paid|payment|pay|bayad|mabayran)\b/i.test(
      text
    )
  ) {
    return true;
  }
  return /\b(field|form|input|example|sample|put|enter|write|select|choose|fill|upload|attach|meaning|mean|confused|help|ibutang|ilalagay|sagutan)\b/i.test(
    text
  );
}

function reasonExamplesForType(typeRecordOrValue) {
  const key = guidelineKeyForType(typeRecordOrValue);
  const examples = {
    vacationLeave: [
      'Personal travel and rest in Cebu City',
      'Family vacation within the Philippines',
    ],
    mandatoryForcedLeave: ['Scheduled mandatory leave under the approved office leave calendar'],
    sickLeave: [
      'Medical consultation and recovery due to illness',
      'Rest and recovery as advised after an outpatient consultation',
    ],
    maternityLeave: ['Maternity leave for childbirth and post-delivery recovery'],
    paternityLeave: ['Paternity leave following the delivery of my spouse'],
    specialPrivilegeLeave: ['Attendance at an immediate family wedding', 'Personal milestone leave'],
    soloParentLeave: ['Attendance to an important parental obligation'],
    studyLeave: ['Preparation and review for the scheduled board examination'],
    tenDayVawcLeave: ['Leave request under RA 9262 with the required supporting document'],
    rehabilitationPrivilege: ['Rehabilitation and recovery from a work-related injury'],
    specialLeaveBenefitsForWomen: ['Recovery after a medically advised gynecological procedure'],
    specialEmergencyCalamityLeave: ['Immediate family and residence needs following the declared calamity'],
    adoptionLeave: ['Adoption leave following finalization of the adoption decree'],
    others: ['Authorized leave under [office memorandum or applicable policy]'],
  };
  return examples[key] || examples.others;
}

function getLeaveFormFieldGuidance(message, typeRecordOrValue) {
  const key = getLeaveFormFieldKey(message);
  if (!key) return null;
  const field = LEAVE_FORM_FIELDS[key];
  return {
    key,
    title: field.title,
    explanation: field.explanation,
    examples: key === 'reason' ? reasonExamplesForType(typeRecordOrValue) : [...field.examples],
    note: field.note,
  };
}

function buildGuidelinesForTypes(typeRecords = []) {
  return typeRecords
    .map((type) => {
      const guidance = getLeaveGuidanceForType(type);
      if (!guidance) return null;
      return {
        leave_type: type.display_name || type.name,
        key: guidance.key,
        description: guidance.description,
        requirements: guidance.requirements,
        limits: guidance.limits || null,
        advanceFiling: guidance.advanceFiling || null,
        notes: guidance.notes || null,
      };
    })
    .filter(Boolean);
}

function buildAllLeaveGuidelines() {
  return Object.entries(GUIDELINES).map(([key, guidance]) => ({
    leave_type: GUIDELINE_DISPLAY_NAMES[key] || key,
    key,
    description: guidance.description,
    requirements: guidance.requirements,
    limits: guidance.limits || null,
    advanceFiling: guidance.advanceFiling || null,
    notes: guidance.notes || null,
  }));
}

module.exports = {
  buildAllLeaveGuidelines,
  buildGuidelinesForTypes,
  getFormGuidanceForType,
  getLeaveFormFieldGuidance,
  getLeaveFormFieldKey,
  getLeaveGuidanceForType,
  getGuidelineSectionsForMessage,
  isLeaveFormFieldHelpQuestion,
  GUIDELINE_SECTIONS,
  LEAVE_FORM_FIELDS,
  summarizeLeaveGuidance,
};
