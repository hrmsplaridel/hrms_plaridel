const PHRASE_REPLACEMENTS = [
  [/\bwat\b/gi, 'what'],
  [/\bpano\b/gi, 'paano'],
  [/\bmaayos\b/gi, 'ayusin'],
  [/\bmg\s+file\b/gi, 'mag file'],
  [/\bpg\s+(?=file|fill|correct|korek)/gi, 'pag '],
  [/\bmed\s*cert\b/gi, 'medical certificate'],
  [/\bmedical\s*cert\b/gi, 'medical certificate'],
  [/\bna\s+approve\b/gi, 'na-approve'],
  [/\bnaapproved\b/gi, 'na-approve'],
  [/\btime\s*inn\b/gi, 'time in'],
  [/\btime\s*outt\b/gi, 'time out'],
  [/\bpm\s+ot\b/gi, 'pm out'],
  [/\bno\s+recrod\b/gi, 'no record'],
  [/\bno\s+reocrd\b/gi, 'no record'],
  [/\bpass\s*slip\b/gi, 'pass slip'],
  [/\bpassslip\b/gi, 'pass slip'],
  [/\boffical\s+business\b/gi, 'official business'],
  [/\boficial\s+business\b/gi, 'official business'],
  [/\boffcial\s+business\b/gi, 'official business'],
  [/\bsik\s+leev\b/gi, 'sick leave'],
  [/\bsik\s+leave\b/gi, 'sick leave'],
  [/\bvacaton\s+leave\b/gi, 'vacation leave'],
  [/\bunsaon\s+nko\b/gi, 'unsaon nako'],
  [/\bunsaon\s+ko\b/gi, 'unsaon nako'],
  [/\bpg\s+file\b/gi, 'pag file'],
  [/\bkarong\s+bulna\b/gi, 'karong bulan'],
  [/\bthis\s+mnth\b/gi, 'this month'],
  [/\bwhats\s+my\b/gi, 'what is my'],
  [/\bwats\s+my\b/gi, 'what is my'],
  [/\bhow\s+many\s+abssents\b/gi, 'how many absents'],
  [/\bhow\s+many\s+absnts\b/gi, 'how many absents'],
  [/\bstaus\s+sa\b/gi, 'status sa'],
  [/\bpwede\s+ko\s+mag\s+lokator\b/gi, 'pwede ko mag locator'],
  [/\bunsaon\s+pag\s+file\s+loacator\b/gi, 'unsaon pag file locator'],
  [/\bunsaon\s+pag\s+file\s+locator\b/gi, 'unsaon pag file locator'],
  [/\bpila\s+accpeted\b/gi, 'pila accepted'],
  [/\bgive\s+sampel\b/gi, 'give sample'],
  [/\bresn\s+feild\b/gi, 'reason field'],
  [/\breason\s+feild\b/gi, 'reason field'],
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
  accpeted: 'accepted',
  acepted: 'accepted',
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
  explan: 'explain',
  explane: 'explain',
  fileded: 'filed',
  fild: 'field',
  fiels: 'fields',
  fieldd: 'field',
  filipinoo: 'filipino',
  feild: 'field',
  feildwork: 'fieldwork',
  fieldwrk: 'fieldwork',
  guidline: 'guideline',
  guidlines: 'guidelines',
  histroy: 'history',
  leav: 'leave',
  leev: 'leave',
  leaves: 'leave',
  locater: 'locator',
  loactor: 'locator',
  lokator: 'locator',
  loacator: 'locator',
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
  sik: 'sick',
  sickk: 'sick',
  reasn: 'reason',
  reazon: 'reason',
  remaks: 'remarks',
  remarkss: 'remarks',
  sampel: 'sample',
  smaple: 'sample',
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
  bakt: 'bakit',
  baket: 'bakit',
  bkit: 'bakit',
  cn: 'can',
  corect: 'correct',
  curent: 'current',
  gahapn: 'gahapon',
  kahapn: 'kahapon',
  korek: 'correct',
  knse: 'kailangan',
  lte: 'late',
  mising: 'missing',
  missng: 'missing',
  mnth: 'month',
  nko: 'nako',
  pno: 'paano',
  shft: 'shift',
  staus: 'status',
  statos: 'status',
  tipes: 'types',
  wek: 'week',
  nganong: 'ngano',
  nganu: 'ngano',
  unsay: 'unsa',
  unsaoy: 'unsa',
  butng: 'butang',
  ibtnag: 'ibutang',
  ibutng: 'ibutang',
  ilagay: 'ilagay',
  ilalagy: 'ilalagay',
  bulna: 'bulan',
  semanha: 'semana',
  semanaa: 'semana',
  komusta: 'kumusta',
  kumustaa: 'kumusta',
  hwat: 'what',
  whos: 'who',
  wat: 'what',
  wats: 'what',
  abssents: 'absents',
  absnts: 'absents',
  accpeted: 'accepted',
  accpted: 'accepted',
  feild: 'field',
  resn: 'reason',
  sampel: 'sample',
  smaple: 'sample',
  explan: 'explain',
  matirnity: 'maternity',
  lokator: 'locator',
  loacator: 'locator',
  balnce: 'balance',
  leev: 'leave',
  sik: 'sick',
  fil: 'file',
  pasok: 'pasok',
  busines: 'business',
  offcial: 'official',
  oficial: 'official',
  offical: 'official',
  attachmnt: 'attachment',
  attachement: 'attachment',
  requirment: 'requirement',
  requirments: 'requirements',
  guidline: 'guideline',
  guidlines: 'guidelines',
  tomorow: 'tomorrow',
  yesterdy: 'yesterday',
  vacaton: 'vacation',
  absentt: 'absent',
  absnt: 'absent',
  absnts: 'absent',
};

const FUZZY_WORDS = [
  'absence',
  'absent',
  'absents',
  'advance',
  'accepted',
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
  'example',
  'field',
  'fields',
  'file',
  'filed',
  'fill',
  'filing',
  'guideline',
  'guidelines',
  'history',
  'holiday',
  'leave',
  'location',
  'log',
  'logs',
  'locator',
  'fieldwork',
  'official',
  'maternity',
  'medical',
  'month',
  'paternity',
  'pending',
  'qualified',
  'reason',
  'remarks',
  'rejected',
  'requirements',
  'requirement',
  'returned',
  'sick',
  'sample',
  'status',
  'shift',
  'supporting',
  'timeline',
  'tomorrow',
  'undertime',
  'vacation',
  'yesterday',
  'missing',
  'explain',
  'correct',
  'month',
  'absent',
  'absents',
  'pm',
  'am',
];

const SKIP_FUZZY = new Set([
  'ngayon',
  'karon',
  'ngano',
  'nganu',
  'unsa',
  'unsay',
  'unsaon',
  'bakit',
  'paano',
  'pano',
  'ugma',
  'gahapon',
  'kailangan',
  'nako',
  'akong',
  'butang',
  'ibutang',
  'maayos',
  'ayusin',
]);

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
  if (normalized.length < 4 || /\d/.test(normalized) || SKIP_FUZZY.has(normalized)) {
    return null;
  }

  let best = null;
  let bestDistance = Infinity;
  for (const word of FUZZY_WORDS) {
    const distance = levenshtein(normalized, word);
    const threshold = normalized.length <= 5 ? 1 : 2;
    const firstCharOk =
      word[0] === normalized[0] || (distance === 1 && normalized.length >= 5);
    if (!firstCharOk) continue;
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
