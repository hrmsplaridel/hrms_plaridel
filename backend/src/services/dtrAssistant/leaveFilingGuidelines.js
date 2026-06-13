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

module.exports = {
  buildGuidelinesForTypes,
  getFormGuidanceForType,
  getLeaveGuidanceForType,
  getGuidelineSectionsForMessage,
  GUIDELINE_SECTIONS,
  summarizeLeaveGuidance,
};
