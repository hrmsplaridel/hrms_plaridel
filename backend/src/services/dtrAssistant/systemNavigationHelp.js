const { detectAssistantLanguage } = require('./dtrAssistantLanguage');
const { systemHelpTopic, asksForeignEmployeeData } = require('./dtrAssistantQuestion');

function systemNavigationHelp(text) {
  const language = detectAssistantLanguage(text);
  const index = language === 'bisaya' ? 1 : language === 'tagalog' ? 2 : 0;
  if (asksForeignEmployeeData(text)) return [
    'I can check only your own employee records in this chat. I cannot show another employee’s attendance, leave balance, or salary. Ask the authorized HR/Admin team through the appropriate system workflow.',
    'Imong kaugalingong employee records ra ang akong ma-check dinhi. Dili nako ipakita ang attendance, leave balance o sweldo sa laing employee. Kontaka ang authorized HR/Admin pinaagi sa sakto nga workflow.',
    'Sarili mong employee records lang ang maaari kong tingnan sa chat. Hindi ko maipapakita ang attendance, leave balance o sahod ng ibang empleyado. Kontakin ang authorized HR/Admin sa tamang workflow.',
  ][index];
  const topic = systemHelpTopic(text);
  const messages = {
    documents: [
      'Open DocuTracker from the sidebar, find your document in your document list, and open it to inspect its current status, routing/tracking history and pending action. Use its document reference to distinguish similar records. I can explain the steps here; live DocuTracker record lookup is not connected to this chat yet.',
      'Ablihi ang DocuTracker sa sidebar, pangitaa ang imong document ug ablihi para makita ang status, routing/tracking history ug pending action. Gamita ang document reference para dili masayop sa record. Wala pa ma-connect ang live DocuTracker lookup sa chat.',
      'Buksan ang DocuTracker sa sidebar, hanapin ang dokumento mo at buksan ito para makita ang status, routing/tracking history at pending action. Gamitin ang document reference para matukoy ang tamang record. Hindi pa konektado ang live DocuTracker lookup sa chat.',
    ],
    training: [
      'Open Training Reports in the sidebar to create or view your report. Complete the report fields shown there, add required supporting files, review the entries, then use that feature’s submit action. Training Requirements is a separate menu for requirements. I cannot submit or read live training-report records through this chat yet.',
      'Ablihi ang Training Reports sa sidebar para maghimo o motan-aw sa report. Kompletoha ang fields ug required files, i-review ug gamita ang submit action didto. Lahi ang Training Requirements nga menu. Dili pa nako ma-submit o ma-lookup ang live training reports pinaagi sa chat.',
      'Buksan ang Training Reports sa sidebar para gumawa o tumingin ng report. Kumpletuhin ang fields at required files, suriin at gamitin ang submit action doon. Hiwalay ang Training Requirements na menu. Hindi pa ako makapagsumite o makapag-lookup ng live training reports sa chat.',
    ],
    profile: [
      'Select your name/avatar to open your profile. Edit the account fields available there and save the changes. For locked employment or personal-record fields, contact HR/Admin. I cannot change your profile through chat.',
      'Pilia ang imong ngalan/avatar para ma-open ang profile. Usba ang account fields nga editable ug i-save. Para sa locked employment o personal-record fields, kontaka ang HR/Admin. Dili nako usbon ang profile pinaagi sa chat.',
      'Piliin ang pangalan/avatar mo para buksan ang profile. Baguhin ang editable account fields at i-save. Para sa locked employment o personal-record fields, kontakin ang HR/Admin. Hindi ko binabago ang profile sa chat.',
    ],
    password: [
      'Open your profile or Settings and use the password/security section to change or request a reset of your password. If you cannot sign in, use the password-reset assistance on the sign-in page or contact your administrator. Do not send passwords or reset codes in chat.',
      'Ablihi ang profile o Settings ug gamita ang password/security section para mag-ilis o mangayo ug password reset. Kung dili maka-sign in, gamita ang password-reset assistance sa sign-in page o kontaka ang administrator. Ayaw ipadala ang password o reset code sa chat.',
      'Buksan ang profile o Settings at gamitin ang password/security section para magpalit o humiling ng password reset. Kung hindi makapag-sign in, gamitin ang password-reset assistance sa sign-in page o kontakin ang administrator. Huwag ipadala ang password o reset code sa chat.',
    ],
    capabilities: [
      'I can check your attendance, missing logs, schedule, leave balances and requests, locator status and coverage, filing requirements, and DTR exports. I can explain fields, suggest wording from your facts, and review an open leave/locator form. I can also guide you to Profile, DocuTracker and Training Reports; live data lookup for those modules is not connected yet.',
      'Makatabang ko sa imong attendance, missing logs, schedule, leave balances/requests, locator status/coverage, filing requirements ug DTR exports. Pwede ko mo-explain sa fields, mosugyot ug sentence base sa imong facts ug mo-review sa open leave/locator form. Makagiya sab ko sa Profile, DocuTracker ug Training Reports, pero wala pa ang live lookup ana nga modules.',
      'Makakatulong ako sa attendance, missing logs, schedule, leave balances/requests, locator status/coverage, filing requirements at DTR exports mo. Maaari akong magpaliwanag ng fields, magmungkahi ng sentence mula sa facts mo at mag-review ng open leave/locator form. Maaari rin kitang gabayan sa Profile, DocuTracker at Training Reports; hindi pa konektado ang live lookup ng mga module na iyon.',
    ],
  };
  const reply=messages[topic]?.[index];
  if(topic==='capabilities')return reply+' '+[
    'Record lookups are limited to your own employee account. My chat actions provide navigation, downloads, suggestions and review; I cannot submit, approve, cancel, or edit HR records or attendance punches.',
    'Imong kaugalingong employee account ra ang records nga ma-lookup. Navigation, downloads, suggestions ug review ra ang chat actions; dili ko maka-submit, approve, cancel o edit sa HR records/punches.',
    'Sarili mong employee account lang ang records na maaaring tingnan. Navigation, downloads, suggestions at review lang ang chat actions; hindi ako nagsusumite, nag-aapruba, nagkakansela o nag-eedit ng HR records/punches.',
  ][index];
  return reply || null;
}

module.exports = { systemNavigationHelp };
