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
  ['unsa akong attendance adtong lunes', 'dtr_daily_record', 'bisaya'],
  ['dtr ko ngayon', 'dtr_daily_record', 'tl'],
  ['did i time in today?', 'today_dtr', 'en'],
  ['naa koy time in karon?', 'dtr_daily_record', 'bisaya'],

  // ---- DTR: missing logs -----------------------------------------------------
  ['do i have missing logs this week', 'dtr_missing_logs', 'en'],
  ['what logs are missing yesterday', 'dtr_missing_logs', 'en'],
  ['kulang ba akong logs karong semanaha?', 'dtr_missing_logs', 'bisaya'],
  ['may kulang ba akong logs ngayong linggo?', 'dtr_missing_logs', 'tl'],
  // dtr_missing_log_reason needs an explicit "why/reason" phrasing so it
  // is not confused with a plain missing-logs lookup.
  ['why are my dtr logs missing', 'dtr_missing_log_reason', 'en'],
  ['ngano wala ang logs sa akong dtr?', 'dtr_missing_log_reason', 'bisaya'],
  ['unsa nga logs ang kulang gahapon', 'dtr_missing_logs', 'bisaya'],
  ['nganong kulang akong pm in', 'dtr_missing_log_reason', 'bisaya'],
  ['paano ayusin missing am in ko', 'dtr_correction_guidance', 'tl'],
  ['pano ko maayos ang mising pm out', 'dtr_correction_guidance', 'typo'],

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
  ['how many days was i present this month', 'dtr_range_summary', 'en'],
  ['pila ko ka adlaw present this month', 'dtr_range_summary', 'mix'],
  ['pila ko ka adlaw ni present karong bulana', 'dtr_range_summary', 'bisaya'],
  ['check my attendance two weeks ago', 'dtr_range_summary', 'en'],
  ['how many hours from monday to friday', 'dtr_hours_summary', 'en'],

  // ---- DTR: status / holiday / schedule -------------------------------------
  ['unsay status sa akong dtr adtung niaging miyerkules?', 'dtr_status_explanation', 'bisaya'],
  ['unsa akong dtr status adtun first week sa june?', 'dtr_status_explanation', 'bisaya'],
  ['why is my dtr incomplete', 'dtr_missing_log_reason', 'en'],
  ['is today a holiday?', 'dtr_holiday_check', 'en'],
  ['holiday ba karon?', 'dtr_holiday_check', 'bisaya'],
  ['naa koy duty karon?', 'dtr_schedule_context', 'bisaya'],
  ['may pasok ba ako ngayon?', 'dtr_schedule_context', 'tl'],
  ['what is my shift today', 'dtr_schedule_context', 'en'],
  ['wat is my curent shft', 'dtr_schedule_context', 'typo'],
  ['late ba ko gahapon', 'dtr_status_explanation', 'mix'],
  ['nganong late ko gahapon', 'dtr_late_reason', 'bisaya'],
  ['nganong late ko adtong lunes', 'dtr_late_reason', 'bisaya'],
  ['late ba ko adtong lunes', 'dtr_status_explanation', 'bisaya'],
  ['naa bay holiday sa june 14', 'dtr_holiday_check', 'bisaya'],
  ['show my record first monday of june', 'dtr_daily_record', 'en'],
  ['unsa akng dtr statos gahapn', 'dtr_status_explanation', 'typo'],
  ['unsay statuz sa akng dtr gahapn', 'dtr_status_explanation', 'typo'],
  ['pila akng absnt dis mnth', 'dtr_absent_summary', 'typo'],

  // ---- DTR: export / policy / correction ------------------------------------
  ['export my dtr this month', 'dtr_export_guidance', 'en'],
  ['i-download ko ang dtr ko', 'dtr_export_guidance', 'tl'],
  ['what are the dtr rules?', 'dtr_policy_guidance', 'en'],
  ['explain attendance grace period', 'dtr_policy_guidance', 'en'],
  ['how do i fix my missing logs', 'dtr_correction_guidance', 'en'],
  ['paano i-correct ang dtr ko', 'dtr_correction_guidance', 'tl'],
  ['i need to correct my pm out', 'dtr_correction_guidance', 'en'],
  ['unsaon pag correct sa pm out nako', 'dtr_correction_guidance', 'bisaya'],
  ['bakt ako lte kahapn', 'dtr_late_reason', 'typo'],
  ['unsaon pg corect missing pm ot', 'dtr_correction_guidance', 'typo'],
  ['unsaon pg korek sa mising log', 'dtr_correction_guidance', 'typo'],
  ['unsaon nako pag correct sa missing am out', 'dtr_correction_guidance', 'bisaya'],
  ['unsa ang grace period sa akong shift', 'dtr_policy_guidance', 'bisaya'],
  ['sakop ba sa leave akong absence gahapon', 'dtr_leave_coverage_check', 'bisaya'],
  ['is my sick leave covering absent yesterday', 'dtr_leave_coverage_check', 'en'],
  ['sakop ba sa approved locator akong am in', 'dtr_locator_coverage_check', 'bisaya'],

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
  ['how can i file a leave?', 'leave_form_guidance', 'en'],
  ['unsaon nako pag file ug leave', 'leave_form_guidance', 'bisaya'],
  ['unsaon pg file og leev', 'leave_form_guidance', 'typo'],
  ['paunsa ko mag leave request', 'leave_form_guidance', 'bisaya'],
  ['pano mg file ng leev', 'leave_form_guidance', 'typo'],
  ['how do i make a leave request', 'leave_form_guidance', 'en'],
  ['how cn i fil a leav', 'leave_form_guidance', 'typo'],
  ['paano mag file ng sick leave?', 'leave_form_guidance', 'tl'],
  ['unsaon pag file ug sick leave?', 'leave_form_guidance', 'bisaya'],
  ['unsaon pag file mandatory leave?', 'leave_form_guidance', 'bisaya'],
  ['what should i put in the reason field for sick leave?', 'leave_form_field_help', 'en'],
  ['give me a sample input for the location field', 'leave_form_field_help', 'en'],
  ['unsa akong ibutang sa reason field sa sick leave?', 'leave_form_field_help', 'bisaya'],
  ['ano ang ilalagay sa illness details field?', 'leave_form_field_help', 'tl'],
  ['what attachment should i upload for 5 days sick leave?', 'leave_form_field_help', 'en'],
  ['unsa nga file akong i attach sa maternity leave', 'leave_form_field_help', 'bisaya'],
  ['unsaon pag fill sa location sa leave form', 'leave_form_field_help', 'bisaya'],
  ['hatagi kog sample reason sa sick leave', 'leave_form_field_help', 'bisaya'],
  ['what is commutation leave of request?', 'leave_form_field_help', 'en'],
  ['unsay commutation checkbox?', 'leave_form_field_help', 'bisaya'],
  ['give sampel input for the reasn feild', 'leave_form_field_help', 'typo'],
  ['unsay requirements sa maternity leave?', 'leave_requirements', 'bisaya'],
  ['ano requirements sa maternity leave?', 'leave_requirements', 'tl'],
  ['need med cert if 5 days sick leave?', 'leave_attachment_requirement', 'en'],
  ['what attachment do i need?', 'leave_attachment_requirement', 'en'],
  ['can i file 1 day sick leave tomorrow?', 'leave_availability_check', 'en'],
  ['pwede akong mag file ug leave ugma?', 'leave_availability_check', 'bisaya'],
  ['can i submit vacation leave for next friday', 'leave_availability_check', 'en'],
  ['what happens after i submit my leave', 'leave_filing_policy', 'en'],
  ['unsa mahitabo human nako ma-submit ang leave', 'leave_filing_policy', 'bisaya'],
  ['unsa mahitabo after nako ma submit ang leave', 'leave_filing_policy', 'mix'],
  ['if i tick commutation will i get cash', 'leave_form_field_help', 'en'],
  ['gi check nako ang commutation mabayran ba ko', 'leave_form_field_help', 'bisaya'],
  ['sample reason for vacation leave', 'leave_form_field_help', 'en'],
  ['how do i fill vacation leave reason and location', 'leave_form_guidance', 'en'],
  ['what documents for paternity leave', 'leave_attachment_requirement', 'en'],
  ['what is the difference between maternity and paternity leave', 'leave_type_compare', 'en'],
  ['guide me file vacation leave tomorrow', 'leave_guided_filing', 'en'],
  ['help me file sick leave june 25 to june 27', 'leave_guided_filing', 'en'],
  ['how many pending leave days do i have', 'leave_pending_days_explanation', 'en'],
  ['nganong naa koy pending balance', 'leave_pending_days_explanation', 'bisaya'],
  ['why are days pending from my balance', 'leave_pending_days_explanation', 'en'],

  // ---- Leave: guidelines / explanation --------------------------------------
  ['explain me the leave types', 'leave_guideline_section', 'en'],
  ['explain the sick leave', 'leave_guideline_section', 'en'],
  ['eh explain daw ang maternity leave', 'leave_guideline_section', 'bisaya'],
  ['eh explain daw ang mga leave types apil ila guidelines', 'leave_guideline_section', 'bisaya'],
  ['okay explain filing deadlines', 'leave_guideline_section', 'en'],
  ['can you give me the guidlines of the leave types?', 'leave_guideline_section', 'en'],
  ['unsay pasabot sa vacation leave?', 'leave_guideline_section', 'bisaya'],
  ['what is the advance filing rule for vacation leave', 'leave_filing_policy', 'en'],
  ['explain supporting documents guideline', 'leave_guideline_section', 'en'],

  // ---- Leave: approvals / status / rejection --------------------------------
  ['kinsa nag hold sa akong leave request?', 'leave_approval_tracker', 'bisaya'],
  ['sino nag-hold ng leave ko?', 'leave_approval_tracker', 'tl'],
  ['ngano gi reject akong leave?', 'leave_rejection_reason', 'bisaya'],
  ['nganong gibalik akong leave request', 'leave_rejection_reason', 'bisaya'],
  ['bakit na-reject ang leave ko?', 'leave_rejection_reason', 'tl'],
  ['show my leave history this month', 'leave_history', 'en'],
  ['show my pending leave requests', 'pending_leave_requests', 'en'],
  ['show summary of my leave requests', 'leave_request_summary', 'en'],
  ['find my leave request on june 9', 'leave_request_lookup', 'en'],
  ['who reviewed my leave request', 'leave_approval_history', 'en'],
  ['show approval timeline of my leave', 'leave_approval_history', 'en'],
  ['show rejected leave requests', 'rejected_leave_requests', 'en'],
  ['what is my latest leave request', 'latest_leave_request', 'en'],
  ['what leave options are available', 'leave_types', 'en'],
  ['unsa nga mga leave akong pwede ma file', 'leave_types', 'bisaya'],
  ['wat leev tipes can i fil', 'leave_types', 'typo'],
  ['sample location for vacation leave', 'leave_form_field_help', 'en'],

  // ---- Locator ---------------------------------------------------------------
  ['what are the locator types i can file?', 'locator_types', 'en'],
  ['how about the wfh?', 'locator_types', 'en'],
  ['unsa ang wfh?', 'locator_types', 'bisaya'],
  ['tell me about official business locator', 'locator_types', 'en'],
  ['locator requirements', 'locator_requirements', 'en'],
  ['how to file a pass slip', 'locator_requirements', 'en'],
  ['unsaon pag file loacator slip?', 'locator_requirements', 'bisaya'],
  ['unsaon pag file ug locator', 'locator_requirements', 'bisaya'],
  ['unsaon pg fil og lokator', 'locator_requirements', 'typo'],
  ['where should i put my destination in locator', 'locator_requirements', 'en'],
  ['what should i write in locator reason', 'locator_requirements', 'en'],
  ['sample destination for official business', 'locator_requirements', 'en'],
  ['what are required fields for wfh', 'locator_requirements', 'en'],
  ['explain wfh rules', 'locator_requirements', 'en'],
  ['loacator reqirements', 'locator_requirements', 'typo'],
  ['how do i fill locator destination', 'locator_requirements', 'en'],
  ['unsa akong ibutang sa destination sa locator', 'locator_requirements', 'bisaya'],
  ['ano ilalagay sa destination ng locator', 'locator_requirements', 'tl'],
  ['pwede ba ko mag file ug pass slip ugma?', 'locator_availability_check', 'bisaya'],
  ['can i file a wfh tomorrow?', 'locator_availability_check', 'en'],
  ['can i submit official business next monday', 'locator_availability_check', 'en'],
  ['hw can i fil locatr tomorow', 'locator_availability_check', 'typo'],
  ['ngano gi reject akong locator?', 'locator_rejection_reason', 'bisaya'],
  ['asa na akong official business request?', 'locator_approval_tracker', 'bisaya'],
  ['nasaan na ang locator request ko?', 'locator_approval_tracker', 'tl'],
  ['what is my locator status', 'locator_status', 'en'],
  ['show my locator status', 'locator_status', 'en'],
  ['pila accepted locator karon nga month?', 'locator_summary', 'mix'],
  ['show locator requests last cutoff', 'locator_summary', 'en'],
  ['how many approved wfh this month', 'locator_summary', 'en'],
  ['pila rejected locator nako', 'locator_summary', 'bisaya'],
  ['pila akong approved locator this month', 'locator_summary', 'mix'],
  ['show my latest wfh', 'latest_locator_request', 'en'],
  ['covered ba sa locator akong PM out?', 'dtr_locator_coverage_check', 'mix'],
];

module.exports = { GOLDEN };
