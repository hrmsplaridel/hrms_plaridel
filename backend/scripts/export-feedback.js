/**
 * Export thumbs-down DTR assistant feedback so it can be promoted into the
 * golden set (scripts/eval-intents.data.js).
 *
 * IMPORTANT LIMITATION: the dtr_assistant_feedback table does NOT store the
 * original user message — only the assistant's reply (content_preview), the
 * classified intent, and the user's comment. So this script cannot produce
 * ready-to-use golden entries automatically. Instead it prints each thumbs-down
 * row with everything a human needs to reconstruct the user's phrasing and add
 * a [message, expectedIntent, language] entry by hand.
 *
 * Recommended workflow:
 *   1. Run:  npm run eval:export-feedback
 *   2. For each row, recall/look up the user's original phrasing, then append
 *      the correct intent to scripts/eval-intents.data.js.
 *   3. Run:  npm run eval:intents  and watch the accuracy number move.
 *
 * Usage:
 *   node scripts/export-feedback.js              # last 30 thumbs-down
 *   node scripts/export-feedback.js --limit 100
 *   node scripts/export-feedback.js --rating up  # show positive instead
 *   node scripts/export-feedback.js --json
 *
 * Requires DATABASE_URL in the environment (same as the running API).
 */
require('dotenv').config();

const args = process.argv.slice(2);
const limitArg = args.find((a) => a.startsWith('--limit='));
const ratingArg = args.find((a) => a.startsWith('--rating='));
const asJson = args.includes('--json');

const limit = Math.max(1, Math.min(500, parseInt((limitArg || '').split('=')[1] || '30', 10)));
const rating = (ratingArg || '').split('=')[1]?.toLowerCase() === 'up' ? 'up' : 'down';

async function main() {
  const { pool } = require('../src/config/db');
  const res = await pool.query(
    `SELECT
        id,
        intent,
        provider,
        model,
        model_profile,
        content_preview,
        comment,
        created_at
       FROM dtr_assistant_feedback
       WHERE rating = $1
       ORDER BY created_at DESC
       LIMIT $2`,
    [rating, limit]
  );

  if (asJson) {
    console.log(JSON.stringify(res.rows, null, 2));
    await pool.end();
    return;
  }

  console.log('');
  console.log(`DTR Assistant feedback — ${rating} (${res.rows.length} most recent, limit ${limit})`);
  console.log('='.repeat(70));
  if (res.rows.length === 0) {
    console.log('No rows. Either there is no feedback yet or the table is empty.');
    console.log('');
    await pool.end();
    return;
  }

  for (const row of res.rows) {
    console.log(`• ${row.created_at?.toISOString?.() || row.created_at}`);
    console.log(`  classified intent : ${row.intent || '(none)'}`);
    console.log(`  model             : ${row.model || '(none)'}  [${row.provider || '-'} / ${row.model_profile || '-'}]`);
    if (row.comment) {
      console.log(`  user comment      : ${row.comment}`);
    }
    console.log(`  assistant replied :`);
    const preview = String(row.content_preview || '(no preview stored)').slice(0, 400);
    for (const line of preview.split('\n')) {
      console.log(`      ${line}`);
    }
    console.log('');
  }

  console.log('='.repeat(70));
  console.log('Next step: for each row above, reconstruct the original user');
  console.log('phrasing and append an entry to scripts/eval-intents.data.js,');
  console.log('then run:  npm run eval:intents');
  console.log('');

  await pool.end();
}

main().catch((err) => {
  console.error('Failed to export feedback:', err.message || err);
  process.exit(1);
});
