const PHRASE_REPLACEMENTS = [
  [/\bmed\s*cert\b/gi, 'medical certificate'],
  [/\bmedical\s*cert\b/gi, 'medical certificate'],
  [/\bna\s+approve\b/gi, 'na-approve'],
  [/\bnaapproved\b/gi, 'na-approve'],
  [/\btime\s*inn\b/gi, 'time in'],
  [/\btime\s*outt\b/gi, 'time out'],
  [/\bno\s+recrod\b/gi, 'no record'],
  [/\bno\s+reocrd\b/gi, 'no record'],
  [/\bpass\s*slip\b/gi, 'pass slip'],
  [/\bpassslip\b/gi, 'pass slip'],
  [/\boffical\s+business\b/gi, 'official business'],
  [/\boficial\s+business\b/gi, 'official business'],
  [/\bfield\s*wrk\b/gi, 'fieldwork'],
  [/\bfield\s*work\b/gi, 'fieldwork'],
  [/\bwork\s+frm\s+home\b/gi, 'work from home'],
  [/\bsick\s+lv\b/gi, 'sick leave'],
  [/\bvacation\s+lv\b/gi, 'vacation leave'],
  [/\bsl\b/gi, 'sick leave'],
  [/\bvl\b/gi, 'vacation leave'],
];

const TOKEN_REPLACEMENTS = {
  absentt: 'absent',
  absents: 'absent',
  absnt: 'absent',
  absnts: 'absent',
  aproval: 'approval',
  aproved: 'approved',
  aprove: 'approve',
  apporved: 'approved',
  atachment: 'attachment',
  attachmnt: 'attachment',
  attachement: 'attachment',
  balace: 'balance',
  balanace: 'balance',
  binisayaa: 'binisaya',
  bisayaa: 'bisaya',
  balnce: 'balance',
  blance: 'balance',
  certficate: 'certificate',
  certifcate: 'certificate',
  compar: 'compare',
  comparision: 'comparison',
  diffrence: 'difference',
  docment: 'document',
  docments: 'documents',
  dtrr: 'dtr',
  dtrs: 'dtr',
  eligble: 'eligible',
  eligibilty: 'eligibility',
  fileded: 'filed',
  filipinoo: 'filipino',
  feild: 'field',
  feildwork: 'fieldwork',
  fieldwrk: 'fieldwork',
  guidline: 'guideline',
  guidlines: 'guidelines',
  histroy: 'history',
  leav: 'leave',
  leaves: 'leave',
  locater: 'locator',
  loactor: 'locator',
  locatorr: 'locator',
  logg: 'log',
  loggs: 'logs',
  miyerkuls: 'miyerkules',
  miyerkulez: 'miyerkules',
  maternityy: 'maternity',
  matirnity: 'maternity',
  maternty: 'maternity',
  maternirty: 'maternity',
  paternitty: 'paternity',
  paternitiy: 'paternity',
  paternnty: 'paternity',
  passslip: 'pass slip',
  qualifed: 'qualified',
  requirment: 'requirement',
  requirments: 'requirements',
  reqirement: 'requirement',
  reqirements: 'requirements',
  reqs: 'requirements',
  sic: 'sick',
  sickk: 'sick',
  suppporting: 'supporting',
  timline: 'timeline',
  tagaloga: 'tagalog',
  tomorow: 'tomorrow',
  undertimee: 'undertime',
  vacaton: 'vacation',
  vacatiion: 'vacation',
  yesterdy: 'yesterday',
  holidy: 'holiday',
  holliday: 'holiday',
  sched: 'schedule',
  sked: 'schedule',
  offical: 'official',
  oficial: 'official',
  pasok: 'pasok',
  busines: 'business',
};

const FUZZY_WORDS = [
  'absence',
  'absent',
  'absents',
  'advance',
  'approved',
  'approval',
  'approve',
  'attendance',
  'attachment',
  'attachments',
  'balance',
  'balances',
  'calamity',
  'certificate',
  'compare',
  'comparison',
  'credits',
  'difference',
  'document',
  'documents',
  'eligible',
  'eligibility',
  'file',
  'filed',
  'filing',
  'guideline',
  'guidelines',
  'history',
  'holiday',
  'leave',
  'log',
  'logs',
  'locator',
  'fieldwork',
  'official',
  'maternity',
  'medical',
  'paternity',
  'pending',
  'qualified',
  'rejected',
  'requirements',
  'requirement',
  'returned',
  'sick',
  'status',
  'supporting',
  'timeline',
  'tomorrow',
  'undertime',
  'vacation',
  'yesterday',
];

function preserveCase(original, replacement) {
  if (!original) return replacement;
  if (original.toUpperCase() === original) return replacement.toUpperCase();
  if (original[0]?.toUpperCase() === original[0]) {
    return `${replacement[0].toUpperCase()}${replacement.slice(1)}`;
  }
  return replacement;
}

function levenshtein(a, b) {
  if (a === b) return 0;
  if (!a) return b.length;
  if (!b) return a.length;

  const previous = Array.from({ length: b.length + 1 }, (_, i) => i);
  const current = Array(b.length + 1).fill(0);

  for (let i = 1; i <= a.length; i += 1) {
    current[0] = i;
    for (let j = 1; j <= b.length; j += 1) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      current[j] = Math.min(
        current[j - 1] + 1,
        previous[j] + 1,
        previous[j - 1] + cost
      );
    }
    for (let j = 0; j <= b.length; j += 1) previous[j] = current[j];
  }

  return previous[b.length];
}

function fuzzyReplacement(token) {
  const normalized = token.toLowerCase();
  if (normalized.length < 4 || /\d/.test(normalized)) return null;

  let best = null;
  let bestDistance = Infinity;
  for (const word of FUZZY_WORDS) {
    if (word[0] !== normalized[0]) continue;
    const distance = levenshtein(normalized, word);
    const threshold = normalized.length <= 5 ? 1 : 2;
    if (distance <= threshold && distance < bestDistance) {
      best = word;
      bestDistance = distance;
    }
  }

  return best;
}

function normalizeAssistantMessageForRules(message) {
  let text = String(message || '');
  for (const [pattern, replacement] of PHRASE_REPLACEMENTS) {
    text = text.replace(pattern, replacement);
  }

  return text.replace(/\b[a-zA-Z][a-zA-Z-]*\b/g, (token) => {
    const lower = token.toLowerCase();
    const replacement = TOKEN_REPLACEMENTS[lower] || fuzzyReplacement(token);
    return replacement ? preserveCase(token, replacement) : token;
  });
}

module.exports = { normalizeAssistantMessageForRules };
