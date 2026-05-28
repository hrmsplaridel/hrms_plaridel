const DEFAULT_PROVIDER = 'ollama';
const DEFAULT_OLLAMA_MODEL = process.env.DOCUTRACKER_OLLAMA_MODEL || 'qwen2.5:7b';
const OLLAMA_BASE_URL = (process.env.OLLAMA_BASE_URL || 'http://127.0.0.1:11434')
  .replace(/\/+$/, '');

function toIso(value) {
  if (!value) return null;
  const dt = value instanceof Date ? value : new Date(value);
  return Number.isNaN(dt.getTime()) ? null : dt.toISOString();
}

function compactText(value, max = 1200) {
  const text = String(value || '').replace(/\s+/g, ' ').trim();
  if (text.length <= max) return text;
  return `${text.slice(0, max - 1)}...`;
}

function cleanSummary(raw) {
  const obj = raw && typeof raw === 'object' ? raw : {};
  const arr = (v) =>
    Array.isArray(v)
      ? v.map((x) => compactText(x, 220)).filter(Boolean).slice(0, 6)
      : [];
  return {
    purpose: compactText(obj.purpose, 500),
    status_summary: compactText(obj.status_summary, 500),
    required_action: compactText(obj.required_action, 500),
    important_dates: arr(obj.important_dates),
    risks_or_missing_info: arr(obj.risks_or_missing_info),
  };
}

function extractJsonObject(content) {
  const text = String(content || '').trim();
  if (!text) throw new Error('AI provider returned an empty response.');
  try {
    return JSON.parse(text);
  } catch (_) {
    const start = text.indexOf('{');
    const end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return JSON.parse(text.slice(start, end + 1));
    }
    throw new Error('AI provider returned invalid summary JSON.');
  }
}

async function getLatestAiSummary(pool, documentId) {
  const result = await pool.query(
    `SELECT s.*, u.full_name AS generated_by_name
     FROM docutracker_ai_summaries s
     LEFT JOIN users u ON u.id = s.generated_by
     WHERE s.document_id = $1
     ORDER BY s.generated_at DESC
     LIMIT 1`,
    [documentId]
  );
  return result.rows[0] || null;
}

async function loadSummaryContext(pool, documentId) {
  const [docResult, historyResult, routingResult] = await Promise.all([
    pool.query(
      `SELECT d.*,
              creator.full_name AS creator_name,
              holder.full_name AS current_holder_name
       FROM docutracker_documents d
       LEFT JOIN users creator ON creator.id = d.created_by
       LEFT JOIN users holder ON holder.id = d.current_holder_id
       WHERE d.id = $1`,
      [documentId]
    ),
    pool.query(
      `SELECT action, actor_name, from_step, to_step, from_status, to_status,
              remarks, is_overdue_log, is_escalation_log, escalation_level,
              created_at
       FROM docutracker_document_history
       WHERE document_id = $1
       ORDER BY created_at DESC
       LIMIT 12`,
      [documentId]
    ),
    pool.query(
      `SELECT step_order, status, deadline_time, reviewed_time, remarks
       FROM docutracker_routing_records
       WHERE document_id = $1
       ORDER BY step_order ASC`,
      [documentId]
    ),
  ]);

  const doc = docResult.rows[0];
  if (!doc) {
    const err = new Error('Document not found');
    err.code = 'NOT_FOUND';
    throw err;
  }

  return {
    document: {
      document_number: doc.document_number,
      document_type: doc.document_type,
      title: doc.title,
      description: compactText(doc.description, 1600),
      source_module: doc.source_module,
      source_title: doc.source_title,
      file_name: doc.file_name,
      creator_name: doc.creator_name,
      current_holder_name: doc.current_holder_name,
      current_step: doc.current_step,
      status: doc.status,
      sent_time: toIso(doc.sent_time),
      deadline_time: toIso(doc.deadline_time),
      reviewed_time: toIso(doc.reviewed_time),
      escalation_level: doc.escalation_level,
      needs_admin_intervention: doc.needs_admin_intervention,
      created_at: toIso(doc.created_at),
      updated_at: toIso(doc.updated_at),
    },
    recent_history: historyResult.rows.map((h) => ({
      action: h.action,
      actor_name: h.actor_name,
      from_step: h.from_step,
      to_step: h.to_step,
      from_status: h.from_status,
      to_status: h.to_status,
      remarks: compactText(h.remarks, 500),
      is_overdue_log: h.is_overdue_log,
      is_escalation_log: h.is_escalation_log,
      escalation_level: h.escalation_level,
      created_at: toIso(h.created_at),
    })),
    routing: routingResult.rows.map((r) => ({
      step_order: r.step_order,
      status: r.status,
      deadline_time: toIso(r.deadline_time),
      reviewed_time: toIso(r.reviewed_time),
      remarks: compactText(r.remarks, 500),
    })),
  };
}

async function callOllamaForSummary(context) {
  let response;
  try {
    response = await fetch(`${OLLAMA_BASE_URL}/api/chat`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: DEFAULT_OLLAMA_MODEL,
        stream: false,
        format: 'json',
        options: {
          temperature: 0.2,
        },
        messages: [
          {
            role: 'system',
            content:
              'You summarize HR document workflow records. Return only JSON with keys: purpose, status_summary, required_action, important_dates, risks_or_missing_info. Do not invent facts not present in the input.',
          },
          {
            role: 'user',
            content: JSON.stringify(context),
          },
        ],
      }),
    });
  } catch (cause) {
    const err = new Error(
      'Local AI is not available. Start Ollama and pull the configured model.'
    );
    err.code = 'AI_LOCAL_UNAVAILABLE';
    err.cause = cause;
    throw err;
  }

  if (!response.ok) {
    const body = await response.text().catch(() => '');
    const err = new Error(`Local AI provider failed (${response.status}).`);
    err.code = 'AI_PROVIDER_FAILED';
    err.status = response.status;
    err.providerCode = response.status === 404 ? 'model_not_found' : null;
    err.providerMessage =
      response.status === 404
        ? `Ollama model '${DEFAULT_OLLAMA_MODEL}' is not available. Run: ollama pull ${DEFAULT_OLLAMA_MODEL}`
        : compactText(body, 500);
    err.detail = body.slice(0, 500);
    throw err;
  }

  const data = await response.json();
  const content = data?.message?.content;
  return cleanSummary(extractJsonObject(content));
}

async function generateAiSummary(pool, { documentId, userId }) {
  const context = await loadSummaryContext(pool, documentId);
  const summary = await callOllamaForSummary(context);
  const result = await pool.query(
    `INSERT INTO docutracker_ai_summaries
       (document_id, summary_json, generated_by, provider, model)
     VALUES ($1, $2::jsonb, $3, $4, $5)
     RETURNING *`,
    [documentId, JSON.stringify(summary), userId || null, DEFAULT_PROVIDER, DEFAULT_OLLAMA_MODEL]
  );
  return result.rows[0];
}

module.exports = {
  generateAiSummary,
  getLatestAiSummary,
};
