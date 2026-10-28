const { normalizeEmployeeDetailSchema } = require('../leaveRequestDetailsPolicy');
const { chatCompletion } = require('../llm/llmClient');
const { draftSentence } = require('./sentenceDraft');
const { detectAssistantLanguage } = require('./dtrAssistantLanguage');

const fields = {
  working_days: ['Number of Working Days Applied For', 'This read-only value is computed from your selected dates, assigned shift, holidays and leave rules. Select the dates first; ask HR if the computed value looks incorrect.', 'Select dates to auto-compute.', 'number'],
  reason: ['General Reason / Remarks', 'Briefly state your actual purpose for requesting leave.', 'I would like to request leave to [your actual purpose].'],
  location_details: ['Location details', 'Enter the actual city, province, or country relevant to your leave.', '[City], [Province or Country]'],
  sick_illness_details: ['Illness details', 'Describe only the symptoms or condition you can accurately report. Do not invent a diagnosis.', '[Your actual symptoms or documented condition]'],
  women_illness_details: ['Illness details', 'Use the accurate condition or procedure described in your supporting document.', '[Condition or procedure from your document]'],
  vawc_case_details: ['Case details', 'Provide only the relevant details you are comfortable sharing and that the form requires.', '[Relevant reference or brief factual explanation]'],
  solo_parent_id_number: ['Solo parent ID number', 'Copy the number exactly from your issued ID.', '[Your issued ID number]'],
  study_purpose_details: ['Study purpose', 'State your actual course, examination, or study activity.', 'I am requesting leave to [actual study activity].'],
};

function invalid(message) {
  return Object.assign(new Error(message), { statusCode: 400 });
}

async function assistLeaveField(pool, form, signal) {
  const module = form?.module || 'leave';
  const typeCode = module === 'locator' ? form?.locatorType : form?.leaveType;
  if (!['leave', 'locator'].includes(module) || typeof typeCode !== 'string' || typeof form?.fieldKey !== 'string' ||
      typeCode.length > 120 || form.fieldKey.length > 100) {
    throw invalid('Select a request type and field first.');
  }
  const result = await pool.query(
    module === 'locator'
      ? `SELECT code AS name, label AS display_name, location_label, location_hint, employee_detail_schema FROM locator_request_types
         WHERE code = $1 AND is_active = true AND COALESCE(filing_access, 'employee') IN ('employee', 'both') LIMIT 1`
      : `SELECT name, display_name, employee_detail_schema FROM leave_types
     WHERE name = $1 AND (is_active IS NULL OR is_active = true)
       AND employee_can_file IS NOT FALSE AND admin_only IS NOT TRUE LIMIT 1`,
    [typeCode]
  );
  const leave = result.rows[0];
  if (!leave) throw invalid(`This ${module} type is no longer available for employee filing.`);
  const locatorFields = {
    reason: ['Remarks / Reasons', 'Explain the actual purpose of your locator request.', 'I am requesting permission to [actual activity or purpose].'],
    office: [leave.location_label || 'Office / Destination', leave.location_hint || 'Enter the actual office or destination.', '[Actual office or destination]'],
  };
  const standard = module === 'leave' ? fields[form.fieldKey] : locatorFields[form.fieldKey];
  const field = standard
    ? { key: form.fieldKey, label: standard[0], type: standard[3] || 'long_text', max_length: 2000,
      required: module === 'locator' || !['reason', 'study_purpose_details'].includes(form.fieldKey) }
    : normalizeEmployeeDetailSchema(leave.employee_detail_schema)
      .find((item) => item.key === form.fieldKey);
  if (!field) throw invalid('This field is no longer configured for the selected request type.');
  const writable = ['text', 'long_text'].includes(field.type) && form.fieldKey !== 'solo_parent_id_number';
  const maximum = field.max_length || (field.type === 'text' ? 255 : 2000);
  const guidance = field.instruction || standard?.[1] || {
    text: `Enter factual information for “${field.label}”. No additional field explanation is configured; ask HR if its meaning is unclear.`,
    long_text: `Briefly describe the facts relevant to “${field.label}”. No additional field explanation is configured; ask HR if its meaning is unclear.`,
    select: `Choose one of the configured options: ${(field.options || []).join(', ')}.`,
    boolean: 'Choose Yes or No based on your actual circumstances.',
    number: 'Enter the actual numeric value requested by this field.',
    date: 'Select the actual date requested by this field.',
  }[field.type];
  const example = field.example || standard?.[2] || {
    text: '[Your factual information]', long_text: '[Your brief factual explanation]',
    select: field.options?.[0], boolean: 'Yes / No', number: '3 (only if this is your actual value)', date: 'YYYY-MM-DD',
  }[field.type];
  const help = `${leave.display_name || leave.name} — ${field.label}\n\n${guidance}\n${field.required ? 'Required field.' : 'Optional field.'}${writable ? ` Maximum ${maximum} characters.` : ''}\n\nExample template (sample only; use your own facts): ${example || 'Use the configured choices.'}${field.sentence_template ? `\n\nSentence template: ${field.sentence_template}` : ''}${field.type === 'select' ? `\nAllowed choices: ${field.options.join(', ')}` : ''}`;
  if (form.task !== 'draft') return { content: help, actions: [] };
  const facts = typeof form.facts === 'string' ? form.facts.trim() : '';
  if (!writable) return { content: help, actions: [] };
  if (!facts) return { content: `${help}\n\nTell me the actual details you want included so I can draft a sentence.`, actions: [] };
  if (facts.length > 2000) throw invalid('Please keep your drafting details under 2,000 characters.');
  const language = form.language || detectAssistantLanguage(facts);
  const generated = await draftSentence({ module, facts, field: field.label,
    instruction: field.instruction || standard?.[1], example: field.example,
    sentenceTemplate: field.sentence_template, maxLength: maximum, language,
    signal, complete: chatCompletion });
  if (generated.question) return { content: generated.question, actions: [] };
  const draft = generated.draft;
  const heading = language === 'bisaya' ? 'Gisugyot nga sentence' : language === 'tagalog' ? 'Mungkahing pangungusap' : 'Suggested wording';
  const review = language === 'bisaya' ? 'I-review ang facts sa dili pa gamiton.' : language === 'tagalog' ? 'Suriin ang mga detalye bago gamitin.' : 'Review the facts before using this suggestion.';
  return {
    content: `${heading}:\n\n${draft}\n\n${review}`,
    actions: [{ id: 'use_field_suggestion', type: 'apply_field_suggestion', label: 'Use this suggestion', payload: { module, ...(module === 'locator' ? { locatorType: leave.name } : { leaveType: leave.name }), fieldKey: field.key, value: draft } }],
  };
}

module.exports = { assistLeaveField };
