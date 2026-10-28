const { extractDraftFacts } = require('./sentenceDraft');
const { detectAssistantLanguage } = require('./dtrAssistantLanguage');
function requestChoices(context, module) {
  const choices = [];
  if (!module || module === 'leave') {
    for (const row of (context.recent_leave_requests || []).slice(0, 5)) {
      choices.push({ module: 'leave', id: row.id, status: row.status, label: `${row.leave_type || 'Leave'} — ${row.start_date} to ${row.end_date} — ${row.status || 'status unavailable'} — #${String(row.id).slice(-8)}` });
    }
  }
  if (!module || module === 'locator') {
    for (const row of (context.recent_locator_slips || []).slice(0, 5)) {
      choices.push({ module: 'locator', id: row.id, status: row.status, label: `${row.request_type_label || 'Locator'} — ${row.slip_date} — ${row.status || 'status unavailable'}${row.office ? ` — ${row.office}` : ''} — #${String(row.id).slice(-8)}` });
    }
  }
  return choices.filter((choice) => choice.id);
}

function choiceActions(choices) {
  return choices.map((choice) => ({
    id: `select_${choice.module}_${choice.id}`, type: 'select_request',
    label: choice.label, prompt: `Check ${choice.label}`,
    payload: { module: choice.module, id: choice.id },
  }));
}

function isRequestFollowUp(text) {
  if (require('./dtrAssistantQuestion').explicitQuestionIntent(text)) return false;
  if (/\b(?:can|how|pwede|paano|unsaon)\b/.test(text)) return false;
  return /\b(status|approved|approve|accepted|pending|rejected|returned|remarks|reason|review|reviewer|waiting|holding|who|where|kinsa|sino|asa|bakit|ngano)\b/i.test(text) &&
    /\b(it|its|that|this|same|one|request|siya|niya|nito|ito|iyon|ana|kadto|na ba)\b/i.test(text) &&
    !/\b(latest|newest|another|other|balance|credits|dtr|attendance|today|tomorrow|yesterday|\d{4}-\d{2}-\d{2})\b/i.test(text);
}

function formChatContext(form, text, memory) {
  if (!form || form.task !== 'chat') return form;
  const module = form.module || 'leave';
  const type = module === 'locator' ? form.locatorType : form.leaveType;
  const sameField = memory?.formFocus?.module === module && memory.formFocus.type === type && memory.formFocus.key === form.fieldKey && memory.formFocus.bindingId === form.bindingId;
  if (/\b(status|approved|pending|rejected|balance|credits|attendance|time logs|history|requests|who|where is|cancel)\b/i.test(text)) return null;
  const writing = require('./dtrAssistantQuestion').isWritingRequest(text);
  const help = writing || /\b(here|field|put|enter|write|wording|phrase|sentence|draft|example|sample|fill|dito|ilagay|isulat|dinhi|ibutang)\b/i.test(text);
  if (!help && !sameField) return null;
  const draft = writing || /\b(draft|sentence|rewrite|phrase|wording|shorter|formal|suggest.*write)\b/i.test(text) || (!help && sameField);
  return { ...form, task: draft ? 'draft' : 'explain', facts: draft ? extractDraftFacts(text, form.facts) : undefined, language: detectAssistantLanguage(text) };
}

module.exports = { requestChoices, choiceActions, isRequestFollowUp, formChatContext };
