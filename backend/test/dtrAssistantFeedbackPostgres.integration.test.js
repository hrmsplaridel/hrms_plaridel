'use strict';

const path = require('node:path');
const { randomUUID } = require('node:crypto');
const test = require('node:test');
const assert = require('node:assert/strict');
const { Pool } = require('pg');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const {
  issueDtrAssistantFeedbackToken,
  submitDtrAssistantFeedback,
} = require('../src/services/dtrAssistant/dtrAssistantFeedbackService');

const hasDatabase = Boolean(process.env.DATABASE_URL);
const integrationTest = hasDatabase ? test : test.skip;
const schema = `assistant_feedback_test_${randomUUID().replaceAll('-', '')}`;
const secret = 'postgres-feedback-test-secret-with-sufficient-entropy';
let adminPool;
let testPool;
let previousSecret;
let previousRetention;

test.before(async () => {
  if (!hasDatabase) return;
  previousSecret = process.env.DTR_ASSISTANT_FEEDBACK_SECRET;
  previousRetention = process.env.DTR_ASSISTANT_FEEDBACK_RETENTION_DAYS;
  process.env.DTR_ASSISTANT_FEEDBACK_SECRET = secret;
  process.env.DTR_ASSISTANT_FEEDBACK_RETENTION_DAYS = '30';

  adminPool = new Pool({ connectionString: process.env.DATABASE_URL });
  await adminPool.query(`CREATE SCHEMA ${schema}`);
  await adminPool.query(
    `CREATE TABLE ${schema}.users (
       id uuid PRIMARY KEY
     )`
  );
  await adminPool.query(
    `CREATE TABLE ${schema}.dtr_assistant_feedback (
       id uuid PRIMARY KEY DEFAULT (md5(random()::text || clock_timestamp()::text)::uuid),
       user_id uuid NOT NULL REFERENCES ${schema}.users(id) ON DELETE CASCADE,
       message_id uuid NOT NULL,
       rating text NOT NULL CHECK (rating IN ('up', 'down')),
       intent text,
       provider text,
       model text,
       model_profile text,
       prompt_preview text,
       content_preview text,
       prompt_hash text,
       response_hash text,
       intent_confidence numeric,
       intent_source text,
       comment text,
       created_at timestamptz NOT NULL DEFAULT now(),
       updated_at timestamptz NOT NULL DEFAULT now(),
       UNIQUE (user_id, message_id)
     )`
  );
  testPool = new Pool({
    connectionString: process.env.DATABASE_URL,
    options: `-c search_path=${schema},public`,
  });
});

test.after(async () => {
  if (previousSecret == null) {
    delete process.env.DTR_ASSISTANT_FEEDBACK_SECRET;
  } else {
    process.env.DTR_ASSISTANT_FEEDBACK_SECRET = previousSecret;
  }
  if (previousRetention == null) {
    delete process.env.DTR_ASSISTANT_FEEDBACK_RETENTION_DAYS;
  } else {
    process.env.DTR_ASSISTANT_FEEDBACK_RETENTION_DAYS = previousRetention;
  }
  if (!hasDatabase) return;
  await testPool?.end();
  await adminPool?.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
  await adminPool?.end();
});

integrationTest('real PostgreSQL removes expired feedback and upserts one response', async () => {
  const userId = randomUUID();
  const staleMessageId = randomUUID();
  const messageId = randomUUID();
  await testPool.query('INSERT INTO users (id) VALUES ($1::uuid)', [userId]);
  await testPool.query(
    `INSERT INTO dtr_assistant_feedback (
       user_id, message_id, rating, created_at, updated_at
     ) VALUES (
       $1::uuid, $2::uuid, 'down', now() - interval '31 days',
       now() - interval '31 days'
     )`,
    [userId, staleMessageId]
  );

  const feedbackToken = issueDtrAssistantFeedbackToken({
    userId,
    messageId,
    intent: 'dtr_late_summary',
    provider: 'hrms',
    model: 'trusted-model',
    modelProfile: 'tools_ollama',
    intentConfidence: 0.91,
    intentSource: 'intent_rules',
    prompt: 'Was I late this month?',
    response: 'You were late once.',
  });

  const first = await submitDtrAssistantFeedback(testPool, {
    userId,
    feedbackToken,
    rating: 'down',
    comment: 'The first rating was incorrect.',
  });
  const second = await submitDtrAssistantFeedback(testPool, {
    userId,
    feedbackToken,
    rating: 'up',
    comment: 'Confirmed after checking the DTR.',
  });

  const rows = await testPool.query(
    `SELECT id, message_id, rating, intent, model, comment,
            prompt_preview, content_preview, prompt_hash, response_hash
       FROM dtr_assistant_feedback
      WHERE user_id = $1::uuid
      ORDER BY created_at`,
    [userId]
  );

  assert.equal(rows.rowCount, 1);
  assert.equal(rows.rows[0].message_id, messageId);
  assert.equal(rows.rows[0].rating, 'up');
  assert.equal(rows.rows[0].intent, 'dtr_late_summary');
  assert.equal(rows.rows[0].model, 'trusted-model');
  assert.equal(rows.rows[0].comment, 'Confirmed after checking the DTR.');
  assert.equal(rows.rows[0].prompt_preview, null);
  assert.equal(rows.rows[0].content_preview, null);
  assert.match(rows.rows[0].prompt_hash, /^[a-f0-9]{64}$/);
  assert.match(rows.rows[0].response_hash, /^[a-f0-9]{64}$/);
  assert.equal(first.id, second.id);
});
