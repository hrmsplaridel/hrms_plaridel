/**
 * DTR assistant intent evaluation harness.
 *
 * Measures the deterministic routing layer — scoreEmployeeAssistantIntent,
 * which is the rule + fuzzy matcher that runs before any LLM call. Every
 * real "the bot misunderstood me" complaint originates here, so this is the
 * number to track across commits.
 *
 * Usage:
 *   node scripts/eval-intents.js                 # full report
 *   node scripts/eval-intents.js --failures      # only failures
 *   node scripts/eval-intents.js --json          # machine-readable
 *   node scripts/eval-intents.js --filter dtr    # substring filter on intent
 *
 * The golden set lives in ./eval-intents.data.js — add to it from real
 * thumbs-down feedback (see scripts/export-feedback.js).
 */
const { scoreEmployeeAssistantIntent } = require('../src/services/dtrAssistant/dtrAssistantIntentService');
const { GOLDEN } = require('./eval-intents.data');

const args = new Set(process.argv.slice(2));
const filterArg = process.argv.find((a) => a.startsWith('--filter='));
const filter = filterArg ? filterArg.slice('--filter='.length).toLowerCase() : null;
const onlyFailures = args.has('--failures');
const asJson = args.has('--json');

function pct(n, d) {
  if (!d) return '0.0%';
  return `${((n / d) * 100).toFixed(1)}%`;
}

function pad(str, len) {
  const s = str === undefined || str === null ? '' : String(str);
  return s.length >= len ? s : s + ' '.repeat(len - s.length);
}

function run() {
  let cases = GOLDEN;
  if (filter) {
    cases = cases.filter(([, expected]) => (expected || 'null').toLowerCase().includes(filter));
  }

  const results = cases.map(([message, expected, language]) => {
    const scored = scoreEmployeeAssistantIntent(message, null);
    const passed = scored.intent === expected;
    return {
      message,
      expected,
      language: language || 'unknown',
      actual: scored.intent,
      confidence: scored.confidence,
      source: scored.source,
      passed,
    };
  });

  const total = results.length;
  const passed = results.filter((r) => r.passed).length;

  // --- per-intent ------------------------------------------------------------
  const byIntent = new Map();
  for (const r of results) {
    const key = r.expected || '(null / out-of-domain)';
    const entry = byIntent.get(key) || { pass: 0, total: 0, failures: [] };
    entry.total += 1;
    if (r.passed) entry.pass += 1;
    else entry.failures.push(r);
    byIntent.set(key, entry);
  }

  // --- per-source ------------------------------------------------------------
  // Buckets: how did the bot decide, and was it right?
  const bySource = new Map();
  for (const r of results) {
    const entry = bySource.get(r.source) || { pass: 0, total: 0 };
    entry.total += 1;
    if (r.passed) entry.pass += 1;
    bySource.set(r.source, entry);
  }

  // --- per-language ----------------------------------------------------------
  const byLanguage = new Map();
  for (const r of results) {
    const entry = byLanguage.get(r.language) || { pass: 0, total: 0 };
    entry.total += 1;
    if (r.passed) entry.pass += 1;
    byLanguage.set(r.language, entry);
  }

  const failures = results.filter((r) => !r.passed);

  if (asJson) {
    console.log(JSON.stringify({
      total,
      passed,
      accuracy: total ? passed / total : 0,
      byIntent: Object.fromEntries(
        [...byIntent.entries()].map(([k, v]) => [k, { pass: v.pass, total: v.total }])
      ),
      bySource: Object.fromEntries(bySource),
      byLanguage: Object.fromEntries(byLanguage),
      failures,
    }, null, 2));
    return;
  }

  // --- text report -----------------------------------------------------------
  console.log('');
  console.log('DTR Assistant — Intent Evaluation');
  console.log('='.repeat(60));
  console.log(`Overall accuracy:  ${passed}/${total}  ${pct(passed, total)}`);
  console.log('');

  console.log('By language');
  console.log('-'.repeat(60));
  console.log(`${pad('language', 12)} ${pad('pass', 6)} ${pad('total', 6)} accuracy`);
  for (const [lang, v] of [...byLanguage.entries()].sort()) {
    console.log(`${pad(lang, 12)} ${pad(v.pass, 6)} ${pad(v.total, 6)} ${pct(v.pass, v.total)}`);
  }
  console.log('');

  console.log('By decision source  (how the routing layer decided)');
  console.log('-'.repeat(60));
  console.log(`${pad('source', 22)} ${pad('pass', 6)} ${pad('total', 6)} accuracy`);
  for (const [src, v] of [...bySource.entries()].sort((a, b) => b[1].total - a[1].total)) {
    console.log(`${pad(src, 22)} ${pad(v.pass, 6)} ${pad(v.total, 6)} ${pct(v.pass, v.total)}`);
  }
  console.log('');

  console.log('Per intent');
  console.log('-'.repeat(60));
  console.log(`${pad('intent', 30)} ${pad('pass', 6)} ${pad('total', 6)} accuracy`);
  const sortedIntents = [...byIntent.entries()].sort((a, b) => {
    const aRate = a[1].total ? a[1].pass / a[1].total : 1;
    const bRate = b[1].total ? b[1].pass / b[1].total : 1;
    if (aRate !== bRate) return aRate - bRate; // worst first
    return b[1].total - a[1].total;
  });
  for (const [intent, v] of sortedIntents) {
    console.log(`${pad(intent, 30)} ${pad(v.pass, 6)} ${pad(v.total, 6)} ${pct(v.pass, v.total)}`);
  }
  console.log('');

  if (failures.length === 0) {
    console.log('No failures. ✅');
  } else if (!onlyFailures || true) {
    console.log(`Failures (${failures.length})`);
    console.log('-'.repeat(60));
    for (const r of failures) {
      console.log(`  "${r.message}"`);
      console.log(`    expected: ${r.expected} | got: ${r.actual} (conf ${r.confidence.toFixed(2)}, ${r.source})`);
    }
  }
  console.log('');

  process.exitCode = passed === total ? 0 : 1;
}

run();
