// Specific question semantics shared by routing, memory and multi-intent handling.
// These are question classes, not responses tied to individual audit sentences.
const locatorTopic = /\b(locator|pass[ -]?slip|wfh|work from home|official business|travel order)\b/i;
const leaveTopic = /\b(leave|credits?|balance|maternity|paternity|sick|vacation)\b/i;

function isWritingRequest(text) {
  if (/\b(?:sample|sampel|example)\s+input\b/i.test(text)) return false;
  if (/\b(?:what|which|unsa\w*|ano\w*)\b.*\b(?:write|put|enter|ibutang|ilalagay|isulat)\b/i.test(text) &&
      !/\b(?:suggest|generate|draft|make|himo\w*|gawan)\b/i.test(text)) return false;
  return /\b(?:sentence|pangungusap|wording|phrase|draft|reason|rason)\b/i.test(text) &&
    /\b(?:suggest|generate|give|make|write|draft|rewrite|himo\w*|gawan|gumawa|help|formal|shorter|mubo|translate)\b/i.test(text) ||
    isDraftRestyle(text);
}
function isDraftRestyle(text) {
  return /\b(?:shorter|more formal|mubo|same meaning|rewrite that|translate that|same reason|that sentence)\b/i.test(text) ||
    /\b(?:rewrite|translate)\b.*\b(?:bisaya|tagalog|english)\b/i.test(text) ||
    /^(?:please\s+)?(?:write|answer) (?:that|it|the sentence)\b.*\b(?:bisaya|tagalog|english)\b/i.test(text);
}

// Negated topics must not become lookup targets or independent clauses.
function currentQuestion(text) {
  if (isWritingRequest(String(text || ''))) return String(text || '').trim();
  return String(text || '').replace(/\b(?:not|rather than|instead of)\s+(?:leave\s+or\s+locator|locator\s+or\s+leave|leave|locator|attendance|dtr)\b/gi, '')
    .replace(/^.*\b(?:ignore that topic[.,]?|i mean)\s*/i, '').trim();
}

function locatorPolicyKind(text) {
  if (!locatorTopic.test(text)) return null;
  if (/\b(?:slots?|markers?|punches|am in|am out|pm in|pm out)\b/i.test(text) && /\b(?:can|only|leaving|unchanged)\b/i.test(text)) return 'slots';
  if (/\b(?:rejected|cancelled|canceled|gi-cancel|revoked)\b/i.test(text) && /\b(?:cover\w*|credit\w*|dtr|attendance|slots?)\b/i.test(text)) return 'inactive';
  if (/\bapproved\b.*\bleave\b.*\b(?:same date|which|apply)\b/i.test(text)) return 'conflict';
  if (/\bholiday\b/i.test(text) && /\b(?:file|duty|locator|pwede)\b/i.test(text)) return 'rest_day';
  if (/\b(?:absent|biometric|punch)\b/i.test(text) && /\bapproved\b/i.test(text)) return 'coverage';
  if (/\b(?:credits?|balance)\b/i.test(text) && /\b(?:deduct\w*|need|required|use|bawas|mobawas|kinahanglan|kailangan)\b/i.test(text)) return 'credits';
  if (/\bpending\b/i.test(text) && /\b(?:cover\w*|sakop|dtr|attendance)\b/i.test(text)) return 'pending';
  if (/\b(?:already approved|approved paper|paper.*(?:record|travel)|record.*paper)\b/i.test(text)) return 'paper';
  if (/\b(?:reconcil\w*|month[ -]?end)\b/i.test(text)) return 'reconciliation';
  if (/\b(?:change|edit|revoke|revocation|cancel)\b/i.test(text) && /\b(?:can|how|pwede|paano|unsaon)\b/i.test(text)) return 'changes';
  if (/\brest day\b/i.test(text) && /\b(?:file|submit|pwede)\b/i.test(text)) return 'rest_day';
  return null;
}

function systemHelpTopic(text) {
  if (/\b(?:docutracker|dokumento|track.*document|document.*(?:status|track))\b/i.test(text)) return 'documents';
  if (/\b(?:training report|training reports|training requirements)\b/i.test(text)) return 'training';
  if (/\b(?:password|forgot password)\b/i.test(text)) return 'password';
  if (/\b(?:profile|personal information|account information)\b/i.test(text)) return 'profile';
  if (/\bwhat can you (?:help|do)|\bunsa.*(?:matabang|tabang)|\bano.*(?:maitutulong|kaya mong)\b/i.test(text)) return 'capabilities';
  if (/\bwhat (?:information|actions)\b.*\b(?:read|perform|about me)\b/i.test(text)) return 'capabilities';
  return null;
}

function asksForeignEmployeeData(text) {
  return /\b(?:another|other|all)\s+employees?\b|\b(?:ibang|lahat ng)\s+empleyado\b/i.test(text) &&
    /\b(?:show|view|see|give|makita|balance|attendance|salary|salaries|records?|credits?)\b/i.test(text);
}

function explicitQuestionIntent(text) {
  text = currentQuestion(text);
  if (systemHelpTopic(text)) return 'system_navigation_help';
  if (/\bstatus\b/i.test(text) && /\bleave\b/i.test(text) && locatorTopic.test(text) && !/\b(?:balance|credits?|attendance|dtr)\b/i.test(text)) return 'request_status_overview';
  if (isWritingRequest(text)) return 'form_sentence_suggestion';
  if (/\b(?:submit|file|cancel|add|mark)\b.*\b(?:for me|through (?:this )?chat|did not work|time[ -]?out|\d{1,2}:\d{2})\b/i.test(text)) return 'assistant_action_guidance';
  if (/\b(?:kaibahan|difference|meaning|mean)\b/i.test(text) && /\bpending\b/i.test(text) && /\b(?:approved|returned)\b/i.test(text)) return 'request_policy_guidance';
  if (/\b(?:checklist|before submitting)\b/i.test(text) && /\bleave\b/i.test(text) && locatorTopic.test(text)) return 'request_checklist';
  if (/\bfamily (?:emergency|event)\b/i.test(text) && /\b(?:which|type|fits)\b/i.test(text)) return 'leave_type_selection';
  if (/\bpending\b/i.test(text) && /\b(?:go on leave|contact next|already|take leave)\b/i.test(text)) return 'request_policy_guidance';
  if (/\b(?:valid|real)\b.*\b(?:attendance )?date\b/i.test(text)) return 'dtr_date_validation';
  if (leaveTopic.test(text) && /\b(?:change the date|submit anyway)\b/i.test(text)) return 'leave_availability_check';
  const locator = locatorTopic.test(text);
  if (locatorPolicyKind(text)) return locatorPolicyKind(text) === 'credits' ? 'locator_requirements' : 'locator_policy_guidance';
  if (locator && /\b(?:difference|compare|versus|kalahi|pagkaiba)\b/i.test(text)) return 'locator_type_compare';
  if (locator && /\b(?:extra|custom|additional)\s+fields?\b/i.test(text)) return 'locator_form_field_help';
  if (/\b(?:explain|what|which|is|are|how many|unsay|ano)\b/i.test(text) &&
      /\b(?:field|purpose|departure|expected date return|character|optional)\b/i.test(text)) return locator ? 'locator_form_field_help' : 'leave_form_field_help';
  const fieldQuestion = /\b(?:put|enter|write|fill|ibutang|ilalagay|ilagay|isulat)\b/i.test(text) &&
    /\b(?:field|reason|remarks|destination|location|office|activity)\b/i.test(text);
  if (fieldQuestion) return locator ? 'locator_form_field_help' : /\breason and location\b/i.test(text) ? 'leave_form_guidance' : 'leave_form_field_help';
  if (locator && /\b(?:attachments?|requirements?|kailangan|kinahanglan)\b/i.test(text)) return 'locator_requirements';
  if (locator && /\b(?:cover\w*|sakop)\b/i.test(text) && /\b(?:october|\d{4}|slots?|date|yesterday|today)\b/i.test(text)) return 'dtr_locator_coverage_check';
  if (!locator && leaveTopic.test(text)) {
    if (/\b(?:days?|adlaw|araw)\b/i.test(text) && /\b(?:still use|this year|remaining annual|annual.*remain|nabilin.*tuig)\b/i.test(text)) return 'leave_annual_remaining';
    if (/\b(?:cover\w*)\b/i.test(text) && /\b(?:approved|dtr|attendance)\b/i.test(text)) return 'dtr_leave_coverage_check';
    if (/\b(?:overlap\w*|conflict\w*)\b/i.test(text)) return 'leave_overlap_check';
    if (/\b(?:remain\w*|left|matira|mabilin|projection|short|kulang)\b/i.test(text) && /\b(?:if|after|kung|file|take|use)\b/i.test(text)) return 'leave_balance_projection';
    if (/\bpending\b/i.test(text) && /\b(?:why|explain|reduce|reserve|bawas)\b/i.test(text)) return 'leave_pending_days_explanation';
    if (/\b(?:eligible|eligibility|qualified|entitled|kwalipikado)\b/i.test(text)) return 'leave_eligibility_check';
    if (/\b(?:balance|credits?)\b/i.test(text) && !/\b(?:deduct\w*|need|required|why|bakit|ngano|guidelines?|explain|earned|pending)\b/i.test(text)) return 'leave_balance';
  }
  if (/\b(?:dtr|attendance)\b/i.test(text) && /\b(?:kumusta|kamusta)\b/i.test(text)) return 'dtr_status_explanation';
  if (/\b(?:before|overdue|shift starts)\b/i.test(text) && /\b(?:shift|punch|absent)\b/i.test(text)) return 'dtr_status_explanation';
  if (/\b(?:why|ngano|bakit)\b/i.test(text) && /\bundertime\b/i.test(text)) return 'dtr_undertime_reason';
  if (/\b(?:dtr|attendance)\b/i.test(text) && /\b(?:rules|policy)\b/i.test(text)) return 'dtr_policy_guidance';
  if (/\b(?:attendance|dtr)\s+only\b/i.test(text)) return 'dtr_status_explanation';
  if (/\b(?:dtr|attendance)\b/i.test(text) && /\b(?:compare|versus|both|either)\b/i.test(text)) return 'dtr_comparison';
  if (/\b(?:punches|logs)\b/i.test(text) && /\b(?:both|either)\b/i.test(text)) return 'dtr_comparison';
  if (/^(?:please\s+)?(?:check|show)(?:\s+my)?\s+attendance(?:\s+(?:today|tomorrow|yesterday|ngayon|kahapon))?[.?!]*$/i.test(text.trim())) return 'dtr_status_explanation';
  return null;
}

module.exports = { explicitQuestionIntent, isWritingRequest, isDraftRestyle, currentQuestion, locatorPolicyKind, systemHelpTopic, asksForeignEmployeeData, locatorTopic };
