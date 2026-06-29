const { normalizeAssistantMessageForRules } = require('./dtrAssistantTextNormalizer');

function lower(value) {
  return String(value || '').toLowerCase();
}

function tokenize(value) {
  return lower(value)
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .split(/\s+/)
    .filter((token) => token.length > 1);
}

function bigrams(tokens) {
  const result = [];
  for (let i = 0; i < tokens.length - 1; i += 1) {
    result.push(`${tokens[i]} ${tokens[i + 1]}`);
  }
  return result;
}

// Concept bags: paraphrases and mixed-language synonyms grouped by intent.
const SEMANTIC_INTENT_SIGNALS = {
  leave_balance: [
    'leave balance',
    'sick leave credits',
    'vacation credits',
    'available credits',
    'remaining credits',
    'paid time off',
    'paid sick time',
    'sick time left',
    'still have sick',
    'have sick leave',
    'leave credits',
    'pila credits',
    'pila balance',
    'natira leave',
    'nabilin leave',
    'may credits',
    'naa credits',
    'enough credits',
    'sapat credits',
    'how many leave days',
    'remaining leave days',
  ],
  leave_availability_check: [
    'can i file leave',
    'pwede mag file leave',
    'allowed to file leave',
    'file sick leave tomorrow',
    'take leave tomorrow',
    'mag leave ugma',
    'puwede leave',
  ],
  dtr_missing_logs: [
    'missing logs',
    'incomplete logs',
    'missing time in',
    'missing pm out',
    'kulang logs',
    'wala logs',
    'no time in',
    'forgot to log',
  ],
  dtr_late_summary: [
    'late summary',
    'how many late',
    'pila late',
    'late count',
    'tardy count',
    'late this week',
  ],
  dtr_absent_summary: [
    'how many absent',
    'absence count',
    'pila absent',
    'absences this month',
    'walay pasok',
  ],
  locator_status: [
    'locator status',
    'locator slip status',
    'approved locator',
    'pending locator',
    'na approve locator',
    'asa na locator',
  ],
  locator_availability_check: [
    'can i file wfh',
    'pwede wfh',
    'file locator tomorrow',
    'can file pass slip',
    'allowed locator',
  ],
  leave_guided_filing: [
    'help file leave',
    'guide leave filing',
    'tabang leave',
    'how to file leave',
    'paano mag file leave',
  ],
  locator_guided_filing: [
    'help file locator',
    'guide wfh filing',
    'tabang locator',
    'help file wfh',
  ],
  dtr_correction_guidance: [
    'fix dtr',
    'correct dtr',
    'dtr correction',
    'ayusin dtr',
    'missing log fix',
    'how to correct attendance',
  ],
  latest_leave_request: [
    'latest leave',
    'recent leave request',
    'last leave filed',
    'leave request status',
  ],
  dtr_hours_summary: [
    'total hours worked',
    'hours this month',
    'pila oras',
    'working hours',
    'hours rendered',
  ],
};

// Weighted single-token concepts for paraphrases that do not match phrase bags exactly.
const SEMANTIC_INTENT_CONCEPTS = {
  leave_balance: {
    leave: 0.18,
    balance: 0.28,
    credits: 0.28,
    remaining: 0.22,
    available: 0.2,
    natira: 0.24,
    nabilin: 0.24,
    pila: 0.16,
    sick: 0.14,
    vacation: 0.14,
    time: 0.1,
    paid: 0.1,
    enough: 0.16,
    sapat: 0.16,
    use: 0.08,
    have: 0.08,
    still: 0.06,
  },
  leave_availability_check: {
    file: 0.18,
    leave: 0.2,
    pwede: 0.2,
    puwede: 0.2,
    allowed: 0.18,
    tomorrow: 0.12,
    ugma: 0.12,
    take: 0.14,
    mag: 0.1,
  },
  dtr_missing_logs: {
    missing: 0.24,
    logs: 0.24,
    incomplete: 0.2,
    kulang: 0.2,
    wala: 0.16,
    forgot: 0.16,
    time: 0.1,
  },
  dtr_late_summary: {
    late: 0.28,
    tardy: 0.24,
    pila: 0.14,
  },
  dtr_absent_summary: {
    absent: 0.28,
    absence: 0.24,
    absences: 0.24,
    walay: 0.16,
    pasok: 0.16,
  },
  locator_status: {
    locator: 0.22,
    status: 0.16,
    approved: 0.18,
    pending: 0.16,
    slip: 0.12,
  },
  locator_availability_check: {
    wfh: 0.24,
    locator: 0.2,
    file: 0.16,
    pwede: 0.18,
    pass: 0.14,
    tomorrow: 0.1,
  },
  leave_guided_filing: {
    help: 0.16,
    guide: 0.18,
    file: 0.16,
    leave: 0.18,
    tabang: 0.2,
    paano: 0.16,
  },
  locator_guided_filing: {
    help: 0.16,
    guide: 0.18,
    locator: 0.2,
    wfh: 0.2,
    tabang: 0.2,
  },
  dtr_correction_guidance: {
    fix: 0.18,
    correct: 0.18,
    correction: 0.2,
    dtr: 0.16,
    ayusin: 0.2,
    missing: 0.12,
  },
  latest_leave_request: {
    latest: 0.2,
    recent: 0.2,
    last: 0.16,
    leave: 0.18,
    request: 0.14,
  },
  dtr_hours_summary: {
    hours: 0.24,
    oras: 0.2,
    worked: 0.16,
    rendered: 0.16,
    total: 0.12,
  },
};

function jaccard(a, b) {
  if (a.size === 0 || b.size === 0) return 0;
  let intersection = 0;
  for (const item of a) {
    if (b.has(item)) intersection += 1;
  }
  const union = a.size + b.size - intersection;
  return union === 0 ? 0 : intersection / union;
}

function partialPhraseOverlap(queryTokens, phraseTokens) {
  if (phraseTokens.length === 0) return 0;
  const querySet = new Set(queryTokens);
  let hits = 0;
  for (const token of phraseTokens) {
    if (querySet.has(token)) hits += 1;
  }
  return hits / phraseTokens.length;
}

function semanticPhraseScore(queryTokens, queryBigrams, phrase) {
  const phraseTokens = tokenize(phrase);
  const phraseBigrams = bigrams(phraseTokens);
  const tokenSet = new Set(queryTokens);
  const phraseTokenSet = new Set(phraseTokens);
  const tokenScore = jaccard(tokenSet, phraseTokenSet);

  const queryBiSet = new Set(queryBigrams);
  const phraseBiSet = new Set(phraseBigrams);
  const bigramScore = phraseBigrams.length > 0 ? jaccard(queryBiSet, phraseBiSet) : 0;

  const queryText = lower(queryTokens.join(' '));
  const phraseText = lower(phraseTokens.join(' '));
  const containsPhrase = phraseText.length > 0 && queryText.includes(phraseText);
  const containsBoost = containsPhrase ? 0.25 : 0;
  const partialBoost = partialPhraseOverlap(queryTokens, phraseTokens) * 0.22;

  return Math.min(
    1,
    tokenScore * 0.45 + bigramScore * 0.3 + containsBoost + partialBoost
  );
}

function conceptScore(queryTokens, intent) {
  const concepts = SEMANTIC_INTENT_CONCEPTS[intent];
  if (!concepts) return 0;
  const querySet = new Set(queryTokens);
  let score = 0;
  let hits = 0;
  for (const [token, weight] of Object.entries(concepts)) {
    if (querySet.has(token)) {
      score += weight;
      hits += 1;
    }
  }
  if (hits < 2) return score * 0.55;
  return Math.min(1, score);
}

function scoreSemanticIntents(message) {
  const normalized = normalizeAssistantMessageForRules(message);
  const queryTokens = tokenize(normalized);
  const queryBigrams = bigrams(queryTokens);
  const scores = Object.entries(SEMANTIC_INTENT_SIGNALS)
    .map(([intent, phrases]) => {
      const phraseScores = phrases.map((phrase) =>
        semanticPhraseScore(queryTokens, queryBigrams, phrase)
      );
      const bestPhrase = Math.max(0, ...phraseScores);
      const secondPhrase = phraseScores.slice().sort((a, b) => b - a)[1] || 0;
      const concepts = conceptScore(queryTokens, intent);
      const blended = Math.min(
        1,
        Math.max(bestPhrase, concepts * 0.92) * 0.78 + secondPhrase * 0.12 + concepts * 0.1
      );
      return {
        intent,
        confidence: blended,
        source: 'semantic',
      };
    })
    .filter((item) => item.confidence >= 0.22)
    .sort((a, b) => b.confidence - a.confidence);

  return {
    normalizedText: normalized,
    top: scores[0] || null,
    runnerUp: scores[1] || null,
    scores: scores.slice(0, 5),
  };
}

module.exports = {
  SEMANTIC_INTENT_SIGNALS,
  SEMANTIC_INTENT_CONCEPTS,
  scoreSemanticIntents,
};
