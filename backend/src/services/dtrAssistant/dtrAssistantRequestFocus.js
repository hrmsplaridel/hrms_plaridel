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
  const exampleOnly = require('./dtrAssistantQuestion').isExampleOnlyRequest(text);
  const draft = !exampleOnly && (writing || /\b(draft|sentence|rewrite|phrase|wording|shorter|formal|suggest.*write)\b/i.test(text) || (!help && sameField));
  const restyle=require('./dtrAssistantQuestion').isDraftRestyle(text);
  const candidate=memory?.draftFocus;
  const previous=sameField && candidate?.module===module && candidate.type===type && candidate.fieldKey===form.fieldKey && candidate.bindingId===form.bindingId ? candidate : null;
  const language=/\b(?:tagalog|bisaya|english|filipino|cebuano)\b/i.test(text)?detectAssistantLanguage(text):previous?.language||detectAssistantLanguage(text);
  return { ...form, task: draft ? 'draft' : 'explain', facts: draft ? isDraftFieldReference(text,memory) ? previous?.facts || '' : extractDraftFacts(text, previous?.facts||form.facts) : undefined,
    language,previousDraft:previous?.draft,rewriteInstruction:restyle?text:undefined };
}

function isDraftFieldReference(text, memory) {
  if (!memory?.formFocus && !memory?.draftFocus) return false;
  if (/\b(?:status|approved|pending|rejected|balance|credits|history|cancel)\b/i.test(text) || text.length > 180) return false;
  const normalized = value => String(value || '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
  const label = normalized(memory.formFocus?.fieldLabel || memory.draftFocus?.fieldLabel);
  const value = normalized(text);
  return Boolean(label && (value === label || value.startsWith(`${label} para sa `) || value.startsWith(`${label} for `))) ||
    /^[\s“"']*(?:general\s+)?(?:reason\s*\/\s*remarks|remarks\s*\/\s*reasons|(?:reason|remarks|destination|location|office|activity)\s+field)\b/i.test(text);
}

function isDraftContinuation(text, memory) {
  if (!memory?.draftFocus || !['form_sentence_suggestion','leave_form_field_help','locator_form_field_help'].includes(memory.intent)) return false;
  if (isDraftFieldReference(text, memory)) return true;
  const question = require('./dtrAssistantQuestion');
  const intent = question.explicitQuestionIntent(text);
  if (intent && intent !== 'form_sentence_suggestion') return false;
  if (/\b(?:status|balance|credits|attendance|time logs|history|cancel|approved|pending|rejected)\b/i.test(text) && !question.isWritingRequest(text)) return false;
  if (question.isDraftRestyle(text) || /^(?:(?:in|sa)\s+)?(?:english|bisaya|cebuano|tagalog|filipino)(?:\s+(?:please|lang|palihug))?[.!]?$/i.test(text.trim())) return true;
  return memory.draftFocus.awaitingDetails === true && Boolean(extractDraftFacts(text)) &&
    !/^(?:show|check|what|who|when|why|how|unsa|pila|kinsa|sino|ano|bakit)\b/i.test(text.trim());
}

module.exports = { requestChoices, choiceActions, isRequestFollowUp, formChatContext, isDraftContinuation, isDraftFieldReference };
