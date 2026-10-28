// Specific question semantics shared by routing, memory and multi-intent handling.
// These are question classes, not responses tied to individual audit sentences.
const locatorTopic = /\b(locator|pass[ -]?slip|wfh|work from home|official business|travel order)\b/i;
const leaveTopic = /\b(leave|credits?|balance|maternity|paternity|sick|vacation)\b/i;

function isWritingRequest(text) {
  return /\b(sentence|pangungusap|wording|phrase|draft|rewrite)\b/i.test(text) &&
    /\b(suggest|generate|give|write|draft|rewrite|himo\w*|gawan|gumawa|help|formal|shorter|mubo)\b/i.test(text) ||
    /\b(?:gawan|himo\w*|gumawa)\b.*\b(?:reason|rason)\b/i.test(text);
}

function locatorPolicyKind(text) {
  if (!locatorTopic.test(text)) return null;
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
  return null;
}

function asksForeignEmployeeData(text) {
  return /\b(?:another|other|all)\s+employees?\b|\b(?:ibang|lahat ng)\s+empleyado\b/i.test(text) &&
    /\b(?:show|view|see|give|makita|balance|attendance|salary|salaries|records?|credits?)\b/i.test(text);
}

function explicitQuestionIntent(text) {
  if (systemHelpTopic(text)) return 'system_navigation_help';
  if (isWritingRequest(text)) return 'form_sentence_suggestion';
  const locator = locatorTopic.test(text);
  if (locatorPolicyKind(text)) return locatorPolicyKind(text) === 'credits' ? 'locator_requirements' : 'locator_policy_guidance';
  if (locator && /\b(?:difference|compare|versus|kalahi|pagkaiba)\b/i.test(text)) return 'locator_type_compare';
  const fieldQuestion = /\b(?:put|enter|write|fill|ibutang|ilalagay|ilagay|isulat)\b/i.test(text) &&
    /\b(?:field|reason|remarks|destination|location|office|activity)\b/i.test(text);
  if (fieldQuestion) return locator ? 'locator_form_field_help' : /\breason and location\b/i.test(text) ? 'leave_form_guidance' : 'leave_form_field_help';
  if (locator && /\b(?:attachments?|requirements?|kailangan|kinahanglan)\b/i.test(text)) return 'locator_requirements';
  if (!locator && leaveTopic.test(text)) {
    if (/\b(?:overlap\w*|conflict\w*)\b/i.test(text)) return 'leave_overlap_check';
    if (/\b(?:remain\w*|left|matira|mabilin|projection)\b/i.test(text) && /\b(?:if|after|kung|file|take|use)\b/i.test(text)) return 'leave_balance_projection';
    if (/\b(?:eligible|eligibility|qualified|entitled|kwalipikado)\b/i.test(text)) return 'leave_eligibility_check';
    if (/\b(?:balance|credits?)\b/i.test(text) && !/\b(?:deduct\w*|need|required|why|bakit|ngano|guidelines?|explain|earned|pending)\b/i.test(text)) return 'leave_balance';
  }
  if (/\b(?:dtr|attendance)\b/i.test(text) && /\b(?:kumusta|kamusta)\b/i.test(text)) return 'dtr_status_explanation';
  if (/^(?:please\s+)?(?:check|show)(?:\s+my)?\s+attendance(?:\s+(?:today|tomorrow|yesterday|ngayon|kahapon))?[.?!]*$/i.test(text.trim())) return 'dtr_status_explanation';
  return null;
}

module.exports = { explicitQuestionIntent, isWritingRequest, locatorPolicyKind, systemHelpTopic, asksForeignEmployeeData, locatorTopic };
