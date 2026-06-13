const { normalizeAssistantMessageForRules } = require('./dtrAssistantTextNormalizer');

function lower(value) {
  return String(value || '').toLowerCase();
}

const LEAVE_TOPIC_PATTERN =
  /\b(leave|leaves|vl|sl|sick|vacation|paternity|maternity|adoption|solo parent|vawc|calamity|mandatory|forced|special privilege)\b/;

function normalizeIntent(value) {
  const intent = String(value || '').trim().toLowerCase();
  return [
    'today_dtr',
    'missing_logs',
    'leave_balance',
    'pending_leave_requests',
    'approved_leave_requests',
    'rejected_leave_requests',
    'leave_history',
    'leave_availability_check',
    'leave_attachment_requirement',
    'leave_overlap_check',
    'leave_pending_days_explanation',
    'leave_balance_after_filing',
    'leave_request_summary',
    'leave_filing_policy',
    'leave_form_guidance',
    'leave_eligibility_check',
    'leave_dtr_impact',
    'leave_guideline_section',
    'leave_type_compare',
    'leave_guided_filing',
    'leave_approval_history',
    'leave_rejection_reason',
    'leave_approval_tracker',
    'leave_request_lookup',
    'leave_types',
    'leave_requirements',
    'latest_leave_request',
    'latest_locator_request',
  ].includes(intent)
    ? intent
    : null;
}

function detectEmployeeAssistantIntent(message, explicitIntent) {
  const forcedIntent = normalizeIntent(explicitIntent);
  if (forcedIntent) return forcedIntent;

  const text = lower(normalizeAssistantMessageForRules(message));

  if (
    /\b(missing|incomplete|kulang|kuwang|wala|absent|no log|nolog|logs?|entries)\b/.test(
      text
    ) &&
    /\b(logs?|dtr|attendance|time[\s-]?in|time[\s-]?out|this week|week|semanaha|semana|karon|ngayon)\b/.test(
      text
    )
  ) {
    return 'missing_logs';
  }

  if (
    /\b(summary|summarize|summarise|overview|recap|total|count|counts)\b/.test(text) &&
    /\b(leave|leaves|request|requests)\b/.test(text)
  ) {
    return 'leave_request_summary';
  }

  if (
    /\b(who|kinsa|sino|where|asa|kanino|holding|hold|pending with|waiting|awaiting|nasa.*kanino|naa.*kinsa)\b/.test(
      text
    ) &&
    /\b(leave|request|approval|approve|pending|status)\b/.test(text)
  ) {
    return 'leave_approval_tracker';
  }

  if (
    /\b(history|timeline|steps|who approved|who reviewed|kinsa.*approve|kinsa.*review|approval history|review history|action history)\b/.test(
      text
    ) &&
    /\b(leave|request|approval|approved|review|timeline)\b/.test(text)
  ) {
    return 'leave_approval_history';
  }

  if (
    /\b(why|ngano|bakit|reason|remarks|comment|returned|rejected|declined|denied|gi reject|gibalik|binalik)\b/.test(
      text
    ) &&
    /\b(leave|request|rejected|returned|declined|denied)\b/.test(text)
  ) {
    return 'leave_rejection_reason';
  }

  if (
    /\b((what|which|unsa|unsay|ano).*(leave type|gi file|g-file|filed)|gi file|g-file|filed|did i file|akong.*file|ko.*file|leave type)\b/.test(
      text
    ) &&
    /\b(leave|type|filed|gi file|g-file|request|april|may|june|july|august|september|october|november|december|january|february|march|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec|\d{4}-\d{2}-\d{2})\b/.test(
      text
    ) &&
    /\b(on|sa|adtung|niadtong|that|to|date|day|today|tomorrow|yesterday|ugma|kagahapon|gahapon|sunod|miaging|niaging|monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|miyerkules|mierkules|huwebes|webes|biyernes|byernes|sabado|domingo|\d{4}-\d{2}-\d{2}|april|may|june|july|august|september|october|november|december|january|february|march|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)\b/.test(
      text
    )
  ) {
    return 'leave_request_lookup';
  }

  if (
    /\b(compare|difference|different|versus| vs |vs\.|unsa.*kalahi|kalahi|pagkaiba|lain.*sa|compare.*leave)\b/.test(
      ` ${text} `
    ) &&
    LEAVE_TOPIC_PATTERN.test(text)
  ) {
    return 'leave_type_compare';
  }

  if (
    /\b(general rules|filing deadline|filing deadlines|supporting documents|leave credits|credits and limits|commutation|monetization|monetisation|terminal leave|guideline|guidelines)\b/.test(
      text
    ) &&
    LEAVE_TOPIC_PATTERN.test(text)
  ) {
    return 'leave_guideline_section';
  }

  if (
    /\b(dtr|attendance|daily time|on leave|mahitabo.*dtr|effect.*dtr|impact.*dtr|mark.*dtr|marked.*leave|attendance status)\b/.test(
      text
    ) &&
    LEAVE_TOPIC_PATTERN.test(text)
  ) {
    return 'leave_dtr_impact';
  }

  if (
    /\b(eligible|eligibility|qualified|qualification|avail|entitled|pwede ba ko|pwede ko|pwede akong|puwede ba ako|qualified ba|eligible ba)\b/.test(
      text
    ) &&
    LEAVE_TOPIC_PATTERN.test(text) &&
    !/\b(\d+\s*(day|days|adlaw)|tomorrow|today|yesterday|ugma|kagahapon|gahapon|\d{4}-\d{2}-\d{2})\b/.test(text)
  ) {
    return 'leave_eligibility_check';
  }

  if (
    /\b(fill|fill up|field|fields|form|details|what to put|what should i put|i-fill|input|reason field|location|delivery|sick nature)\b/.test(
      text
    ) &&
    LEAVE_TOPIC_PATTERN.test(text)
  ) {
    return 'leave_form_guidance';
  }

  if (
    /\b(help me file|guide me file|assist me file|tabangi.*file|tabangi ko|mag file ko|mag-file ko|i want to file|gusto ko mag file|gusto nako mag file)\b/.test(
      text
    ) &&
    LEAVE_TOPIC_PATTERN.test(text)
  ) {
    return 'leave_guided_filing';
  }

  if (
    /\b(pending days|pending balance|pending leave days|asa.*pending|where.*pending|why.*pending|ngano.*pending|bakit.*pending)\b/.test(
      text
    ) &&
    /\b(leave|balance|days|pending)\b/.test(text)
  ) {
    return 'leave_pending_days_explanation';
  }

  if (
    /\b(after filing|mabilin|matira|nabilin|natira|remaining after|balance after|pila.*mabilin|pila.*nabilin|how much.*remain|what.*remain)\b/.test(
      text
    ) &&
    /\b(\d+|day|days|adlaw|leave|sick|vacation|vl|sl)\b/.test(text)
  ) {
    return 'leave_balance_after_filing';
  }

  if (
    /\b(overlap|conflict|already|existing|naa.*leave|may.*leave|on leave|leave.*date|same date|ana nga date)\b/.test(
      text
    ) &&
    /\b(leave|date|day|today|tomorrow|yesterday|ugma|kagahapon|gahapon|sunod|miaging|niaging|monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|miyerkules|mierkules|huwebes|webes|biyernes|byernes|sabado|domingo|\d{4}-\d{2}-\d{2}|january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec)\b/.test(
      text
    )
  ) {
    return 'leave_overlap_check';
  }

  if (
    /\b(attachment|attachments|document|documents|docs|proof|supporting|medical certificate|med cert|need.*attach|required.*attach|kinahanglan.*attach)\b/.test(
      text
    ) &&
    LEAVE_TOPIC_PATTERN.test(text)
  ) {
    return 'leave_attachment_requirement';
  }

  if (
    /\b(policy|rule|rules|advance|before|deadline|how many days before|pila.*days.*before|kanus-a|when.*file|max|maximum|limit|allowed|pwede.*past|past date|late filing)\b/.test(
      text
    ) &&
    LEAVE_TOPIC_PATTERN.test(text)
  ) {
    return 'leave_filing_policy';
  }

  if (
    /\b(requirements?|requirement|attachment|document|docs|needed|need|kinahanglan|unsa.*kinahanglan|ano.*kailangan|file.*request|pag file|pag-file)\b/.test(
      text
    ) &&
    LEAVE_TOPIC_PATTERN.test(text)
  ) {
    return 'leave_requirements';
  }

  if (
    /\b(enough|sapat|kaya|pwede|can i file|can file|file.*leave|leave.*file|available.*for)\b/.test(
      text
    ) &&
    (LEAVE_TOPIC_PATTERN.test(text) || /\b\d+\b/.test(text))
  ) {
    return 'leave_availability_check';
  }

  if (
    /\b(leave types|types of leave|available leave types|unsa.*leave type|ano.*leave type|what leave types)\b/.test(
      text
    )
  ) {
    return 'leave_types';
  }

  if (
    /\b(pending leave|leave.*pending|naa.*pending.*leave|may.*pending.*leave|pending.*request)\b/.test(
      text
    )
  ) {
    return 'pending_leave_requests';
  }

  if (
    /\b(leave request|latest leave|last leave|leave status|status.*leave|ano status.*leave|na-approve.*leave|approved na ba.*leave)\b/.test(
      text
    )
  ) {
    return 'latest_leave_request';
  }

  if (
    /\b(show.*approved.*leave|list.*approved.*leave|all.*approved.*leave|my approved leave|approved leaves|approved.*request)\b/.test(
      text
    )
  ) {
    return 'approved_leave_requests';
  }

  if (
    /\b(rejected leave|leave.*rejected|declined leave|deny.*leave|rejected.*request|gi reject.*leave)\b/.test(
      text
    )
  ) {
    return 'rejected_leave_requests';
  }

  if (
    /\b(leave history|history.*leave|my leaves|leaves nako|leave requests|show.*leave|list.*leave)\b/.test(
      text
    )
  ) {
    return 'leave_history';
  }

  if (
    /\b(leave balance|leave balances|leave credit|leave credits|credits|balance|available leave|remaining leave|pila.*leave|leave.*pila|ilan.*leave|leave.*ilan|sick leave|vacation leave|paternity leave|maternity leave|adoption leave)\b/.test(
      text
    )
  ) {
    return 'leave_balance';
  }

  if (
    /\b(locator|pass slip|locator slip|wfh|work from home|official business|ob request|na-approve|approved.*locator|status.*locator)\b/.test(
      text
    )
  ) {
    return 'latest_locator_request';
  }

  if (
    /\b(dtr|attendance|late|time[\s-]?in|time[\s-]?out|status)\b/.test(text) &&
    /\b(today|tomorrow|yesterday|ugma|kagahapon|gahapon|karon|ngayon|karong adlawa|this day|late|status|time[\s-]?in|time[\s-]?out)\b/.test(
      text
    )
  ) {
    return 'today_dtr';
  }

  return null;
}

module.exports = {
  detectEmployeeAssistantIntent,
  normalizeIntent,
};
