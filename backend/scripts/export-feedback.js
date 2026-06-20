/**
 * Export thumbs-down DTR assistant feedback so it can be promoted into the
 * golden set (scripts/eval-intents.data.js).
 *
 * New feedback rows store prompt_preview and prompt_hash. Older rows may only
 * have the assistant's reply (content_preview), the classified intent, and the
 * user's comment, so those still need a human to reconstruct the prompt.
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
        prompt_preview,
        prompt_hash,
        intent_confidence,
        intent_source,
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
    console.log(`  decision          : ${row.intent_source || '(unknown)'}${row.intent_confidence == null ? '' : ` @ ${Number(row.intent_confidence).toFixed(2)}`}`);
    console.log(`  model             : ${row.model || '(none)'}  [${row.provider || '-'} / ${row.model_profile || '-'}]`);
    if (row.prompt_preview) {
      console.log(`  user asked        :`);
      const prompt = String(row.prompt_preview || '').slice(0, 400);
      for (const line of prompt.split('\n')) {
        console.log(`      ${line}`);
      }
    } else if (row.prompt_hash) {
      console.log(`  user prompt hash  : ${row.prompt_hash}`);
    }
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
  console.log('Next step: append failed user prompts to scripts/eval-intents.data.js');
  console.log('with the correct expected intent, then run:');
  console.log('  npm run eval:intents');
  console.log('');

  await pool.end();
}

main().catch((err) => {
  console.error('Failed to export feedback:', err.message || err);
  process.exit(1);
});
