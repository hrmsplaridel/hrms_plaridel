// Hypothetical examples, never employee facts or statements of eligibility.
// Unknown configured types deliberately have no borrowed built-in example.
const leaveReasons = {
  vacationLeave: [
    ['I would like to request vacation leave to spend time with my family.', 'I would like to request vacation leave for personal rest.'],
    ['Mangayo ko og vacation leave aron makagahin og panahon uban sa akong pamilya.', 'Mangayo ko og vacation leave aron makapahulay.'],
    ['Humihiling ako ng vacation leave upang makasama ang aking pamilya.', 'Humihiling ako ng vacation leave para makapagpahinga.'],
  ],
  mandatoryForcedLeave: [
    ['I would like to take my mandatory leave on the dates in my leave plan.'],
    ['Mogamit ko sa akong mandatory leave sa mga petsa sa akong leave plan.'],
    ['Nais kong gamitin ang aking mandatory leave sa mga petsang nasa aking leave plan.'],
  ],
  sickLeave: [
    ['I would like to request sick leave to rest and recover from illness.', 'I would like to request sick leave to attend a medical consultation.'],
    ['Mangayo ko og sick leave aron makapahulay ug makaayo gikan sa akong gibati.', 'Mangayo ko og sick leave aron makapakonsulta bahin sa akong gibati.'],
    ['Humihiling ako ng sick leave upang makapagpahinga at gumaling mula sa aking karamdaman.', 'Humihiling ako ng sick leave upang makapagpakonsulta tungkol sa aking karamdaman.'],
  ],
  maternityLeave: [
    ['I would like to request maternity leave for childbirth and recovery.'],
    ['Mangayo ko og maternity leave alang sa pagpanganak ug pagpahiuli sa akong kusog.'],
    ['Humihiling ako ng maternity leave para sa panganganak at pagpapagaling.'],
  ],
  paternityLeave: [
    ['I would like to request paternity leave to support my spouse following childbirth.'],
    ['Mangayo ko og paternity leave aron maatiman ang akong asawa human sa pagpanganak.'],
    ['Humihiling ako ng paternity leave upang maalalayan ang aking asawa pagkatapos manganak.'],
  ],
  specialPrivilegeLeave: [
    ['I would like to request special privilege leave to attend a family occasion.'],
    ['Mangayo ko og special privilege leave aron makatambong sa okasyon sa among pamilya.'],
    ['Humihiling ako ng special privilege leave upang makadalo sa isang okasyon ng aming pamilya.'],
  ],
  soloParentLeave: [
    ['I would like to request solo parent leave to attend my child\'s school meeting.'],
    ['Mangayo ko og solo parent leave aron makatambong sa meeting sa eskwelahan sa akong anak.'],
    ['Humihiling ako ng solo parent leave upang makadalo sa pulong sa paaralan ng aking anak.'],
  ],
  studyLeave: [
    ['I would like to request study leave to prepare for my board examination.'],
    ['Mangayo ko og study leave aron makaandam alang sa akong board examination.'],
    ['Humihiling ako ng study leave upang makapaghanda para sa aking board examination.'],
  ],
  tenDayVawcLeave: [
    ['I would like to request VAWC leave to attend to matters related to my case.'],
    ['Mangayo ko og VAWC leave aron maasikaso ang mga butang nga may kalabotan sa akong kaso.'],
    ['Humihiling ako ng VAWC leave upang maasikaso ang mga bagay na may kaugnayan sa aking kaso.'],
  ],
  rehabilitationPrivilege: [
    ['I would like to request rehabilitation leave for treatment and recovery from a work-related injury.'],
    ['Mangayo ko og rehabilitation leave alang sa pagtambal ug pagpaayo sa kadaot nga may kalabotan sa trabaho.'],
    ['Humihiling ako ng rehabilitation leave para sa paggamot at paggaling mula sa pinsalang may kaugnayan sa trabaho.'],
  ],
  specialLeaveBenefitsForWomen: [
    ['I would like to request special leave benefits for women for recovery following a gynecological procedure.'],
    ['Mangayo ko og special leave benefits for women alang sa pagpaayo human sa gynecological procedure.'],
    ['Humihiling ako ng special leave benefits for women para sa pagpapagaling matapos ang gynecological procedure.'],
  ],
  specialEmergencyCalamityLeave: [
    ['I would like to request calamity leave to attend to my family and home affected by the calamity.'],
    ['Mangayo ko og calamity leave aron maatiman ang akong pamilya ug balay nga naapektuhan sa kalamidad.'],
    ['Humihiling ako ng calamity leave upang maasikaso ang aking pamilya at tahanang naapektuhan ng kalamidad.'],
  ],
  adoptionLeave: [
    ['I would like to request adoption leave to attend to my adopted child\'s care and adjustment.'],
    ['Mangayo ko og adoption leave aron maatiman ang akong gisagop nga anak samtang nag-adjust siya.'],
    ['Humihiling ako ng adoption leave upang maalagaan at matulungang makapag-adjust ang aking inampon na anak.'],
  ],
  others: [
    ['I would like to request leave to attend to a personal matter.'],
    ['Mangayo ko og leave aron maasikaso ang usa ka personal nga butang.'],
    ['Humihiling ako ng leave upang maasikaso ang isang personal na bagay.'],
  ],
};

const locatorReasons = {
  locator: [
    ['I am requesting permission to attend a coordination meeting at the municipal office.', 'I am requesting permission to submit work documents to the provincial office.'],
    ['Mangayo ko og permiso aron makatambong sa coordination meeting sa municipal office.', 'Mangayo ko og permiso aron mosumite og mga dokumento sa trabaho sa provincial office.'],
    ['Humihiling ako ng pahintulot upang dumalo sa coordination meeting sa municipal office.', 'Humihiling ako ng pahintulot upang magsumite ng mga dokumento sa trabaho sa provincial office.'],
  ],
  work_from_home: [
    ['I am requesting to work from home to complete my assigned reports.'],
    ['Mangayo ko og permiso nga magtrabaho gikan sa balay aron mahuman ang akong gi-assign nga mga report.'],
    ['Humihiling akong magtrabaho mula sa bahay upang matapos ang mga ulat na nakatalaga sa akin.'],
  ],
  pass_slip: [
    ['I am requesting a pass slip to attend to a personal matter outside the office.'],
    ['Mangayo ko og pass slip aron maasikaso ang usa ka personal nga butang sa gawas sa opisina.'],
    ['Humihiling ako ng pass slip upang maasikaso ang isang personal na bagay sa labas ng opisina.'],
  ],
};

const locatorDestinations = {
  locator: [['Municipal Engineering Office'], ['Municipal Engineering Office'], ['Municipal Engineering Office']],
  work_from_home: [['Home work location in Poblacion'], ['Lugar sa pagtrabaho sa balay sa Poblacion'], ['Lugar ng pagtatrabaho sa bahay sa Poblacion']],
  pass_slip: [['Municipal Health Office'], ['Municipal Health Office'], ['Municipal Health Office']],
};

const fieldInputs = {
  location_details: [['Cebu City, Cebu, Philippines'], ['Cebu City, Cebu, Philippines'], ['Cebu City, Cebu, Philippines']],
  sick_illness_details: [
    ['Medical consultation for my current symptoms.'],
    ['Pagpakonsulta bahin sa mga sintomas nga akong gibati.'],
    ['Pagpapakonsulta tungkol sa aking kasalukuyang mga sintomas.'],
  ],
  women_illness_details: [
    ['Recovery following my gynecological procedure.'],
    ['Pagpaayo human sa akong gynecological procedure.'],
    ['Pagpapagaling matapos ang aking gynecological procedure.'],
  ],
  vawc_case_details: [
    ['Attendance at an appointment related to my case.'],
    ['Pagtambong sa appointment nga may kalabotan sa akong kaso.'],
    ['Pagdalo sa appointment na may kaugnayan sa aking kaso.'],
  ],
  study_purpose_details: [
    ['Preparation and review for my board examination.'],
    ['Pagpangandam ug pag-review alang sa akong board examination.'],
    ['Paghahanda at pagre-review para sa aking board examination.'],
  ],
};

function localizedExamples(catalog, key, language) {
  const variants = catalog[key];
  return variants ? [...variants[language === 'bisaya' ? 1 : language === 'tagalog' ? 2 : 0]] : [];
}

module.exports = {
  leaveReasonExamples: (key, language) => localizedExamples(leaveReasons, key, language),
  locatorReasonExamples: (key, language) => localizedExamples(locatorReasons, key, language),
  locatorDestinationExamples: (key, language) => localizedExamples(locatorDestinations, key, language),
  standardFieldExamples: (key, language) => localizedExamples(fieldInputs, key, language),
};
