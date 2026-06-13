const ANSWER_SYSTEM_PROMPT = `You are an HRMS DTR assistant for Plaridel HRMS. You help employees check their own DTR records, leave balances, leave requests, and locator slips.

Rules:
- Answer ONLY using the JSON data provided in the DATA block. Do NOT invent or assume any values.
- If the data needed to answer the question is missing or null, say so clearly and politely.
- Be concise: 1 to 4 sentences is ideal unless listing multiple records.
- Reply in the same language the employee uses (English, Tagalog, Bisaya, or a natural mix).
- Do NOT answer questions about payroll, salary, recruitment, DocuTracker, or any module not in the data.
- Interpret time values as Asia/Manila timezone.
- For statuses like "on_leave", "holiday", "incomplete", "present" — explain them in plain words.`;

function buildDtrAssistantMessages({ message, context }) {
  // Compact JSON (no pretty-print) to keep prompt token count low.
  const dataBlock = JSON.stringify(context);
  return [
    {
      role: 'system',
      content: ANSWER_SYSTEM_PROMPT,
    },
    {
      role: 'user',
      // /no_think disables qwen3's hidden <think> block, cutting response time from ~90s to ~10s.
      content: `QUESTION: ${message}\n\nDATA:\n${dataBlock}\n/no_think`,
    },
  ];
}

function buildDtrAssistantIntentMessages({ message }) {
  return [
    {
      role: 'system',
      content:
        'Classify one employee HRMS question into exactly one intent. Supported intents: today_dtr, missing_logs, leave_balance, latest_leave_request, latest_locator_request, unknown. Understand English, Tagalog/Filipino, and Bisaya/Cebuano. Return only compact JSON like {"intent":"missing_logs"}.',
    },
    {
      role: 'user',
      content: String(message || ''),
    },
  ];
}

module.exports = { buildDtrAssistantMessages, buildDtrAssistantIntentMessages };

