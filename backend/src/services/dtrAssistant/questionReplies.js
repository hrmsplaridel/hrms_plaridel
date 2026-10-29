const { detectAssistantLanguage } = require('./dtrAssistantLanguage');
const { configuredLeaveType } = require('./configuredLeaveType');
const { configuredLocatorType } = require('./configuredLocatorType');
const { locatorPolicyKind } = require('./dtrAssistantQuestion');
const { coverageForDate } = require('./effectiveAttendance');

function choose(text, english, bisaya, tagalog) {
  const language=detectAssistantLanguage(text);
  return language==='bisaya' ? bisaya : language==='tagalog' ? tagalog : english;
}
function punchTime(value) {
  if (!value) return 'not recorded';
  if (/^\d{1,2}:\d{2}(?::\d{2})?$/.test(String(value))) {
    const [hour,minute]=String(value).split(':').map(Number);
    return `${hour%12||12}:${String(minute).padStart(2,'0')} ${hour<12?'AM':'PM'}`;
  }
  const date=new Date(value);
  return Number.isNaN(date.getTime()) ? 'unrecognized time' : new Intl.DateTimeFormat('en-US',{
    timeZone:process.env.HRMS_TIMEZONE||'Asia/Manila',hour:'numeric',minute:'2-digit',hour12:true,
  }).format(date);
}
function questionReply(text, context, intent) {
  if (intent==='dtr_status_explanation' && /\b(?:why|ngano|bakit|discrepancy|different)\b/i.test(text) && /\b(?:monthly|summary)\b/i.test(text)) {
    const date=context.date_range?.startDate;
    const coverage=coverageForDate(context,date);
    if (coverage.slips.length) return `${date}: ${coverage.label || 'Approved locator'}\n`+choose(text,
      `Approved coverage ${coverage.isFullCoverage?'satisfies the full assigned shift':'covers only part of the assigned shift'}. A missing biometric DTR row is different from missing approved coverage: a punch-only summary can show no record while the approved locator covers its saved slots. The current check includes that coverage. If another monthly report still says no DTR record, refresh it and ask HR to reconcile its date, approval state and coverage source; I cannot verify an earlier summary from this single-date check.`,
      `Ang approved locator ${coverage.isFullCoverage?'kompleto para sa assigned shift':'partial ra sa assigned shift'}. Lahi ang walay biometric row sa walay approved coverage: mahimong no record ang punch-only summary bisan covered ang saved slots. Apil ang coverage sa current check. I-refresh ang monthly report ug ipa-reconcile sa HR ang petsa, approval ug coverage source kung no record gihapon; dili nako ma-verify ang daang summary gikan sa usa ka petsa ra.`,
      `Ang approved locator ay ${coverage.isFullCoverage?'kumpleto para sa assigned shift':'partial lang sa assigned shift'}. Magkaiba ang walang biometric row at walang approved coverage: maaaring no record ang punch-only summary kahit covered ang saved slots. Kasama ang coverage sa current check. I-refresh ang monthly report at ipa-reconcile sa HR ang petsa, approval at coverage source kung no record pa rin; hindi ko mabe-verify ang lumang summary mula sa isang petsa lamang.`);
  }
  if(intent==='dtr_date_validation') return choose(text,`${context.date_range.startDate} is a valid calendar date. Whether attendance logs are required depends on your assigned shift and the configured holiday calendar.`,`${context.date_range.startDate} kay valid nga petsa. Ang required logs magdepende sa shift ug holidays.`,`${context.date_range.startDate} ay valid na petsa. Ang required logs ay depende sa shift at holidays.`);
  if(intent==='assistant_action_guidance') {
    const records=/\b(?:punch|pm out|am in|time[ -]?out|time[ -]?in)\b/i.test(text)
      ? (context.dtr_records||[]).map(r=>{
        const existing=/\bpm out\b/i.test(text)&&r.time_out ? choose(text,`PM out already exists at ${punchTime(r.time_out)}.`, `Naa nay PM out nga ${punchTime(r.time_out)}.`, `May PM out na sa ${punchTime(r.time_out)}.`) : '';
        return `${r.attendance_date}: AM in ${punchTime(r.time_in)}, AM out ${punchTime(r.break_out)}, PM in ${punchTime(r.break_in)}, PM out ${punchTime(r.time_out)}. ${existing}`;
      }).join('\n') : '';
    return choose(text,
    'I cannot submit, cancel, approve or change an HR request or attendance punch through chat. Use My Leave or Locator Requests to review the current request and available actions. For approved-request changes or missing/incorrect punches, contact HR/Admin with the date, request reference, actual work details and proof. Attendance must reflect work or valid approved coverage; I cannot mark an unworked day present.',
    'Dili ko maka-submit, cancel, approve o mag-usab sa request/punch pinaagi sa chat. Ablihi ang My Leave o Locator Requests. Para sa approved request o sayop nga punch, kontaka ang HR/Admin uban sa petsa, reference ug tinuod nga work details/proof. Dili nato markahan present ang adlaw nga walay trabaho o valid approved coverage.',
    'Hindi ako nagsusumite, nagkakansela, nag-aapruba o nagbabago ng request/punch sa chat. Buksan ang My Leave o Locator Requests. Para sa approved request o maling punch, kontakin ang HR/Admin gamit ang petsa, reference at totoong work details/proof. Hindi maaaring markahang present ang araw na walang trabaho o valid approved coverage.')+(records?'\n'+records:'');
  }
  if(intent==='request_checklist') return choose(text,
    'Before submitting: for leave, verify the active type, eligibility, dates, computed working days, available balance or annual quota, advance notice, custom details and configured attachments. For a locator, verify its type, scheduled workday, destination/purpose, exact covered slots, reason, required custom fields and attachments. Check overlaps and review all facts. Submit in the appropriate form; this chat has submitted nothing. Approval is still required.',
    'Sa dili pa mo-submit: sa leave, i-check ang type, eligibility, petsa, working days, balance/quota, advance notice, custom fields ug attachments. Sa locator, i-check ang type, workday, destination/purpose, covered slots, reason ug required fields/files. I-check ang overlaps ug facts. Sa form ra mo-submit; wala koy gi-submit dinhi ug kinahanglan pa ang approval.',
    'Bago magsumite: sa leave, suriin ang type, eligibility, petsa, working days, balance/quota, advance notice, custom fields at attachments. Sa locator, suriin ang type, workday, destination/purpose, covered slots, reason at required fields/files. Suriin ang overlaps at facts. Sa form magsumite; wala akong isinumite rito at kailangan pa ang approval.');
  if(intent==='request_policy_guidance') {
    const pending=(context.recent_leave_requests||[]).find(r=>/^pending/.test(r.status));
    const owner={pending_hr:'HR final review',pending_department_head:'Department Head review',pending_mayor:'Mayor / authorized final reviewer'}[pending?.status]||'the assigned reviewer shown in the request tracker';
    const reviewer=pending?.reviewer_name||pending?.latest_history_actor_name||pending?.last_reviewer_name;
    const personal=/\b(?:my|akong|nako|ko|contact|next|take leave|go on leave)\b/i.test(text);
    const tracker=pending&&personal ? `\n${pending.leave_type || 'Leave'} (${pending.start_date}): ${pending.status}. `+choose(text,`Current stage/contact: ${owner}.`,`Current stage/kontakon: ${owner}.`,`Kasalukuyang stage/kontakin: ${owner}.`)+(reviewer?` Last recorded reviewer: ${reviewer}.`:'') : '';
    return choose(text,
      'Pending means the request is waiting for its required reviewers; it is not final permission to take leave or DTR coverage. Approved means the required approval stages are complete. Returned means corrections or more information are needed before resubmission. Contact the current reviewer or HR to clarify an urgent pending request; do not assume approval.'+tracker,
      'Pending: naghulat pa sa required reviewers; dili pa final permiso sa leave o DTR coverage. Approved: kompleto na ang approvals. Returned: kinahanglan correction o dugang detalye sa dili pa resubmit. Kontaka ang current reviewer o HR kung urgent; ayaw pag-assume nga approved.'+tracker,
      'Pending: naghihintay pa sa required reviewers; hindi pa final na pahintulot sa leave o DTR coverage. Approved: kumpleto na ang approvals. Returned: kailangan ng correction o dagdag na detalye bago muling isumite. Kontakin ang current reviewer o HR kung urgent; huwag ipagpalagay na approved.'+tracker);
  }
  if(intent==='leave_type_selection') {
    const types=(context.leave_types||[]).filter(t=>t.employee_can_file!==false&&!t.admin_only);
    return choose(text,'What is the actual circumstance—your illness, an affected family member, a declared calamity, or another personal obligation? I can help compare the configured types, but cannot assume eligibility. Prepare your actual dates, working days, brief factual reason, relationship/circumstances relevant to eligibility, and the selected type’s required custom details and supporting documents; do not invent medical details or obtain unrelated documents. We should check its balance/quota and advance-notice rules before filing. Available configured types: ',
      'Unsa ang tinuod nga circumstance—imong sakit, family member, declared calamity o personal obligation? Dili ta mo-assume sa eligibility. Andama ang petsa, working days, mubo nga tinuod nga rason, relasyon/circumstances, ug required custom details ug supporting documents sa napiling type. I-check una ang balance/quota ug advance notice; ayaw pag-invent ug medical details. Available types: ',
      'Ano ang totoong sitwasyon—sariling sakit, family member, declared calamity o personal na obligasyon? Hindi natin ipagpapalagay ang eligibility. Ihanda ang petsa, working days, maikling totoong dahilan, relasyon/circumstances, at required custom details at supporting documents ng napiling type. Suriin muna ang balance/quota at advance notice; huwag mag-imbento ng medical details. Available types: ')+types.map(t=>t.display_name||t.name).join(', ');
  }
  if(intent==='leave_annual_remaining') {
    const type=configuredLeaveType(text,context.leave_types);
    const rows=(context.annual_entitlements||[]).filter(r=>!type||r.leave_type===type.name);
    if(!rows.length)return choose(text,'I cannot verify an annual entitlement for that type from the loaded records. Name the type, or check My Leave → Annual Leave Entitlements. I will not infer remaining days from a per-request limit.',
      'Dili nako ma-verify ang annual entitlement niini. Ihatag ang type o tan-awa ang My Leave → Annual Leave Entitlements.',
      'Hindi ko ma-verify ang annual entitlement nito. Ibigay ang type o tingnan ang My Leave → Annual Leave Entitlements.');
    return choose(text,'Annual leave entitlement','Annual leave entitlement nimo','Annual leave entitlement mo')+'\n'+rows.map(r=>{
      const label=(context.leave_types||[]).find(t=>t.name===r.leave_type)?.display_name||r.leave_type;
      return `${label} (${r.year}): ${r.error ? `Unable to verify: ${r.error}` : `${r.limit_days} entitled, ${r.approved_days} approved, ${r.pending_days} pending, ${r.remaining_days} days available`}.`;
    }).join('\n');
  }
  if(intent==='dtr_undertime_reason') {
    const rows=context.dtr_records||[];
    return choose(text,'Recorded undertime explanation','Pasabot sa na-record nga undertime','Paliwanag sa naitalang undertime')+'\n'+rows.map(r=>`${r.attendance_date}: ${Number(r.undertime_minutes)||0} minutes. AM out: ${punchTime(r.break_out)}, PM in: ${punchTime(r.break_in)}, PM out: ${punchTime(r.time_out)}.`).join('\n')+'\n'+choose(text,
      'A late final time-out alone does not prove that every shift segment was complete: break timing and the configured schedule can affect the saved total. The exact calculation trace is not stored in this chat context, so I cannot prove which rule produced these minutes. Ask HR to review the actual punches and assigned shift; I will not invent a missing punch.',
      'Dili igo ang late time-out aron mapamatud-an nga kompleto ang tanang segment. Makaapekto ang break ug shift rules. Wala dinhi ang exact calculation trace; ipa-review sa HR ang actual punches ug shift.',
      'Hindi sapat ang late time-out para patunayang kumpleto ang lahat ng segment. Maaaring makaapekto ang break at shift rules. Wala rito ang exact calculation trace; ipa-review sa HR ang actual punches at shift.');
  }
  if(intent==='locator_policy_guidance') {
    const kind=locatorPolicyKind(text);
    if(['slots','inactive','coverage','conflict'].includes(kind)) {
      const rules={
        slots:['Choose only the actual slots the locator should cover (AM in, AM out, PM in, PM out); one or several can be selected when allowed by its configured coverage mode. Uncovered actual biometric punches remain unchanged. Full-day coverage is assessed against your assigned shift.', 'Pilia ra ang sakto nga slots nga sakop; usa o daghan depende sa type coverage mode. Ang actual punches sa ubang slots dili mausab. I-check ang full coverage batok sa shift.', 'Piliin lang ang tamang sakop na slots; isa o marami depende sa coverage mode. Hindi binabago ang actual punches sa ibang slots. Nakabatay sa shift ang full coverage.'],
        inactive:['Rejected, cancelled or revoked locators do not provide approved DTR slot coverage. Your actual punches and other valid approved coverage still apply. A pending slip also does not provide final coverage.', 'Ang rejected, cancelled o revoked locator walay approved DTR coverage. Ang actual punches ug laing valid approvals maoy basehan. Dili sab final coverage ang pending.', 'Walang approved DTR coverage ang rejected, cancelled o revoked locator. Basehan pa rin ang actual punches at ibang valid approvals. Hindi rin final coverage ang pending.'],
        coverage:['Approved locator coverage can satisfy the required slots even without biometric punches. It applies only to the saved date and approved slots; partial coverage does not complete the whole shift. Tell me the date to check the actual record.', 'Ang approved locator makasatisfy sa required slots bisan walay biometric punch, pero sa saved date ug approved slots ra. Dili whole-shift coverage ang partial. Ihatag ang petsa para ma-check.', 'Maaaring masatisfy ng approved locator ang required slots kahit walang biometric punch, pero para lang sa saved date at approved slots. Hindi buong shift ang partial coverage. Ibigay ang petsa para ma-check.'],
        conflict:['Do not double-count an approved leave and locator on the same date. Give the date and request references so HR can review the overlap and correct the applicable records. Chat cannot choose or revoke an approval for you.', 'Ayaw i-double count ang leave ug locator sa usa ka petsa. Ihatag sa HR ang date ug references aron ma-review ang overlap ug records. Dili nako pilion o i-revoke ang approval dinhi.', 'Huwag i-double count ang leave at locator sa isang petsa. Ibigay sa HR ang date at references para ma-review ang overlap at records. Hindi ako pumipili o nagre-revoke ng approval rito.'],
      };
      return choose(text,...rules[kind]);
    }
  }
  if(intent==='dtr_locator_coverage_check' && !/\b(?:am in|am out|pm in|pm out)\b/i.test(text)) {
    const date=context.date_range?.startDate;
    const type=configuredLocatorType(text,context.locator_types);
    const matches=(context.recent_locator_slips||[]).filter(r=>r.slip_date===date&&(!type||r.request_type===type.code));
    const coverage=coverageForDate({...context,recent_locator_slips:matches},date);
    return `Locator coverage — ${date}\n`+(matches.length?matches.map(r=>`${r.request_type_label||r.request_type}: ${r.status}`).join('\n'):'No matching locator for that date.')+
      `\nApproved slots: ${coverage.coveredSlots.map(s=>s.replace('_',' ').replace(/^(am|pm)/,m=>m.toUpperCase())).join(', ')||'none'}. Required shift slots: ${coverage.expectedSlots.join(', ')||'not available'}.\n`+
      (coverage.expectedSlots.length?(coverage.isFullCoverage?'Approved coverage fully satisfies the assigned shift.':'No approved coverage fully satisfies the assigned shift.'):'No full-shift conclusion is possible without the date’s schedule.');
  }
  if(intent==='dtr_leave_coverage_check') {
    const range=context.date_range;
    const rows=(context.recent_leave_requests||[]).filter(r=>r.status==='approved'&&r.start_date<=range.endDate&&r.end_date>=range.startDate);
    return choose(text,'Approved leave coverage','Approved leave coverage nimo','Approved leave coverage mo')+` — ${range.startDate} to ${range.endDate}\n`+
      (rows.length?rows.map(r=>`${r.leave_type}: ${r.start_date} to ${r.end_date}. Approved dates can be recorded as on leave after posting; this is leave coverage rather than biometric work punches.`).join('\n'):'No approved leave covers this date range. Pending requests are not approved attendance coverage.');
  }
  return null;
}
module.exports={questionReply,choose};
