const HRMS_TIMEZONE = process.env.HRMS_TIMEZONE || 'Asia/Manila';
const {
  getDtrPolicySectionsForMessage,
  getLocatorPolicySectionsForMessage,
  policyPointLines,
} = require('./attendanceLocatorPolicies');
const {
  GUIDELINE_SECTIONS,
  getFormGuidanceForType,
  getLeaveFormFieldGuidance,
  getLeaveGuidanceForType,
  getGuidelineSectionsForMessage,
} = require('./leaveFilingGuidelines');

function lower(value) {
  return String(value || '').toLowerCase();
}

function fmtDate(value) {
  if (!value) return '';
  const s = String(value);
  return s.length >= 10 ? s.slice(0, 10) : s;
}

function fmtFriendlyDate(value) {
  const iso = fmtDate(value);
  const match = iso.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return iso;
  const dt = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
  return new Intl.DateTimeFormat('en-US', {
    timeZone: 'UTC',
    month: 'long',
    day: 'numeric',
    year: 'numeric',
  }).format(dt);
}

function fmtFriendlyDateRange(start, end) {
  const startIso = fmtDate(start);
  const endIso = fmtDate(end);
  if (!startIso && !endIso) return '';
  if (!endIso || startIso === endIso) return `on ${fmtFriendlyDate(startIso)}`;
  return `from ${fmtFriendlyDate(startIso)} to ${fmtFriendlyDate(endIso)}`;
}

function fmtLocalizedDateRange(start, end, language) {
  const phrase = fmtFriendlyDateRange(start, end);
  if (!phrase) return '';
  if (language === 'bisaya') {
    return phrase.replace(/^on /, 'sa ').replace(/^from /, 'gikan ').replace(/ to /, ' hangtod ');
  }
  if (language === 'tagalog') {
    return phrase.replace(/^on /, 'noong ').replace(/^from /, 'mula ').replace(/ to /, ' hanggang ');
  }
  return phrase;
}

function fmtTime(value) {
  if (!value) return 'none';
  const dt = new Date(value);
  if (Number.isNaN(dt.getTime())) return 'none';
  return new Intl.DateTimeFormat('en-US', {
    timeZone: HRMS_TIMEZONE,
    hour: 'numeric',
    minute: '2-digit',
  }).format(dt);
}

function fmtDays(value) {
  const n = Number(value || 0);
  if (!Number.isFinite(n)) return '0';
  if (Number.isInteger(n)) return String(n);
  return String(Number(n.toFixed(2)));
}

function fmtDayCount(value) {
  const text = fmtDays(value);
  return `${text} ${Number(value) === 1 ? 'day' : 'days'}`;
}

function fmtLocalizedDayCount(value, language) {
  const text = fmtDays(value);
  if (language === 'bisaya') return `${text} ka adlaw`;
  if (language === 'tagalog') return `${text} araw`;
  return fmtDayCount(value);
}

function plural(count, singular, pluralValue = `${singular}s`) {
  return Number(count) === 1 ? singular : pluralValue;
}

function localizedPeriodLabel(label, language) {
  const value = String(label || 'selected period').toLowerCase();
  if (language === 'bisaya') {
    if (value === 'today') return 'karon';
    if (value === 'this week') return 'karong semanaha';
    if (value === 'this month') return 'aning bulana';
    if (value === 'last month') return 'miaging bulan';
    if (value === 'next month') return 'sunod bulan';
  }
  if (language === 'tagalog') {
    if (value === 'today') return 'ngayon';
    if (value === 'this week') return 'ngayong linggo';
    if (value === 'this month') return 'ngayong buwan';
    if (value === 'last month') return 'nakaraang buwan';
    if (value === 'next month') return 'susunod na buwan';
  }
  return label || 'selected period';
}

function displayPeriodLabel(label, language) {
  const localized = localizedPeriodLabel(label, language);
  return String(localized || 'selected period').replace(
    /\b(january|february|march|april|may|june|july|august|september|october|november|december)\b/gi,
    (month) => `${month[0].toUpperCase()}${month.slice(1).toLowerCase()}`
  );
}

function asNumber(value) {
  if (value == null || value === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function statusLabel(value) {
  return String(value || 'unknown').replace(/_/g, ' ');
}

function trimTrailingSentencePunctuation(value) {
  return String(value || '').replace(/[.\s]+$/g, '').trim();
}

function firstSentence(value) {
  const text = String(value || '').replace(/\s+/g, ' ').trim();
  if (!text) return '';
  const match = text.match(/^.*?[.!?](?:\s|$)/);
  return trimTrailingSentencePunctuation(match ? match[0] : text);
}

function compactText(value, maxLength = 120) {
  const text = firstSentence(value);
  if (text.length <= maxLength) return text;
  const cut = text.slice(0, maxLength - 3);
  const atWord = cut.replace(/\s+\S*$/, '').trim();
  return `${atWord || cut.trim()}...`;
}

const LEAVE_GUIDANCE_TRANSLATIONS = {
  bisaya: {
    vacationLeave: {
      description: 'Para sa personal nga pahuway, lakaw, o travel; kinahanglan i-file daan ug subject sa approval.',
      requirements: 'Walay required document. Ibutang ang location kung sulod ba sa Pilipinas o abroad.',
      advanceFiling: 'I-file labing menos 5 ka adlaw before sa leave date.',
    },
    mandatoryForcedLeave: {
      description: 'Required nga vacation leave para sa officials ug employees, kasagaran 5 working days kada tuig.',
      requirements: 'Walay required document.',
      limits: '5 working days kada tuig.',
      notes: 'Kung dili magamit sulod sa tuig, mahimong i-deduct sa HR/Admin sa vacation leave credits.',
    },
    sickLeave: {
      description: 'Para kung dili ka makareport tungod sa sakit, injury, recovery, o medical appointment.',
      requirements: 'Medical certificate kasagaran kinahanglan kung 5 o labaw ka sunod-sunod nga adlaw, o kung pangayoon sa head of office.',
      advanceFiling: 'I-file dayon pagbalik nimo o samtang absent kung posible.',
    },
    maternityLeave: {
      description: 'Para sa female employees tungod sa childbirth o miscarriage, married man o unmarried.',
      requirements: 'Medical certificate o birth/delivery record. Marriage certificate kung applicable.',
      limits: 'Normal delivery: hangtod 105 working days. Caesarean section: hangtod 115 working days.',
      advanceFiling: 'I-notify ang supervisor labing menos 30 ka adlaw before expected delivery date.',
      notes: 'Apil niini ang normal delivery, caesarean section, ug miscarriage.',
    },
    paternityLeave: {
      description: 'Para sa married male employee kung nanganak o na-miscarriage ang iyang legitimate spouse.',
      requirements: 'Marriage certificate ug birth certificate o medical record sa delivery/miscarriage.',
      limits: '7 working days; gamiton sulod sa 60 ka adlaw gikan sa delivery.',
      advanceFiling: 'I-notify ang HR before o dayon after sa event.',
    },
    specialPrivilegeLeave: {
      description: 'Para sa personal milestones o special occasions sama sa birthday, wedding, o hospitalization sa immediate family.',
      requirements: 'Walay required document. Ibutang ang occasion o location.',
      limits: '3 ka adlaw kada tuig, dili ma-carry over.',
      advanceFiling: 'I-file daan kung posible.',
    },
    soloParentLeave: {
      description: 'Para sa solo parents under RA 8972 para sa parental obligations.',
      requirements: 'Solo Parent ID o DSWD-issued certificate.',
      limits: '7 working days kada tuig.',
    },
    studyLeave: {
      description: 'Para sa higher education o licensure exam review, kinahanglan prior approval ug service obligation.',
      requirements: 'Written request, school enrollment certificate o review documents, ug agency head approval.',
      limits: 'Maximum 6 months o 180 working days. Naay service obligation after.',
      advanceFiling: 'I-file daan kay kinahanglan agency head approval.',
    },
    tenDayVawcLeave: {
      description: 'Para sa women employees nga victims of Violence Against Women and Children under RA 9262.',
      requirements: 'Barangay Protection Order, court order, o certified government document nga nag-confirm sa VAWC situation.',
      limits: '10 ka adlaw kada tuig; mahimong ma-extend kung kinahanglan sa agency.',
    },
    rehabilitationPrivilege: {
      description: 'Para sa employees nga na-injure samtang nagtrabaho sa official duties.',
      requirements: 'Medical certificate nga nagpakita sa injury ug incident/accident report endorsed by the office.',
      limits: 'Hangtod 6 months o 180 working days.',
      notes: 'Para ra ni sa work-related injuries, dili personal accidents.',
    },
    specialLeaveBenefitsForWomen: {
      description: 'Para sa female employees nga moagi ug surgery tungod sa gynecological disorder under RA 9710.',
      requirements: 'Medical certificate gikan sa licensed physician nga nag-confirm sa condition ug operation.',
      limits: 'Maximum 60 days, non-cumulative.',
      advanceFiling: 'I-file before o dayon after sa procedure.',
    },
    specialEmergencyCalamityLeave: {
      description: 'Para kung ang residence naa sa declared calamity area o kinahanglan mo-atiman sa immediate family tungod sa calamity.',
      requirements: 'Certification from Barangay/LDRRMO/NDRRMC ug proof of residency sa affected area.',
      limits: '5 working days kada calamity incident.',
    },
    adoptionLeave: {
      description: 'Para sa adoptive parents human ma-finalize ang adoption decree under RA 8552.',
      requirements: 'Court order/adoption decree ug certified copy sa Certificate of Finality.',
      limits: '60 working days para sa adoptive mother; 7 working days para sa adoptive father.',
    },
    others: {
      description: 'Para sa leave types nga dili covered sa standard categories; kinahanglan klaro ang reason ug details.',
      requirements: 'I-attach ang supporting documents nga fit sa imong circumstance kung applicable.',
      notes: 'Supervisor ug HR ang mo-review kung unsang rule ang applicable.',
    },
  },
  tagalog: {
    vacationLeave: {
      description: 'Para sa personal na pahinga, lakad, o travel; kailangang i-file in advance at subject sa approval.',
      requirements: 'Walang required document. Ilagay ang location kung within the Philippines o abroad.',
      advanceFiling: 'I-file kahit 5 araw bago ang leave date.',
    },
    mandatoryForcedLeave: {
      description: 'Required vacation leave para sa officials at employees, karaniwang 5 working days bawat taon.',
      requirements: 'Walang required document.',
      limits: '5 working days bawat taon.',
      notes: 'Kung hindi nagamit sa loob ng taon, puwedeng i-deduct ng HR/Admin sa vacation leave credits.',
    },
    sickLeave: {
      description: 'Para kapag hindi makakapasok dahil sa sakit, injury, recovery, o medical appointment.',
      requirements: 'Medical certificate ang karaniwang kailangan kapag 5 o higit pang sunod-sunod na araw, o kung hiningi ng head of office.',
      advanceFiling: 'I-file agad pagbalik o habang absent kung posible.',
    },
    maternityLeave: {
      description: 'Para sa female employees dahil sa childbirth o miscarriage, married man o unmarried.',
      requirements: 'Medical certificate o birth/delivery record. Marriage certificate kung applicable.',
      limits: 'Normal delivery: hanggang 105 working days. Caesarean section: hanggang 115 working days.',
      advanceFiling: 'I-notify ang supervisor kahit 30 araw bago ang expected delivery date.',
      notes: 'Kasama rito ang normal delivery, caesarean section, at miscarriage.',
    },
    paternityLeave: {
      description: 'Para sa married male employee kapag nanganak o nag-miscarriage ang legitimate spouse.',
      requirements: 'Marriage certificate at birth certificate o medical record ng delivery/miscarriage.',
      limits: '7 working days; gamitin sa loob ng 60 araw mula delivery.',
      advanceFiling: 'I-notify ang HR bago o agad pagkatapos ng event.',
    },
    specialPrivilegeLeave: {
      description: 'Para sa personal milestones o special occasions tulad ng birthday, wedding, o hospitalization ng immediate family.',
      requirements: 'Walang required document. Ilagay ang occasion o location.',
      limits: '3 araw bawat taon, non-cumulative.',
      advanceFiling: 'I-file in advance kung posible.',
    },
    soloParentLeave: {
      description: 'Para sa solo parents under RA 8972 para sa parental obligations.',
      requirements: 'Solo Parent ID o DSWD-issued certificate.',
      limits: '7 working days bawat taon.',
    },
    studyLeave: {
      description: 'Para sa higher education o licensure exam review, kailangan ng prior approval at service obligation.',
      requirements: 'Written request, school enrollment certificate o review documents, at agency head approval.',
      limits: 'Maximum 6 months o 180 working days. May service obligation after.',
      advanceFiling: 'I-file nang maaga dahil kailangan ng agency head approval.',
    },
    tenDayVawcLeave: {
      description: 'Para sa women employees na victims of Violence Against Women and Children under RA 9262.',
      requirements: 'Barangay Protection Order, court order, o certified government document na nag-confirm ng VAWC situation.',
      limits: '10 araw bawat taon; puwedeng ma-extend kung kailangan ng agency.',
    },
    rehabilitationPrivilege: {
      description: 'Para sa employees na na-injure habang gumaganap ng official duties.',
      requirements: 'Medical certificate na nagpapakita ng injury at incident/accident report endorsed by the office.',
      limits: 'Hanggang 6 months o 180 working days.',
      notes: 'Para lang ito sa work-related injuries, hindi personal accidents.',
    },
    specialLeaveBenefitsForWomen: {
      description: 'Para sa female employees na sasailalim sa surgery dahil sa gynecological disorder under RA 9710.',
      requirements: 'Medical certificate mula sa licensed physician na nag-confirm ng condition at operation.',
      limits: 'Maximum 60 days, non-cumulative.',
      advanceFiling: 'I-file bago o agad pagkatapos ng procedure.',
    },
    specialEmergencyCalamityLeave: {
      description: 'Para kung ang residence ay nasa declared calamity area o kailangang asikasuhin ang immediate family dahil sa calamity.',
      requirements: 'Certification from Barangay/LDRRMO/NDRRMC at proof of residency sa affected area.',
      limits: '5 working days bawat calamity incident.',
    },
    adoptionLeave: {
      description: 'Para sa adoptive parents pagkatapos ma-finalize ang adoption decree under RA 8552.',
      requirements: 'Court order/adoption decree at certified copy ng Certificate of Finality.',
      limits: '60 working days para sa adoptive mother; 7 working days para sa adoptive father.',
    },
    others: {
      description: 'Para sa leave types na hindi covered ng standard categories; kailangang malinaw ang reason at details.',
      requirements: 'Mag-attach ng supporting documents na tugma sa circumstance kung applicable.',
      notes: 'Supervisor at HR ang magre-review kung anong rule ang applicable.',
    },
  },
};

function isTagalogOrBisaya(message) {
  const text = lower(message);
  return /\b(ano|ba|ko|akong|ngano|unsa|unsay|karon|ngayon|kumusta|pila|kabuok|naa|wala|pasok|na-approve|adtong|adtung|atong|niadtong|niadtung|ana|adto|ato|daw|apil|ila)\b/.test(
    text
  );
}

function languageOf(message) {
  const text = lower(message);
  if (/\b(tagaloga?|tagalog|filipino)\b/.test(text)) return 'tagalog';
  if (/\b(bisayaa?|binisayaa?|cebuano)\b/.test(text)) return 'bisaya';
  if (/\b(english|ingles)\b/.test(text)) return 'english';
  if (/\b(ngano|unsa|unsaon|unsay|unsa'y|karon|pila|kabuok|naa|akong|nako|nabilin|gamay|kuwang|imong|nimo|gikan|mahimong|adlaw|kinahanglan|ug|kay|aning|bulana|adtong|adtung|adtun|atong|niadtong|niadtung|ana|adto|ato|duty|daw|apil|ila|nga)\b/.test(text)) {
    return 'bisaya';
  }
  if (/\b(tagalog|filipino|ano|paano|pano|ngayon|ako|ko|ba|may|wala|ilan|bakit|maliit|natira|kailangan|pasok|noong|nung)\b/.test(text)) {
    return 'tagalog';
  }
  return 'english';
}

function responseLabels(language) {
  if (language === 'bisaya') {
    return {
      details: 'Detalye',
      nextStep: 'Sunod buhaton',
      more: 'Naa pa',
    };
  }
  if (language === 'tagalog') {
    return {
      details: 'Detalye',
      nextStep: 'Susunod',
      more: 'May',
    };
  }
  return {
    details: 'Details',
    nextStep: 'Next step',
    more: 'Plus',
  };
}

function localizeTitle(title, language) {
  const value = String(title || '').trim();
  if (!value) return value;

  if (language === 'bisaya') {
    return value
      .replace(/^Leave balance$/i, 'Leave balance nimo')
      .replace(/^Leave requirements$/i, 'Leave requirements')
      .replace(/^Attachment requirement$/i, 'Attachment requirement nimo')
      .replace(/^Leave form guide$/i, 'Giya sa pag-file ug leave')
      .replace(/^Leave types you can file$/i, 'Leave types nga pwede nimo ma-file')
      .replace(/^Pending leave requests$/i, 'Pending leave requests nimo')
      .replace(/^Approved leave requests$/i, 'Approved leave requests nimo')
      .replace(/^Rejected leave requests$/i, 'Rejected leave requests nimo')
      .replace(/^Locator types you can file$/i, 'Locator types nga pwede nimo ma-file')
      .replace(/^Locator filing requirements$/i, 'Giya sa pag-file ug locator')
      .replace(/^Locator filing check$/i, 'Locator filing check')
      .replace(/^Absence check/i, 'Absence check')
      .replace(/^Missing logs/i, 'Missing logs')
      .replace(/^DTR summary/i, 'DTR summary');
  }

  if (language === 'tagalog') {
    return value
      .replace(/^Leave balance$/i, 'Leave balance mo')
      .replace(/^Leave requirements$/i, 'Leave requirements')
      .replace(/^Attachment requirement$/i, 'Attachment requirement mo')
      .replace(/^Leave form guide$/i, 'Gabay sa pag-file ng leave')
      .replace(/^Leave types you can file$/i, 'Leave types na puwede mong i-file')
      .replace(/^Pending leave requests$/i, 'Pending leave requests mo')
      .replace(/^Approved leave requests$/i, 'Approved leave requests mo')
      .replace(/^Rejected leave requests$/i, 'Rejected leave requests mo')
      .replace(/^Locator types you can file$/i, 'Locator types na puwede mong i-file')
      .replace(/^Locator filing requirements$/i, 'Gabay sa pag-file ng locator')
      .replace(/^Locator filing check$/i, 'Locator filing check')
      .replace(/^Absence check/i, 'Absence check')
      .replace(/^Missing logs/i, 'Missing logs')
      .replace(/^DTR summary/i, 'DTR summary');
  }

  return value;
}

function normalizeDayCountText(value, language) {
  return String(value || '')
    .replace(/\b(\d+(?:\.\d+)?)\s*calendar\s+day\(s\)/gi, (_, n) => {
      const text = fmtDays(n);
      if (language === 'bisaya') return `${text} ka calendar day`;
      if (language === 'tagalog') return `${text} calendar day`;
      return `${text} calendar ${Number(n) === 1 ? 'day' : 'days'}`;
    })
    .replace(/\b(\d+(?:\.\d+)?)\s*day\(s\)/gi, (_, n) => fmtLocalizedDayCount(n, language))
    .replace(/\b(\d+)\.00\s+days?\b/gi, (_, n) => fmtLocalizedDayCount(n, language));
}

function localizeDetailPrefix(line, language) {
  const maps = {
    bisaya: {
      Date: 'Petsa',
      Type: 'Type',
      Status: 'Status',
      Coverage: 'Coverage',
      Location: 'Lugar',
      Reason: 'Rason',
      Remarks: 'Remarks',
      Attachment: 'Attachment',
      Schedule: 'Schedule',
      Shift: 'Shift',
      Holiday: 'Holiday',
      'Expected logs': 'Expected logs',
      'Missing logs': 'Missing logs',
      'Total hours': 'Total hours',
      Late: 'Late',
      Undertime: 'Undertime',
      Overtime: 'Overtime',
      Pending: 'Pending',
      Approved: 'Approved',
      Rejected: 'Rejected',
      Cancelled: 'Cancelled',
    },
    tagalog: {
      Date: 'Petsa',
      Type: 'Uri',
      Status: 'Status',
      Coverage: 'Coverage',
      Location: 'Lugar',
      Reason: 'Reason',
      Remarks: 'Remarks',
      Attachment: 'Attachment',
      Schedule: 'Schedule',
      Shift: 'Shift',
      Holiday: 'Holiday',
      'Expected logs': 'Expected logs',
      'Missing logs': 'Missing logs',
      'Total hours': 'Total hours',
      Late: 'Late',
      Undertime: 'Undertime',
      Overtime: 'Overtime',
      Pending: 'Pending',
      Approved: 'Approved',
      Rejected: 'Rejected',
      Cancelled: 'Cancelled',
    },
    english: {},
  };
  const labels = maps[language] || maps.english;
  for (const [source, target] of Object.entries(labels)) {
    if (line.startsWith(`${source}:`)) {
      return `${target}: ${line.slice(source.length + 1).trim()}`;
    }
  }
  return line;
}

function friendlyText(value, language) {
  return normalizeDayCountText(value, language)
    .replace(/\b(\d{4})-(\d{2})-(\d{2})\b/g, (match) => fmtFriendlyDate(match))
    .replace(/\bapproved by HR\b/gi, 'approved by HR')
    .replace(/\bwaiting for HR final review\b/gi, 'waiting for HR final review')
    .replace(/\bwaiting for department head review\b/gi, 'waiting for department head review')
    .trim();
}

function friendlyDetailLine(item, language) {
  return localizeDetailPrefix(friendlyText(item, language), language);
}

function bulletLines(items, limit = 7) {
  const clean = (items || []).filter(Boolean);
  const visible = clean.slice(0, limit);
  const rest = clean.length - visible.length;
  const lines = visible.map((item) => `- ${item}`);
  if (rest > 0) lines.push(`- Plus ${rest} more.`);
  return lines;
}

function structuredReply(language, { title, summary, details = [], nextStep, limit = 7 }) {
  const labels = responseLabels(language);
  const parts = [
    localizeTitle(title, language),
    '',
    friendlyText(summary, language),
  ].filter((part) => part != null && part !== '');
  const lines = bulletLines(
    details.map((detail) => friendlyDetailLine(detail, language)),
    limit
  );
  if (lines.length > 0) {
    parts.push('', `${labels.details}:`, ...lines);
  }
  if (nextStep) {
    parts.push('', `${labels.nextStep}: ${friendlyText(nextStep, language)}`);
  }
  return parts.join('\n');
}

function dtrPolicyLines(message, fallbackKeys, options = {}) {
  return policyPointLines(
    getDtrPolicySectionsForMessage(message, { fallbackKeys }),
    options
  );
}

function locatorPolicyLines(message, fallbackKeys, options = {}) {
  return policyPointLines(
    getLocatorPolicySectionsForMessage(message, { fallbackKeys }),
    options
  );
}

function requestedLeaveType(message) {
  const text = lower(message).replace(/[\s_-]+/g, '');
  if (/\b(sick|sl|sickleave)\b/.test(lower(message)) || text.includes('sickleave')) {
    return 'sick';
  }
  if (
    /\b(vacation|vl|vacationleave)\b/.test(lower(message)) ||
    text.includes('vacationleave')
  ) {
    return 'vacation';
  }
  return null;
}

function normalizedText(value) {
  return lower(value).replace(/[^a-z0-9]+/g, '');
}

function leaveTypeSearchText(typeRecord) {
  return `${typeRecord.display_name || ''} ${typeRecord.name || ''} ${typeRecord.description || ''}`;
}

function inferLeaveTypeFromRecords(message, typeRecords = []) {
  const normalizedMessage = normalizedText(message);
  if (!normalizedMessage || typeRecords.length === 0) return null;

  let best = null;
  let bestScore = 0;
  for (const type of typeRecords) {
    const label = leaveTypeSearchText(type);
    const normalizedLabel = normalizedText(label);
    if (!normalizedLabel) continue;

    const words = lower(label)
      .split(/[^a-z0-9]+/)
      .filter((word) => word.length >= 3 && word !== 'leave');
    const uniqueWords = [...new Set(words)];
    const score = uniqueWords.reduce((total, word) => {
      return total + (normalizedMessage.includes(word) ? 1 : 0);
    }, normalizedMessage.includes(normalizedLabel) ? 3 : 0);

    if (score > bestScore) {
      best = type;
      bestScore = score;
    }
  }

  return bestScore > 0 ? best : null;
}

function mentionedLeaveTypeRecords(context, message) {
  const normalizedMessage = normalizedText(message);
  const scored = (context.leave_types || [])
    .map((type) => {
      const label = leaveTypeSearchText(type);
      const normalizedLabel = normalizedText(label);
      const words = lower(label)
        .split(/[^a-z0-9]+/)
        .filter((word) => word.length >= 3 && word !== 'leave');
      const uniqueWords = [...new Set(words)];
      const score = uniqueWords.reduce((total, word) => {
        return total + (normalizedMessage.includes(word) ? 1 : 0);
      }, normalizedLabel && normalizedMessage.includes(normalizedLabel) ? 3 : 0);
      return { type, score };
    })
    .filter((item) => item.score > 0)
    .sort((a, b) => b.score - a.score);
  return scored.map((item) => item.type);
}

function requestedLeaveTypeRecord(message, context) {
  const type = requestedLeaveType(message);
  if (type) {
    return (context.leave_types || []).find((record) => leaveTypeRecordMatches(record, type)) || null;
  }
  return inferLeaveTypeFromRecords(message, context.leave_types || []);
}

function normalizeSex(value) {
  const text = lower(value);
  if (text === 'm' || text === 'male') return 'male';
  if (text === 'f' || text === 'female') return 'female';
  return text || null;
}

function isWhyBalanceQuestion(message) {
  const text = lower(message);
  return /\b(why|ngano|bakit|gamay|small|low|maliit|nabilin|natira|remaining)\b/.test(
    text
  );
}

function hasDateRangeHint(message) {
  const text = lower(message);
  return /\b(today|tomorrow|yesterday|ugma|kagahapon|gahapon|karon|karong adlawa|week|semana|semanaha|month|pay\s*period|payroll\s*period|cutoff|cut-off|cut off|bulan|bulana|buwan|buwana|aning bulana|last month|this month|next month|last week|this week|next week|next day|following day|previous day|day before|same day|same date|sunod adlaw|sunod|miaging|niaging|adtong|adtung|atong|niadtong|niadtung|noong|nung|monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|miyerkules|mierkules|huwebes|webes|biyernes|byernes|sabado|domingo|\d{4}-\d{2}-\d{2}|january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\b|\b\d{1,2}\s+(?:days?|weeks?|months?)\s+ago\b|\b(?:sa|pag|noong|nung|adtong|adtung|atong|niadtong|niadtung)\s+\d{1,2}\b/.test(
    text
  );
}

function requestOverlapsRange(request, range) {
  if (!range?.startDate || !range?.endDate) return true;
  if (!request?.start_date || !request?.end_date) return true;
  return request.start_date <= range.endDate && request.end_date >= range.startDate;
}

function daysBetweenIso(startDate, endDate) {
  if (!startDate || !endDate) return null;
  const start = new Date(`${startDate}T00:00:00Z`);
  const end = new Date(`${endDate}T00:00:00Z`);
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) return null;
  return Math.round((end.getTime() - start.getTime()) / 86400000);
}

function rangeDayCount(range) {
  const diff = daysBetweenIso(range?.startDate, range?.endDate);
  return diff == null ? null : diff + 1;
}

function pendingStatus(value) {
  return /^(pending|pending_department_head|pending_hr)$/i.test(String(value || ''));
}

function approvedStatus(value) {
  return /^approved/i.test(String(value || ''));
}

function rejectedStatus(value) {
  return /^(rejected|rejected_department_head|rejected_by_department_head|rejected_hr|rejected_by_hr|declined|denied)$/i.test(
    String(value || '')
  );
}

function returnedStatus(value) {
  return /^returned$/i.test(String(value || ''));
}

function activeLeaveStatus(value) {
  const status = String(value || '').toLowerCase();
  return (
    pendingStatus(status) ||
    approvedStatus(status) ||
    status === 'returned' ||
    status === 'draft'
  );
}

function parseRequestedDays(message) {
  const text = lower(message);
  const match = text.match(/\b(\d+(?:\.\d+)?)\s*(?:day|days|adlaw|ka\s*adlaw)?\b/);
  return match ? asNumber(match[1]) : null;
}

function requestedDaysOrRangeDays(message, context) {
  return parseRequestedDays(message) || rangeDayCount(context.date_range);
}

function leaveTypeMatches(balance, type) {
  if (!type) return true;
  const name = lower(balance.leave_type).replace(/[\s_-]+/g, '');
  if (type === 'sick') return name.includes('sick') || name === 'sl';
  if (type === 'vacation') return name.includes('vacation') || name === 'vl';
  return true;
}

function leaveBalanceMatchesRecord(balance, typeRecord) {
  if (!typeRecord) return true;
  const balanceName = normalizedText(balance.leave_type);
  const typeName = normalizedText(`${typeRecord.display_name || ''} ${typeRecord.name || ''}`);
  if (!balanceName || !typeName) return false;
  return typeName.includes(balanceName) || balanceName.includes(typeName);
}

function leaveTypeRecordMatches(typeRecord, type) {
  if (!type) return true;
  const name = lower(`${typeRecord.display_name || ''} ${typeRecord.name || ''}`).replace(
    /[\s_-]+/g,
    ''
  );
  if (type === 'sick') return name.includes('sick') || name === 'sl';
  if (type === 'vacation') return name.includes('vacation') || name === 'vl';
  return true;
}

function labelLeaveType(value) {
  const text = String(value || 'Leave').replace(/([a-z])([A-Z])/g, '$1 $2');
  return text.replace(/\bleave\b/i, 'leave');
}

function leaveGuidanceKey(type, guidance) {
  if (guidance?.key) return guidance.key;
  return getLeaveGuidanceForType(type)?.key || null;
}

function localizedLeaveGuidanceField(type, guidance, field, language) {
  const key = leaveGuidanceKey(type, guidance);
  const translated = key ? LEAVE_GUIDANCE_TRANSLATIONS[language]?.[key]?.[field] : null;
  return translated || guidance?.[field] || getLeaveGuidanceForType(type)?.[field] || '';
}

function summarizeLocalizedLeaveGuidance(type, guidance, language, options = {}) {
  if (!guidance) return null;
  const parts = [];
  if (options.includeDescription !== false) {
    const description = localizedLeaveGuidanceField(type, guidance, 'description', language);
    if (description) parts.push(description);
  }
  const requirements = localizedLeaveGuidanceField(type, guidance, 'requirements', language);
  const limits = localizedLeaveGuidanceField(type, guidance, 'limits', language);
  const advanceFiling = localizedLeaveGuidanceField(type, guidance, 'advanceFiling', language);
  const notes = localizedLeaveGuidanceField(type, guidance, 'notes', language);
  if (requirements) parts.push(`Requirements: ${requirements}`);
  if (limits) parts.push(`Limit: ${limits}`);
  if (advanceFiling) parts.push(`Filing: ${advanceFiling}`);
  if (notes) parts.push(`Note: ${notes}`);
  return parts.join(' ');
}

function localizedAvailableForFiling(language) {
  if (language === 'bisaya') return 'available sa HRMS filing';
  if (language === 'tagalog') return 'available sa HRMS filing';
  return 'available for filing in HRMS';
}

function localizedLeaveRequirementParts(type, language) {
  if (language === 'english') return leaveRequirementParts(type);

  const parts = [];
  if (language === 'bisaya') {
    parts.push(
      type.employee_can_file === false || type.admin_only
        ? 'dili pwede i-file sa employee'
        : 'pwede i-file sa employee'
    );
    parts.push(type.allows_past_dates === false ? 'dili pwede past dates' : 'pwede past dates');
    parts.push(localizedAttachmentRuleText(type, null, language));
    if (type.minimum_advance_days != null) {
      parts.push(`${fmtLocalizedDayCount(type.minimum_advance_days, language)} advance notice`);
    }
    if (type.max_days != null) {
      parts.push(`max ${fmtLocalizedDayCount(type.max_days, language)}`);
    }
    return parts;
  }

  if (language === 'tagalog') {
    parts.push(
      type.employee_can_file === false || type.admin_only
        ? 'hindi puwedeng i-file ng employee'
        : 'puwedeng i-file ng employee'
    );
    parts.push(type.allows_past_dates === false ? 'hindi puwede past dates' : 'puwede past dates');
    parts.push(localizedAttachmentRuleText(type, null, language));
    if (type.minimum_advance_days != null) {
      parts.push(`${fmtLocalizedDayCount(type.minimum_advance_days, language)} advance notice`);
    }
    if (type.max_days != null) {
      parts.push(`max ${fmtLocalizedDayCount(type.max_days, language)}`);
    }
    return parts;
  }

  return leaveRequirementParts(type);
}

function localizedLeaveFormGuideLine(type, language, days) {
  const label = labelLeaveType(type.display_name || type.name);
  const requirement = localizedAttachmentRuleText(type, days, language);
  if (language === 'bisaya') {
    return `${label}: Pilia ang ${label}. Ibutang ang covered dates ug pila ka adlaw, dayon isulat ang klarong reason. Attachment: ${requirement}.`;
  }
  if (language === 'tagalog') {
    return `${label}: Piliin ang ${label}. Ilagay ang covered dates at bilang ng araw, tapos isulat ang malinaw na reason. Attachment: ${requirement}.`;
  }

  const form = getFormGuidanceForType(type);
  return `${label}: ${form.fields.join(' ')} Requirement: ${attachmentRuleText(type, days)}.`;
}

function fmtLeaveRequest(request, language = 'english') {
  const days = request.days != null ? ` (${fmtLocalizedDayCount(request.days, language)})` : '';
  return `${labelLeaveType(request.leave_type)} ${fmtLocalizedDateRange(
    request.start_date,
    request.end_date,
    language
  )} - ${workflowStatusText(request.status)}${days}`;
}

function leaveRequestMatchesRecord(request, typeRecord) {
  if (!typeRecord) return true;
  const requestName = normalizedText(request.leave_type);
  const typeName = normalizedText(`${typeRecord.display_name || ''} ${typeRecord.name || ''}`);
  if (!requestName || !typeName) return false;
  return typeName.includes(requestName) || requestName.includes(typeName);
}

function requestedStatusMatcher(message) {
  const text = lower(message);
  if (/\b(pending|waiting|awaiting|hold|holding)\b/.test(text)) return pendingStatus;
  if (/\b(approved|approve|na-approve)\b/.test(text)) return approvedStatus;
  if (/\b(rejected|declined|denied|gi reject)\b/.test(text)) return rejectedStatus;
  if (/\b(returned|gibalik|binalik|correction)\b/.test(text)) return returnedStatus;
  return null;
}

function requestMatchesMessageFilters(request, message, context) {
  const requestedRecord = requestedLeaveTypeRecord(message, context);
  const matcher = requestedStatusMatcher(message);
  const useRange = hasDateRangeHint(message);
  if (requestedRecord && !leaveRequestMatchesRecord(request, requestedRecord)) return false;
  if (matcher && !matcher(request.status)) return false;
  if (useRange && !requestOverlapsRange(request, context.date_range)) return false;
  return true;
}

function limitedRequests(requests, limit = 5) {
  return requests.slice(0, limit);
}

function balanceFormulaLine(b, language = 'english') {
  return `earned ${fmtLocalizedDayCount(b.earned_days, language)}, used ${fmtLocalizedDayCount(
    b.used_days,
    language
  )}, adjusted ${fmtLocalizedDayCount(
    b.adjusted_days,
    language
  )}, pending ${fmtLocalizedDayCount(
    b.pending_days,
    language
  )}, remaining ${fmtLocalizedDayCount(
    b.remaining_days,
    language
  )}, available ${fmtLocalizedDayCount(b.available_days, language)}`;
}

function attachmentRequiredForType(type, days) {
  if (!type) return false;
  const threshold = asNumber(type.requires_attachment_when_over_days);
  if (threshold != null && days != null) return days >= threshold;
  return type.requires_attachment === true;
}

function attachmentRuleText(type, days) {
  const threshold = asNumber(type.requires_attachment_when_over_days);
  if (threshold != null) {
    const requiredNow = days != null && days >= threshold;
    return requiredNow
      ? `attachment required because the request reaches ${fmtDayCount(threshold)}`
      : `attachment required when filing ${fmtDayCount(threshold)} or more`;
  }
  return type.requires_attachment ? 'attachment required' : 'no attachment required';
}

function localizedAttachmentRuleText(type, days, language) {
  const threshold = asNumber(type.requires_attachment_when_over_days);
  if (threshold != null) {
    const count = fmtLocalizedDayCount(threshold, language);
    const requiredNow = days != null && days >= threshold;
    if (language === 'bisaya') {
      return requiredNow
        ? `kinahanglan ug attachment kay niabot sa ${count} ang request`
        : `kinahanglan ug attachment kung ${count} o labaw ang i-file`;
    }
    if (language === 'tagalog') {
      return requiredNow
        ? `kailangan ng attachment dahil umabot sa ${count} ang request`
        : `kailangan ng attachment kapag ${count} o higit pa ang i-file`;
    }
  }
  if (language === 'bisaya') {
    return type.requires_attachment ? 'kinahanglan ug attachment' : 'walay required attachment';
  }
  if (language === 'tagalog') {
    return type.requires_attachment ? 'kailangan ng attachment' : 'walang required attachment';
  }
  return attachmentRuleText(type, days);
}

function workflowStatusText(status) {
  const value = String(status || '').toLowerCase();
  if (value === 'pending_department_head') return 'waiting for department head review';
  if (value === 'pending_hr' || value === 'pending') return 'waiting for HR final review';
  if (value === 'approved') return 'approved by HR';
  if (value === 'returned') return 'returned for correction';
  if (value === 'rejected_by_department_head' || value === 'rejected_department_head') {
    return 'rejected by department head';
  }
  if (value === 'rejected_by_hr' || value === 'rejected_hr' || value === 'rejected') {
    return 'rejected by HR';
  }
  if (value === 'draft') return 'still in draft';
  if (value === 'cancelled') return 'cancelled';
  return statusLabel(status);
}

function firstReviewReason(request) {
  const details = request?.details || {};
  return (
    request?.reviewer_remarks ||
    request?.hr_remarks ||
    request?.dept_head_remarks ||
    request?.latest_history?.remarks ||
    details.disapproval_reason ||
    details.disapprovalReason ||
    details.recommendation_remarks ||
    details.recommendationRemarks ||
    null
  );
}

function todayDtrReply(context, localized) {
  const record = context.dtr_records?.[0];
  const range = context.date_range;
  if (!record) {
    const displayDate = range?.startDate ? ` (${fmtFriendlyDate(range.startDate)})` : '';
    return localized
      ? `Wala akong nakitang DTR record para sa ${range?.label || 'today'}${displayDate}.`
      : `I found no DTR record for ${range?.label || 'today'}${displayDate}.`;
  }

  const parts = [
    `Status: ${statusLabel(record.status)}`,
    `AM in: ${fmtTime(record.time_in)}`,
    `AM out: ${fmtTime(record.break_out)}`,
    `PM in: ${fmtTime(record.break_in)}`,
    `PM out: ${fmtTime(record.time_out)}`,
    `Late: ${record.late_minutes || 0} min`,
    `Undertime: ${record.undertime_minutes || 0} min`,
  ];
  if (record.pm_status) parts.push(`PM status: ${statusLabel(record.pm_status)}`);
  if (record.holiday_name) parts.push(`Holiday: ${record.holiday_name}`);
  if (record.leave_type) parts.push(`Leave: ${record.leave_type}`);
  if (record.remarks) parts.push(`Remarks: ${record.remarks}`);

  return localized
    ? `Ito ang DTR record mo for ${fmtFriendlyDate(record.attendance_date)}. ${parts.join(
        '. '
      )}.`
    : `Here is your DTR record for ${fmtFriendlyDate(record.attendance_date)}. ${parts.join(
        '. '
      )}.`;
}

function missingLogsReply(context, localized) {
  const records = context.dtr_records || [];
  if (records.length === 0) {
    return localized
      ? `Wala akong nakitang DTR records sa ${context.date_range?.label || 'selected period'}, kaya hindi ko ma-confirm kung may missing logs.`
      : `I found no DTR records for ${context.date_range?.label || 'the selected period'}, so I cannot confirm missing logs.`;
  }

  const incomplete = records.filter((r) => {
    return (
      r.status === 'incomplete' ||
      (!r.time_in && !r.leave_type && !r.holiday_name) ||
      (!r.time_out && r.status !== 'on_leave' && r.status !== 'holiday')
    );
  });

  if (incomplete.length === 0) {
    return localized
      ? `Wala akong nakitang missing or incomplete DTR logs sa ${context.date_range?.label || 'selected period'}.`
      : `I found no missing or incomplete DTR logs for ${context.date_range?.label || 'the selected period'}.`;
  }

  const dates = incomplete.map((r) => fmtFriendlyDate(r.attendance_date)).join(', ');
  return localized
    ? `May ${incomplete.length} DTR ${plural(incomplete.length, 'record')} na mukhang incomplete: ${dates}.`
    : `I found ${incomplete.length} DTR ${plural(incomplete.length, 'record')} that look incomplete: ${dates}.`;
}

function dtrRecords(context) {
  return context.dtr_records || [];
}

function isNonWorkingDtrRecord(record) {
  const status = lower(record?.status);
  return (
    status === 'on_leave' ||
    status === 'holiday' ||
    status === 'rest_day' ||
    !!record?.leave_type ||
    !!record?.holiday_name
  );
}

function missingDtrSlots(record) {
  if (!record) return ['no DTR record'];
  if (isNonWorkingDtrRecord(record)) return [];
  const missing = [];
  if (!record.time_in) missing.push('AM in');
  if (!record.break_out) missing.push('AM out');
  if (!record.break_in) missing.push('PM in');
  if (!record.time_out) missing.push('PM out');
  return missing;
}

function requestedDtrSlot(message) {
  const text = lower(message);
  if (/\b(am\s*in|time[\s-]?in|clock[\s-]?in)\b/.test(text)) return 'AM in';
  if (/\b(am\s*out|break[\s-]?out|morning out)\b/.test(text)) return 'AM out';
  if (/\b(pm\s*in|break[\s-]?in|afternoon in)\b/.test(text)) return 'PM in';
  if (/\b(pm\s*out|time[\s-]?out|clock[\s-]?out)\b/.test(text)) return 'PM out';
  return null;
}

function isIncompleteDtrRecord(record) {
  if (!record) return true;
  if (isNonWorkingDtrRecord(record)) return false;
  const status = lower(record.status);
  return status === 'incomplete' || missingDtrSlots(record).length > 0;
}

function isIncompleteDtrRecordForContext(context, record) {
  if (!record) return true;
  if (isNonWorkingDtrRecord(record)) return false;
  const status = lower(record.status);
  return status === 'incomplete' || missingDtrSlotsForContext(context, record).length > 0;
}

function isAbsentDtrRecord(record) {
  const status = lower(record?.status);
  return status === 'absent' || status === 'no_record' || status === 'missing';
}

function dtrIssueRecords(records, predicate) {
  return records.filter(predicate).sort((a, b) => String(a.attendance_date).localeCompare(String(b.attendance_date)));
}

function todayIsoInHrmsTimezone() {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: HRMS_TIMEZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date());
  const year = parts.find((part) => part.type === 'year')?.value;
  const month = parts.find((part) => part.type === 'month')?.value;
  const day = parts.find((part) => part.type === 'day')?.value;
  return `${year}-${month}-${day}`;
}

function noRecordWorkingDays(context) {
  const today = todayIsoInHrmsTimezone();
  return dtrCalendarDays(context).filter((day) => {
    if (day.attendance_date > today) return false;
    if (!isCalendarWorkingDay(day)) return false;
    if (dtrRecordForDate(context, day.attendance_date)) return false;
    if (firstMatchingLeave(context, day.attendance_date)) return false;
    return true;
  });
}

function fmtMinutes(value) {
  const n = Number(value || 0);
  if (!Number.isFinite(n) || n <= 0) return '0 min';
  if (n < 60) return `${n} min`;
  const hours = Math.floor(n / 60);
  const minutes = n % 60;
  return minutes > 0 ? `${hours} hr ${minutes} min` : `${hours} hr`;
}

function fmtHours(value) {
  const n = Number(value || 0);
  if (!Number.isFinite(n) || n <= 0) return '0 min';
  const totalMinutes = Math.round(n * 60);
  if (totalMinutes < 60) return `${totalMinutes} min`;
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  return minutes > 0 ? `${hours} hr ${minutes} min` : `${hours} hr`;
}

function timeTextToMinutes(value) {
  if (!value) return null;
  const match = String(value).match(/^(\d{1,2}):(\d{2})/);
  if (!match) return null;
  return Number(match[1]) * 60 + Number(match[2]);
}

function minutesFromIsoInHrmsTimezone(value) {
  if (!value) return null;
  const dt = new Date(value);
  if (Number.isNaN(dt.getTime())) return null;
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: HRMS_TIMEZONE,
    hour12: false,
    hour: '2-digit',
    minute: '2-digit',
  }).formatToParts(dt);
  const hour = Number(parts.find((part) => part.type === 'hour')?.value || 0);
  const minute = Number(parts.find((part) => part.type === 'minute')?.value || 0);
  return hour * 60 + minute;
}

function fmtClockMinutes(value) {
  if (value == null) return 'none';
  const h = Math.floor(value / 60);
  const m = value % 60;
  const hour12 = h % 12 || 12;
  const suffix = h >= 12 ? 'PM' : 'AM';
  return `${hour12}:${String(m).padStart(2, '0')} ${suffix}`;
}

function fmtScheduleTime(value) {
  const minutes = timeTextToMinutes(value);
  return minutes == null ? String(value || '').trim() : fmtClockMinutes(minutes);
}

function fmtScheduleRange(day) {
  const start = fmtScheduleTime(day?.start_time);
  const end = fmtScheduleTime(day?.end_time);
  if (!start && !end) return '';
  if (!end) return start;
  if (!start) return end;
  return `${start}-${end}`;
}

function isoDayOfWeek(dateString) {
  const dt = new Date(`${dateString}T00:00:00Z`);
  const day = dt.getUTCDay();
  return day === 0 ? 7 : day;
}

function dtrCalendarDays(context) {
  return context.dtr_calendar_days || [];
}

function calendarDayForDate(context, date) {
  const key = fmtDate(date);
  return dtrCalendarDays(context).find((day) => day.attendance_date === key) || null;
}

function dtrRecordForDate(context, date) {
  const key = fmtDate(date);
  return dtrRecords(context).find((record) => fmtDate(record.attendance_date) === key) || null;
}

function shiftTypeFromCalendar(day) {
  if (!day?.start_time) return null;
  const explicit = lower(day.punch_mode || 'auto');
  if (explicit && explicit !== 'auto') return explicit;
  const start = timeTextToMinutes(day.start_time);
  const end = timeTextToMinutes(day.end_time);
  const breakEnd = timeTextToMinutes(day.break_end);
  if (start == null) return null;
  if (start >= 12 * 60) return 'pm_only';
  if (breakEnd == null && end != null && end <= 13 * 60) return 'am_only';
  return 'full_day';
}

function isCalendarWorkingDay(day) {
  if (!day?.shift_id || !day.start_time) return false;
  const workingDays = Array.isArray(day.working_days) ? day.working_days : [];
  if (workingDays.length > 0 && !workingDays.includes(isoDayOfWeek(day.attendance_date))) {
    return false;
  }
  return day.holiday_coverage !== 'whole_day';
}

function expectedSlotsForCalendarDay(day) {
  if (!isCalendarWorkingDay(day)) return [];
  const type = shiftTypeFromCalendar(day);
  let slots;
  if (type === 'single_session') slots = ['AM in', 'PM out'];
  else if (type === 'am_only') slots = ['AM in', 'AM out'];
  else if (type === 'pm_only') slots = ['PM in', 'PM out'];
  else slots = ['AM in', 'AM out', 'PM in', 'PM out'];

  if (day.holiday_coverage === 'am_only') {
    slots = slots.filter((slot) => slot === 'PM in' || slot === 'PM out');
  }
  if (day.holiday_coverage === 'pm_only') {
    slots = slots.filter((slot) => slot === 'AM in' || slot === 'AM out');
  }
  return slots;
}

function slotValue(record, slot) {
  if (slot === 'AM in') return record?.time_in;
  if (slot === 'AM out') return record?.break_out;
  if (slot === 'PM in') return record?.break_in;
  if (slot === 'PM out') return record?.time_out;
  return null;
}

function missingDtrSlotsForContext(context, recordOrDate) {
  const date = fmtDate(recordOrDate?.attendance_date || recordOrDate);
  const record =
    typeof recordOrDate === 'object' && recordOrDate?.attendance_date
      ? recordOrDate
      : dtrRecordForDate(context, date);
  const day = calendarDayForDate(context, date);
  if (!record) {
    if (day && isCalendarWorkingDay(day)) return ['no DTR record'];
    return [];
  }
  if (isNonWorkingDtrRecord(record)) return [];
  const expected = day ? expectedSlotsForCalendarDay(day) : ['AM in', 'AM out', 'PM in', 'PM out'];
  return expected.filter((slot) => !slotValue(record, slot));
}

function dtrRecordLine(record, context = null) {
  const missing = context ? missingDtrSlotsForContext(context, record) : missingDtrSlots(record);
  const day = context ? calendarDayForDate(context, record.attendance_date) : null;
  const missingText = missing.length > 0 ? `, missing ${missing.join(', ')}` : '';
  const leave = record.leave_type ? `, leave ${labelLeaveType(record.leave_type)}` : '';
  const holiday = record.holiday_name ? `, holiday ${record.holiday_name}` : '';
  const schedule = day?.shift_name
    ? `, shift ${day.shift_name} ${day.start_time || ''}-${day.end_time || ''}, grace ${day.grace_period_minutes || 0} min`
    : '';
  return `${fmtFriendlyDate(record.attendance_date)}: ${statusLabel(record.status)}, AM in ${fmtTime(
    record.time_in
  )}, AM out ${fmtTime(record.break_out)}, PM in ${fmtTime(record.break_in)}, PM out ${fmtTime(
    record.time_out
  )}, hours ${fmtHours(record.total_hours)}, late ${record.late_minutes || 0} min, undertime ${
    record.undertime_minutes || 0
  } min, overtime ${record.overtime_minutes || 0} min${missingText}${leave}${holiday}${schedule}`;
}

function dtrDailyRecordReply(context, message) {
  const language = languageOf(message);
  const record = dtrRecords(context)[0];
  const label = context.date_range?.label || 'selected date';
  if (!record) {
    const day = calendarDayForDate(context, context.date_range?.startDate);
    if (day?.holiday_name) {
      return structuredReply(language, {
        title: 'DTR check',
        summary:
          language === 'bisaya'
            ? `Wala koy DTR punch record sa ${fmtFriendlyDate(day.attendance_date)}, pero holiday ni: ${day.holiday_name}.`
            : language === 'tagalog'
              ? `Wala akong DTR punch record noong ${fmtFriendlyDate(day.attendance_date)}, pero holiday ito: ${day.holiday_name}.`
              : `${fmtFriendlyDate(day.attendance_date)} has no DTR record, but it is marked as ${day.holiday_name}.`,
        details: [
          `Holiday coverage: ${day.holiday_coverage || 'whole_day'}`,
          day.shift_name ? `Schedule: ${day.shift_name}` : null,
        ],
        nextStep:
          language === 'bisaya'
            ? 'No action needed kung sakto ang holiday setup.'
            : language === 'tagalog'
              ? 'No action needed kung tama ang holiday setup.'
              : 'No action is needed unless HR expected you to report for work that day.',
      });
    }
    if (day && !isCalendarWorkingDay(day)) {
      return structuredReply(language, {
        title: 'DTR check',
        summary:
          language === 'bisaya'
            ? `Wala koy DTR record sa ${fmtFriendlyDate(day.attendance_date)} kay dili siya required-log day base sa schedule context.`
            : language === 'tagalog'
              ? `Wala akong DTR record noong ${fmtFriendlyDate(day.attendance_date)} dahil hindi siya required-log day base sa schedule context.`
              : `${fmtFriendlyDate(day.attendance_date)} has no DTR record because it is not a required-log day in the schedule context.`,
        details: [
          `Schedule: ${day.shift_name || 'rest day/no required logs'}`,
          'Expected logs: none',
        ],
        nextStep:
          language === 'bisaya'
            ? 'No action needed kung sakto ang imong schedule ani nga date.'
            : language === 'tagalog'
              ? 'No action needed kung tama ang schedule mo sa date na ito.'
              : 'No action is needed unless your schedule for that date is wrong.',
      });
    }
    if (day && isCalendarWorkingDay(day)) {
      const expected = expectedSlotsForCalendarDay(day);
      return structuredReply(language, {
        title: 'DTR check',
        summary:
          language === 'bisaya'
            ? `Status: Absent/no DTR record. Scheduled workday ni pero wala koy nakitang DTR punches.`
            : language === 'tagalog'
              ? `Status: Absent/no DTR record. Scheduled workday ito pero wala akong nakitang DTR punches.`
              : `No DTR record was found for ${fmtFriendlyDate(day.attendance_date)}, but it is a scheduled workday.`,
        details: [
          `Shift: ${day.shift_name || 'shift'} ${fmtScheduleRange(day)}`.trim(),
          `Grace period: ${fmtMinutes(day.grace_period_minutes || 0)}`,
          `Expected logs: ${expected.join(', ')}`,
        ],
        nextStep:
          language === 'bisaya'
            ? 'Kung ni-duty ka ani nga adlaw, i-check kung kinahanglan ba ug DTR correction, locator slip, or leave coverage.'
            : language === 'tagalog'
              ? 'Kung pumasok ka sa araw na ito, i-check kung kailangan ng DTR correction, locator slip, o leave coverage.'
              : 'If you worked that day, check whether you need a DTR correction, locator slip, or leave coverage.',
      });
    }
    return structuredReply(language, {
      title: 'DTR check',
      summary: `I found no DTR record for ${label}${
        context.date_range?.startDate ? ` (${fmtFriendlyDate(context.date_range.startDate)})` : ''
      }.`,
      nextStep: 'Ask HR/Admin to confirm if a schedule or DTR record should exist for that date.',
    });
  }
  const missing = missingDtrSlotsForContext(context, record);
  const day = calendarDayForDate(context, record.attendance_date);
  const details = [
    `Status: ${statusLabel(record.status)}`,
    `AM in: ${fmtTime(record.time_in)}`,
    `AM out: ${fmtTime(record.break_out)}`,
    `PM in: ${fmtTime(record.break_in)}`,
    `PM out: ${fmtTime(record.time_out)}`,
    `Total hours: ${fmtHours(record.total_hours)}`,
    `Late: ${fmtMinutes(record.late_minutes || 0)}`,
    `Undertime: ${fmtMinutes(record.undertime_minutes || 0)}`,
    missing.length > 0 ? `Missing: ${missing.join(', ')}` : null,
    day?.shift_name ? `Shift: ${day.shift_name} ${day.start_time || ''}-${day.end_time || ''}` : null,
    record.leave_type ? `Linked leave: ${labelLeaveType(record.leave_type)}` : null,
    record.holiday_name ? `Holiday: ${record.holiday_name}` : null,
  ];
  return structuredReply(language, {
    title: `DTR for ${fmtFriendlyDate(record.attendance_date)}`,
    summary: missing.length > 0
      ? `Your DTR is ${statusLabel(record.status)} and has missing logs.`
      : `Your DTR is ${statusLabel(record.status)}.`,
    details,
    nextStep: missing.length > 0
      ? 'Review the missing logs, then check locator, leave, or HR correction coverage.'
      : null,
  });
}

function dtrRangeSummaryReply(context, message) {
  const language = languageOf(message);
  const records = dtrRecords(context);
  const label = displayPeriodLabel(context.date_range?.label || 'selected period', language);
  const noRecords = noRecordWorkingDays(context);
  if (records.length === 0 && noRecords.length === 0) {
    if (language === 'bisaya') return `Wala koy nakitang DTR records para sa ${label}.`;
    if (language === 'tagalog') return `Wala akong nakitang DTR records para sa ${label}.`;
    return `I found no DTR records for ${label}.`;
  }

  const totals = records.reduce(
    (acc, record) => {
      const status = lower(record.status);
      acc.hours += asNumber(record.total_hours) || 0;
      acc.late += Number(record.late_minutes || 0);
      acc.undertime += Number(record.undertime_minutes || 0);
      acc.overtime += Number(record.overtime_minutes || 0);
      if (status === 'present' || status === 'complete') acc.present += 1;
      else if (isAbsentDtrRecord(record)) acc.absent += 1;
      else if (isIncompleteDtrRecord(record)) acc.incomplete += 1;
      else if (status === 'on_leave' || record.leave_type) acc.onLeave += 1;
      else if (status === 'holiday' || record.holiday_name) acc.holiday += 1;
      else acc.other += 1;
      return acc;
    },
    { hours: 0, late: 0, undertime: 0, overtime: 0, present: 0, absent: 0, incomplete: 0, onLeave: 0, holiday: 0, other: 0 }
  );
  const issues = totals.incomplete + totals.absent + noRecords.length;
  const possibleAbsentOrNoRecord = totals.absent + noRecords.length;
  const wantsPresent =
    /\b(present|complete|kompleto|kumpleto)\b/.test(lower(message)) &&
    /\b(pila|ilan|how many|count|counts|total)\b/.test(lower(message));
  const wantsAbsent =
    /\b(absent|absents|absence|absences|pasabot|wala|no record|no-record)\b/.test(lower(message)) &&
    /\b(pila|ilan|how many|count|counts|total)\b/.test(lower(message));
  const summary = (() => {
    if (language === 'bisaya') {
      if (wantsPresent) {
        return `Naa kay ${totals.present} ka present/complete DTR day sa ${label}.`;
      }
      if (wantsAbsent) {
        return `Naa koy nakitang ${possibleAbsentOrNoRecord} ka possible absent/no-record workday sa ${label}.`;
      }
      return issues > 0
        ? `Nakita nako ang ${issues} ka DTR ${plural(issues, 'item')} nga angay i-review para ani nga period.`
        : 'Wala koy nakitang klaro nga DTR issue para ani nga period.';
    }
    if (language === 'tagalog') {
      if (wantsPresent) {
        return `May ${totals.present} present/complete DTR day ka sa ${label}.`;
      }
      if (wantsAbsent) {
        return `May nakita akong ${possibleAbsentOrNoRecord} possible absent/no-record workday sa ${label}.`;
      }
      return issues > 0
        ? `May nakita akong ${issues} DTR ${plural(issues, 'item')} na kailangang i-review para sa period na ito.`
        : 'Wala akong nakitang obvious DTR issue para sa period na ito.';
    }
    if (wantsPresent) {
      return `You have ${totals.present} present/complete DTR ${plural(totals.present, 'day')} for ${label}.`;
    }
    if (wantsAbsent) {
      return `You have ${possibleAbsentOrNoRecord} possible absent/no-record workday ${plural(possibleAbsentOrNoRecord, 'entry', 'entries')} for ${label}.`;
    }
    return issues > 0
      ? `I found ${issues} DTR ${plural(issues, 'item')} to review for this period.`
      : 'I did not find obvious DTR issues for this period.';
  })();
  const absenceTotalLine =
    noRecords.length > 0 || totals.absent > 0
      ? `Absent/no-record days: ${possibleAbsentOrNoRecord}`
      : null;
  const savedAbsentLine =
    totals.absent > 0 || noRecords.length > 0
      ? `Saved absent rows: ${totals.absent}`
      : null;
  const noRecordLine =
    noRecords.length > 0
      ? `Generated no-record workdays: ${noRecords.length}`
      : null;
  const issueNextStep =
    issues > 0
      ? noRecords.length > 0
        ? language === 'bisaya'
          ? 'Ang saved absent rows kay kanang naa gyud sa DTR table. Ang generated no-record workdays kay scheduled workdays nga walay punches, mao na sila ang possible absent days.'
          : language === 'tagalog'
            ? 'Ang saved absent rows ay yung totoong nasa DTR table. Ang generated no-record workdays ay scheduled workdays na walang punches, kaya sila ang possible absent days.'
            : 'Saved absent rows are actual DTR rows. Generated no-record workdays are scheduled workdays with no punches, so they are possible absent days.'
        : 'Check missing logs, leave coverage, or locator coverage for the issue dates.'
      : null;
  return structuredReply(language, {
    title: `DTR summary for ${label}`,
    summary,
    details: [
      `Saved DTR rows: ${records.length}`,
      `Present/complete days: ${totals.present}`,
      absenceTotalLine,
      `Incomplete: ${totals.incomplete}`,
      savedAbsentLine,
      noRecordLine,
      `On leave days: ${totals.onLeave}`,
      `Holiday days: ${totals.holiday}`,
      `Total hours: ${fmtHours(totals.hours)}`,
      `Late: ${fmtMinutes(totals.late)}`,
      `Undertime: ${fmtMinutes(totals.undertime)}`,
      `Overtime: ${fmtMinutes(totals.overtime)}`,
    ],
    nextStep: issueNextStep,
    limit: 13,
  });
}

function dtrMissingLogsReply(context, message, explain = false) {
  const language = languageOf(message);
  const label = context.date_range?.label || 'selected period';
  const records = dtrRecords(context);
  const noRecords = noRecordWorkingDays(context);
  if (records.length === 0 && noRecords.length === 0) {
    if (language === 'bisaya') return `Wala koy DTR record para sa ${label}; dili nako ma-confirm kung unsang log ang missing.`;
    if (language === 'tagalog') return `Wala akong DTR record para sa ${label}; hindi ko ma-confirm kung anong log ang missing.`;
    return `I found no DTR record for ${label}, so I cannot confirm which log is missing.`;
  }

  const incomplete = dtrIssueRecords(records, (record) => isIncompleteDtrRecordForContext(context, record));
  if (incomplete.length === 0 && noRecords.length === 0) {
    if (language === 'bisaya') return `Wala koy nakitang missing or incomplete DTR logs sa ${label}.`;
    if (language === 'tagalog') return `Wala akong nakitang missing or incomplete DTR logs sa ${label}.`;
    return `I found no missing or incomplete DTR logs for ${label}.`;
  }

  const recordLines = limitedRequests(incomplete, 8).map((record) => {
    const missing = missingDtrSlotsForContext(context, record);
    const reason = firstMatchingCoverageText(context, record, missing);
    return `${fmtFriendlyDate(record.attendance_date)}: missing ${missing.join(', ')}${
      explain && reason ? `; possible coverage found: ${reason}` : ''
    }`;
  });
  const noRecordLines = limitedRequests(noRecords, Math.max(0, 8 - recordLines.length)).map((day) => {
    return `${fmtFriendlyDate(day.attendance_date)}: no DTR record; expected logs: ${expectedSlotsForCalendarDay(day).join(', ')}${day.shift_name ? ` (${day.shift_name})` : ''}`;
  });
  const lines = [...recordLines, ...noRecordLines];
  const count = incomplete.length + noRecords.length;
  return structuredReply(language, {
    title: `Missing logs for ${label}`,
    summary:
      language === 'bisaya'
        ? `Naa koy nakitang ${count} ka missing or incomplete DTR item.`
        : language === 'tagalog'
          ? `May nakita akong ${count} missing or incomplete DTR item.`
          : `I found ${count} missing or incomplete DTR ${plural(count, 'item')}.`,
    details: lines,
    nextStep:
      language === 'bisaya'
        ? 'I-check kada date kung kinahanglan ba ug HR/Admin correction, locator slip, or leave coverage.'
        : language === 'tagalog'
          ? 'I-check bawat date kung kailangan ng HR/Admin correction, locator slip, o leave coverage.'
          : 'For each date, check if it should be corrected by HR/Admin, covered by a locator slip, or covered by leave.',
    limit: 8,
  });
}

function dtrMinuteSummaryReply(context, message, kind) {
  const language = languageOf(message);
  const records = dtrRecords(context);
  const label = context.date_range?.label || 'selected period';
  const field =
    kind === 'late'
      ? 'late_minutes'
      : kind === 'undertime'
        ? 'undertime_minutes'
        : 'overtime_minutes';
  const issueRecords = dtrIssueRecords(records, (record) => Number(record[field] || 0) > 0);
  const total = issueRecords.reduce((sum, record) => sum + Number(record[field] || 0), 0);
  if (issueRecords.length === 0) {
    if (language === 'bisaya') return `Wala koy nakitang ${kind} records sa ${label}.`;
    if (language === 'tagalog') return `Wala akong nakitang ${kind} records sa ${label}.`;
    return `I found no ${kind} records for ${label}.`;
  }
  const lines = issueRecords.map((record) => `${fmtFriendlyDate(record.attendance_date)}: ${fmtMinutes(record[field])}`);
  return structuredReply(language, {
    title: `${kind} summary for ${label}`,
    summary:
      language === 'bisaya'
        ? `Naa koy nakitang ${issueRecords.length} ka ${kind} record, total ${fmtMinutes(total)}.`
        : language === 'tagalog'
          ? `May nakita akong ${issueRecords.length} ${kind} record, total ${fmtMinutes(total)}.`
          : `I found ${issueRecords.length} ${kind} ${plural(issueRecords.length, 'record')}, total ${fmtMinutes(total)}.`,
    details: lines,
    nextStep: kind === 'late'
      ? 'Ask why you were late if you want the schedule/grace-period breakdown.'
      : null,
    limit: 8,
  });
}

function dtrLateReasonReply(context, message) {
  const language = languageOf(message);
  const records = dtrIssueRecords(dtrRecords(context), (record) => Number(record.late_minutes || 0) > 0);
  if (records.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang late minutes sa selected DTR records.';
    if (language === 'tagalog') return 'Wala akong nakitang late minutes sa selected DTR records.';
    return 'I found no late minutes in the selected DTR records.';
  }
  const lines = records.map((record) => {
    const day = calendarDayForDate(context, record.attendance_date);
    const grace = Number(day?.grace_period_minutes || 0);
    const shiftStart = timeTextToMinutes(day?.start_time);
    const breakEnd = timeTextToMinutes(day?.break_end);
    const timeInMinutes = minutesFromIsoInHrmsTimezone(record.time_in);
    const breakInMinutes = minutesFromIsoInHrmsTimezone(record.break_in);
    const amCutoff = shiftStart != null ? shiftStart + grace : null;
    const pmCutoff = breakEnd != null ? breakEnd + grace : null;
    const computed = [];
    if (amCutoff != null && timeInMinutes != null && timeInMinutes > amCutoff) {
      computed.push(`AM in ${fmtClockMinutes(timeInMinutes)} after cutoff ${fmtClockMinutes(amCutoff)} by ${fmtMinutes(timeInMinutes - amCutoff)}`);
    }
    if (pmCutoff != null && breakInMinutes != null && breakInMinutes > pmCutoff) {
      computed.push(`PM in ${fmtClockMinutes(breakInMinutes)} after cutoff ${fmtClockMinutes(pmCutoff)} by ${fmtMinutes(breakInMinutes - pmCutoff)}`);
    }
    const pieces = [
      `time in ${fmtTime(record.time_in)}`,
      `late ${fmtMinutes(record.late_minutes)}`,
      day?.shift_name
        ? `shift ${day.shift_name} ${day.start_time || ''}-${day.end_time || ''}, grace ${grace} min`
        : 'no shift schedule found',
      computed.length > 0 ? `reason: ${computed.join('. ')}` : null,
      record.source ? `source ${record.source}` : null,
      record.remarks ? `remarks ${record.remarks}` : null,
    ].filter(Boolean);
    return `${fmtFriendlyDate(record.attendance_date)}: ${pieces.join(', ')}`;
  });
  return structuredReply(language, {
    title: 'Late details',
    summary:
      language === 'bisaya'
        ? `Naa koy nakitang ${records.length} ka late record sa selected DTR records.`
        : language === 'tagalog'
          ? `May nakita akong ${records.length} late record sa selected DTR records.`
          : `I found ${records.length} late ${plural(records.length, 'record')} in the selected DTR records.`,
    details: lines,
    nextStep: 'If the late minutes look wrong, compare the cutoff time with your actual time-in and ask HR/Admin to review.',
    limit: 5,
  });
}

function dtrAbsentSummaryReply(context, message) {
  const language = languageOf(message);
  const label = context.date_range?.label || 'selected period';
  const displayLabel = displayPeriodLabel(label, language);
  const absent = dtrIssueRecords(dtrRecords(context), isAbsentDtrRecord);
  const noRecords = noRecordWorkingDays(context);
  if (absent.length === 0 && noRecords.length === 0) {
    if (language === 'bisaya') return `Wala koy nakitang absent or no-record DTR para sa ${displayLabel}.`;
    if (language === 'tagalog') return `Wala akong nakitang DTR record na marked absent sa ${displayLabel}.`;
    return `I found no DTR records marked absent for ${displayLabel}.`;
  }
  const absentLines = absent.map((record) => `${fmtFriendlyDate(record.attendance_date)}: saved as ${statusLabel(record.status)}`);
  const noRecordLines = noRecords.map((day) => `${fmtFriendlyDate(day.attendance_date)}: no DTR record saved for a scheduled workday${day.shift_name ? ` (${day.shift_name})` : ''}`);
  const all = [...absentLines, ...noRecordLines];
  if (language === 'bisaya') {
    return structuredReply(language, {
      title: `Absence check - ${displayLabel}`,
      summary: `Naa koy nakitang ${all.length} ka possible absent/no-record workday sa ${displayLabel}.`,
      details: all.map((line) =>
        line
          .replace(/saved as/i, 'saved as')
          .replace(/no DTR record saved for a scheduled workday/i, 'walay DTR record nga na-save sa scheduled workday')
      ),
      nextStep: 'I-check kung dapat ba ni ma-cover sa leave, locator, holiday, or DTR correction.',
      limit: 8,
    });
  }
  if (language === 'tagalog') {
    return structuredReply(language, {
      title: `Absence check para sa ${displayLabel}`,
      summary: `May nakita akong ${all.length} possible absence/no-record ${plural(all.length, 'day')}.`,
      details: all.map((line) =>
        line.replace(/no DTR record saved for a scheduled workday/i, 'walang DTR record na na-save para sa scheduled workday')
      ),
      nextStep: 'I-check kung dapat ba itong ma-cover ng leave, locator, holiday, o DTR correction.',
      limit: 8,
    });
  }
  return structuredReply(language, {
    title: `Absence check for ${displayLabel}`,
    summary: `I found ${all.length} possible absence/no-record ${plural(all.length, 'day')}.`,
    details: all,
    nextStep: 'Check if these dates should be covered by leave, locator, holiday, or a DTR correction.',
    limit: 8,
  });
}

function firstMatchingLeave(context, date) {
  return (context.recent_leave_requests || []).find((request) => {
    if (!approvedStatus(request.status)) return false;
    return request.start_date <= date && request.end_date >= date;
  });
}

function firstMatchingLocator(context, date) {
  return (context.recent_locator_slips || []).find((slip) => {
    return slip.slip_date === date && approvedStatus(slip.status);
  });
}

function locatorCoversSlot(slip, slot) {
  if (slot === 'AM in') return slip?.coverage?.am_in === true;
  if (slot === 'AM out') return slip?.coverage?.am_out === true;
  if (slot === 'PM in') return slip?.coverage?.pm_in === true;
  if (slot === 'PM out') return slip?.coverage?.pm_out === true;
  if (slot === 'no DTR record') {
    return (
      slip?.coverage?.am_in === true ||
      slip?.coverage?.am_out === true ||
      slip?.coverage?.pm_in === true ||
      slip?.coverage?.pm_out === true
    );
  }
  return false;
}

function locatorCoverageForMissingSlots(context, date, missingSlots = []) {
  const slips = (context.recent_locator_slips || []).filter((slip) => {
    return slip.slip_date === date && approvedStatus(slip.status);
  });
  if (slips.length === 0) return null;
  const missing = missingSlots.length > 0 ? missingSlots : ['no DTR record'];
  for (const slip of slips) {
    const covered = missing.filter((slot) => locatorCoversSlot(slip, slot));
    if (covered.length > 0) {
      const uncovered = missing.filter((slot) => !covered.includes(slot));
      return `${locatorCoverageText(slip)}. Covered: ${covered.join(', ')}${
        uncovered.length > 0 ? `. Not covered: ${uncovered.join(', ')}` : ''
      }`;
    }
  }
  return `${locatorCoverageText(slips[0])}. It does not match the missing logs: ${missing.join(', ')}`;
}

function locatorCoverageText(slip) {
  const slots = [];
  if (slip?.coverage?.am_in) slots.push('AM in');
  if (slip?.coverage?.am_out) slots.push('AM out');
  if (slip?.coverage?.pm_in) slots.push('PM in');
  if (slip?.coverage?.pm_out) slots.push('PM out');
  return `${slip.request_type_label || slip.request_type || 'Locator'} ${statusLabel(slip.status)}${
    slots.length > 0 ? ` covering ${slots.join(', ')}` : ''
  }`;
}

function firstMatchingCoverageText(context, record, missingSlots = []) {
  const date = fmtDate(record?.attendance_date);
  const leave = firstMatchingLeave(context, date);
  if (leave) return `${labelLeaveType(leave.leave_type)} (${workflowStatusText(leave.status)})`;
  const locatorText = locatorCoverageForMissingSlots(context, date, missingSlots);
  if (locatorText) return locatorText;
  return null;
}

function dtrStatusExplanationReply(context, message) {
  const language = languageOf(message);
  const range = context.date_range || {};
  if (range.startDate && range.endDate && range.startDate !== range.endDate) {
    return dtrRangeSummaryReply(context, message);
  }
  const record = dtrRecords(context)[0];
  if (!record) {
    const day = range.startDate ? calendarDayForDate(context, range.startDate) : null;
    const dateText = range.startDate
      ? fmtLocalizedDateRange(range.startDate, range.endDate, language)
      : range.label || 'the selected date';
    if (day?.holiday_name) {
      return structuredReply(language, {
        title: 'DTR check',
        summary:
          language === 'bisaya'
            ? `Wala koy DTR punch record ${dateText}, pero holiday ni: ${day.holiday_name}.`
            : language === 'tagalog'
              ? `Wala akong DTR punch record ${dateText}, pero holiday ito: ${day.holiday_name}.`
              : `I found no DTR punch record ${dateText}, but this date is marked as ${day.holiday_name}.`,
        details: [
          `Status: ${statusLabel('holiday')}`,
          `Holiday coverage: ${day.holiday_coverage || 'whole_day'}`,
          day.shift_name ? `Schedule: ${day.shift_name}` : null,
        ],
        nextStep:
          language === 'bisaya'
            ? 'No action needed kung sakto ang holiday setup.'
            : language === 'tagalog'
              ? 'No action needed kung tama ang holiday setup.'
              : 'No action is needed if the holiday setup is correct.',
      });
    }
    if (day && !isCalendarWorkingDay(day)) {
      return structuredReply(language, {
        title: 'DTR check',
        summary:
          language === 'bisaya'
            ? `Wala koy DTR record ${dateText} kay dili siya required-log day base sa schedule context.`
            : language === 'tagalog'
              ? `Wala akong DTR record ${dateText} dahil hindi siya required-log day base sa schedule context.`
              : `I found no DTR record ${dateText} because it is not a required-log day in the schedule context.`,
        details: [
          `Status: ${statusLabel('rest_day')}`,
          `Schedule: ${day.shift_name || 'rest day/no required logs'}`,
          'Expected logs: none',
        ],
        nextStep:
          language === 'bisaya'
            ? 'No action needed kung sakto ang imong schedule ani nga date.'
            : language === 'tagalog'
              ? 'No action needed kung tama ang schedule mo sa date na ito.'
              : 'No action is needed if your schedule for that date is correct.',
      });
    }
    if (day && isCalendarWorkingDay(day)) {
      const expected = expectedSlotsForCalendarDay(day);
      const coverage = locatorCoverageForMissingSlots(context, day.attendance_date, ['no DTR record']);
      return structuredReply(language, {
        title: `DTR check for ${fmtFriendlyDate(day.attendance_date)}`,
        summary:
          language === 'bisaya'
            ? `Status: Absent/no DTR record. Scheduled workday ni pero wala koy nakitang DTR punches.`
            : language === 'tagalog'
              ? `Status: Absent/no DTR record. Scheduled workday ito pero wala akong nakitang DTR punches.`
              : 'Status: Absent/no DTR record. This is a scheduled workday, but no DTR punches were found.',
        details: [
          `Shift: ${day.shift_name || 'shift'} ${fmtScheduleRange(day)}`.trim(),
          `Grace period: ${fmtMinutes(day.grace_period_minutes || 0)}`,
          `Expected logs: ${expected.join(', ') || 'none'}`,
          coverage ? `Locator coverage: ${coverage}` : null,
          ...dtrPolicyLines(message, ['daily_logs', 'coverage'], {
            maxPointsPerSection: 1,
          }),
        ],
        nextStep:
          language === 'bisaya'
            ? 'Kung ni-duty ka ani nga adlaw, i-check kung kinahanglan ba ug DTR correction, locator slip, or leave coverage.'
            : language === 'tagalog'
              ? 'Kung pumasok ka sa araw na ito, i-check kung kailangan ng DTR correction, locator slip, o leave coverage.'
              : 'If you worked that day, check whether you need a DTR correction, locator slip, or leave coverage.',
      });
    }
    if (language === 'bisaya') {
      return structuredReply(language, {
        title: 'DTR check',
        summary: `Wala koy nakitang DTR record ${dateText}.`,
        nextStep: 'Kung working day ni, i-check kung covered ba siya sa leave, locator, holiday, or HR correction.',
      });
    }
    if (language === 'tagalog') {
      return structuredReply(language, {
        title: 'DTR check',
        summary: `Wala akong nakitang DTR record ${dateText}.`,
        nextStep: 'Kung working day ito, i-check kung covered siya ng leave, locator, holiday, o HR correction.',
      });
    }
    return structuredReply(language, {
      title: 'DTR check',
      summary: `I found no DTR record ${dateText}.`,
      nextStep: 'If this is a working day, check whether leave, locator, holiday, or HR correction should cover it.',
    });
  }
  const missing = missingDtrSlotsForContext(context, record);
  const coverage = firstMatchingCoverageText(context, record, missing);
  const day = calendarDayForDate(context, record.attendance_date);
  const parts = [
    `Status: ${statusLabel(record.status)}`,
    day?.shift_name ? `Shift: ${day.shift_name} ${fmtScheduleRange(day)}` : null,
    missing.length > 0 ? `Missing logs: ${missing.join(', ')}` : null,
    record.leave_type ? `Linked leave: ${labelLeaveType(record.leave_type)}` : null,
    record.holiday_name ? `Holiday: ${record.holiday_name}` : null,
    coverage ? `Coverage: ${coverage}` : null,
    record.remarks ? `Remarks: ${record.remarks}` : null,
  ];
  const summary =
    language === 'bisaya'
      ? `Ang DTR status nimo kay ${statusLabel(record.status)}.`
      : language === 'tagalog'
        ? `Ang DTR status mo ay ${statusLabel(record.status)}.`
        : `Your DTR status is ${statusLabel(record.status)}.`;
  const nextStep =
    missing.length > 0
      ? language === 'bisaya'
        ? 'I-review ang missing logs ug i-check kung dapat covered sa leave, locator, or HR correction.'
        : language === 'tagalog'
          ? 'I-review ang missing logs at i-check kung dapat covered ng leave, locator, o HR correction.'
          : 'Review the missing logs and check if leave, locator, or HR correction should cover them.'
      : null;
  return structuredReply(language, {
    title: `DTR explanation for ${fmtFriendlyDate(record.attendance_date)}`,
    summary,
    details: parts,
    nextStep,
  });
}

function dtrCorrectionGuidanceReply(context, message) {
  const language = languageOf(message);
  const incomplete = dtrIssueRecords(dtrRecords(context), (record) =>
    isIncompleteDtrRecordForContext(context, record)
  );
  const requestedSlot = requestedDtrSlot(message);
  const target =
    (requestedSlot
      ? incomplete.find((record) => missingDtrSlotsForContext(context, record).includes(requestedSlot))
      : null) ||
    incomplete[0] ||
    dtrRecords(context)[0] ||
    null;
  const missing = missingDtrSlotsForContext(context, target);
  const coverage = target ? firstMatchingCoverageText(context, target, missing) : null;
  const issue = target
    ? `${fmtFriendlyDate(target.attendance_date)}${missing.length > 0 ? ` missing ${missing.join(', ')}` : ''}`
    : context.date_range?.label || 'selected date';
  const guidance = coverage
    ? language === 'bisaya'
      ? [
          `Posibleng coverage nga nakita: ${coverage}`,
          'Pangutan-a ang HR/Admin kung na-post o na-sync na ba kini sa imong DTR.',
        ]
      : language === 'tagalog'
        ? [
            `Posibleng coverage na nakita: ${coverage}`,
            'Tanungin ang HR/Admin kung na-post o na-sync na ito sa DTR mo.',
          ]
        : [
            `Possible coverage found: ${coverage}`,
            'Ask HR/Admin if this has already been posted or synced to your DTR.',
          ]
    : language === 'bisaya'
      ? [
          'Kung official business o WFH kini, i-file o i-check ang matching locator slip.',
          'Kung missed punch kini, kontaka ang HR/Admin para sa manual correction ug andama ang proof o remarks.',
          'Kung naka-leave ka, i-file o i-check ang matching leave request.',
        ]
      : language === 'tagalog'
        ? [
            'Kung official business o WFH ito, i-file o i-check ang matching locator slip.',
            'Kung missed punch ito, kontakin ang HR/Admin para sa manual correction at ihanda ang proof o remarks.',
            'Kung naka-leave ka, i-file o i-check ang matching leave request.',
          ]
        : [
            'If this was official business or WFH, file/check a locator slip.',
            'If this was a missed punch, contact HR/Admin for manual correction and prepare proof or remarks.',
            'If you were on leave, file/check the leave request.',
          ];
  const policyDetails =
    language === 'english'
      ? dtrPolicyLines(message, ['coverage', 'correction'], {
          maxPointsPerSection: 1,
        })
      : [
          language === 'bisaya'
            ? 'Andama ang date, exact missing slot, actual work details, ug supporting proof o remarks para sa HR/Admin review.'
            : 'Ihanda ang date, exact missing slot, actual work details, at supporting proof o remarks para sa HR/Admin review.',
        ];
  return structuredReply(language, {
    title:
      language === 'bisaya'
        ? 'Unsaon pag-correct sa DTR issue'
        : language === 'tagalog'
          ? 'Paano ayusin ang DTR issue'
          : 'How to fix this DTR issue',
    summary:
      language === 'bisaya'
        ? `Issue nga i-check: ${issue}.`
        : language === 'tagalog'
          ? `Issue na iche-check: ${issue}.`
          : `Target issue: ${issue}.`,
    details: [
      ...guidance,
      ...policyDetails,
    ],
    nextStep:
      language === 'bisaya'
        ? 'Sugdi sa option nga tinuod nga nahitabo sa maong date.'
        : language === 'tagalog'
          ? 'Magsimula sa option na talagang nangyari sa petsang iyon.'
          : 'Start with the option that matches what actually happened on that date.',
    limit: 7,
  });
}

function dtrLeaveCoverageReply(context, message) {
  const language = languageOf(message);
  const label = context.date_range?.label || 'selected period';
  const leaves = (context.recent_leave_requests || []).filter((request) => {
    return approvedStatus(request.status) && requestOverlapsRange(request, context.date_range);
  });
  if (leaves.length === 0) {
    if (language === 'bisaya') return `Wala koy nakitang approved leave nga ni-cover sa ${label}.`;
    if (language === 'tagalog') return `Wala akong nakitang approved leave na nag-cover sa ${label}.`;
    return `I found no approved leave covering ${label}.`;
  }
  const lines = leaves.map((request) => fmtLeaveRequest(request, language));
  return structuredReply(language, {
    title: `Leave coverage for ${label}`,
    summary:
      language === 'bisaya'
        ? `Naa koy nakitang ${leaves.length} ka approved leave request nga ni-cover ani nga period.`
        : language === 'tagalog'
          ? `May nakita akong ${leaves.length} approved leave request na nag-cover sa period na ito.`
          : `I found ${leaves.length} approved leave ${plural(leaves.length, 'request')} covering this period.`,
    details: lines,
    nextStep:
      language === 'bisaya'
        ? 'Kung absent/missing logs gihapon sa DTR, ipa-check sa HR/Admin kung na-post ba ang leave sa DTR.'
        : language === 'tagalog'
          ? 'Kung absent/missing logs pa rin sa DTR, ipa-check sa HR/Admin kung na-post na ang leave sa DTR.'
          : 'If the DTR still shows absent/missing logs, ask HR/Admin to verify whether the leave was posted to DTR.',
    limit: 5,
  });
}

function dtrLocatorCoverageReply(context, message) {
  const language = languageOf(message);
  const label = context.date_range?.label || 'selected period';
  const requestedSlot = requestedDtrSlot(message);
  const slips = (context.recent_locator_slips || []).filter((slip) => {
    if (!context.date_range?.startDate || !context.date_range?.endDate) return true;
    return slip.slip_date >= context.date_range.startDate && slip.slip_date <= context.date_range.endDate;
  });
  if (slips.length === 0) {
    return structuredReply(language, {
      title: 'Locator coverage check',
      summary:
        language === 'bisaya'
          ? `Wala koy nakitang locator slip para sa ${localizedPeriodLabel(label, language)}.`
          : language === 'tagalog'
            ? `Wala akong nakitang locator slip para sa ${localizedPeriodLabel(label, language)}.`
            : `I found no locator slip for ${label}.`,
      nextStep:
        language === 'bisaya'
          ? 'Kung missing log ni, i-check kung kinahanglan ba mag-file ug locator or DTR correction.'
          : language === 'tagalog'
            ? 'Kung missing log ito, i-check kung kailangan ng locator o DTR correction.'
            : 'If this is for a missing log, check whether you need a locator slip or DTR correction.',
    });
  }
  const approvedMatching = requestedSlot
    ? slips.filter((slip) => approvedStatus(slip.status) && locatorCoversSlot(slip, requestedSlot))
    : slips.filter((slip) => approvedStatus(slip.status));
  const lines = slips.map((slip) => {
    const slotCheck = requestedSlot
      ? locatorCoversSlot(slip, requestedSlot)
        ? `covers ${requestedSlot}`
        : `does not cover ${requestedSlot}`
      : locatorSlots(slip).length > 0
        ? `covers ${locatorSlots(slip).join(', ')}`
        : 'no covered slot saved';
    const finalCoverage = approvedStatus(slip.status) ? '' : ', not final coverage until approved';
    return `${fmtFriendlyDate(slip.slip_date)}: ${locatorCoverageText(slip)} (${slotCheck}${finalCoverage})${
      slip.hr_remarks ? `, HR remarks ${slip.hr_remarks}` : ''
    }`;
  });
  const summary = requestedSlot
    ? approvedMatching.length > 0
      ? language === 'bisaya'
        ? `Naa koy approved locator nga ni-cover sa ${requestedSlot} para sa ${localizedPeriodLabel(label, language)}.`
        : language === 'tagalog'
          ? `May approved locator na nag-cover sa ${requestedSlot} para sa ${localizedPeriodLabel(label, language)}.`
          : `I found an approved locator covering ${requestedSlot} for ${label}.`
      : language === 'bisaya'
        ? `Naa koy locator slip, pero wala koy approved locator nga klarong ni-cover sa ${requestedSlot}.`
        : language === 'tagalog'
          ? `May locator slip, pero wala akong approved locator na malinaw na nag-cover sa ${requestedSlot}.`
          : `I found locator slips, but no approved locator clearly covers ${requestedSlot}.`
    : language === 'bisaya'
      ? `Nakita nako ang ${slips.length} ka locator slip para sa ${localizedPeriodLabel(label, language)}.`
      : language === 'tagalog'
        ? `May nakita akong ${slips.length} locator slip para sa ${localizedPeriodLabel(label, language)}.`
        : `I found ${slips.length} locator ${plural(slips.length, 'slip')} in this period.`;
  return structuredReply(language, {
    title: `Locator coverage for ${label}`,
    summary,
    details: lines,
    nextStep:
      requestedSlot && approvedMatching.length === 0
        ? language === 'bisaya'
          ? 'Kung mao ni ang missing slot, i-check kung naa bay lain approved locator, leave, holiday, or DTR correction.'
          : language === 'tagalog'
            ? 'Kung ito ang missing slot, i-check kung may ibang approved locator, leave, holiday, o DTR correction.'
            : 'If this is the missing slot, check for another approved locator, leave, holiday, or DTR correction.'
        : 'If a specific log is missing, ask me to check locator coverage for that missing slot.',
    limit: 5,
  });
}

function dtrHolidayReply(context, message) {
  const language = languageOf(message);
  const recordHolidays = dtrRecords(context)
    .filter((record) => record.holiday_name || lower(record.status) === 'holiday')
    .map((record) => ({
      date: fmtDate(record.attendance_date),
      displayDate: fmtFriendlyDate(record.attendance_date),
      name: record.holiday_name || 'holiday',
      type: record.holiday_type || statusLabel(record.status),
      coverage: 'from DTR',
    }));
  const calendarHolidays = dtrCalendarDays(context)
    .filter((day) => day.holiday_name)
    .map((day) => ({
      date: day.attendance_date,
      displayDate: fmtFriendlyDate(day.attendance_date),
      name: day.holiday_name,
      type: day.holiday_type,
      coverage: day.holiday_coverage,
    }));
  const seen = new Set();
  const holidays = [...recordHolidays, ...calendarHolidays].filter((item) => {
    const key = `${item.date}|${item.name}|${item.coverage}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  if (holidays.length === 0) {
    const range = context.date_range || {};
    const period = range.startDate
      ? fmtLocalizedDateRange(range.startDate, range.endDate, language)
      : range.label || 'the selected period';
    if (language === 'bisaya') {
      return structuredReply(language, {
        title: 'Holiday check',
        summary: `Wala koy nakitang holiday record ${period}.`,
        nextStep: 'Kung dapat holiday ni, ipa-check sa HR/Admin ang holiday calendar setup.',
      });
    }
    if (language === 'tagalog') {
      return structuredReply(language, {
        title: 'Holiday check',
        summary: `Wala akong nakitang holiday record ${period}.`,
        nextStep: 'Kung dapat holiday ito, ipa-check sa HR/Admin ang holiday calendar setup.',
      });
    }
    return structuredReply(language, {
      title: 'Holiday check',
      summary: `I found no holiday record ${period}.`,
      nextStep: 'If this should be a holiday, ask HR/Admin to check the holiday calendar setup.',
    });
  }
  const lines = holidays.map((holiday) => `${holiday.displayDate || fmtFriendlyDate(holiday.date)}: ${holiday.name} (${holiday.type || 'holiday'}, ${holiday.coverage || 'whole_day'})`);
  const summary =
    language === 'bisaya'
      ? `Nakita nako ang ${holidays.length} ka holiday record para ani nga period.`
      : language === 'tagalog'
        ? `Nakakita ako ng ${holidays.length} holiday ${plural(holidays.length, 'record')} para sa period na ito.`
        : `I found ${holidays.length} holiday-linked ${plural(holidays.length, 'record')} for this period.`;
  const nextStep =
    language === 'bisaya'
      ? 'Kung holiday date pero na-count gihapon nga absent, ipa-review sa HR/Admin ang holiday coverage ug schedule setup.'
      : language === 'tagalog'
        ? 'Kung holiday date pero na-count pa rin as absent, ipa-review sa HR/Admin ang holiday coverage at schedule setup.'
        : 'If a holiday date is still counted as absent, ask HR/Admin to review the holiday coverage and schedule setup.';
  return structuredReply(language, {
    title: 'Holiday check',
    summary,
    details: lines,
    nextStep,
    limit: 5,
  });
}

function dtrScheduleContextReply(context, message) {
  const language = languageOf(message);
  const days = dtrCalendarDays(context).filter((day) => day.shift_id || day.holiday_id);
  if (days.length === 0) {
    const text = 'I found no assignment/shift schedule for the selected period. HR/Admin should confirm schedule-specific late or undertime rules.';
    if (language === 'bisaya') return 'Wala koy nakitang assigned shift schedule para sa gipiling period. Ipa-confirm sa HR/Admin ang exact schedule, late cutoff, ug undertime rules.';
    if (language === 'tagalog') return 'Wala akong nakitang assigned shift schedule para sa napiling period. Ipa-confirm sa HR/Admin ang exact schedule, late cutoff, at undertime rules.';
    return text;
  }
  if (days.length === 1) {
    const day = days[0];
    const expected = expectedSlotsForCalendarDay(day);
    const scheduleRange = fmtScheduleRange(day);
    const shiftName = day.shift_name || 'scheduled shift';
    const date = fmtFriendlyDate(day.attendance_date);
    const details = [
      `Date: ${date}`,
      scheduleRange ? `Time: ${scheduleRange}` : null,
      `Grace period: ${fmtMinutes(day.grace_period_minutes || 0)}`,
      `Expected logs: ${expected.length > 0 ? expected.join(', ') : 'none'}`,
      day.holiday_name
        ? `Holiday: ${day.holiday_name} (${day.holiday_coverage || 'whole_day'})`
        : null,
    ];

    if (!isCalendarWorkingDay(day)) {
      return structuredReply(language, {
        title: 'Current shift',
        summary:
          language === 'bisaya'
            ? `Wala kay required DTR logs sa ${date} base sa schedule context. ${day.holiday_name ? `${day.holiday_name} ni.` : 'Non-working/rest day ni.'}`
            : language === 'tagalog'
              ? `Wala kang required DTR logs noong ${date} base sa schedule context. ${day.holiday_name ? `${day.holiday_name} ito.` : 'Non-working/rest day ito.'}`
              : `You have no required DTR logs on ${date} based on the schedule context. ${day.holiday_name ? `It is ${day.holiday_name}.` : 'It is a non-working/rest day.'}`,
        details,
      });
    }

    return structuredReply(language, {
      title: 'Current shift',
      summary:
        language === 'bisaya'
          ? `Ang imong current shift kay ${shiftName}${scheduleRange ? `, ${scheduleRange}` : ''}.`
          : language === 'tagalog'
            ? `Ang current shift mo ay ${shiftName}${scheduleRange ? `, ${scheduleRange}` : ''}.`
            : `Your current shift is ${shiftName}${scheduleRange ? `, ${scheduleRange}` : ''}.`,
      details,
      nextStep:
        language === 'bisaya'
          ? 'I-check kini kung gusto nimo mahibaloan ang expected logs, late cutoff, or undertime basis.'
          : language === 'tagalog'
            ? 'Gamitin ito para ma-check ang expected logs, late cutoff, o undertime basis.'
            : 'Use this to check expected logs, late cutoff, or undertime basis.',
    });
  }
  const lines = limitedRequests(days, 7).map((day) => {
    const expected = expectedSlotsForCalendarDay(day);
    const working = isCalendarWorkingDay(day) ? 'working day' : 'non-working/no required logs';
    const holiday = day.holiday_name
      ? `, holiday ${day.holiday_name} (${day.holiday_coverage || 'whole_day'})`
      : '';
    return `${fmtFriendlyDate(day.attendance_date)}: ${day.shift_name || 'no shift'} ${day.start_time || ''}-${day.end_time || ''}, grace ${day.grace_period_minutes || 0} min, ${working}, expected ${expected.length > 0 ? expected.join(', ') : 'none'}${holiday}`;
  });
  return structuredReply(language, {
    title: `Schedule context for ${context.date_range?.label || 'selected period'}`,
    summary:
      language === 'bisaya'
        ? `Naa koy nakitang ${days.length} ka schedule/holiday day.`
        : language === 'tagalog'
          ? `May nakita akong ${days.length} schedule/holiday day.`
          : `I found ${days.length} schedule/holiday ${plural(days.length, 'day')}.`,
    details: [
      ...lines,
      ...dtrPolicyLines(message, ['daily_logs', 'schedule_late_undertime'], {
        maxPointsPerSection: 1,
      }),
    ],
    nextStep: 'Use this to verify expected logs, late cutoff, undertime, rest day, or holiday handling.',
    limit: 10,
  });
}

function dtrExportGuidanceReply(context, message) {
  const language = languageOf(message);
  return structuredReply(language, {
    title: 'DTR export',
    summary:
      language === 'bisaya'
        ? 'Nakahimo ko ug Excel export para sa selected DTR period.'
        : language === 'tagalog'
          ? 'Nakagawa ako ng Excel export para sa selected DTR period.'
          : 'I generated an Excel export for the selected DTR period.',
    details: [
      'The file includes the DTR records currently loaded for this chat.',
      'For signed official DTR forms, still use the DTR/attendance report page or HR/Admin workflow.',
      ...dtrPolicyLines(message, ['export_review'], { maxPointsPerSection: 2 }),
    ],
    nextStep: 'Download the attached Excel file from this message.',
    limit: 5,
  });
}

function dtrPolicyGuidanceReply(context, message) {
  const language = languageOf(message);
  if (/\b(grace period|grace minutes|late cutoff)\b/i.test(message)) {
    const scheduledDay = (context.calendar_days || []).find(
      (day) => day?.shift_name || day?.shift_start
    );
    const graceMinutes = Number(scheduledDay?.grace_minutes || 0);
    const details = [
      language === 'bisaya'
        ? 'Ang grace period idugang sa scheduled time-in. Late na ang punch kung molapas sa scheduled start plus grace period.'
        : language === 'tagalog'
          ? 'Idinadagdag ang grace period sa scheduled time-in. Late na ang punch kapag lumampas sa scheduled start plus grace period.'
          : 'The grace period is added to the scheduled time-in. A punch becomes late only after the scheduled start plus the grace period.',
      scheduledDay?.shift_name
        ? `${language === 'bisaya' ? 'Assigned shift' : language === 'tagalog' ? 'Assigned shift' : 'Assigned shift'}: ${scheduledDay.shift_name}${
            fmtScheduleRange(scheduledDay) ? ` (${fmtScheduleRange(scheduledDay)})` : ''
          }`
        : null,
      scheduledDay
        ? `${language === 'bisaya' ? 'Configured grace period' : language === 'tagalog' ? 'Configured grace period' : 'Configured grace period'}: ${fmtMinutes(graceMinutes)}`
        : language === 'bisaya'
          ? 'Wala na-load ang exact assigned schedule para sa selected date, mao nga dili ko mo-invent ug grace minutes.'
          : language === 'tagalog'
            ? 'Hindi naka-load ang exact assigned schedule para sa selected date, kaya hindi ako mag-iimbento ng grace minutes.'
            : 'The exact assigned schedule is not loaded for the selected date, so I will not invent a grace-period value.',
    ];
    return structuredReply(language, {
      title:
        language === 'bisaya'
          ? 'DTR grace period'
          : language === 'tagalog'
            ? 'DTR grace period'
            : 'DTR grace period',
      summary:
        language === 'bisaya'
          ? 'Base ang late computation sa imong assigned shift ug configured grace period.'
          : language === 'tagalog'
            ? 'Nakabase ang late computation sa assigned shift at configured grace period mo.'
            : 'Late computation uses your assigned shift and its configured grace period.',
      details,
      nextStep:
        language === 'bisaya'
          ? 'Pangutan-a ko sa specific date kung gusto nimo makita ang exact shift ug late cutoff.'
          : language === 'tagalog'
            ? 'Magtanong ng specific date kung gusto mong makita ang exact shift at late cutoff.'
            : 'Ask about a specific date to see the exact shift and late cutoff.',
      limit: 4,
    });
  }
  const sections = getDtrPolicySectionsForMessage('', {
    fallbackKeys: [
      'daily_logs',
      'schedule_late_undertime',
      'coverage',
      'correction',
      'export_review',
    ],
  });
  const label = context.date_range?.label || 'selected period';
  return structuredReply(language, {
    title: 'DTR policy guide',
    summary:
      language === 'bisaya'
        ? 'Mao ni ang DTR rules nga gamit sa assistant para mo-explain sa logs, absences, late, undertime, coverage, ug corrections.'
        : language === 'tagalog'
          ? 'Ito ang DTR rules na ginagamit ng assistant para i-explain ang logs, absences, late, undertime, coverage, at corrections.'
          : 'These are the DTR rules the assistant uses to explain logs, absences, late, undertime, coverage, and corrections.',
    details: policyPointLines(sections, { maxPointsPerSection: 2 }),
    nextStep:
      language === 'bisaya'
        ? `Kung gusto nimo exact check, ask about a specific date or period like ${label}.`
        : language === 'tagalog'
          ? `Kung gusto mo ng exact check, magtanong tungkol sa specific date o period tulad ng ${label}.`
          : `For an exact check, ask about a specific date or period such as ${label}.`,
    limit: 10,
  });
}

function leaveBalanceReply(context, localized, message) {
  const balances = context.leave_balances || [];
  if (balances.length === 0) {
    return localized
      ? 'Wala akong nakitang leave balance records para sa account mo.'
      : 'I found no leave balance records for your account.';
  }

  const language = languageOf(message);
  const requestedType = requestedLeaveType(message);
  const requestedRecord = requestedLeaveTypeRecord(message, context);
  const selected = balances.filter((b) => {
    if (requestedRecord) return leaveBalanceMatchesRecord(b, requestedRecord);
    return leaveTypeMatches(b, requestedType);
  });
  const visibleBalances = selected.length > 0 ? selected : balances;
  const why = isWhyBalanceQuestion(message);

  if (why && visibleBalances.length === 1) {
    const b = visibleBalances[0];
    const type = labelLeaveType(b.leave_type);
    if (language === 'bisaya') {
      return `Ang ${type} balance nimo kay ${fmtLocalizedDayCount(
        b.available_days,
        language
      )} available to file. Gamay siya kung gamay pa ang na-earn or naa nay nagamit/pending: ${balanceFormulaLine(
        b,
        language
      )}.`;
    }
    if (language === 'tagalog') {
      return `Ang ${type} balance mo ay ${fmtLocalizedDayCount(
        b.available_days,
        language
      )} available to file. Maliit ito kung kaunti pa ang earned o may used/pending days: ${balanceFormulaLine(
        b,
        language
      )}.`;
    }
    return `Your ${type} balance is ${fmtLocalizedDayCount(
      b.available_days,
      language
    )} available to file. It may be low because of earned, used, adjusted, and pending days: ${balanceFormulaLine(
      b,
      language
    )}.`;
  }

  if (why) {
    const explanations = visibleBalances.map((b) => {
      return `${labelLeaveType(b.leave_type)}: ${balanceFormulaLine(b, language)}`;
    });
    if (language === 'bisaya') {
      return `Base sa records, mao ni nganong mao ra ang nabilin nga leave balance: ${explanations.join(
        '; '
      )}. Ang available balance maapektuhan sa earned, used, adjusted, ug pending days.`;
    }
    if (language === 'tagalog') {
      return `Base sa records, ito ang breakdown kung bakit ganyan ang natitirang leave balance: ${explanations.join(
        '; '
      )}. Naaapektuhan ang available balance ng earned, used, adjusted, at pending days.`;
    }
    return `Here is why your leave balance is at that amount: ${explanations.join(
      '; '
    )}. Available balance is affected by earned, used, adjusted, and pending days.`;
  }

  const lines = visibleBalances.map((b) => {
    return `${labelLeaveType(b.leave_type)}: ${fmtLocalizedDayCount(
      b.available_days,
      language
    )} available to file; ${fmtLocalizedDayCount(
      b.remaining_days,
      language
    )} remaining; ${fmtLocalizedDayCount(b.pending_days, language)} pending`;
  });

  return structuredReply(language, {
    title: 'Leave balance',
    summary:
      language === 'bisaya'
        ? `Mao ni ang leave balance nga naa sa imong HRMS records.`
        : language === 'tagalog'
          ? `Ito ang leave balance na nasa HRMS records mo.`
          : `Here are the leave balances in your HRMS records.`,
    details: lines,
    limit: 8,
  });
}

function latestLeaveReply(context, localized, message = '') {
  const language = languageOf(message);
  const request = context.recent_leave_requests?.[0];
  if (!request) {
    return localized
      ? 'Wala akong nakitang leave request records para sa account mo.'
      : 'I found no leave request records for your account.';
  }

  const details = `${labelLeaveType(request.leave_type || 'Leave')} ${fmtLocalizedDateRange(
    request.start_date,
    request.end_date,
    language
  )} is ${workflowStatusText(request.status)}`;
  const reviewer =
    request.reviewer_name || request.approver_name || request.latest_history?.actor_name;
  const remarks = firstReviewReason(request)
    ? ` Remarks: ${firstReviewReason(request)}.`
    : '';
  const reviewedBy = reviewer ? ` Last reviewer: ${reviewer}.` : '';

  return localized
    ? `${details}.${remarks}${reviewedBy}`
    : `Your latest leave request: ${details}.${remarks}${reviewedBy}`;
}

function leaveRequestsByStatusReply(context, message, matcher, labels) {
  const language = languageOf(message);
  const useRange = hasDateRangeHint(message);
  const requests = (context.recent_leave_requests || []).filter((request) => {
    if (!matcher(request.status)) return false;
    if (!requestMatchesMessageFilters(request, message, context)) return false;
    if (useRange && !requestOverlapsRange(request, context.date_range)) return false;
    return true;
  });

  if (requests.length === 0) {
    if (language === 'bisaya') return `Wala koy nakitang ${labels.bisaya} leave request.`;
    if (language === 'tagalog') return `Wala akong nakitang ${labels.tagalog} leave request.`;
    return `I found no ${labels.english} leave requests.`;
  }

  const lines = requests.map((request) => {
    const reason = firstReviewReason(request);
    return `${fmtLeaveRequest(request, language)}${
      reason ? `. Remarks: ${trimTrailingSentencePunctuation(reason)}.` : ''
    }`;
  });
  return structuredReply(language, {
    title: `${labels.english[0].toUpperCase()}${labels.english.slice(1)} leave requests`,
    summary:
      language === 'bisaya'
        ? `Nakita nako ang ${requests.length} ka ${labels.bisaya} leave request.`
        : language === 'tagalog'
          ? `May nakita akong ${requests.length} ${labels.tagalog} leave request.`
          : `I found ${requests.length} ${labels.english} leave request${requests.length === 1 ? '' : 's'}.`,
    details: lines,
    limit: 5,
  });
}

function leaveHistoryReply(context, message) {
  const language = languageOf(message);
  const useRange = hasDateRangeHint(message);
  const requests = (context.recent_leave_requests || []).filter((request) => {
    return requestMatchesMessageFilters(request, message, context);
  });

  if (requests.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang leave history para ana nga period.';
    if (language === 'tagalog') return 'Wala akong nakitang leave history para sa period na iyon.';
    return 'I found no leave history for that period.';
  }

  const label = useRange ? context.date_range?.label || 'selected period' : 'recent requests';
  return structuredReply(language, {
    title: `Leave history (${label})`,
    summary:
      language === 'bisaya'
        ? `Naa koy nakitang ${requests.length} ka leave request.`
        : language === 'tagalog'
          ? `May nakita akong ${requests.length} leave request.`
          : `I found ${requests.length} leave request${requests.length === 1 ? '' : 's'}.`,
    details: requests.map((request) => fmtLeaveRequest(request, language)),
    limit: 5,
  });
}

function leaveAvailabilityReply(context, message) {
  const language = languageOf(message);
  const requestedType = requestedLeaveType(message);
  const requestedRecord = requestedLeaveTypeRecord(message, context);
  const days = requestedDaysOrRangeDays(message, context);
  const balances = context.leave_balances || [];
  const selected = balances.filter((b) => {
    if (requestedRecord) return leaveBalanceMatchesRecord(b, requestedRecord);
    return leaveTypeMatches(b, requestedType);
  });
  const balance = requestedType || requestedRecord || selected.length === 1 ? selected[0] : null;

  if (!days) {
    if (language === 'bisaya') return 'Pila ka adlaw nga leave ang imong plano i-file?';
    if (language === 'tagalog') return 'Ilang araw ng leave ang balak mong i-file?';
    return 'How many leave days are you planning to file?';
  }

  if (!requestedType && !requestedRecord && selected.length > 1) {
    if (language === 'bisaya') return 'Unsang leave type ang imong gamiton: sick leave, vacation leave, or lain?';
    if (language === 'tagalog') return 'Anong leave type ang gagamitin mo: sick leave, vacation leave, o iba pa?';
    return 'Which leave type do you want to use: sick leave, vacation leave, or another type?';
  }

  const available = balance ? asNumber(balance.available_days) || 0 : null;
  const type = labelLeaveType(balance?.leave_type || requestedRecord?.display_name || requestedRecord?.name || 'leave');
  const enough = available == null ? null : available >= days;
  const warnings = [];
  const blockers = [];
  const notes = [];
  if (requestedRecord?.employee_can_file === false) {
    blockers.push('employee filing is disabled for this leave type');
  }
  if (requestedRecord?.admin_only === true) {
    blockers.push('this leave type is admin/HR-only');
  }
  if (requestedRecord?.allows_past_dates === false && context.date_range?.startDate) {
    const daysFromToday = daysBetweenIso(new Date().toISOString().slice(0, 10), context.date_range.startDate);
    if (daysFromToday != null && daysFromToday < 0) {
      blockers.push('past-date filing is not allowed for this leave type');
    }
  }
  const advanceDays = asNumber(requestedRecord?.minimum_advance_days);
  if (advanceDays != null && context.date_range?.startDate) {
    const daysFromToday = daysBetweenIso(new Date().toISOString().slice(0, 10), context.date_range.startDate);
    if (daysFromToday != null && daysFromToday < advanceDays) {
      warnings.push(`needs ${fmtDayCount(advanceDays)} advance notice`);
    }
  }
  const maxDays = asNumber(requestedRecord?.max_days);
  if (maxDays != null && days > maxDays) {
    blockers.push(`max allowed is ${fmtDayCount(maxDays)}`);
  }
  if (requestedRecord) {
    notes.push(localizedAttachmentRuleText(requestedRecord, days, language));
  }
  if (!balance) {
    notes.push('no matching leave balance row was found for this leave type');
  }
  if (hasDateRangeHint(message)) {
    const overlaps = (context.recent_leave_requests || []).filter((request) => {
      if (!activeLeaveStatus(request.status)) return false;
      if (!requestOverlapsRange(request, context.date_range)) return false;
      if (requestedRecord && !leaveRequestMatchesRecord(request, requestedRecord)) return false;
      return true;
    });
    if (overlaps.length > 0) {
      blockers.push(
        `Overlap found: ${limitedRequests(overlaps, 2)
          .map((request) => fmtLeaveRequest(request, language))
          .join(' | ')}`
      );
    }
  }
  const baseBalanceEnglish =
    available == null
      ? `I could not verify a balance row for ${type}, but I checked the filing rules for ${fmtDayCount(days)}`
      : `you have ${fmtLocalizedDayCount(available, language)} available ${type} for ${fmtDayCount(days)}`;
  const baseBalanceBisaya =
    available == null
      ? `wala koy matching balance row para sa ${type}, pero na-check nako ang filing rules para sa ${fmtLocalizedDayCount(days, language)}`
      : `naa kay ${fmtLocalizedDayCount(available, language)} available ${type} para sa ${fmtLocalizedDayCount(days, language)}`;
  const baseBalanceTagalog =
    available == null
      ? `wala akong matching balance row para sa ${type}, pero na-check ko ang filing rules para sa ${fmtLocalizedDayCount(days, language)}`
      : `may ${fmtLocalizedDayCount(available, language)} available ${type} para sa ${fmtLocalizedDayCount(days, language)}`;

  if (language === 'bisaya') {
    const details = [
      blockers.length > 0 ? `Issue: ${blockers.join(' | ')}` : null,
      warnings.length > 0 ? `Warning: ${warnings.join(' | ')}` : null,
      ...notes.map((note) => `Note: ${note}`),
    ].filter(Boolean);
    if (blockers.length > 0 || enough === false) {
      const balanceText =
        enough === false
          ? `dili igo ang balance: naa kay ${fmtLocalizedDayCount(available, language)} available ${type}, pero ${fmtLocalizedDayCount(days, language)} imong plano`
          : baseBalanceBisaya;
      return structuredReply(language, {
        title: 'Leave filing check',
        summary: `Dili pa limpyo ang filing check: ${balanceText}.`,
        details,
        nextStep: 'Final approval gihapon ang HR workflow.',
      });
    }
    return structuredReply(language, {
      title: 'Leave filing check',
      summary: `Pwede sa initial filing check: ${baseBalanceBisaya}.`,
      details,
      nextStep: 'Dili pa ni final approval.',
    });
  }
  if (language === 'tagalog') {
    const details = [
      blockers.length > 0 ? `Issue: ${blockers.join(' | ')}` : null,
      warnings.length > 0 ? `Warning: ${warnings.join(' | ')}` : null,
      ...notes.map((note) => `Note: ${note}`),
    ].filter(Boolean);
    if (blockers.length > 0 || enough === false) {
      const balanceText =
        enough === false
          ? `hindi sapat ang balance: may ${fmtLocalizedDayCount(available, language)} available ${type}, pero ${fmtLocalizedDayCount(days, language)} ang plano mo`
          : baseBalanceTagalog;
      return structuredReply(language, {
        title: 'Leave filing check',
        summary: `May issue sa filing check: ${balanceText}.`,
        details,
        nextStep: 'Dadaan pa rin ito sa HR approval workflow.',
      });
    }
    return structuredReply(language, {
      title: 'Leave filing check',
      summary: `Puwede sa initial filing check: ${baseBalanceTagalog}.`,
      details,
      nextStep: 'Hindi pa ito final approval.',
    });
  }
  const details = [
    blockers.length > 0 ? `Issue: ${blockers.join(' | ')}` : null,
    warnings.length > 0 ? `Warning: ${warnings.join(' | ')}` : null,
    ...notes.map((note) => `Note: ${note}`),
  ].filter(Boolean);
  if (blockers.length > 0 || enough === false) {
    const balanceText =
      enough === false
        ? `balance is not enough: you have ${fmtLocalizedDayCount(available, language)} available ${type}, but plan to file ${fmtDayCount(days)}`
        : baseBalanceEnglish;
    return structuredReply(language, {
      title: 'Leave filing check',
      summary: `Filing check found an issue: ${balanceText}.`,
      details,
      nextStep: 'This still needs the normal HR approval workflow.',
    });
  }
  return structuredReply(language, {
    title: 'Leave filing check',
    summary: `Initial filing check looks okay: ${baseBalanceEnglish}.`,
    details,
    nextStep: 'This is not final approval yet.',
  });
}

function leaveTypesReply(context, message) {
  const language = languageOf(message);
  const types = context.leave_types || [];
  if (types.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang active leave types sa system records.';
    if (language === 'tagalog') return 'Wala akong nakitang active leave types sa system records.';
    return 'I found no active leave types in the system records.';
  }

  const visibleTypes = types
    .filter((type) => type.employee_can_file !== false);
  const details = visibleTypes.map((type) => {
    const label = labelLeaveType(type.display_name || type.name);
    const guidance = getLeaveGuidanceForType(type);
    const description = guidance?.description
      ? compactText(localizedLeaveGuidanceField(type, guidance, 'description', language), 125)
      : localizedAvailableForFiling(language);
    return `${label}: ${description}`;
  });

  return structuredReply(language, {
    title: 'Leave types you can file',
    summary:
      language === 'bisaya'
        ? 'Mao ni ang leave types nga pwede nimo ma-file, apil ang short explanation sa kada type.'
        : language === 'tagalog'
          ? 'Ito ang leave types na puwede mong i-file, kasama ang short explanation ng bawat type.'
          : 'These are the leave types you can file, with a short explanation for each one.',
    details,
    nextStep:
      language === 'bisaya'
        ? 'Kung gusto nimo ang requirements, pangutana: "unsay requirements sa sick leave?"'
        : language === 'tagalog'
          ? 'Kung gusto mo ang requirements, itanong: "requirements sa sick leave?"'
          : 'Ask for a specific type if you want requirements, for example: "requirements for sick leave".',
    limit: details.length,
  });
}

function leaveRequirementsReply(context, message) {
  const language = languageOf(message);
  const requestedType = requestedLeaveType(message);
  const requestedRecord = requestedLeaveTypeRecord(message, context);
  const allTypes = context.leave_types || [];
  const selected = requestedRecord
    ? [requestedRecord]
    : allTypes.filter((type) => leaveTypeRecordMatches(type, requestedType));
  const visibleTypes = selected.length > 0 ? selected : allTypes.filter((type) => type.employee_can_file !== false);

  if (visibleTypes.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang leave filing requirements sa system records.';
    if (language === 'tagalog') return 'Wala akong nakitang leave filing requirements sa system records.';
    return 'I found no leave filing requirements in the system records.';
  }

  const lines = visibleTypes.slice(0, 4).map((type) => {
    const guidance = getLeaveGuidanceForType(type);
    const guidelineText = guidance
      ? ` Guideline: ${trimTrailingSentencePunctuation(
          [
            localizedLeaveGuidanceField(type, guidance, 'requirements', language),
            localizedLeaveGuidanceField(type, guidance, 'limits', language),
            localizedLeaveGuidanceField(type, guidance, 'advanceFiling', language),
          ]
            .filter(Boolean)
            .join(' ')
        )}.`
      : '';
    return `${labelLeaveType(type.display_name || type.name)}: ${localizedLeaveRequirementParts(
      type,
      language
    ).join(', ')}.${guidelineText}`;
  });

  return structuredReply(language, {
    title: 'Leave requirements',
    summary:
      language === 'bisaya'
        ? 'Mao ni ang filing requirements base sa HRMS setup ug leave guidelines.'
        : language === 'tagalog'
          ? 'Ito ang filing requirements base sa HRMS setup at leave guidelines.'
          : 'Here are the filing requirements I found from the HRMS setup and guidelines.',
    details: lines.map(trimTrailingSentencePunctuation),
    nextStep: 'Final approval still follows the HR review workflow.',
    limit: 4,
  });
}

function leaveRequirementParts(type) {
  const parts = [];
  parts.push(
    type.employee_can_file === false || type.admin_only
      ? 'employee filing disabled'
      : 'employee can file'
  );
  parts.push(type.allows_past_dates === false ? 'past dates not allowed' : 'past dates allowed');
  parts.push(attachmentRuleText(type));
  if (type.minimum_advance_days != null) {
    parts.push(`${fmtDayCount(type.minimum_advance_days)} advance notice`);
  }
  if (type.max_days != null) {
    parts.push(`max ${fmtDayCount(type.max_days)}`);
  }
  return parts;
}

function matchingLeaveTypes(context, message) {
  const requestedType = requestedLeaveType(message);
  const requestedRecord = requestedLeaveTypeRecord(message, context);
  const allTypes = context.leave_types || [];
  if (requestedRecord) return [requestedRecord];
  const selected = allTypes.filter((type) => leaveTypeRecordMatches(type, requestedType));
  return selected.length > 0 ? selected : allTypes.filter((type) => type.employee_can_file !== false);
}

function leaveAttachmentRequirementReply(context, message) {
  const language = languageOf(message);
  const types = matchingLeaveTypes(context, message);
  const hasSpecificType =
    Boolean(requestedLeaveType(message)) ||
    Boolean(requestedLeaveTypeRecord(message, context));
  const days = requestedDaysOrRangeDays(message, context);
  if (types.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang attachment rule para ana nga leave type.';
    if (language === 'tagalog') return 'Wala akong nakitang attachment rule para sa leave type na iyon.';
    return 'I found no attachment rule for that leave type.';
  }

  const visibleTypes = hasSpecificType ? types.slice(0, 4) : types;
  const lines = visibleTypes.map((type) => {
    const guidance = getLeaveGuidanceForType(type);
    const guideline = guidance?.requirements
      ? ` Guideline: ${trimTrailingSentencePunctuation(
          localizedLeaveGuidanceField(type, guidance, 'requirements', language)
        )}.`
      : '';
    return `${labelLeaveType(type.display_name || type.name)}: ${localizedAttachmentRuleText(
      type,
      days,
      language
    )}.${guideline}`;
  });

  return structuredReply(language, {
    title: 'Attachment requirement',
    summary:
      language === 'bisaya'
        ? 'Mao ni ang attachment rule base sa HRMS setup.'
        : language === 'tagalog'
          ? 'Ito ang attachment rule base sa HRMS setup.'
          : 'Here is what the HRMS setup says about attachments.',
    details: lines.map(trimTrailingSentencePunctuation),
    limit: lines.length,
  });
}

function leaveFilingPolicyReply(context, message) {
  const language = languageOf(message);
  if (
    /\b(what happens?|what will happen|what happens next|after i submit|after submitting|after submission|human after submit|unsa.*mahitabo|mahitabo.*submit|ano.*mangyayari|mangyayari.*submit)\b/i.test(
      message
    )
  ) {
    return structuredReply(language, {
      title:
        language === 'bisaya'
          ? 'Human nimo ma-submit ang leave'
          : language === 'tagalog'
            ? 'Pagkatapos mong i-submit ang leave'
            : 'After you submit the leave request',
      summary:
        language === 'bisaya'
          ? 'Ma-record ang request ug moagi sa normal approval workflow. Dili pa dayon na approved.'
          : language === 'tagalog'
            ? 'Mare-record ang request at dadaan sa normal approval workflow. Hindi pa ito awtomatikong approved.'
            : 'The request is recorded and enters the normal approval workflow. Submission does not mean it is already approved.',
      details:
        language === 'bisaya'
          ? [
              'I-check sa assigned reviewer ang dates, balance, reason, ug attachment.',
              'Makita nimo sa My Leave kung pending, approved, returned, o rejected ang request.',
              'Kung returned, basaha ang remarks, i-correct ang form, ug i-submit pag-usab.',
            ]
          : language === 'tagalog'
            ? [
                'Iche-check ng assigned reviewer ang dates, balance, reason, at attachment.',
                'Makikita mo sa My Leave kung pending, approved, returned, o rejected ang request.',
                'Kung returned, basahin ang remarks, ayusin ang form, at i-submit ulit.',
              ]
            : [
                'The assigned reviewer checks the dates, balance, reason, and attachment.',
                'You can track whether it is pending, approved, returned, or rejected in My Leave.',
                'If it is returned, read the remarks, correct the form, and submit it again.',
              ],
      nextStep:
        language === 'bisaya'
          ? 'Ablihi ang My Leave aron ma-track ang status ug reviewer remarks.'
          : language === 'tagalog'
            ? 'Buksan ang My Leave para ma-track ang status at reviewer remarks.'
            : 'Open My Leave to track the status and reviewer remarks.',
      limit: 4,
    });
  }
  const types = matchingLeaveTypes(context, message);
  if (types.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang filing policy para ana nga leave type.';
    if (language === 'tagalog') return 'Wala akong nakitang filing policy para sa leave type na iyon.';
    return 'I found no filing policy for that leave type.';
  }

  const lines = types.slice(0, 4).map((type) => {
    const guidance = getLeaveGuidanceForType(type);
    const guidelineSummary = trimTrailingSentencePunctuation(
      summarizeLocalizedLeaveGuidance(type, guidance, language)
    );
    return `${labelLeaveType(type.display_name || type.name)}: ${localizedLeaveRequirementParts(
      type,
      language
    ).join(', ')}.${guidelineSummary ? ` Guideline: ${guidelineSummary}` : ''}`;
  });

  return structuredReply(language, {
    title: 'Leave filing policy',
    summary:
      language === 'bisaya'
        ? 'Mao ni ang filing policy base sa HRMS setup ug guidelines.'
        : language === 'tagalog'
          ? 'Ito ang filing policy base sa HRMS setup at guidelines.'
          : 'Here is the filing policy from the HRMS setup and guidelines.',
    details: lines.map(trimTrailingSentencePunctuation),
    nextStep: 'Approval still follows the HR workflow.',
    limit: 4,
  });
}

function leaveFormGuidanceReply(context, message) {
  const language = languageOf(message);
  const requestedType = requestedLeaveType(message);
  const requestedRecord = requestedLeaveTypeRecord(message, context);
  const hasSpecificType = Boolean(requestedType || requestedRecord);

  if (!hasSpecificType) {
    return structuredReply(language, {
      title:
        language === 'bisaya'
          ? 'Unsaon pag-file ug leave'
          : language === 'tagalog'
            ? 'Paano mag-file ng leave'
            : 'How to file a leave request',
      summary:
        language === 'bisaya'
          ? 'Ablihi ang leave form, kompletuha ang required details, dayon i-submit para sa approval.'
          : language === 'tagalog'
            ? 'Buksan ang leave form, kumpletuhin ang required details, at i-submit para sa approval.'
            : 'Open the leave form, complete the required details, and submit it for approval.',
      details:
        language === 'bisaya'
          ? [
              'Ablihi ang My Leave ug pili-a ang File Leave Request.',
              'Pilia ang leave type nga sakto sa imong purpose.',
              'Ibutang ang start ug end date. Ang HRMS maoy mo-compute sa working days.',
              'Isulat ang mubo ug tinuod nga reason, ug kompletuha ang additional fields kung naa.',
              'I-upload ang supporting document kung required sa leave type o duration.',
              'Reviewha ang details, dayon i-submit. Dili pa automatic approved ang request.',
            ]
          : language === 'tagalog'
            ? [
                'Buksan ang My Leave at piliin ang File Leave Request.',
                'Piliin ang leave type na tama sa purpose mo.',
                'Ilagay ang start at end date. HRMS ang magko-compute ng working days.',
                'Sumulat ng maikli at totoong reason, at kumpletuhin ang additional fields kung mayroon.',
                'Mag-upload ng supporting document kung required sa leave type o duration.',
                'I-review ang details at i-submit. Hindi pa awtomatikong approved ang request.',
              ]
            : [
                'Open My Leave and select File Leave Request.',
                'Choose the leave type that matches your purpose.',
                'Enter the start and end dates. HRMS calculates the covered working days.',
                'Write a short, truthful reason and complete any additional fields shown.',
                'Upload a supporting document when the leave type or duration requires one.',
                'Review the details and submit. The request is not automatically approved.',
              ],
      nextStep:
        language === 'bisaya'
          ? 'Pwede nimo i-open ang leave form sa button sa ubos. Kung gusto nimo specific nga tabang, pangutana: "Unsaon pag-file ug sick leave?"'
          : language === 'tagalog'
            ? 'Puwede mong buksan ang leave form gamit ang button sa ibaba. Para sa specific na tulong, itanong: "Paano mag-file ng sick leave?"'
            : 'Use the button below to open the leave form. For specific requirements, ask: "How do I file sick leave?"',
      limit: 7,
    });
  }

  const types = matchingLeaveTypes(context, message).slice(0, 3);
  if (types.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang leave type para sa form guidance.';
    if (language === 'tagalog') return 'Wala akong nakitang leave type para sa form guidance.';
    return 'I found no leave type for form guidance.';
  }

  const lines = types.map((type) => {
    return localizedLeaveFormGuideLine(
      type,
      language,
      requestedDaysOrRangeDays(message, context)
    );
  });

  return structuredReply(language, {
    title: 'Leave form guide',
    summary:
      language === 'bisaya'
        ? 'Mao ni gamita kung mag-fill out ka sa leave form.'
        : language === 'tagalog'
          ? 'Ito ang gamitin mo kapag nag-fill out ka ng leave form.'
          : 'Use these details when filling out the leave form.',
    details: lines.map(trimTrailingSentencePunctuation),
    limit: 3,
  });
}

function localizedLeaveFieldExplanation(field, language) {
  if (language === 'english') return field.explanation;
  const bisaya = {
    leave_type:
      'Pilia ang leave category nga tinuod nga mo-match sa hinungdan sa imong absence.',
    custom_leave_type:
      'Ibutang ang eksaktong official leave name kung wala kini sa standard list.',
    dates:
      'Pilia ang unang ug kataposang calendar date nga sakop sa imong leave request.',
    working_days:
      'Mao ni ang scheduled working days nga sakop sa imong gipiling dates.',
    reason:
      'Pagsulat ug mubo pero tin-aw ug tinuod nga explanation nganong kinahanglan nimo ang leave.',
    location_option:
      'Pilia kung ang imong destination naa sulod sa Pilipinas o abroad.',
    location_details:
      'Ibutang ang klarong city, municipality, province, o country sa imong leave destination.',
    sick_nature:
      'Pilia ang In Hospital kung na-confine ka; piliang Out Patient para sa consultation, treatment, o home recovery.',
    illness_details:
      'Isulat sa mubo ang illness, consultation, treatment, o recovery nga related sa imong absence.',
    expected_delivery_date:
      'Ibutang ang expected delivery date nga naa sa medical record o gi-hatag sa doctor.',
    maternity_classification:
      'Pilia ang Normal Delivery o Caesarean Section base sa medical record.',
    child_delivery_date:
      'Ibutang ang actual delivery o miscarriage date nga naa sa supporting record.',
    accident_date:
      'Ibutang ang petsa sa work-related accident o injury nga sakop sa rehabilitation request.',
    calamity_date:
      'Ibutang ang petsa sa calamity o disaster nga nakaapekto sa imong residence o immediate family.',
    women_illness_details:
      'Isulat sa mubo ang gynecological condition o procedure nga related sa request.',
    study_purpose:
      'Pilia ang option nga mo-match sa approved study activity.',
    study_details:
      'Ibutang ang school, degree, exam, o review program nga related sa request.',
    attachment:
      'I-upload ang document nga required sa gipiling leave type ug duration.',
    commutation:
      'Kung i-check nimo kini, ma-mark ang leave request nga nangayo usab ug HR/Admin review para sa commutation ubos sa office policy.',
  };
  const tagalog = {
    leave_type:
      'Piliin ang leave category na talagang tumutugma sa dahilan ng iyong pagliban.',
    custom_leave_type:
      'Ilagay ang eksaktong official leave name kung wala ito sa standard list.',
    dates:
      'Piliin ang una at huling calendar date na sakop ng leave request.',
    working_days:
      'Ito ang scheduled working days na sakop ng napiling dates.',
    reason:
      'Sumulat ng maikli, malinaw, at totoong paliwanag kung bakit kailangan ang leave.',
    location_option:
      'Piliin kung ang destination ay nasa loob ng Pilipinas o abroad.',
    location_details:
      'Ilagay ang malinaw na city, municipality, province, o country ng leave destination.',
    sick_nature:
      'Piliin ang In Hospital kung na-confine; piliin ang Out Patient para sa consultation, treatment, o home recovery.',
    illness_details:
      'Ilagay nang maikli ang illness, consultation, treatment, o recovery na kaugnay ng absence.',
    expected_delivery_date:
      'Ilagay ang expected delivery date mula sa medical record o physician.',
    maternity_classification:
      'Piliin ang Normal Delivery o Caesarean Section ayon sa medical record.',
    child_delivery_date:
      'Ilagay ang actual delivery o miscarriage date mula sa supporting record.',
    accident_date:
      'Ilagay ang petsa ng work-related accident o injury na sakop ng rehabilitation request.',
    calamity_date:
      'Ilagay ang petsa ng calamity o disaster na nakaapekto sa residence o immediate family.',
    women_illness_details:
      'Ilagay nang maikli ang gynecological condition o procedure na kaugnay ng request.',
    study_purpose:
      'Piliin ang option na tumutugma sa approved study activity.',
    study_details:
      'Ilagay ang school, degree, exam, o review program na kaugnay ng request.',
    attachment:
      'I-upload ang document na required sa napiling leave type at duration.',
    commutation:
      'Kapag chineck ito, mamarkahan ang leave request na humihiling din ng HR/Admin review para sa commutation ayon sa office policy.',
  };
  return (language === 'bisaya' ? bisaya : tagalog)[field.key] || field.explanation;
}

function localizedLeaveFieldNote(field, language) {
  if (language === 'english') return field.note;
  const bisaya = {
    reason:
      'Ayaw pagbutang ug dili kinahanglan nga private medical details. Ayaw kopyaha ang example kung dili kini tinuod.',
    working_days:
      'HRMS ang mo-compute ani. Usba ang dates imbis manghula o mag-manual input.',
    commutation:
      'Dili niini automatic ma-approve ang leave, ma-convert ang credits ngadto sa cash, o ma-guarantee ang payment. HR/Admin gihapon ang mo-review.',
  };
  const tagalog = {
    reason:
      'Huwag maglagay ng hindi kailangang private medical details. Huwag kopyahin ang example kung hindi ito totoo.',
    working_days:
      'HRMS ang nagko-compute nito. Baguhin ang dates sa halip na hulaan o i-manual input.',
    commutation:
      'Hindi nito awtomatikong ina-approve ang leave, kino-convert ang credits sa cash, o ginagarantiya ang payment. HR/Admin pa rin ang magre-review.',
  };
  const specific = (language === 'bisaya' ? bisaya : tagalog)[field.key];
  if (specific) return specific;
  return language === 'bisaya'
    ? 'Gamita ang imong tinuod nga details ug siguroa nga mo-match sa supporting records.'
    : 'Gamitin ang tunay mong details at tiyaking tugma sa supporting records.';
}

function localizedLeaveFieldExamples(field, language) {
  if (language === 'english') return field.examples;
  const translations = {
    bisaya: {
      'Medical consultation and recovery due to illness':
        'Medical consultation ug recovery tungod sa illness',
      'Rest and recovery as advised after an outpatient consultation':
        'Rest ug recovery human sa outpatient consultation',
      'Personal travel and rest in Cebu City':
        'Personal travel ug rest sa Cebu City',
      'Family vacation within the Philippines':
        'Family vacation sulod sa Pilipinas',
      'Fever and medical consultation':
        'Hilanat ug medical consultation',
      'Recovery after an outpatient procedure':
        'Recovery human sa outpatient procedure',
      'Leave it unchecked for an ordinary absence request':
        'Pasagdi nga unchecked para sa ordinary leave absence request',
      'Leave it unchecked for an ordinary leave absence request':
        'Pasagdi nga unchecked para sa ordinary leave absence request',
      'Check it only when HR has instructed you to request commutation':
        'I-check lang kung gi-instruct ka sa HR nga mag-request ug commutation',
      'A Monday-to-Tuesday request may show 2 working days if both are scheduled workdays':
        'Ang Monday hangtod Tuesday mahimong 2 ka working days kung pareho silang scheduled workdays',
    },
    tagalog: {
      'Medical consultation and recovery due to illness':
        'Medical consultation at recovery dahil sa illness',
      'Rest and recovery as advised after an outpatient consultation':
        'Rest at recovery pagkatapos ng outpatient consultation',
      'Personal travel and rest in Cebu City':
        'Personal travel at pahinga sa Cebu City',
      'Family vacation within the Philippines':
        'Family vacation sa loob ng Pilipinas',
      'Fever and medical consultation':
        'Lagnat at medical consultation',
      'Recovery after an outpatient procedure':
        'Recovery pagkatapos ng outpatient procedure',
      'Leave it unchecked for an ordinary absence request':
        'Iwanang unchecked para sa ordinary leave absence request',
      'Leave it unchecked for an ordinary leave absence request':
        'Iwanang unchecked para sa ordinary leave absence request',
      'Check it only when HR has instructed you to request commutation':
        'I-check lamang kung inutusan ka ng HR na humiling ng commutation',
      'A Monday-to-Tuesday request may show 2 working days if both are scheduled workdays':
        'Ang Monday hanggang Tuesday ay maaaring 2 working days kung parehong scheduled workdays',
    },
  };
  return field.examples.map(
    (example) => translations[language]?.[example] || example
  );
}

function leaveFormFieldHelpReply(context, message) {
  const language = languageOf(message);
  const type = requestedLeaveTypeRecord(message, context);
  const field = getLeaveFormFieldGuidance(message, type);
  if (!field) {
    return structuredReply(language, {
      title: 'Leave form field help',
      summary:
        language === 'bisaya'
          ? 'Unsang field sa leave form ang nakalibog nimo? Isulti ang exact field label.'
          : language === 'tagalog'
            ? 'Aling field sa leave form ang nakakalito? Sabihin ang exact field label.'
            : 'Which leave-form field is confusing? Tell me the exact field label.',
      details: [
        'Leave Type',
        'Start Date / End Date',
        'Reason / Remarks',
        'Location or Illness Details',
        'Attachment',
        'Requested Commutation',
      ],
      nextStep:
        language === 'bisaya'
          ? 'Example: "unsa akong ibutang sa reason field sa sick leave?"'
          : language === 'tagalog'
            ? 'Example: "ano ang ilalagay sa reason field ng sick leave?"'
            : 'Example: "What should I put in the sick leave reason field?"',
      limit: 6,
    });
  }

  const typeLabel = type
    ? labelLeaveType(type.display_name || type.name)
    : null;
  const examples = localizedLeaveFieldExamples(field, language);
  const exampleLabel =
    language === 'bisaya'
      ? 'Example input'
      : language === 'tagalog'
        ? 'Halimbawang input'
        : 'Example input';
  const details = [
    `${language === 'bisaya' ? 'Unsaon pag-fill' : language === 'tagalog' ? 'Paano sagutan' : 'How to fill it'}: ${localizedLeaveFieldExplanation(
      field,
      language
    )}`,
    ...examples.map((example) => `${exampleLabel}: ${example}`),
  ];

  if (field.key === 'attachment' && type) {
    details.push(
      `${
        language === 'bisaya'
          ? 'Rule para sa leave type'
          : language === 'tagalog'
            ? 'Rule para sa leave type'
            : 'Rule for this leave type'
      }: ${localizedAttachmentRuleText(type, requestedDaysOrRangeDays(message, context), language)}`
    );
  }

  const asksCommutationEffect =
    field.key === 'commutation' &&
    /\b(happen|check|checked|checking|tick|ticked|cash|paid|payment|pay|bayad|mabayran|mahitabo|mangyayari)\b/i.test(
      message
    );
  return structuredReply(language, {
    title: field.title,
    summary: asksCommutationEffect
      ? language === 'bisaya'
        ? 'Dili. Ang pag-check ani dili automatic nga mabayran, ma-convert to cash, o ma-approve ang leave.'
        : language === 'tagalog'
          ? 'Hindi. Ang pag-check nito ay hindi awtomatikong payment, cash conversion, o approval ng leave.'
          : 'No. Checking it does not automatically create a payment, convert leave credits to cash, or approve the leave.'
      : language === 'bisaya'
        ? `Mao ni ang tabang para sa ${field.title}${typeLabel ? ` sa ${typeLabel}` : ''}.`
        : language === 'tagalog'
          ? `Narito ang tulong para sa ${field.title}${typeLabel ? ` ng ${typeLabel}` : ''}.`
          : `Here is how to complete ${field.title}${typeLabel ? ` for ${typeLabel}` : ''}.`,
    details,
    nextStep: localizedLeaveFieldNote(field, language),
    limit: 6,
  });
}

function leaveEligibilityReply(context, message) {
  const language = languageOf(message);
  const types = matchingLeaveTypes(context, message).slice(0, 3);
  const employeeSex = normalizeSex(context.employee?.sex);
  if (types.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang leave type para sa eligibility check.';
    if (language === 'tagalog') return 'Wala akong nakitang leave type para sa eligibility check.';
    return 'I found no leave type for an eligibility check.';
  }

  const lines = types.map((type) => {
    const blockers = [];
    const warnings = [];
    const sexRule = lower(type.sex_eligibility || 'any') || 'any';
    if (type.employee_can_file === false || type.admin_only) {
      blockers.push('employee filing disabled/admin-only');
    }
    if (sexRule !== 'any') {
      if (!employeeSex) {
        warnings.push(`profile sex is missing, HR should confirm ${sexRule} eligibility`);
      } else if (employeeSex !== sexRule) {
        blockers.push(`configured for ${sexRule} employees only`);
      }
    }
    const label = labelLeaveType(type.display_name || type.name);
    if (blockers.length > 0) return `${label}: not eligible by current rule (${blockers.join(', ')})`;
    if (warnings.length > 0) return `${label}: likely eligible, but ${warnings.join(', ')}`;
    return `${label}: eligible by profile/rule check`;
  });

  return structuredReply(language, {
    title: 'Eligibility check',
    summary:
      language === 'bisaya'
        ? 'Initial filing check ra ni.'
        : language === 'tagalog'
          ? 'Initial filing check lang ito.'
          : 'This is only an initial filing check.',
    details: lines,
    nextStep: 'Final approval still follows the HR workflow.',
    limit: 3,
  });
}

function leaveDtrImpactReply(context, message) {
  const language = languageOf(message);
  const types = matchingLeaveTypes(context, message).slice(0, 3);
  if (types.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang leave type para sa DTR impact.';
    if (language === 'tagalog') return 'Wala akong nakitang leave type para sa DTR impact.';
    return 'I found no leave type for DTR impact.';
  }

  const lines = types.map((type) => {
    const label = labelLeaveType(type.display_name || type.name);
    const balance = type.balance_ledger_type
      ? `balance ledger: ${type.balance_ledger_type}`
      : 'no specific balance ledger shown';
    if (type.affects_dtr_normally === false) {
      return `${label}: configured not to affect DTR normally; HR may handle attendance manually.`;
    }
    return `${label}: once approved/posting runs, covered dates can be marked on leave in DTR; ${balance}.`;
  });

  return structuredReply(language, {
    title: 'DTR impact',
    summary:
      language === 'bisaya'
        ? 'Mao ni ang possible DTR effect after approval/posting.'
        : language === 'tagalog'
          ? 'Ito ang possible DTR effect after approval/posting.'
          : 'Here is how the leave can affect DTR after approval/posting.',
    details: lines,
    nextStep: 'Final posting or approval is still the basis.',
    limit: 3,
  });
}

function isLeaveTypeGuidelineOverviewQuestion(message) {
  const text = lower(message);
  return /\b(guidelines?|guide|rules?|policy|policies|explain|describe|details?|detail|tell me about|what are|pasabot|meaning|i-explain)\b/.test(text) &&
    /\b(leave types?|types of leave|all leave|available leave)\b/.test(text);
}

function compactLeaveTypeGuidelineLine(type, guidance, language = 'english') {
  const label = labelLeaveType(type.display_name || type.name || type.leave_type);
  const description =
    compactText(localizedLeaveGuidanceField(type, guidance, 'description', language), 125) ||
    localizedAvailableForFiling(language);
  const requirements = compactText(
    localizedLeaveGuidanceField(type, guidance, 'requirements', language),
    105
  );
  const limits = compactText(localizedLeaveGuidanceField(type, guidance, 'limits', language), 80);
  const parts = [description];
  if (requirements) parts.push(`Req: ${requirements}`);
  if (limits) parts.push(`Limit: ${limits}`);
  return `${label}: ${parts.join(' | ')}`;
}

function uniqueLeaveGuidelineLines(lines) {
  const seen = new Set();
  const result = [];
  for (const line of lines) {
    const key = lower(String(line || '').split(':')[0]).replace(/[^a-z0-9]+/g, '');
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(line);
  }
  return result;
}

function leaveTypeGuidelineOverviewReply(context, message) {
  const language = languageOf(message);
  const typeGuidelines = (context.leave_types || [])
    .filter((type) => type.employee_can_file !== false)
    .map((type) => {
      const guidance = getLeaveGuidanceForType(type);
      return compactLeaveTypeGuidelineLine(type, guidance, language);
    })
    .filter(Boolean);

  const fallbackGuidelines = (context.leave_guidelines || []).map((guidance) => {
    return compactLeaveTypeGuidelineLine(
      {
        name: guidance.leave_type,
        display_name: guidance.leave_type,
      },
      guidance,
      language
    );
  });
  const catalogGuidelines = (context.leave_guideline_catalog || []).map((guidance) => {
    return compactLeaveTypeGuidelineLine(
      {
        name: guidance.leave_type,
        display_name: guidance.leave_type,
      },
      guidance,
      language
    );
  });

  const lines = uniqueLeaveGuidelineLines([
    ...typeGuidelines,
    ...fallbackGuidelines,
    ...catalogGuidelines,
  ]);
  if (lines.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang leave type guidelines sa system records.';
    if (language === 'tagalog') return 'Wala akong nakitang leave type guidelines sa system records.';
    return 'I found no leave type guidelines in the system records.';
  }

  return structuredReply(language, {
    title: 'Leave Type Guidelines',
    summary:
      language === 'bisaya'
        ? 'Mao ni ang guideline summary sa leave types nga naa sa HRMS.'
        : language === 'tagalog'
          ? 'Ito ang guideline summary ng leave types na nasa HRMS.'
          : 'Here is the guideline summary for the HRMS leave types.',
    details: lines,
    nextStep:
      language === 'bisaya'
        ? 'Pwede ka mangutana ug specific leave type, example: "unsay requirements sa sick leave?"'
        : language === 'tagalog'
          ? 'Pwede kang magtanong ng specific leave type, example: "requirements sa sick leave?"'
          : 'Ask for a specific leave type if you want more detail, for example: "requirements for sick leave".',
    limit: lines.length,
  });
}

function leaveTypeGuidanceDetailReply(context, message, type, guidance) {
  const language = languageOf(message);
  const label = labelLeaveType(type.display_name || type.name);
  const setupParts = localizedLeaveRequirementParts(type, language);
  const detailLabels =
    language === 'bisaya'
      ? {
          what: 'Pasabot',
          requirements: 'Requirements',
          limit: 'Limit',
          filing: 'Filing',
          note: 'Note',
          setup: 'HRMS setup',
        }
      : language === 'tagalog'
        ? {
            what: 'Ibig sabihin',
            requirements: 'Requirements',
            limit: 'Limit',
            filing: 'Filing',
            note: 'Note',
            setup: 'HRMS setup',
          }
        : {
            what: 'What it is',
            requirements: 'Requirements',
            limit: 'Limit',
            filing: 'Filing',
            note: 'Note',
            setup: 'HRMS setup',
          };
  const details = [
    localizedLeaveGuidanceField(type, guidance, 'description', language)
      ? `${detailLabels.what}: ${localizedLeaveGuidanceField(type, guidance, 'description', language)}`
      : null,
    localizedLeaveGuidanceField(type, guidance, 'requirements', language)
      ? `${detailLabels.requirements}: ${localizedLeaveGuidanceField(
          type,
          guidance,
          'requirements',
          language
        )}`
      : null,
    localizedLeaveGuidanceField(type, guidance, 'limits', language)
      ? `${detailLabels.limit}: ${localizedLeaveGuidanceField(type, guidance, 'limits', language)}`
      : null,
    localizedLeaveGuidanceField(type, guidance, 'advanceFiling', language)
      ? `${detailLabels.filing}: ${localizedLeaveGuidanceField(
          type,
          guidance,
          'advanceFiling',
          language
        )}`
      : null,
    localizedLeaveGuidanceField(type, guidance, 'notes', language)
      ? `${detailLabels.note}: ${localizedLeaveGuidanceField(type, guidance, 'notes', language)}`
      : null,
    setupParts.length > 0 ? `${detailLabels.setup}: ${setupParts.join(', ')}` : null,
  ].filter(Boolean);

  return structuredReply(language, {
    title: `${label} guideline`,
    summary:
      language === 'bisaya'
        ? `Mao ni ang explanation sa ${label} base sa HRMS setup ug leave guidelines.`
        : language === 'tagalog'
          ? `Ito ang explanation ng ${label} base sa HRMS setup at leave guidelines.`
          : `Here is the explanation for ${label} from the HRMS setup and leave guidelines.`,
    details,
    nextStep:
      language === 'bisaya'
        ? 'Kung gusto ka mag-file, i-check gihapon ang balance, date, attachment, ug HR approval workflow.'
        : language === 'tagalog'
          ? 'Kung magfa-file ka, i-check pa rin ang balance, date, attachment, at HR approval workflow.'
          : 'If you plan to file it, still check balance, dates, attachment, and the HR approval workflow.',
    limit: 6,
  });
}

function leaveGuidelineSectionReply(context, message) {
  const language = languageOf(message);
  const sections = getGuidelineSectionsForMessage(message);
  const type = requestedLeaveTypeRecord(message, context);
  const guidance = type ? getLeaveGuidanceForType(type) : null;

  if (isLeaveTypeGuidelineOverviewQuestion(message)) {
    return leaveTypeGuidelineOverviewReply(context, message);
  }

  if (guidance && /\b(supporting|document|docs|attachment|requirements?)\b/i.test(message)) {
    const line = `${labelLeaveType(type.display_name || type.name)}: ${trimTrailingSentencePunctuation(
      [
        localizedLeaveGuidanceField(type, guidance, 'requirements', language),
        localizedLeaveGuidanceField(type, guidance, 'limits', language),
        localizedLeaveGuidanceField(type, guidance, 'advanceFiling', language),
        localizedLeaveGuidanceField(type, guidance, 'notes', language),
      ]
        .filter(Boolean)
        .join(' ')
    )}. Requirement: ${localizedAttachmentRuleText(
      type,
      requestedDaysOrRangeDays(message, context),
      language
    )}.`;
    return structuredReply(language, {
      title: 'Guideline answer',
      summary:
        language === 'bisaya'
          ? 'Mao ni ang guideline detail nga akong nakita.'
          : language === 'tagalog'
            ? 'Ito ang guideline detail na nakita ko.'
            : 'Here is the guideline detail I found.',
      details: [line],
    });
  }

  if (guidance) {
    return leaveTypeGuidanceDetailReply(context, message, type, guidance);
  }

  if (sections.length === 0) {
    const titles = GUIDELINE_SECTIONS.map((section) => section.title).join(', ');
    if (language === 'bisaya') return `Pwede nako i-explain ang leave guideline sections: ${titles}. Ingna lang ko unsa imong gusto, example: "explain filing deadlines".`;
    if (language === 'tagalog') return `Pwede kong i-explain ang leave guideline sections: ${titles}. Sabihin mo lang alin ang gusto mo, example: "explain filing deadlines".`;
    return `I can explain these leave guideline sections: ${titles}. Tell me which one you want, for example: "explain filing deadlines".`;
  }

  const lines = sections.map((section) => `${section.title}: ${section.points.join(' ')}`);
  const sectionNames = sections.map((section) => section.title).join(', ');
  return structuredReply(language, {
    title: sections.length === 1 ? sections[0].title : 'Leave Guidelines',
    summary:
      language === 'bisaya'
        ? `Mao ni ang ${sectionNames} guideline.`
        : language === 'tagalog'
          ? `Ito ang ${sectionNames} guideline.`
          : `Here is the ${sectionNames} guideline${sections.length === 1 ? '' : 's'}.`,
    details: lines,
    limit: 4,
  });
}

function leaveTypeCompareReply(context, message) {
  const language = languageOf(message);
  const types = mentionedLeaveTypeRecords(context, message).slice(0, 2);
  if (types.length < 2) {
    if (language === 'bisaya') return 'Unsang duha ka leave types ang imong gusto i-compare? Example: sick leave vs vacation leave.';
    if (language === 'tagalog') return 'Aling dalawang leave types ang gusto mong i-compare? Example: sick leave vs vacation leave.';
    return 'Which two leave types do you want to compare? Example: sick leave vs vacation leave.';
  }

  const lines = types.map((type) => {
    const guidance = getLeaveGuidanceForType(type);
    const pieces = [
      localizedLeaveRequirementParts(type, language).join(', '),
      localizedLeaveGuidanceField(type, guidance, 'requirements', language)
        ? `guideline requirements: ${localizedLeaveGuidanceField(
            type,
            guidance,
            'requirements',
            language
          )}`
        : null,
      localizedLeaveGuidanceField(type, guidance, 'limits', language)
        ? `limit: ${localizedLeaveGuidanceField(type, guidance, 'limits', language)}`
        : null,
    ].filter(Boolean);
    return `${labelLeaveType(type.display_name || type.name)}: ${pieces.join('. ')}`;
  });

  return structuredReply(language, {
    title: 'Leave type comparison',
    summary:
      language === 'bisaya'
        ? 'Mao ni ang side-by-side comparison.'
        : language === 'tagalog'
          ? 'Ito ang side-by-side comparison.'
          : 'Here is the side-by-side comparison.',
    details: lines,
    limit: 2,
  });
}

function leaveGuidedFilingReply(context, message) {
  const language = languageOf(message);
  const type = requestedLeaveTypeRecord(message, context);
  const days = requestedDaysOrRangeDays(message, context);
  const missing = [];
  if (!type) missing.push('leave type');
  if (!hasDateRangeHint(message)) missing.push('date or date range');
  if (!days) missing.push('number of days');

  if (missing.length > 0) {
    if (language === 'bisaya') {
      return `Tabangan tika sa leave filing. Kulang pa: ${missing.join(', ')}. Ihatag ang leave type, date range, number of days, ug reason/attachment kung required.`;
    }
    if (language === 'tagalog') {
      return `Tutulungan kita sa leave filing. Kulang pa: ${missing.join(', ')}. Ibigay ang leave type, date range, number of days, at reason/attachment kung required.`;
    }
    return `I can guide the leave filing. Missing: ${missing.join(', ')}. Provide leave type, date range, number of days, and reason/attachment if required.`;
  }

  const check = leaveAvailabilityReply(context, message);
  const form = getFormGuidanceForType(type);
  if (language === 'bisaya') {
    return `${check} Sunod: ${localizedLeaveFormGuideLine(
      type,
      language,
      days
    )} I-submit ra sa leave module; dili pa ko mo-auto-submit.`;
  }
  if (language === 'tagalog') {
    return `${check} Next: ${localizedLeaveFormGuideLine(
      type,
      language,
      days
    )} I-submit sa leave module; hindi ako mag-auto-submit.`;
  }
  return `${check} Next in the form: ${form.fields.join(' ')} Submit it in the leave module; I will not auto-submit it.`;
}

function leaveOverlapCheckReply(context, message) {
  const language = languageOf(message);
  if (!hasDateRangeHint(message)) {
    if (language === 'bisaya') return 'Unsang date or date range ang imong gusto ipa-check?';
    if (language === 'tagalog') return 'Anong date or date range ang gusto mong ipa-check?';
    return 'Which date or date range do you want me to check?';
  }

  const requestedRecord = requestedLeaveTypeRecord(message, context);
  const overlaps = (context.recent_leave_requests || []).filter((request) => {
    if (!activeLeaveStatus(request.status)) return false;
    if (!requestOverlapsRange(request, context.date_range)) return false;
    if (requestedRecord && !leaveRequestMatchesRecord(request, requestedRecord)) return false;
    return true;
  });

  if (overlaps.length === 0) {
    if (language === 'bisaya') {
      return `Wala koy nakitang active leave request nga ni-overlap sa ${context.date_range?.label || 'selected date'}.`;
    }
    if (language === 'tagalog') {
      return `Wala akong nakitang active leave request na nag-o-overlap sa ${context.date_range?.label || 'selected date'}.`;
    }
    return `I found no active leave request overlapping ${context.date_range?.label || 'the selected date'}.`;
  }

  return structuredReply(language, {
    title: 'Leave overlap check',
    summary:
      language === 'bisaya'
        ? `Naa koy nakitang ${overlaps.length} ka overlapping leave request.`
        : language === 'tagalog'
          ? `May nakita akong ${overlaps.length} overlapping leave request.`
          : `I found ${overlaps.length} overlapping leave ${plural(overlaps.length, 'request')}.`,
    details: overlaps.map((request) => fmtLeaveRequest(request, language)),
    nextStep:
      language === 'bisaya'
        ? 'I-review ang overlapping request before ka mag-file ug another leave sa same date.'
        : language === 'tagalog'
          ? 'I-review ang overlapping request bago mag-file ng another leave sa same date.'
          : 'Review the overlapping request before filing another leave for the same date.',
    limit: 5,
  });
}

function leavePendingDaysExplanationReply(context, message) {
  const language = languageOf(message);
  const requestedRecord = requestedLeaveTypeRecord(message, context);
  const pendingBalances = (context.leave_balances || []).filter((balance) => {
    if ((asNumber(balance.pending_days) || 0) <= 0) return false;
    if (requestedRecord) return leaveBalanceMatchesRecord(balance, requestedRecord);
    return true;
  });
  const pendingRequests = (context.recent_leave_requests || []).filter((request) => {
    if (!pendingStatus(request.status)) return false;
    if (requestedRecord && !leaveRequestMatchesRecord(request, requestedRecord)) return false;
    return true;
  });

  if (pendingBalances.length === 0 && pendingRequests.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang pending leave days sa imong current records.';
    if (language === 'tagalog') return 'Wala akong nakitang pending leave days sa current records mo.';
    return 'I found no pending leave days in your current records.';
  }

  const balanceLines = pendingBalances.map((b) => {
    return `${labelLeaveType(b.leave_type)} pending ${fmtLocalizedDayCount(b.pending_days, language)}`;
  });
  const requestLines = limitedRequests(pendingRequests, 4).map((request) =>
    fmtLeaveRequest(request, language)
  );
  const details = [...balanceLines, ...requestLines];

  return structuredReply(language, {
    title: 'Pending leave days',
    summary:
      language === 'bisaya'
        ? 'Mao ni kung asa gikan ang pending leave days.'
        : language === 'tagalog'
          ? 'Ito kung saan galing ang pending leave days.'
          : 'Here is where the pending leave days are coming from.',
    details,
    limit: 6,
  });
}

function leaveBalanceAfterFilingReply(context, message) {
  const language = languageOf(message);
  const days = parseRequestedDays(message);
  if (!days) {
    if (language === 'bisaya') return 'Pila ka adlaw nga leave ang imong plano i-file?';
    if (language === 'tagalog') return 'Ilang araw ng leave ang balak mong i-file?';
    return 'How many leave days are you planning to file?';
  }

  const requestedType = requestedLeaveType(message);
  const requestedRecord = requestedLeaveTypeRecord(message, context);
  const balances = context.leave_balances || [];
  const selected = balances.filter((b) => {
    if (requestedRecord) return leaveBalanceMatchesRecord(b, requestedRecord);
    return leaveTypeMatches(b, requestedType);
  });
  const balance = requestedType || requestedRecord || selected.length === 1 ? selected[0] : null;

  if (!requestedType && !requestedRecord && selected.length > 1) {
    if (language === 'bisaya') return 'Unsang leave type ang imong gamiton para sa balance-after-filing check?';
    if (language === 'tagalog') return 'Anong leave type ang gagamitin mo para sa balance-after-filing check?';
    return 'Which leave type should I use for the balance-after-filing check?';
  }
  if (!balance) {
    if (language === 'bisaya') return 'Wala koy matching leave balance para ana nga leave type.';
    if (language === 'tagalog') return 'Wala akong matching leave balance para sa leave type na iyon.';
    return 'I found no matching leave balance for that leave type.';
  }

  const available = asNumber(balance.available_days) || 0;
  const after = available - days;
  const type = labelLeaveType(balance.leave_type);
  if (language === 'bisaya') {
    return `Kung mag-file ka ug ${fmtLocalizedDayCount(
      days,
      language
    )} nga ${type}, gikan sa ${fmtLocalizedDayCount(
      available,
      language
    )} available mahimong ${fmtLocalizedDayCount(
      after,
      language
    )} ang estimated balance. Balance estimate ra ni, dili pa approval.`;
  }
  if (language === 'tagalog') {
    return `Kung mag-file ka ng ${fmtLocalizedDayCount(
      days,
      language
    )} na ${type}, mula ${fmtLocalizedDayCount(
      available,
      language
    )} available magiging ${fmtLocalizedDayCount(
      after,
      language
    )} ang estimated balance. Estimate lang ito, hindi pa approval.`;
  }
  return `If you file ${fmtDayCount(days)} of ${type}, your estimated balance would go from ${fmtDayCount(
    available
  )} to ${fmtDayCount(after)}. This is only an estimate, not approval.`;
}

function leaveRequestSummaryReply(context, message) {
  const language = languageOf(message);
  const useRange = hasDateRangeHint(message);
  const requests = (context.recent_leave_requests || []).filter((request) => {
    if (useRange && !requestOverlapsRange(request, context.date_range)) return false;
    return true;
  });

  if (requests.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang leave requests para ana nga period.';
    if (language === 'tagalog') return 'Wala akong nakitang leave requests para sa period na iyon.';
    return 'I found no leave requests for that period.';
  }

  const counts = requests.reduce(
    (acc, request) => {
      if (pendingStatus(request.status)) acc.pending += 1;
      else if (approvedStatus(request.status)) acc.approved += 1;
      else if (rejectedStatus(request.status)) acc.rejected += 1;
      else acc.other += 1;
      acc.days += asNumber(request.days) || 0;
      return acc;
    },
    { pending: 0, approved: 0, rejected: 0, other: 0, days: 0 }
  );

  const label = useRange ? context.date_range?.label || 'selected period' : 'recent records';
  return structuredReply(language, {
    title: `Leave summary (${label})`,
    summary:
      language === 'bisaya'
        ? `Naa koy nakitang ${requests.length} ka leave request, total ${fmtLocalizedDayCount(
            counts.days,
            language
          )}.`
        : language === 'tagalog'
          ? `May nakita akong ${requests.length} leave request, total ${fmtLocalizedDayCount(
              counts.days,
              language
            )}.`
          : `I found ${requests.length} leave ${plural(requests.length, 'request')}, total ${fmtDayCount(counts.days)}.`,
    details: [
      `Pending: ${counts.pending}`,
      `Approved: ${counts.approved}`,
      `Rejected: ${counts.rejected}`,
      `Other: ${counts.other}`,
    ],
  });
}

function leaveRequestLookupReply(context, message) {
  const language = languageOf(message);
  const useRange = hasDateRangeHint(message);
  const requests = (context.recent_leave_requests || []).filter((request) => {
    if (useRange && !requestOverlapsRange(request, context.date_range)) return false;
    return requestMatchesMessageFilters(request, message, context);
  });

  if (requests.length === 0) {
    const label = context.date_range?.label || 'that date';
    if (language === 'bisaya') return `Wala koy nakitang leave request nga gi-file para sa ${label}.`;
    if (language === 'tagalog') return `Wala akong nakitang leave request na na-file para sa ${label}.`;
    return `I found no leave request filed for ${label}.`;
  }

  const lines = limitedRequests(requests, 3).map((request) => {
    return `${labelLeaveType(request.leave_type)} (${workflowStatusText(
      request.status
    )}, ${fmtLocalizedDayCount(request.days, language)}, ${fmtLocalizedDateRange(
      request.start_date,
      request.end_date,
      language
    ).replace(
      /^on /,
      ''
    )})`;
  });
  const more = requests.length > 3 ? ` plus ${requests.length - 3} more` : '';
  const label = context.date_range?.label || 'that date';

  return structuredReply(language, {
    title: `Leave request for ${label}`,
    summary:
      language === 'bisaya'
        ? `Naa koy nakitang ${requests.length} ka matching leave request.`
        : language === 'tagalog'
          ? `May nakita akong ${requests.length} matching leave request.`
          : `I found ${requests.length} matching leave ${plural(requests.length, 'request')}.`,
    details: [...lines, ...(more ? [more.trim()] : [])],
    limit: 4,
  });
}

function leaveRejectionReasonReply(context, message) {
  const language = languageOf(message);
  const requests = (context.recent_leave_requests || []).filter((request) => {
    if (!requestMatchesMessageFilters(request, message, context)) return false;
    return rejectedStatus(request.status) || returnedStatus(request.status);
  });
  const request = requests[0] || (context.recent_leave_requests || []).find((r) => rejectedStatus(r.status) || returnedStatus(r.status));

  if (!request) {
    if (language === 'bisaya') return 'Wala koy nakitang rejected o returned leave request sa imong recent records.';
    if (language === 'tagalog') return 'Wala akong nakitang rejected or returned leave request sa recent records mo.';
    return 'I found no rejected or returned leave request in your recent records.';
  }

  const reason = firstReviewReason(request);
  const base = `${fmtLeaveRequest(request, language)}`;
  if (!reason) {
    return structuredReply(language, {
      title:
        language === 'bisaya'
          ? 'Rason sa rejected o returned leave'
          : language === 'tagalog'
            ? 'Dahilan ng rejected o returned leave'
            : 'Leave rejection reason',
      summary: base,
      details: [
        language === 'bisaya'
          ? 'Walay reviewer remarks o reason nga naka-save sa record.'
          : language === 'tagalog'
            ? 'Walang reviewer remarks o dahilan na naka-save sa record.'
            : 'No reviewer remarks or reason were found in the record.',
      ],
    });
  }
  const cleanReason = String(reason).replace(/[.\s]+$/, '');
  return structuredReply(language, {
    title:
      language === 'bisaya'
        ? 'Rason sa rejected o returned leave'
        : language === 'tagalog'
          ? 'Dahilan ng rejected o returned leave'
          : 'Leave rejection reason',
    summary: base,
    details: [
      `${language === 'bisaya' ? 'Reviewer remarks' : language === 'tagalog' ? 'Reviewer remarks' : 'Remarks'}: ${cleanReason}`,
    ],
  });
}

function leaveApprovalTrackerReply(context, message) {
  const language = languageOf(message);
  const requests = (context.recent_leave_requests || []).filter((request) => {
    if (!requestMatchesMessageFilters(request, message, context)) return false;
    return pendingStatus(request.status) || returnedStatus(request.status) || approvedStatus(request.status);
  });
  const request = requests[0] || context.recent_leave_requests?.[0];

  if (!request) {
    if (language === 'bisaya') return 'Wala koy nakitang leave request nga i-track sa recent records mo.';
    if (language === 'tagalog') return 'Wala akong nakitang leave request na puwedeng i-track sa recent records mo.';
    return 'I found no leave request to track in your recent records.';
  }

  const status = String(request.status || '').toLowerCase();
  let owner = workflowStatusText(status);
  if (language === 'bisaya') {
    if (status === 'pending_department_head') owner = 'naghulat sa department head review';
    if (status === 'pending_hr' || status === 'pending') owner = 'naghulat sa final HR review';
    if (status === 'approved') owner = 'approved na';
    if (status === 'returned') owner = 'gibalik sa imo para i-correct';
    if (rejectedStatus(status)) owner = 'rejected na';
  } else if (language === 'tagalog') {
    if (status === 'pending_department_head') owner = 'naghihintay ng department head review';
    if (status === 'pending_hr' || status === 'pending') owner = 'naghihintay ng final HR review';
    if (status === 'approved') owner = 'approved na';
    if (status === 'returned') owner = 'ibinalik sa iyo para ayusin';
    if (rejectedStatus(status)) owner = 'rejected na';
  } else {
    if (status === 'pending_department_head') owner = 'currently waiting for department head review';
    if (status === 'pending_hr' || status === 'pending') owner = 'currently waiting for HR final review';
    if (status === 'approved') owner = 'already approved';
    if (status === 'returned') owner = 'returned to you for correction';
    if (rejectedStatus(status)) owner = 'already rejected';
  }

  const actor = request.reviewer_name || request.approver_name || request.latest_history?.actor_name;
  const actorText = actor
    ? ` ${language === 'bisaya' ? 'Last reviewer/action' : language === 'tagalog' ? 'Huling reviewer/action' : 'Last action/reviewer'}: ${actor}.`
    : '';
  const remarks = firstReviewReason(request);
  const remarksText = remarks ? ` Reviewer remarks: ${remarks}.` : '';
  const content = `${labelLeaveType(request.leave_type)} ${fmtLocalizedDateRange(
    request.start_date,
    request.end_date,
    language
  )}${language === 'bisaya' ? ` kay ${owner}` : language === 'tagalog' ? ` ay ${owner}` : ` is ${owner}`}.${actorText}${remarksText}`;

  return content;
}

function leaveApprovalHistoryReply(context, message) {
  const language = languageOf(message);
  const requests = (context.recent_leave_requests || []).filter((request) => {
    return requestMatchesMessageFilters(request, message, context);
  });
  const request = requests[0] || context.recent_leave_requests?.[0];

  if (!request) {
    if (language === 'bisaya') return 'Wala koy nakitang leave request para sa approval timeline.';
    if (language === 'tagalog') return 'Wala akong nakitang leave request para sa approval timeline.';
    return 'I found no leave request for an approval timeline.';
  }

  const history = Array.isArray(request.history) ? request.history : [];
  if (history.length === 0 && !request.latest_history) {
    const base = fmtLeaveRequest(request, language);
    if (language === 'bisaya') return `${base}. Wala koy detailed approval history sa record.`;
    if (language === 'tagalog') return `${base}. Wala akong detailed approval history sa record.`;
    return `${base}. I found no detailed approval history in the record.`;
  }

  const events = history.length > 0 ? history : [request.latest_history];
  const lines = limitedRequests(events, 6).map((event) => {
    const action = statusLabel(event.action || event.to_status || 'action');
    const actor = event.actor_name ? ` by ${event.actor_name}` : '';
    const when = event.acted_at ? ` on ${fmtFriendlyDate(event.acted_at)}` : '';
    const remarks = event.remarks ? ` (${event.remarks})` : '';
    return `${action}${actor}${when}${remarks}`;
  });
  const more = events.length > 6 ? ` plus ${events.length - 6} more` : '';
  const base = fmtLeaveRequest(request, language);

  return structuredReply(language, {
    title: 'Approval timeline',
    summary: base,
    details: [...lines, ...(more ? [more.trim()] : [])],
    limit: 7,
  });
}

function locatorSlots(slip) {
  const slots = [];
  if (slip?.coverage?.am_in) slots.push('AM in');
  if (slip?.coverage?.am_out) slots.push('AM out');
  if (slip?.coverage?.pm_in) slots.push('PM in');
  if (slip?.coverage?.pm_out) slots.push('PM out');
  return slots;
}

function locatorStatusText(status) {
  const value = lower(status);
  if (value === 'pending_department_head') return 'waiting for department head review';
  if (value === 'pending_hr' || value === 'pending') return 'waiting for HR review';
  if (value === 'approved') return 'approved by HR';
  if (value === 'rejected_by_department_head') return 'rejected by department head';
  if (value === 'rejected_by_hr' || value === 'rejected') return 'rejected by HR';
  if (value === 'cancelled' || value === 'canceled') return 'cancelled';
  return statusLabel(status);
}

function requestedLocatorType(message) {
  const text = lower(message);
  if (/\b(wfh|work from home|home)\b/.test(text)) return 'work_from_home';
  if (/\b(pass slip|pass-slip|passslip)\b/.test(text)) return 'pass_slip';
  if (/\b(official business|official|business|ob|on field|field|fieldwork|field work|out of office|outside office|travel order|locator)\b/.test(text)) return 'locator';
  return null;
}

function requestedSpecificLocatorType(message) {
  const requestedType = requestedLocatorType(message);
  if (requestedType !== 'locator') return requestedType;
  const text = lower(message);
  return /\b(official business|official|business|ob|on field|field|fieldwork|field work|out of office|outside office|travel order)\b/.test(text)
    ? 'locator'
    : null;
}

function locatorTypeMatches(item, requestedType) {
  if (!requestedType) return true;
  const code = lower(item?.request_type || item?.code);
  const label = lower(item?.request_type_label || item?.label);
  if (requestedType === 'locator') {
    return (
      code === 'locator' ||
      code === 'official_business' ||
      code === 'official business' ||
      label.includes('locator') ||
      label.includes('official business') ||
      label.includes('on field')
    );
  }
  return (
    code === requestedType ||
    label.includes(requestedType.replace(/_/g, ' '))
  );
}

function requestedLocatorStatus(message) {
  const text = lower(message);
  if (/\b(pending|waiting|awaiting|hold|holding|asa|where|kinsa|sino)\b/.test(text)) return 'pending';
  if (/\b(approved|approve|na-approve|accepted|accept)\b/.test(text)) return 'approved';
  if (/\b(rejected|reject|declined|denied|gi reject|gireject|not approved|wala.*approve|dili.*approved|hindi.*approved)\b/.test(text)) return 'rejected';
  if (/\b(cancelled|canceled|cancel)\b/.test(text)) return 'cancelled';
  return null;
}

function localizedLocatorStatusName(status, language) {
  if (status === 'approved') {
    if (language === 'bisaya') return 'approved/accepted';
    if (language === 'tagalog') return 'approved/accepted';
    return 'approved';
  }
  if (status === 'pending') {
    if (language === 'bisaya') return 'pending';
    if (language === 'tagalog') return 'pending';
    return 'pending';
  }
  if (status === 'rejected') {
    if (language === 'bisaya') return 'rejected';
    if (language === 'tagalog') return 'rejected';
    return 'rejected';
  }
  if (status === 'cancelled') {
    if (language === 'bisaya') return 'cancelled';
    if (language === 'tagalog') return 'cancelled';
    return 'cancelled';
  }
  return '';
}

function locatorStatusMatches(status, requested) {
  if (!requested) return true;
  const value = lower(status);
  if (requested === 'pending') return value === 'pending' || value === 'pending_department_head' || value === 'pending_hr';
  if (requested === 'approved') return value === 'approved';
  if (requested === 'rejected') return value === 'rejected' || value === 'rejected_by_department_head' || value === 'rejected_by_hr';
  if (requested === 'cancelled') return value === 'cancelled' || value === 'canceled';
  return true;
}

function locatorSlipsForMessage(context, message) {
  const range = context.date_range || {};
  const useRange = hasDateRangeHint(message);
  const requestedType = requestedSpecificLocatorType(message);
  const requestedStatus = requestedLocatorStatus(message);
  return (context.recent_locator_slips || []).filter((slip) => {
    if (useRange && range.startDate && range.endDate) {
      if (slip.slip_date < range.startDate || slip.slip_date > range.endDate) return false;
    }
    if (!locatorTypeMatches(slip, requestedType)) return false;
    if (!locatorStatusMatches(slip.status, requestedStatus)) return false;
    return true;
  });
}

function locatorTypeRulesForMessage(context, message, { genericLocatorMeansAll = true } = {}) {
  const requestedType = genericLocatorMeansAll
    ? requestedSpecificLocatorType(message)
    : requestedLocatorType(message);
  const types = context.locator_types || [];
  const matches = types.filter((type) => locatorTypeMatches(type, requestedType));
  return matches.length > 0 ? matches : requestedType ? [] : types;
}

function locatorTypeName(type) {
  const label = type?.label || type?.code || 'Locator';
  if (type?.short_label && !lower(label).includes(lower(type.short_label))) {
    return `${label} (${type.short_label})`;
  }
  return label;
}

function locatorCoverageModeText(type, language) {
  if (type?.coverage_mode === 'wfh') {
    if (language === 'bisaya') return 'WFH coverage sa DTR';
    if (language === 'tagalog') return 'WFH coverage sa DTR';
    return 'WFH coverage in DTR';
  }
  if (language === 'bisaya') return 'pili-a ang sakop nga AM/PM DTR slots';
  if (language === 'tagalog') return 'piliin ang sakop na AM/PM DTR slots';
  return 'manual AM/PM slot selection';
}

function locatorAttachmentText(type, language) {
  if (type?.requires_attachment) {
    if (language === 'bisaya') return 'kinahanglan ug attachment';
    if (language === 'tagalog') return 'kailangan ng attachment';
    return 'attachment required';
  }
  if (language === 'bisaya') return 'walay required attachment ani nga type';
  if (language === 'tagalog') return 'walang required attachment sa type na ito';
  return 'no attachment required by this type';
}

function locatorLocationText(type, language) {
  if (!type?.location_label) return null;
  const hint = type.location_hint ? String(type.location_hint) : '';
  if (language === 'bisaya') {
    const hintText = hint
      .replace(/^Enter office or destination$/i, 'ibutang ang office o destination')
      .replace(/^Enter destination or location$/i, 'ibutang ang destination o location')
      .replace(/^Enter work location$/i, 'ibutang ang work location');
    return hintText ? `${type.location_label}: ${hintText}` : type.location_label;
  }
  if (language === 'tagalog') {
    const hintText = hint
      .replace(/^Enter office or destination$/i, 'ilagay ang office o destination')
      .replace(/^Enter destination or location$/i, 'ilagay ang destination o location')
      .replace(/^Enter work location$/i, 'ilagay ang work location');
    return hintText ? `${type.location_label}: ${hintText}` : type.location_label;
  }
  return `${type.location_label}${hint ? `: ${hint}` : ''}`;
}

function locatorDtrLabelText(type, language) {
  if (!type?.dtr_slot_label) return null;
  if (language === 'bisaya') return `DTR label nga gamiton: ${type.dtr_slot_label}`;
  if (language === 'tagalog') return `DTR label na gagamitin: ${type.dtr_slot_label}`;
  return `DTR label: ${type.dtr_slot_label}`;
}

function fmtLocatorTypeRule(type, language) {
  const parts = [
    locatorCoverageModeText(type, language),
    locatorAttachmentText(type, language),
    locatorLocationText(type, language),
    locatorDtrLabelText(type, language),
  ].filter(Boolean);
  return `${locatorTypeName(type)}: ${parts.join('; ')}`;
}

function locatorRequirementPolicyLines(language) {
  if (language === 'bisaya') {
    return [
      'Locator filing: Kinahanglan ug slip date, locator type, covered DTR slot/s, destination/location, ug reason.',
      'DTR coverage: Makatabang lang sa DTR ang locator kung approved na ug sakto ang covered slot/s.',
      'Approval workflow: Muagi gihapon ni sa normal approval workflow; dili pa ni final kung pending pa.',
    ];
  }
  if (language === 'tagalog') {
    return [
      'Locator filing: Kailangan ng slip date, locator type, covered DTR slot/s, destination/location, at reason.',
      'DTR coverage: Makakatulong lang sa DTR ang locator kapag approved na at tama ang covered slot/s.',
      'Approval workflow: Dadaan pa rin ito sa normal approval workflow; hindi pa final kung pending pa.',
    ];
  }
  return policyPointLines(getLocatorPolicySectionsForMessage('', {
    fallbackKeys: [
      'filing_requirements',
      'dtr_coverage',
      'approval_workflow',
    ],
  }), {
    maxPointsPerSection: 2,
  });
}

function locatorTypesReply(context, message) {
  const language = languageOf(message);
  const requestedType = requestedSpecificLocatorType(message);
  const types = locatorTypeRulesForMessage(context, message);
  if (types.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang matching locator type sa system.';
    if (language === 'tagalog') return 'Wala akong nakitang matching locator type sa system.';
    return 'I found no matching locator type in the system.';
  }

  const singleType = requestedType && types.length === 1;
  const summary = singleType
    ? language === 'bisaya'
      ? `${locatorTypeName(types[0])} kay available nga locator type sa HRMS.`
      : language === 'tagalog'
        ? `${locatorTypeName(types[0])} ay available na locator type sa HRMS.`
        : `${locatorTypeName(types[0])} is available as a locator type in HRMS.`
    : language === 'bisaya'
      ? `Mao ni ang ${types.length} ka locator type nga pwede i-file sa HRMS.`
      : language === 'tagalog'
        ? `Ito ang ${types.length} locator type na puwedeng i-file sa HRMS.`
        : `These are the ${types.length} locator types you can file in HRMS.`;

  return structuredReply(language, {
    title:
      language === 'bisaya'
        ? singleType
          ? 'Detalye sa locator type'
          : 'Locator types nga pwede nimo ma-file'
        : language === 'tagalog'
          ? singleType
            ? 'Detalye ng locator type'
            : 'Mga locator type na puwede mong i-file'
          : singleType
            ? 'Locator type details'
            : 'Locator types you can file',
    summary,
    details: [
      ...types.map((type) => fmtLocatorTypeRule(type, language)),
      singleType && types[0]?.coverage_mode === 'wfh'
        ? language === 'bisaya'
          ? 'Human ma-approve, ang covered DTR slots kasagarang ma-mark as WFH.'
          : language === 'tagalog'
            ? 'Kapag approved na, karaniwang mamamarkahan bilang WFH ang covered DTR slots.'
            : 'WFH usually marks covered DTR slots as WFH after approval.'
        : null,
      ...(language === 'english'
        ? locatorPolicyLines(message, ['types', 'dtr_coverage'], {
            maxPointsPerSection: 1,
          })
        : language === 'bisaya'
          ? [
              'Ang available locator types gikan sa active HRMS setup.',
              'Makatabang lang sa DTR ang locator kung approved na ug sakto ang covered slots.',
            ]
          : [
              'Ang available locator types ay galing sa active HRMS setup.',
              'Makakatulong lang sa DTR ang locator kapag approved na at tama ang covered slots.',
            ]),
      language === 'bisaya'
        ? 'Kinahanglan gihapon ang slip date, covered slots, location/destination, ug reason.'
        : language === 'tagalog'
          ? 'Kailangan pa rin ang slip date, covered slots, location/destination, at reason.'
          : 'You still need a slip date, covered slots, location/destination, and reason.',
      language === 'bisaya'
        ? 'Kinahanglan pa ang approval bago mahimong final DTR coverage.'
        : language === 'tagalog'
          ? 'Kailangan pa ng approval bago maging final DTR coverage.'
          : 'Approval is still required before it becomes final DTR coverage.',
    ],
    nextStep:
      language === 'bisaya'
        ? 'Kung gusto nimo i-check ang specific date, pangutan-a ko: "Pwede ba ko mag-WFH ugma?"'
        : language === 'tagalog'
          ? 'Kung gusto mong i-check ang specific date, itanong: "Puwede ba akong mag-WFH bukas?"'
          : 'To check a specific date, ask: "Can I file WFH tomorrow?"',
    limit: 8,
  });
}

function localizedLocatorStatusText(status, language) {
  if (language === 'bisaya') {
    const value = lower(status);
    if (value === 'pending_department_head') return 'naghulat sa department head review';
    if (value === 'pending_hr' || value === 'pending') return 'naghulat sa HR review';
    if (value === 'approved') return 'approved sa HR';
    if (value === 'rejected_by_department_head') return 'rejected sa department head';
    if (value === 'rejected_by_hr' || value === 'rejected') return 'rejected sa HR';
    if (value === 'cancelled' || value === 'canceled') return 'cancelled';
  }
  if (language === 'tagalog') {
    const value = lower(status);
    if (value === 'pending_department_head') return 'naghihintay ng department head review';
    if (value === 'pending_hr' || value === 'pending') return 'naghihintay ng HR review';
    if (value === 'approved') return 'approved ng HR';
    if (value === 'rejected_by_department_head') return 'rejected ng department head';
    if (value === 'rejected_by_hr' || value === 'rejected') return 'rejected ng HR';
    if (value === 'cancelled' || value === 'canceled') return 'cancelled';
  }
  return locatorStatusText(status);
}

function fmtLocatorSlip(slip, language = 'english') {
  const slots = locatorSlots(slip);
  const type = slip.request_type_label || slip.request_type || 'Locator';
  const place = slip.office ? `, ${slip.office}` : '';
  const attachment = slip.has_attachment
    ? language === 'bisaya'
      ? ', naay attachment'
      : language === 'tagalog'
        ? ', may attachment'
        : ', with attachment'
    : '';
  const dateConnector = language === 'bisaya' ? 'sa' : language === 'tagalog' ? 'noong' : 'on';
  const coverageConnector =
    language === 'bisaya' ? 'nag-cover sa' : language === 'tagalog' ? 'sakop ang' : 'covering';
  return `${type} ${dateConnector} ${fmtFriendlyDate(slip.slip_date)} - ${localizedLocatorStatusText(slip.status, language)}${
    slots.length > 0 ? `, ${coverageConnector} ${slots.join(', ')}` : ''
  }${place}${attachment}`;
}

function locatorRemarks(slip) {
  return slip.hr_remarks || slip.dept_head_remarks || null;
}

function locatorReply(context, localized, message = '') {
  const language = languageOf(message);
  const slips = locatorSlipsForMessage(context, message);
  const slip = slips[0] || context.recent_locator_slips?.[0];
  if (!slip) {
    if (language === 'bisaya') return 'Wala koy nakitang locator slip records sa imong account.';
    if (language === 'tagalog' || localized) return 'Wala akong nakitang locator slip records para sa account mo.';
    return 'I found no locator slip records for your account.';
  }

  const remarks = locatorRemarks(slip);
  const details = [
    `Status: ${locatorStatusText(slip.status)}`,
    `Date: ${fmtFriendlyDate(slip.slip_date)}`,
    `Type: ${slip.request_type_label || slip.request_type || 'Locator'}`,
    locatorSlots(slip).length > 0 ? `Coverage: ${locatorSlots(slip).join(', ')}` : null,
    slip.office ? `${slip.request_type_location_label || 'Location'}: ${slip.office}` : null,
    slip.reason ? `Reason: ${slip.reason}` : null,
    slip.dept_head_reviewer_name ? `Department head reviewer: ${slip.dept_head_reviewer_name}` : null,
    slip.hr_reviewer_name ? `HR reviewer: ${slip.hr_reviewer_name}` : null,
    remarks ? `Remarks: ${remarks}` : null,
  ];
  const title = language === 'bisaya' ? 'Locator status' : language === 'tagalog' ? 'Status ng locator' : 'Locator status';
  const summary =
    language === 'bisaya'
      ? `Ang locator request nimo kay ${locatorStatusText(slip.status)}.`
      : language === 'tagalog'
        ? `Ang locator request mo ay ${locatorStatusText(slip.status)}.`
        : `Your locator request is ${locatorStatusText(slip.status)}.`;
  return structuredReply(language, {
    title,
    summary,
    details,
    nextStep: lower(slip.status).startsWith('pending')
      ? language === 'bisaya'
        ? 'Hulat sa review, or i-check kung naa bay remarks/attachment nga kinahanglan.'
        : language === 'tagalog'
          ? 'Hintayin ang review, o i-check kung may remarks/attachment na kailangan.'
          : 'Wait for review, or check if remarks/attachment are needed.'
      : null,
    limit: 9,
  });
}

function locatorSummaryReply(context, message) {
  const language = languageOf(message);
  const slips = locatorSlipsForMessage(context, message);
  const label = hasDateRangeHint(message) ? context.date_range?.label || 'selected period' : 'recent records';
  const requestedStatus = requestedLocatorStatus(message);
  const statusText = localizedLocatorStatusName(requestedStatus, language);
  if (slips.length === 0) {
    if (language === 'bisaya') {
      return `Wala koy nakitang ${statusText ? `${statusText} ` : ''}locator slip para sa ${displayPeriodLabel(label, language)}.`;
    }
    if (language === 'tagalog') {
      return `Wala akong nakitang ${statusText ? `${statusText} ` : ''}locator slip para sa ${displayPeriodLabel(label, language)}.`;
    }
    return `I found no ${statusText ? `${statusText} ` : ''}locator slips for ${label}.`;
  }
  const counts = slips.reduce(
    (acc, slip) => {
      const status = lower(slip.status);
      if (status === 'approved') acc.approved += 1;
      else if (status === 'pending' || status === 'pending_department_head' || status === 'pending_hr') acc.pending += 1;
      else if (status === 'rejected' || status === 'rejected_by_department_head' || status === 'rejected_by_hr') acc.rejected += 1;
      else if (status === 'cancelled' || status === 'canceled') acc.cancelled += 1;
      else acc.other += 1;
      return acc;
    },
    { pending: 0, approved: 0, rejected: 0, cancelled: 0, other: 0 }
  );
  const lines = limitedRequests(slips, 6).map(fmtLocatorSlip);
  const summary =
    language === 'bisaya'
      ? `Nakita nako ang ${slips.length} ka ${statusText ? `${statusText} ` : ''}locator slip para sa ${displayPeriodLabel(label, language)}.`
      : language === 'tagalog'
        ? `May nakita akong ${slips.length} ${statusText ? `${statusText} ` : ''}locator slip para sa ${displayPeriodLabel(label, language)}.`
        : `I found ${slips.length} ${statusText ? `${statusText} ` : ''}locator ${plural(slips.length, 'slip')} for ${label}.`;
  return structuredReply(language, {
    title: `Locator summary (${label})`,
    summary,
    details: [
      `Pending: ${counts.pending}`,
      `Approved: ${counts.approved}`,
      `Rejected: ${counts.rejected}`,
      `Cancelled: ${counts.cancelled}`,
      ...lines,
    ],
    limit: 10,
  });
}

function locatorRequirementsReply(context, message) {
  const language = languageOf(message);
  const asksDestination =
    /\b(destination|destination field|location field|office field|where.*(?:put|enter|write|type)|asa.*ibutang|saan.*ilalagay)\b/i.test(
      message
    );
  const asksReason =
    /\b(reason field|locator reason|what.*(?:put|enter|write|type).*reason|sample reason|example reason|unsa.*ibutang.*reason|ano.*ilalagay.*reason)\b/i.test(
      message
    );
  const asksRequiredFields =
    /\b(required fields?|fields? required|what fields? (?:are )?required|which fields? (?:are )?required|unsa.*(?:required|kinahanglan).*fields?|ano.*(?:required|kailangan).*fields?)\b/i.test(
      message
    );

  if (asksDestination || asksReason || asksRequiredFields) {
    const details = [];
    if (asksDestination || asksRequiredFields) {
      details.push(
        language === 'bisaya'
          ? 'Office / Destination: Isulat ang tinuod nga office, agency, client site, o work location. Example: "Municipal Engineering Office, Plaridel" o "Home work location - Poblacion, Plaridel" para sa WFH.'
          : language === 'tagalog'
            ? 'Office / Destination: Ilagay ang totoong office, agency, client site, o work location. Halimbawa: "Municipal Engineering Office, Plaridel" o "Home work location - Poblacion, Plaridel" para sa WFH.'
            : 'Office / Destination: Enter the actual office, agency, client site, or work location. Example: "Municipal Engineering Office, Plaridel" or "Home work location - Poblacion, Plaridel" for WFH.'
      );
    }
    if (asksReason || asksRequiredFields) {
      details.push(
        language === 'bisaya'
          ? 'Reason: Mubo pero klaro nga official purpose. Example: "Submit and follow up payroll documents" o "Attend the scheduled coordination meeting."'
          : language === 'tagalog'
            ? 'Reason: Maikli pero malinaw na official purpose. Halimbawa: "Submit and follow up payroll documents" o "Attend the scheduled coordination meeting."'
            : 'Reason: Give a short, clear official purpose. Example: "Submit and follow up payroll documents" or "Attend the scheduled coordination meeting."'
      );
    }
    if (asksRequiredFields) {
      details.push(
        language === 'bisaya'
          ? 'Kompletuhon ang locator type, slip date, covered DTR slots, office/destination, reason, ug attachment kung required sa selected type.'
          : language === 'tagalog'
            ? 'Kumpletuhin ang locator type, slip date, covered DTR slots, office/destination, reason, at attachment kung required sa napiling type.'
            : 'Complete the locator type, slip date, covered DTR slots, office/destination, reason, and any attachment required by the selected type.'
      );
    }
    return structuredReply(language, {
      title:
        language === 'bisaya'
          ? 'Tabang sa locator form'
          : language === 'tagalog'
            ? 'Tulong sa locator form'
            : 'Locator form help',
      summary:
        language === 'bisaya'
          ? 'Mao ni ang pwede nimo ibutang. Ilisi ang examples sa imong tinuod nga detalye.'
          : language === 'tagalog'
            ? 'Ito ang puwede mong ilagay. Palitan ang examples ng totoong detalye mo.'
            : 'Here is what to enter. Replace the examples with your real details.',
      details,
      nextStep:
        language === 'bisaya'
          ? 'Pilia usab ang exact AM/PM slots nga kinahanglan ma-cover sa approved locator.'
          : language === 'tagalog'
            ? 'Piliin din ang eksaktong AM/PM slots na kailangang ma-cover ng approved locator.'
            : 'Also select the exact AM/PM slots that the approved locator should cover.',
      limit: 5,
    });
  }
  const visible = locatorTypeRulesForMessage(context, message);
  if (visible.length === 0) {
    if (language === 'bisaya') return 'Wala koy nakitang locator request type rules sa system.';
    if (language === 'tagalog') return 'Wala akong nakitang locator request type rules sa system.';
    return 'I found no locator request type rules in the system.';
  }
  const lines = visible.map((type) => fmtLocatorTypeRule(type, language));
  const summary =
    language === 'bisaya'
      ? 'Base sa locator type setup, mao ni ang rules sa pag-file.'
      : language === 'tagalog'
        ? 'Base sa locator type setup, ito ang filing rules.'
        : 'Based on the locator type setup, these are the filing rules.';
  return structuredReply(language, {
    title: 'Locator filing requirements',
    summary,
    details: [
      ...lines,
      ...locatorRequirementPolicyLines(language),
      language === 'bisaya'
        ? 'Kinahanglan valid working-day schedule ang slip date.'
        : language === 'tagalog'
          ? 'Kailangan valid working-day schedule ang slip date.'
          : 'You need a valid working-day schedule for the slip date.',
      language === 'bisaya'
        ? 'Pili ug bisan usa ka covered slot: AM in, AM out, PM in, o PM out.'
        : language === 'tagalog'
          ? 'Pumili ng kahit isang covered slot: AM in, AM out, PM in, o PM out.'
          : 'Choose at least one covered slot: AM in, AM out, PM in, or PM out.',
      language === 'bisaya'
        ? 'Kinahanglan ang office/destination ug klarong reason.'
        : language === 'tagalog'
          ? 'Kailangan ang office/destination at malinaw na reason.'
          : 'Office/destination and reason are required.',
    ],
    nextStep:
      language === 'bisaya'
        ? 'Kung rejected o pending imong locator, pangutan-a ko bahin sa status o reviewer remarks.'
        : language === 'tagalog'
          ? 'Kung rejected or pending ang locator mo, tanungin mo ako tungkol sa status o remarks.'
          : 'If your locator is rejected or pending, ask me about its status or remarks.',
    limit: 12,
  });
}

function locatorAvailabilityReply(context, message) {
  const language = languageOf(message);
  const range = context.date_range || {};
  const date = range.startDate || range.endDate || null;
  const day = date ? calendarDayForDate(context, date) : null;
  const type = locatorTypeRulesForMessage(context, message)[0] || null;
  const requestedSlot = requestedDtrSlot(message);
  const requestedType = requestedLocatorType(message);
  const existing = (context.recent_locator_slips || []).filter((slip) => {
    if (date && slip.slip_date !== date) return false;
    return locatorTypeMatches(slip, requestedType);
  });
  const issues = [];
  if (!date) issues.push('No target date was detected.');
  if (day?.holiday_name && day.holiday_coverage === 'whole_day') {
    issues.push(`Date is marked as whole-day holiday: ${day.holiday_name}`);
  }
  if (day && !isCalendarWorkingDay(day)) {
    issues.push('Schedule says this is not a required-log working day.');
  }
  if (!day && date) {
    issues.push('Schedule details are not loaded for this date.');
  }

  const typeLabel = type?.label || type?.code || (requestedType ? requestedType.replace(/_/g, ' ') : 'not selected');
  const details = [
    date ? `Date: ${fmtFriendlyDate(date)}` : null,
    `Locator type: ${typeLabel}`,
    day?.shift_name
      ? `Schedule: ${day.shift_name}${fmtScheduleRange(day) ? ` (${fmtScheduleRange(day)})` : ''}`
      : null,
    day?.holiday_name ? `Holiday: ${day.holiday_name} (${day.holiday_coverage || 'whole_day'})` : null,
    requestedSlot
      ? `Requested DTR coverage: ${requestedSlot}`
      : 'DTR coverage: choose AM in, AM out, PM in, or PM out.',
    type
      ? `Attachment: ${type.requires_attachment ? 'required' : 'not required by this locator type'}`
      : 'Type rules: choose the exact locator type to check attachment rules.',
    existing.length > 0
      ? `Existing locator on this date: ${existing.map(fmtLocatorSlip).join('; ')}`
      : null,
    ...issues,
    ...locatorPolicyLines(message, ['filing_checks', 'dtr_coverage'], {
      maxPointsPerSection: 1,
    }),
  ];
  const hasBlockingIssue = issues.some((issue) => !issue.includes('not loaded'));
  const title =
    language === 'bisaya'
      ? 'Locator filing check'
      : language === 'tagalog'
        ? 'Locator filing check'
        : 'Locator filing check';
  const summary =
    hasBlockingIssue
      ? language === 'bisaya'
        ? 'Naay issue sa initial locator check. Tan-awa ang detalye sa ubos.'
        : language === 'tagalog'
          ? 'May issue sa initial locator check. Tingnan ang detalye sa baba.'
          : 'The initial locator filing check found an issue.'
      : language === 'bisaya'
        ? 'Initial check: murag pwede ka mag-file, basta kompleto ang type, slots, destination, reason, ug required attachment.'
        : language === 'tagalog'
          ? 'Initial check: mukhang puwede kang mag-file kung kumpleto ang type, slots, destination, reason, at required attachment.'
          : 'Initial check: you can file if the type, slots, destination, reason, and required attachment are complete.';
  return structuredReply(language, {
    title,
    summary,
    details,
    nextStep:
      language === 'bisaya'
        ? 'Submit gihapon sa normal approval workflow; dili pa ni final approval.'
        : language === 'tagalog'
          ? 'I-submit pa rin sa normal approval workflow; hindi pa ito final approval.'
          : 'Submit it through the normal approval workflow; this is not final approval.',
    limit: 12,
  });
}

function locatorRejectionReasonReply(context, message) {
  const language = languageOf(message);
  const slips = locatorSlipsForMessage(context, message);
  const slip =
    slips.find((item) => rejectedStatus(item.status)) ||
    (context.recent_locator_slips || []).find((item) => rejectedStatus(item.status));
  if (!slip) {
    if (language === 'bisaya') return 'Wala koy nakitang rejected locator slip sa imong recent records.';
    if (language === 'tagalog') return 'Wala akong nakitang rejected locator slip sa recent records mo.';
    return 'I found no rejected locator slip in your recent records.';
  }
  const rejectedBy = /department_head/.test(lower(slip.status))
    ? 'department head'
    : /hr/.test(lower(slip.status))
      ? 'HR'
      : 'reviewer';
  const remarks = locatorRemarks(slip);
  const summary =
    language === 'bisaya'
      ? `Gi-reject ang locator request nimo ${fmtLocalizedDateRange(slip.slip_date, slip.slip_date, language)}.`
      : language === 'tagalog'
        ? `Na-reject ang locator request mo ${fmtLocalizedDateRange(slip.slip_date, slip.slip_date, language)}.`
        : `Your locator request ${fmtLocalizedDateRange(slip.slip_date, slip.slip_date, language)} was rejected.`;
  return structuredReply(language, {
    title: 'Locator rejection reason',
    summary,
    details: [
      fmtLocatorSlip(slip, language),
      `Rejected by: ${rejectedBy}`,
      remarks ? `Remarks: ${remarks}` : 'Remarks: no rejection remarks saved in the record.',
      slip.dept_head_reviewer_name ? `Department head reviewer: ${slip.dept_head_reviewer_name}` : null,
      slip.hr_reviewer_name ? `HR reviewer: ${slip.hr_reviewer_name}` : null,
    ],
    nextStep:
      language === 'bisaya'
        ? 'Kung kulang ang remarks, i-check sa reviewer or HR unsay kinahanglan usbon.'
        : language === 'tagalog'
          ? 'Kung kulang ang remarks, i-check sa reviewer o HR kung ano ang kailangang ayusin.'
          : 'If the remarks are not enough, check with the reviewer or HR what needs to be corrected.',
    limit: 7,
  });
}

function locatorApprovalOwner(slip, language = 'english') {
  const status = lower(slip?.status);
  if (status === 'pending_department_head') {
    return slip.dept_head_reviewer_name
      ? `department head (${slip.dept_head_reviewer_name})`
      : language === 'bisaya'
        ? 'department head review'
        : language === 'tagalog'
          ? 'department head review'
          : 'department head review';
  }
  if (status === 'pending_hr' || status === 'pending') {
    return slip.hr_reviewer_name ? `HR (${slip.hr_reviewer_name})` : 'HR review';
  }
  if (status === 'approved') {
    return slip.hr_reviewer_name ? `completed by HR (${slip.hr_reviewer_name})` : 'completed by HR';
  }
  if (/department_head/.test(status)) {
    return slip.dept_head_reviewer_name
      ? `department head (${slip.dept_head_reviewer_name})`
      : 'department head';
  }
  if (/hr/.test(status)) {
    return slip.hr_reviewer_name ? `HR (${slip.hr_reviewer_name})` : 'HR';
  }
  return 'reviewer';
}

function locatorApprovalTrackerReply(context, message) {
  const language = languageOf(message);
  const slips = locatorSlipsForMessage(context, message);
  const slip = slips.find((item) => pendingStatus(item.status)) || slips[0] || context.recent_locator_slips?.[0];
  if (!slip) {
    if (language === 'bisaya') return 'Wala koy nakitang locator slip nga ma-track sa imong account.';
    if (language === 'tagalog') return 'Wala akong nakitang locator slip na puwedeng i-track sa account mo.';
    return 'I found no locator slip to track for your account.';
  }
  const owner = locatorApprovalOwner(slip, language);
  const status = localizedLocatorStatusText(slip.status, language);
  const summary =
    pendingStatus(slip.status)
      ? language === 'bisaya'
        ? `Pending pa ang locator request nimo. Naa siya sa ${owner}.`
        : language === 'tagalog'
          ? `Pending pa ang locator request mo. Nasa ${owner} siya.`
          : `Your locator request is still pending with ${owner}.`
      : language === 'bisaya'
        ? `Dili na pending ang locator request nimo; status niya kay ${status}.`
        : language === 'tagalog'
          ? `Hindi na pending ang locator request mo; status nito ay ${status}.`
          : `Your locator request is no longer pending; its status is ${status}.`;
  return structuredReply(language, {
    title:
      language === 'bisaya'
        ? 'Pagsubay sa locator approval'
        : language === 'tagalog'
          ? 'Pagsubaybay sa locator approval'
          : 'Locator approval tracker',
    summary,
    details: [
      fmtLocatorSlip(slip, language),
      `${language === 'bisaya' ? 'Current review step' : language === 'tagalog' ? 'Kasalukuyang review step' : 'Current step'}: ${owner}`,
      slip.created_at
        ? `${language === 'bisaya' ? 'Gi-file' : language === 'tagalog' ? 'Na-file' : 'Filed'}: ${fmtFriendlyDate(slip.created_at)}`
        : null,
      slip.dept_head_reviewed_at ? `Department head reviewed: ${fmtFriendlyDate(slip.dept_head_reviewed_at)}` : null,
      slip.hr_reviewed_at ? `HR reviewed: ${fmtFriendlyDate(slip.hr_reviewed_at)}` : null,
      locatorRemarks(slip) ? `Reviewer remarks: ${locatorRemarks(slip)}` : null,
    ],
    nextStep:
      pendingStatus(slip.status)
        ? language === 'bisaya'
          ? 'Kung dugay na pending, i-follow up sa current reviewer.'
          : language === 'tagalog'
            ? 'Kung matagal nang pending, i-follow up sa current reviewer.'
            : 'If it has been pending for a while, follow up with the current reviewer.'
        : null,
    limit: 8,
  });
}

function buildFastEmployeeAssistantReply(message, context, intent) {
  const text = lower(message);
  const localized = isTagalogOrBisaya(message);

  if (intent === 'today_dtr') {
    return dtrDailyRecordReply(context, message);
  }
  if (intent === 'missing_logs') {
    return dtrMissingLogsReply(context, message);
  }
  if (intent === 'dtr_daily_record') {
    return dtrDailyRecordReply(context, message);
  }
  if (intent === 'dtr_range_summary') {
    return dtrRangeSummaryReply(context, message);
  }
  if (intent === 'dtr_missing_logs') {
    return dtrMissingLogsReply(context, message);
  }
  if (intent === 'dtr_missing_log_reason') {
    return dtrMissingLogsReply(context, message, true);
  }
  if (intent === 'dtr_late_summary') {
    return dtrMinuteSummaryReply(context, message, 'late');
  }
  if (intent === 'dtr_late_reason') {
    return dtrLateReasonReply(context, message);
  }
  if (intent === 'dtr_undertime_summary') {
    return dtrMinuteSummaryReply(context, message, 'undertime');
  }
  if (intent === 'dtr_overtime_summary') {
    return dtrMinuteSummaryReply(context, message, 'overtime');
  }
  if (intent === 'dtr_absent_summary') {
    return dtrAbsentSummaryReply(context, message);
  }
  if (intent === 'dtr_status_explanation') {
    return dtrStatusExplanationReply(context, message);
  }
  if (intent === 'dtr_correction_guidance') {
    return dtrCorrectionGuidanceReply(context, message);
  }
  if (intent === 'dtr_leave_coverage_check') {
    return dtrLeaveCoverageReply(context, message);
  }
  if (intent === 'dtr_locator_coverage_check') {
    return dtrLocatorCoverageReply(context, message);
  }
  if (intent === 'dtr_holiday_check') {
    return dtrHolidayReply(context, message);
  }
  if (intent === 'dtr_schedule_context') {
    return dtrScheduleContextReply(context, message);
  }
  if (intent === 'dtr_export_guidance') {
    return dtrExportGuidanceReply(context, message);
  }
  if (intent === 'dtr_policy_guidance') {
    return dtrPolicyGuidanceReply(context, message);
  }
  if (intent === 'leave_balance') {
    return leaveBalanceReply(context, localized, message);
  }
  if (intent === 'latest_leave_request') {
    return latestLeaveReply(context, localized, message);
  }
  if (intent === 'pending_leave_requests') {
    return leaveRequestsByStatusReply(context, message, pendingStatus, {
      bisaya: 'pending',
      tagalog: 'pending',
      english: 'pending',
    });
  }
  if (intent === 'approved_leave_requests') {
    return leaveRequestsByStatusReply(context, message, approvedStatus, {
      bisaya: 'approved',
      tagalog: 'approved',
      english: 'approved',
    });
  }
  if (intent === 'rejected_leave_requests') {
    return leaveRequestsByStatusReply(context, message, rejectedStatus, {
      bisaya: 'rejected',
      tagalog: 'rejected',
      english: 'rejected',
    });
  }
  if (intent === 'leave_history') {
    return leaveHistoryReply(context, message);
  }
  if (intent === 'leave_availability_check') {
    return leaveAvailabilityReply(context, message);
  }
  if (intent === 'leave_attachment_requirement') {
    return leaveAttachmentRequirementReply(context, message);
  }
  if (intent === 'leave_overlap_check') {
    return leaveOverlapCheckReply(context, message);
  }
  if (intent === 'leave_pending_days_explanation') {
    return leavePendingDaysExplanationReply(context, message);
  }
  if (intent === 'leave_balance_after_filing') {
    return leaveBalanceAfterFilingReply(context, message);
  }
  if (intent === 'leave_request_summary') {
    return leaveRequestSummaryReply(context, message);
  }
  if (intent === 'leave_request_lookup') {
    return leaveRequestLookupReply(context, message);
  }
  if (intent === 'leave_filing_policy') {
    return leaveFilingPolicyReply(context, message);
  }
  if (intent === 'leave_form_guidance') {
    return leaveFormGuidanceReply(context, message);
  }
  if (intent === 'leave_form_field_help') {
    return leaveFormFieldHelpReply(context, message);
  }
  if (intent === 'leave_eligibility_check') {
    return leaveEligibilityReply(context, message);
  }
  if (intent === 'leave_dtr_impact') {
    return leaveDtrImpactReply(context, message);
  }
  if (intent === 'leave_guideline_section') {
    return leaveGuidelineSectionReply(context, message);
  }
  if (intent === 'leave_type_compare') {
    return leaveTypeCompareReply(context, message);
  }
  if (intent === 'leave_guided_filing') {
    return leaveGuidedFilingReply(context, message);
  }
  if (intent === 'leave_rejection_reason') {
    return leaveRejectionReasonReply(context, message);
  }
  if (intent === 'leave_approval_tracker') {
    return leaveApprovalTrackerReply(context, message);
  }
  if (intent === 'leave_approval_history') {
    return leaveApprovalHistoryReply(context, message);
  }
  if (intent === 'leave_types') {
    return leaveTypesReply(context, message);
  }
  if (intent === 'leave_requirements') {
    return leaveRequirementsReply(context, message);
  }
  if (intent === 'latest_locator_request') {
    return locatorReply(context, localized, message);
  }
  if (intent === 'locator_status') {
    return locatorReply(context, localized, message);
  }
  if (intent === 'locator_summary') {
    return locatorSummaryReply(context, message);
  }
  if (intent === 'locator_types') {
    return locatorTypesReply(context, message);
  }
  if (intent === 'locator_requirements') {
    return locatorRequirementsReply(context, message);
  }
  if (intent === 'locator_availability_check') {
    return locatorAvailabilityReply(context, message);
  }
  if (intent === 'locator_rejection_reason') {
    return locatorRejectionReasonReply(context, message);
  }
  if (intent === 'locator_approval_tracker') {
    return locatorApprovalTrackerReply(context, message);
  }

  if (/\b(dtr|attendance|late|time[\s-]?in|time[\s-]?out)\b/.test(text)) {
    if (/\b(today|karon|ngayon|status|late)\b/.test(text)) {
      return dtrDailyRecordReply(context, message);
    }
  }

  // Calculated intents
  if (intent === 'dtr_hours_summary') {
    return dtrHoursSummaryReply(context, message);
  }
  if (intent === 'leave_balance_projection') {
    return leaveBalanceProjectionReply(context, message);
  }

  return null;
}

// ─── DTR Hours Summary ────────────────────────────────────────────────────────
// Answers: "How many total hours did I work this month?"
function dtrHoursSummaryReply(context, message) {
  const language = languageOf(message);
  const records = context.dtr_records || [];
  const range = context.date_range;
  const period = displayPeriodLabel(range && range.label, language);

  if (records.length === 0) {
    if (language === 'bisaya') {
      return `Wala akong nakitang DTR records para sa ${period}.`;
    }
    if (language === 'tagalog') {
      return `Wala akong nakitang DTR records para sa ${period}.`;
    }
    return `I found no DTR records for ${period}, so I cannot calculate your total hours.`;
  }

  const workedRecords = records.filter(function(r) {
    const s = lower(r.status || '');
    return (
      r.total_hours != null &&
      Number.isFinite(Number(r.total_hours)) &&
      Number(r.total_hours) > 0 &&
      s !== 'absent' &&
      s !== 'on_leave' &&
      s !== 'holiday' &&
      s !== 'no_record'
    );
  });

  const totalHours = workedRecords.reduce(function(sum, r) { return sum + (Number(r.total_hours) || 0); }, 0);
  const daysWorked = workedRecords.length;
  const totalDays = records.length;
  const lateRecords = records.filter(function(r) { return (r.late_minutes || 0) > 0; });
  const totalLateMinutes = records.reduce(function(sum, r) { return sum + (r.late_minutes || 0); }, 0);
  const undertimeRecords = records.filter(function(r) { return (r.undertime_minutes || 0) > 0; });
  const totalUndertimeMinutes = records.reduce(function(sum, r) { return sum + (r.undertime_minutes || 0); }, 0);

  const hoursStr = Number.isInteger(totalHours) ? String(totalHours) : totalHours.toFixed(2);
  const lateNote = lateRecords.length > 0
    ? (language === 'bisaya'
        ? `Late: ${lateRecords.length} ka adlaw (${totalLateMinutes} min total).`
        : language === 'tagalog'
          ? `Late: ${lateRecords.length} araw (${totalLateMinutes} min kabuuan).`
          : `Late: ${lateRecords.length} day(s) (${totalLateMinutes} min total).`)
    : null;
  const undertimeNote = undertimeRecords.length > 0
    ? (language === 'bisaya'
        ? `Undertime: ${undertimeRecords.length} ka adlaw (${totalUndertimeMinutes} min total).`
        : language === 'tagalog'
          ? `Undertime: ${undertimeRecords.length} araw (${totalUndertimeMinutes} min kabuuan).`
          : `Undertime: ${undertimeRecords.length} day(s) (${totalUndertimeMinutes} min total).`)
    : null;
  const notes = [lateNote, undertimeNote].filter(Boolean).join(' ');

  if (language === 'bisaya') {
    return `DTR Hours Summary\n\n${daysWorked} sa ${totalDays} ka adlaw ang nagtrabaho ka sa ${period}.\nTotal rendered hours: ${hoursStr} hours.${notes ? '\n' + notes : ''}`;
  }
  if (language === 'tagalog') {
    return `DTR Hours Summary\n\n${daysWorked} sa ${totalDays} araw nagtrabaho ka sa ${period}.\nKabuuang oras na rendered: ${hoursStr} oras.${notes ? '\n' + notes : ''}`;
  }
  return `DTR Hours Summary\n\nYou worked ${daysWorked} out of ${totalDays} day(s) in ${period}.\nTotal hours rendered: ${hoursStr} hours.${notes ? '\n' + notes : ''}`;
}

// ─── Leave Balance Projection ─────────────────────────────────────────────────
// Answers: "If I take N days of sick/vacation leave, how many days will be left?"
function parseRequestedDaysFromProjection(message) {
  const text = lower(message);
  const wordToNum = { one: 1, isa: 1, uno: 1, two: 2, duha: 2, dos: 2, three: 3, tulo: 3, tres: 3, four: 4, upat: 4, kwatro: 4, apat: 4, five: 5, lima: 5, singko: 5 };
  const patterns = [
    /\b(\d+(?:\.\d+)?)\s*(?:day|days|adlaw|ka\s*adlaw)\b/,
    /\btake\s+(\d+(?:\.\d+)?)/,
    /\bfile\s+ug?\s+(\d+(?:\.\d+)?)/,
    /\bfile\s+(\d+(?:\.\d+)?)\s*(?:day|days|adlaw)/,
    /\buse\s+(\d+(?:\.\d+)?)/,
    /\bavail\s+(?:ug\s+)?(\d+(?:\.\d+)?)/,
    /\bmag\s*-?file\s+(?:ug\s+)?(\d+(?:\.\d+)?)/,
  ];
  for (var i = 0; i < patterns.length; i++) {
    var m = text.match(patterns[i]);
    if (m && m[1]) {
      var val = parseFloat(m[1]);
      if (Number.isFinite(val) && val > 0 && val <= 365) return val;
    }
  }
  // Try word numbers
  for (var word in wordToNum) {
    if (new RegExp('\\b' + word + '\\b').test(text)) return wordToNum[word];
  }
  return null;
}

function leaveBalanceProjectionReply(context, message) {
  const language = languageOf(message);
  const balances = context.leave_balances || [];
  const requestedDays = parseRequestedDaysFromProjection(message);
  const leaveTypeStr = requestedLeaveType(message);

  if (balances.length === 0) {
    if (language === 'bisaya') return 'Wala akong nakitang leave balance records para sa imong account.';
    if (language === 'tagalog') return 'Wala akong nakitang leave balance records para sa account mo.';
    return 'I found no leave balance records for your account.';
  }

  if (!requestedDays) {
    const balanceLines = balances.map(function(b) {
      return b.leave_type + ': ' + fmtDays(Number(b.available_days || 0)) + ' available';
    });
    if (language === 'bisaya') {
      return 'Pila ka adlaw ang imong gusto i-file? Mao ni ang imong current leave balance:\n\n' +
        balanceLines.map(function(l) { return '- ' + l; }).join('\n') +
        '\n\nSulti lang ug pila ka adlaw, e.g. "If I take 3 days vacation leave, how many left?"';
    }
    if (language === 'tagalog') {
      return 'Ilang araw ang gusto mong i-file? Ito ang iyong kasalukuyang leave balance:\n\n' +
        balanceLines.map(function(l) { return '- ' + l; }).join('\n') +
        '\n\nSabihin lang ang bilang, e.g. "If I take 3 days vacation leave, how many will be left?"';
    }
    return 'How many days do you want to take? Here is your current leave balance:\n\n' +
      balanceLines.map(function(l) { return '- ' + l; }).join('\n') +
      '\n\nTell me the number, e.g. "If I take 3 days vacation leave, how many days will I have left?"';
  }

  var targetBalances = leaveTypeStr
    ? balances.filter(function(b) { return leaveTypeMatches(b, leaveTypeStr); })
    : balances;
  if (targetBalances.length === 0) targetBalances = balances;

  const lines = targetBalances.map(function(b) {
    const avail = Number(b.available_days || 0);
    const remaining = avail - requestedDays;
    const enough = remaining >= 0;
    const label = b.leave_type;
    if (language === 'bisaya') {
      return enough
        ? label + ': ' + fmtDays(avail) + ' available - ' + fmtDays(requestedDays) + ' = ' + fmtDays(remaining) + ' ka adlaw ang mabilin'
        : label + ': ' + fmtDays(avail) + ' available - ' + fmtDays(requestedDays) + ' = kulang ug ' + fmtDays(Math.abs(remaining)) + ' ka adlaw';
    }
    if (language === 'tagalog') {
      return enough
        ? label + ': ' + fmtDays(avail) + ' available - ' + fmtDays(requestedDays) + ' = ' + fmtDays(remaining) + ' araw ang matitira'
        : label + ': ' + fmtDays(avail) + ' available - ' + fmtDays(requestedDays) + ' = kulang ng ' + fmtDays(Math.abs(remaining)) + ' araw';
    }
    return enough
      ? label + ': ' + fmtDays(avail) + ' available - ' + fmtDays(requestedDays) + ' = ' + fmtDays(remaining) + ' days remaining'
      : label + ': ' + fmtDays(avail) + ' available - ' + fmtDays(requestedDays) + ' = short by ' + fmtDays(Math.abs(remaining)) + ' day(s)';
  });

  if (language === 'bisaya') {
    return 'Leave Balance Projection\n\nKung mag-file ka ug ' + fmtDays(requestedDays) + ' ka adlaw nga leave:\n\n' +
      lines.map(function(l) { return '- ' + l; }).join('\n');
  }
  if (language === 'tagalog') {
    return 'Leave Balance Projection\n\nKung mag-file ka ng ' + fmtDays(requestedDays) + ' araw na leave:\n\n' +
      lines.map(function(l) { return '- ' + l; }).join('\n');
  }
  return 'Leave Balance Projection\n\nIf you take ' + fmtDays(requestedDays) + ' day(s) of leave:\n\n' +
    lines.map(function(l) { return '- ' + l; }).join('\n');
}

module.exports = {
  buildFastEmployeeAssistantReply,
  requestedLeaveType,
  requestedLocatorType,
};

