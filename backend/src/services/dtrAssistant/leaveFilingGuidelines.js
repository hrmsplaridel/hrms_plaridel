const GUIDELINES = {
  vacationLeave: {
    description:
      'Granted to employees for personal recreation, rest, or travel. Must be applied for in advance and is subject to approval.',
    requirements:
      'No documentary requirement, but HRMS requires the location option and specific location/details.',
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
      'Choose In Hospital or Out Patient and enter illness details. Medical certificate required if the absence is 5 or more consecutive days, or at the discretion of the head of office.',
    advanceFiling: 'Apply immediately upon return or during absence if possible.',
  },
  maternityLeave: {
    description:
      'Granted to female employees for childbirth or miscarriage, both married and unmarried.',
    requirements:
      'Expected delivery date, maternity classification, and supporting attachment are required. Use the date and classification from the medical record.',
    limits:
      'Normal delivery: up to 105 working days. Caesarean section: up to 115 working days.',
    advanceFiling:
      'HRMS blocks submission if filed less than 30 days before the expected delivery date.',
    notes: 'Covers normal delivery, caesarean section, and miscarriage.',
  },
  paternityLeave: {
    description:
      'Granted to married male employees upon the delivery/miscarriage of their legitimate spouse.',
    requirements:
      'Child delivery or miscarriage date and supporting attachment are required, such as marriage certificate plus birth certificate or medical record.',
    limits:
      '7 working days. HRMS blocks requests that start before the child delivery date or end more than 60 days from delivery.',
    advanceFiling: 'Notify HR prior or immediately after the event.',
  },
  specialPrivilegeLeave: {
    description:
      'Granted for personal milestones and special occasions such as birthdays, weddings, or hospitalization of immediate family.',
    requirements:
      'No documentary requirement, but HRMS requires the location option and specific location/details.',
    limits: '3 days per year, non-cumulative.',
    advanceFiling: 'File at least 7 days before the intended leave date.',
  },
  soloParentLeave: {
    description:
      'Granted to solo parents as defined by RA 8972 for parental obligations.',
    requirements:
      'Solo Parent ID number, Solo Parent ID expiry date, and supporting attachment are required.',
    limits:
      '7 working days per year. HRMS counts pending plus approved requests and requires the Solo Parent ID to be valid through the leave start date.',
    advanceFiling: 'File at least 5 days before the intended leave date.',
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
      'Supporting attachment, supporting document type, and case/protection order details are required.',
    limits:
      '10 working days per year. HRMS counts pending plus approved requests for the annual cap.',
  },
  rehabilitationPrivilege: {
    description:
      'Granted to employees who suffered injuries while in the performance of official duties.',
    requirements:
      'Medical certificate showing the injury and its direct connection to official duties. Incident/accident report endorsed by the head of office.',
    limits: 'Up to 6 months or 180 working days.',
    notes:
      'Available only for work-related injuries, not personal accidents. HRMS requires the accident date and blocks filing more than 1 week after the accident.',
  },
  specialLeaveBenefitsForWomen: {
    description:
      'Granted to female employees who undergo surgery caused by gynecological disorders under RA 9710.',
    requirements:
      'Illness/procedure details and medical certificate from a licensed physician confirming the gynecological disorder and necessity of the operation.',
    limits: 'Maximum 60 days, non-cumulative.',
    advanceFiling: 'Apply before or immediately after the procedure.',
  },
  specialEmergencyCalamityLeave: {
    description:
      "Granted when an employee's residence is within a declared calamity area or the employee must attend to immediate family needs due to calamity.",
    requirements:
      'Calamity/disaster occurrence date, affected location, and supporting certification from Barangay/LDRRMO/NDRRMC or proof of residency.',
    limits:
      '5 working days per calamity incident. HRMS blocks requests that start before the calamity date or end more than 30 days from the calamity.',
  },
  adoptionLeave: {
    description:
      'Granted to adoptive parents upon finalization of the adoption decree under RA 8552.',
    requirements:
      'PAPA/adoption placement date, adoption leave eligibility role, and supporting attachment are required.',
    limits:
      '60 working days for the adoptive mother or single male adopter; 7 working days for the legitimate male spouse. HRMS blocks requests that start before the placement date.',
  },
  others: {
    description:
      'Other leave types not covered by the standard categories. Include complete details in the reason/remarks field.',
    requirements:
      'Provide supporting documents as applicable to the specific circumstance.',
    notes:
      'Your supervisor and HR will review and determine applicable rules. Monetization of Leave Credits and Terminal Leave are HR/admin processes only.',
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
      'Employees should provide accurate dates, number of days, reason, required form details, and required documents.',
    ],
  },
  {
    key: 'filing_deadlines',
    title: 'Filing Deadlines',
    aliases: ['deadline', 'deadlines', 'filing deadline', 'advance', 'before filing'],
    points: [
      'Vacation leave is normally filed in advance; HRMS leave type rules may require a minimum advance notice.',
      'Sick leave may be filed during the absence or immediately upon return when advance filing is not practical.',
      'HRMS hard-blocks some timing rules, such as maternity 30-day notice, paternity 60-day window, adoption placement-date start, calamity 30-day use, and rehabilitation filing within 1 week from accident.',
    ],
  },
  {
    key: 'supporting_documents',
    title: 'Supporting Documents',
    aliases: ['supporting', 'supporting documents', 'attachments', 'attachment', 'documents', 'docs'],
    points: [
      'Sick leave normally needs a medical certificate for 5 or more consecutive days, or when required by the head of office.',
      'Maternity, paternity, solo parent, VAWC, calamity, rehabilitation, adoption, and special women leave commonly need supporting documents.',
      'Some leave types also require form details before submission, such as location, illness nature, delivery date, placement date, VAWC case details, or Solo Parent ID validity.',
    ],
  },
  {
    key: 'credits_limits',
    title: 'Leave Credits & Limits',
    aliases: [
      'credits',
      'leave credits',
      'monthly credits',
      'monthly accrual',
      'earned credits',
      'earned leave',
      '1.25',
      '1.250',
      'limits',
      'maximum',
      'max',
      'balance',
    ],
    points: [
      'Vacation and sick leave earn 1.250 days per month through monthly accrual when the employee is leave-credit eligible and has an active assignment for the month.',
      'Monthly accrual does not require a shift and does not check employment type in the current HRMS rule.',
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
    'Choose the location option, then enter the specific location/details.',
  ],
  mandatoryForcedLeave: [
    'Select Mandatory/Forced Leave if available for employee filing.',
    'Enter the covered dates and number of days.',
    'Confirm with HR if the schedule is office-assigned or year-end compliance related.',
  ],
  sickLeave: [
    'Select Sick Leave.',
    'Enter the absence dates and number of days.',
    'Choose In Hospital or Out Patient, then enter illness details.',
    'Attach a medical certificate when required, especially for 5 or more consecutive days.',
  ],
  maternityLeave: [
    'Select Maternity Leave.',
    'Enter the expected delivery date and covered leave dates.',
    'Choose the maternity classification, such as Normal Delivery or Caesarean Section.',
    'Attach the medical certificate, birth/delivery record, or related document required by HR.',
    'File at least 30 days before the expected delivery date.',
  ],
  paternityLeave: [
    'Select Paternity Leave.',
    'Enter the spouse delivery/miscarriage date and requested covered dates.',
    'Make sure the leave starts on or after the delivery date and ends within 60 days from delivery.',
    'Attach marriage certificate plus birth certificate or medical record when required.',
  ],
  specialPrivilegeLeave: [
    'Select Special Privilege Leave.',
    'Enter covered dates, number of days, and occasion/reason.',
    'Choose the location option, then enter the specific location/details.',
  ],
  soloParentLeave: [
    'Select Solo Parent Leave.',
    'Enter covered dates and reason related to parental obligation.',
    'Enter the Solo Parent ID number and expiry date.',
    'Make sure the ID is not expired and is valid through the leave start date.',
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
    'Choose the VAWC supporting document type.',
    'Enter the case or protection order details.',
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
    'Make sure the leave starts on or after the calamity date and ends within 30 days from the calamity.',
    'Attach barangay/LDRRMO/NDRRMC certification or proof of residency when required.',
  ],
  adoptionLeave: [
    'Select Adoption Leave.',
    'Enter the PAPA/adoption placement date.',
    'Choose the adoption leave eligibility role.',
    'Make sure the leave starts on or after the placement date.',
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
  adoption_placement_date: {
    title: 'PAPA / Adoption Placement Date',
    aliases: [
      'papa date',
      'papa placement date',
      'adoption placement date',
      'adoption finalization date',
      'placement date',
      'papa field',
      'adoption date',
    ],
    explanation:
      'Enter the PAPA or adoption placement date supported by the adoption record.',
    examples: ['PAPA / Adoption Placement Date: July 10, 2026'],
    note: 'Adoption Leave cannot start before this date.',
  },
  adoption_parent_role: {
    title: 'Adoption Leave Eligibility',
    aliases: [
      'adoption eligibility',
      'adoption leave eligibility',
      'adoption role',
      'adoption parent role',
      'adoptive mother',
      'single male adopter',
      'legitimate male spouse',
    ],
    explanation:
      'Choose the role that matches your eligibility for adoption leave.',
    examples: [
      'Adoptive mother / single male adopter (60 days)',
      'Legitimate male spouse (7 days)',
    ],
    note: 'HRMS uses this selection to apply the correct 60-day or 7-day maximum.',
  },
  vawc_support_document_type: {
    title: 'VAWC Supporting Document Type',
    aliases: [
      'vawc supporting document type',
      'vawc document type',
      'supporting document type',
      'protection order',
      'police report',
      'prosecutor report',
      'vawc medical certificate',
    ],
    explanation:
      'Choose the document type that matches the VAWC proof you will attach.',
    examples: [
      'Protection Order',
      'Police / Prosecutor Report',
      'Medical Certificate',
      'Other Supporting Document',
    ],
    note: 'The selected document type should match the uploaded attachment.',
  },
  vawc_case_details: {
    title: 'Case / Protection Order Details',
    aliases: [
      'vawc case details',
      'case details',
      'protection order details',
      'case protection order details',
      'vawc details',
      'vawc case',
    ],
    explanation:
      'Enter the case reference, protection order details, issuing office, or brief supporting context from the document.',
    examples: ['BPO issued by [barangay] on July 10, 2026', 'Police blotter/report reference [number]'],
    note: 'Keep the details accurate and limited to what HR needs to match the supporting document.',
  },
  solo_parent_id_number: {
    title: 'Solo Parent ID Number',
    aliases: [
      'solo parent id number',
      'solo parent id',
      'solo parent number',
      'solo parent id field',
      'solo parent id no',
    ],
    explanation:
      'Enter the ID number shown on your valid Solo Parent ID.',
    examples: ['Solo Parent ID Number: SP-2026-00123'],
    note: 'Use the exact number from the document you will attach.',
  },
  solo_parent_id_expiry_date: {
    title: 'Solo Parent ID Expiry Date',
    aliases: [
      'solo parent id expiry date',
      'solo parent expiry date',
      'solo parent id valid until',
      'solo parent validity',
      'id expiry',
      'expiry date',
    ],
    explanation:
      'Enter the expiry or valid-until date shown on your Solo Parent ID.',
    examples: ['Solo Parent ID Expiry Date: December 31, 2026'],
    note: 'The ID must not be expired and must still be valid on the leave start date.',
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
