const { normalizeAssistantMessageForRules } = require('./dtrAssistantTextNormalizer');

const BISAYA_MARKERS = [
  /\b(unsa|unsay|unsay|ngano|nganu|nganong|pila|naa|wala|akong|nako|nko|imong|nimo|ug|karon|ugma|gahapon|kagahapon|adtong|adtung|atong|niadtong|niadtung|kinsa|asa|unsaon|paunsa|tabangi|tabangan|gusto nako|ana|adto|dili|ning|bulan|bulana|semanaha|adlaw|ka adlaw|kumusta|unsaka|daw|apil|ila|nga|eh)\b/i,
  /\b(bisayaa?|binisayaa?|cebuano)\b/i,
];

const TAGALOG_MARKERS = [
  /\b(ano|bakit|bkit|ilan|ngayon|ako|ko|ba|may|wala|kailangan|knse|pasok|noong|nung|paano|pano|mag file|gusto ko|ilagay|ilalagay|araw|buwan|buwana|semana|kanino|saan|nasaan|puwede|pwede|kamusta|sino)\b/i,
  /\b(tagaloga?|filipino)\b/i,
];

function scorePatterns(text, patterns) {
  let score = 0;
  for (const pattern of patterns) {
    if (pattern.test(text)) score += 1;
  }
  return score;
}

/**
 * Detect reply language from normalized employee text.
 * Returns 'bisaya', 'tagalog', or 'english'.
 */
function detectAssistantLanguage(message) {
  const raw = String(message || '').toLowerCase();
  if (/\bkumusta\b/.test(raw)) return 'bisaya';
  if (/\bkamusta\b/.test(raw)) return 'tagalog';
  if (/\b(unsaka|kinsa ka)\b/.test(raw)) return 'bisaya';
  if (/\b(sino ka|ano ka ba|ano ka)\b/.test(raw)) return 'tagalog';

  const text = normalizeAssistantMessageForRules(message).toLowerCase();
  if (!text.trim()) return 'english';

  if (/\b(reply|answer|explain|sultih|isulti).*\b(bisayaa?|binisayaa?|cebuano)\b/.test(text)) {
    return 'bisaya';
  }
  if (/\b(reply|answer|explain|sagot|sagutin).*\b(tagaloga?|filipino)\b/.test(text)) {
    return 'tagalog';
  }
  if (/\b(bisayaa?|binisayaa?|cebuano)\b/.test(text) && !/\b(tagaloga?|filipino)\b/.test(text)) {
    return 'bisaya';
  }
  if (/\b(tagaloga?|filipino)\b/.test(text) && !/\b(bisayaa?|binisayaa?|cebuano)\b/.test(text)) {
    return 'tagalog';
  }
  if (/\b(english|ingles)\b/.test(text)) return 'english';

  const bisayaScore = scorePatterns(text, BISAYA_MARKERS);
  const tagalogScore = scorePatterns(text, TAGALOG_MARKERS);

  if (bisayaScore > 0 && tagalogScore === 0) return 'bisaya';
  if (tagalogScore > 0 && bisayaScore === 0) return 'tagalog';
  if (bisayaScore > 0 && tagalogScore > 0) {
    return bisayaScore >= tagalogScore ? 'bisaya' : 'tagalog';
  }
  return 'english';
}

module.exports = {
  detectAssistantLanguage,
};
