const crypto = require('crypto');
const jwt = require('jsonwebtoken');

const FEEDBACK_TOKEN_ISSUER = 'hrms-plaridel';
const FEEDBACK_TOKEN_AUDIENCE = 'dtr-assistant-feedback';
const FEEDBACK_TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60;
const DEFAULT_FEEDBACK_RETENTION_DAYS = 180;

function compactText(value, max = 1000) {
  return String(value || '').replace(/\s+/g, ' ').trim().slice(0, max);
}

function hashText(value) {
  const text = compactText(value, 4000);
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

function feedbackSecret(options = {}) {
  const secret = String(
    options.secret ||
      process.env.DTR_ASSISTANT_FEEDBACK_SECRET ||
      process.env.JWT_SECRET ||
      ''
  ).trim();
  if (!secret) {
    const err = new Error('DTR assistant feedback signing is not configured.');
    err.statusCode = 503;
    err.code = 'DTR_ASSISTANT_FEEDBACK_NOT_CONFIGURED';
    throw err;
  }
  return secret;
}

function feedbackRetentionDays(env = process.env) {
  const parsed = Number.parseInt(
    env.DTR_ASSISTANT_FEEDBACK_RETENTION_DAYS || '',
    10
  );
  if (!Number.isFinite(parsed)) return DEFAULT_FEEDBACK_RETENTION_DAYS;
  return Math.max(30, Math.min(3650, parsed));
}

function issueDtrAssistantFeedbackToken(payload, options = {}) {
  const userId = String(payload.userId || '').trim();
  const messageId = String(payload.messageId || '').trim();
  if (!userId || !messageId) {
    const err = new Error('Feedback token identity is incomplete.');
    err.statusCode = 500;
    throw err;
  }

  return jwt.sign(
    {
      version: 1,
      intent: compactText(payload.intent, 120) || null,
      provider: compactText(payload.provider, 80) || null,
      model: compactText(payload.model, 120) || null,
      modelProfile: compactText(payload.modelProfile, 80) || null,
      intentConfidence: normalizeConfidence(payload.intentConfidence),
      intentSource: compactText(payload.intentSource, 80) || null,
      promptHash: hashText(payload.prompt),
      responseHash: hashText(payload.response),
    },
    feedbackSecret(options),
    {
      algorithm: 'HS256',
      audience: FEEDBACK_TOKEN_AUDIENCE,
      issuer: FEEDBACK_TOKEN_ISSUER,
      subject: userId,
      jwtid: messageId,
      expiresIn:
        options.expiresInSeconds || FEEDBACK_TOKEN_TTL_SECONDS,
    }
  );
}

function feedbackTokenError(message, statusCode, code) {
  const err = new Error(message);
  err.statusCode = statusCode;
  err.code = code;
  return err;
}

function verifyDtrAssistantFeedbackToken(token, userId, options = {}) {
  const value = String(token || '').trim();
  if (!value || value.length > 4096) {
    throw feedbackTokenError(
      'Feedback token is required.',
      400,
      'DTR_ASSISTANT_FEEDBACK_TOKEN_INVALID'
    );
  }

  let claims;
  try {
    claims = jwt.verify(value, feedbackSecret(options), {
      algorithms: ['HS256'],
      audience: FEEDBACK_TOKEN_AUDIENCE,
      issuer: FEEDBACK_TOKEN_ISSUER,
      clockTimestamp: options.clockTimestamp,
    });
  } catch (error) {
    if (error?.name === 'TokenExpiredError') {
      throw feedbackTokenError(
        'Feedback token has expired.',
        410,
        'DTR_ASSISTANT_FEEDBACK_TOKEN_EXPIRED'
      );
    }
    throw feedbackTokenError(
      'Feedback token is invalid.',
      400,
      'DTR_ASSISTANT_FEEDBACK_TOKEN_INVALID'
    );
  }

  if (String(claims.sub || '') !== String(userId || '').trim()) {
    throw feedbackTokenError(
      'Feedback token belongs to another employee.',
      403,
      'DTR_ASSISTANT_FEEDBACK_TOKEN_FORBIDDEN'
    );
  }
  const messageId = String(claims.jti || '').trim();
  if (
    claims.version !== 1 ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      messageId
    )
  ) {
    throw feedbackTokenError(
      'Feedback token is invalid.',
      400,
      'DTR_ASSISTANT_FEEDBACK_TOKEN_INVALID'
    );
  }

  return {
    messageId,
    intent: compactText(claims.intent, 120) || null,
    provider: compactText(claims.provider, 80) || null,
    model: compactText(claims.model, 120) || null,
    modelProfile: compactText(claims.modelProfile, 80) || null,
    promptHash: compactText(claims.promptHash, 64) || null,
    responseHash: compactText(claims.responseHash, 64) || null,
    intentConfidence: normalizeConfidence(claims.intentConfidence),
    intentSource: compactText(claims.intentSource, 80) || null,
  };
}

async function submitDtrAssistantFeedback(pool, payload) {
  const rating = normalizeRating(payload.rating);
  if (!rating) {
    const err = new Error('Feedback rating must be up or down.');
    err.statusCode = 400;
    throw err;
  }
  const trusted = verifyDtrAssistantFeedbackToken(
    payload.feedbackToken,
    payload.userId
  );

  await pool.query(
    `DELETE FROM dtr_assistant_feedback
     WHERE created_at < now() - ($1::int * interval '1 day')`,
    [feedbackRetentionDays()]
  );

  const result = await pool.query(
    `INSERT INTO dtr_assistant_feedback (
       user_id,
       message_id,
       rating,
       intent,
       provider,
       model,
       model_profile,
       prompt_hash,
       response_hash,
       intent_confidence,
       intent_source,
       comment,
       updated_at
     )
     VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, now())
     ON CONFLICT (user_id, message_id)
     DO UPDATE SET
       rating = EXCLUDED.rating,
       intent = EXCLUDED.intent,
       provider = EXCLUDED.provider,
       model = EXCLUDED.model,
       model_profile = EXCLUDED.model_profile,
       prompt_preview = NULL,
       prompt_hash = EXCLUDED.prompt_hash,
       response_hash = EXCLUDED.response_hash,
       intent_confidence = EXCLUDED.intent_confidence,
       intent_source = EXCLUDED.intent_source,
       content_preview = NULL,
       comment = EXCLUDED.comment,
       updated_at = now()
     RETURNING id, rating, created_at, updated_at`,
    [
      payload.userId,
      trusted.messageId,
      rating,
      trusted.intent,
      trusted.provider,
      trusted.model,
      trusted.modelProfile,
      trusted.promptHash,
      trusted.responseHash,
      trusted.intentConfidence,
      trusted.intentSource,
      compactText(payload.comment, 500) || null,
    ]
  );

  return result.rows[0];
}

module.exports = {
  issueDtrAssistantFeedbackToken,
  normalizeRating,
  submitDtrAssistantFeedback,
  verifyDtrAssistantFeedbackToken,
  __test: {
    compactText,
    feedbackRetentionDays,
    hashText,
    normalizeConfidence,
  },
};
