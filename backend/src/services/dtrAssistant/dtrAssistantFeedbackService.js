const crypto = require('crypto');

function compactText(value, max = 1000) {
  return String(value || '').replace(/\s+/g, ' ').trim().slice(0, max);
}

function hashText(value) {
  const text = compactText(value, 1000);
  if (!text) return null;
  return crypto.createHash('sha256').update(text).digest('hex');
}

function normalizeConfidence(value) {
  if (value == null || value === '') return null;
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return Math.max(0, Math.min(1, n));
}

function normalizeRating(value) {
  const rating = String(value || '').trim().toLowerCase();
  if (['up', 'correct', 'helpful', 'good', 'positive'].includes(rating)) {
    return 'up';
  }
  if (['down', 'wrong', 'bad', 'negative', 'incorrect'].includes(rating)) {
    return 'down';
  }
  return null;
}

async function submitDtrAssistantFeedback(pool, payload) {
  const rating = normalizeRating(payload.rating);
  if (!rating) {
    const err = new Error('Feedback rating must be up or down.');
    err.statusCode = 400;
    throw err;
  }
  const messageId = String(payload.messageId || '').trim();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(messageId)) {
    const err = new Error('Feedback message id is invalid.');
    err.statusCode = 400;
    throw err;
  }

  const result = await pool.query(
    `INSERT INTO dtr_assistant_feedback (
       user_id,
       message_id,
       rating,
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
       updated_at
     )
     VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, now())
     ON CONFLICT (user_id, message_id)
     DO UPDATE SET
       rating = EXCLUDED.rating,
       intent = EXCLUDED.intent,
       provider = EXCLUDED.provider,
       model = EXCLUDED.model,
       model_profile = EXCLUDED.model_profile,
       prompt_preview = EXCLUDED.prompt_preview,
       prompt_hash = EXCLUDED.prompt_hash,
       intent_confidence = EXCLUDED.intent_confidence,
       intent_source = EXCLUDED.intent_source,
       content_preview = EXCLUDED.content_preview,
       comment = EXCLUDED.comment,
       updated_at = now()
     RETURNING id, rating, intent, intent_confidence, intent_source, created_at, updated_at`,
    [
      payload.userId,
      messageId,
      rating,
      compactText(payload.intent, 120) || null,
      compactText(payload.provider, 80) || null,
      compactText(payload.model, 120) || null,
      compactText(payload.modelProfile, 80) || null,
      compactText(payload.promptPreview, 1000) || null,
      hashText(payload.promptPreview),
      normalizeConfidence(payload.intentConfidence),
      compactText(payload.intentSource, 80) || null,
      compactText(payload.contentPreview, 1000) || null,
      compactText(payload.comment, 500) || null,
    ]
  );

  return result.rows[0];
}

module.exports = {
  submitDtrAssistantFeedback,
  normalizeRating,
  __test: {
    compactText,
    hashText,
    normalizeConfidence,
  },
};
