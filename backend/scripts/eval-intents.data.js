/**
 * Golden set for the DTR assistant intent evaluation harness.
 *
 * Each entry is [message, expectedIntent, language?].
 *   - expectedIntent = null  => out-of-domain (the bot should NOT route to a real intent)
 *   - language = 'en' | 'tl' | 'bisaya' | 'mix' (optional, used for per-language reporting)
 *
 * Keep this file human-curated. Sources for new cases:
 *   1. Real thumbs-down feedback (see `npm run eval:export-feedback`).
 *   2. Phrasings from dtrAssistantRegression.test.js.
 *   3. The fuzzy phrase profiles in dtrAssistantIntentService.js.
 *
 * Try to keep the set balanced across languages and intents so per-intent
 * accuracy numbers stay meaningful.
 */
const GOLDEN = [
  // ---- out-of-domain (expectedIntent = null) ---------------------------------
  ['can you write me a poem', null, 'en'],
  ['hello who are you', null, 'en'],
  ['tell me a joke', null, 'en'],
  ['what is the capital of France', null, 'en'],
  ['kinsa ka?', null, 'bisaya'],
  ['sino ka?', null, 'tl'],
  ['thank you', null, 'en'],
  ['salamat', null, 'tl'],

  // ---- DTR: today / daily ----------------------------------------------------
  // NOTE: today_dtr and dtr_daily_record share the same reply handler, so
  // these phrasings route to dtr_daily_record. Keep a couple of true
  // today_dtr expectations using the narrower "did i time in" wording.
  ['show my dtr for today', 'dtr_daily_record', 'en'],
  ['unsa akong dtr karon?', 'dtr_daily_record', 'bisaya'],
  ['dtr ko ngayon', 'dtr_daily_record', 'tl'],
  ['did i time in today?', 'today_dtr', 'en'],
  ['naa koy time in karon?', 'dtr_daily_record', 'bisaya'],

  // ---- DTR: missing logs -----------------------------------------------------
  ['do i have missing logs this week', 'dtr_missing_logs', 'en'],
  ['kulang ba akong logs karong semanaha?', 'dtr_missing_logs', 'bisaya'],
  ['may kulang ba akong logs ngayong linggo?', 'dtr_missing_logs', 'tl'],
  // dtr_missing_log_reason needs an explicit "why/reason" phrasing so it
  // is not confused with a plain missing-logs lookup.
  ['why are my dtr logs missing', 'dtr_missing_log_reason', 'en'],
  ['ngano wala ang logs sa akong dtr?', 'dtr_missing_log_reason', 'bisaya'],

  // ---- DTR: range summary / counts ------------------------------------------
  ['show my dtr from Monday to Friday', 'dtr_range_summary', 'en'],
  ['how many absents i have for this month?', 'dtr_absent_summary', 'en'],
  ['pila kabuok absent nako aning bulana?', 'dtr_absent_summary', 'bisaya'],
  ['ilan absent ko ngayong buwan?', 'dtr_absent_summary', 'tl'],
  ['how many absent last pay period?', 'dtr_absent_summary', 'en'],
  ['how many late this month', 'dtr_late_summary', 'en'],
  ['pila late nako aning bulana?', 'dtr_late_summary', 'bisaya'],
  ['undertime summary this month', 'dtr_undertime_summary', 'en'],
  ['overtime summary this pay period', 'dtr_overtime_summary', 'en'],
  ['how many total hours did i work this month', 'dtr_hours_summary', 'en'],
  ['pila oras nagtrabaho this month', 'dtr_hours_summary', 'mix'],

  // ---- DTR: status / holiday / schedule -------------------------------------
  ['unsay status sa akong dtr adtung niaging miyerkules?', 'dtr_status_explanation', 'bisaya'],
  ['unsa akong dtr status adtun first week sa june?', 'dtr_status_explanation', 'bisaya'],
  ['why is my dtr incomplete', 'dtr_missing_log_reason', 'en'],
  ['is today a holiday?', 'dtr_holiday_check', 'en'],
  ['holiday ba karon?', 'dtr_holiday_check', 'bisaya'],
  ['naa koy duty karon?', 'dtr_schedule_context', 'bisaya'],
  ['may pasok ba ako ngayon?', 'dtr_schedule_context', 'tl'],
  ['what is my shift today', 'dtr_schedule_context', 'en'],

  // ---- DTR: export / policy / correction ------------------------------------
  ['export my dtr this month', 'dtr_export_guidance', 'en'],
  ['i-download ko ang dtr ko', 'dtr_export_guidance', 'tl'],
  ['what are the dtr rules?', 'dtr_policy_guidance', 'en'],
  ['how do i fix my missing logs', 'dtr_correction_guidance', 'en'],
  ['paano i-correct ang dtr ko', 'dtr_correction_guidance', 'tl'],

  // ---- Leave: balance --------------------------------------------------------
  ['what is my leave balance?', 'leave_balance', 'en'],
  ['pila akong balance sa sick leave?', 'leave_balance', 'bisaya'],
  ['ilan ang leave credits ko?', 'leave_balance', 'tl'],
  ['why is my vacation leave balance low?', 'leave_balance', 'en'],
  ['ngano gamay nalang akong vacation leave?', 'leave_balance', 'bisaya'],
  ['if i take 3 days sick leave how many days left', 'leave_balance_projection', 'en'],
  ['pila mabilin kung mag file ug 2 days vacation leave', 'leave_balance_projection', 'mix'],

  // ---- Leave: filing / form / requirements ----------------------------------
  ['how can i file sick leave?', 'leave_form_guidance', 'en'],
  ['paano mag file ng sick leave?', 'leave_form_guidance', 'tl'],
  ['unsaon pag file ug sick leave?', 'leave_form_guidance', 'bisaya'],
  ['unsaon pag file mandatory leave?', 'leave_form_guidance', 'bisaya'],
  ['unsay requirements sa maternity leave?', 'leave_requirements', 'bisaya'],
  ['ano requirements sa maternity leave?', 'leave_requirements', 'tl'],
  ['need med cert if 5 days sick leave?', 'leave_attachment_requirement', 'en'],
  ['what attachment do i need?', 'leave_attachment_requirement', 'en'],
  ['can i file 1 day sick leave tomorrow?', 'leave_availability_check', 'en'],
  ['pwede akong mag file ug leave ugma?', 'leave_availability_check', 'bisaya'],

  // ---- Leave: guidelines / explanation --------------------------------------
  ['explain me the leave types', 'leave_guideline_section', 'en'],
  ['explain the sick leave', 'leave_guideline_section', 'en'],
  ['okay explain filing deadlines', 'leave_guideline_section', 'en'],
  ['can you give me the guidlines of the leave types?', 'leave_guideline_section', 'en'],
  ['unsay pasabot sa vacation leave?', 'leave_guideline_section', 'bisaya'],

  // ---- Leave: approvals / status / rejection --------------------------------
  ['kinsa nag hold sa akong leave request?', 'leave_approval_tracker', 'bisaya'],
  ['sino nag-hold ng leave ko?', 'leave_approval_tracker', 'tl'],
  ['ngano gi reject akong leave?', 'leave_rejection_reason', 'bisaya'],
  ['bakit na-reject ang leave ko?', 'leave_rejection_reason', 'tl'],
  ['show my leave history this month', 'leave_history', 'en'],
  ['show my pending leave requests', 'pending_leave_requests', 'en'],

  // ---- Locator ---------------------------------------------------------------
  ['what are the locator types i can file?', 'locator_types', 'en'],
  ['how about the wfh?', 'locator_types', 'en'],
  ['unsa ang wfh?', 'locator_types', 'bisaya'],
  ['locator requirements', 'locator_requirements', 'en'],
  ['how to file a pass slip', 'locator_requirements', 'en'],
  ['pwede ba ko mag file ug pass slip ugma?', 'locator_availability_check', 'bisaya'],
  ['can i file a wfh tomorrow?', 'locator_availability_check', 'en'],
  ['ngano gi reject akong locator?', 'locator_rejection_reason', 'bisaya'],
  ['asa na akong official business request?', 'locator_approval_tracker', 'bisaya'],
  ['nasaan na ang locator request ko?', 'locator_approval_tracker', 'tl'],
  ['what is my locator status', 'locator_status', 'en'],
  ['covered ba sa locator akong PM out?', 'dtr_locator_coverage_check', 'mix'],
];

module.exports = { GOLDEN };
