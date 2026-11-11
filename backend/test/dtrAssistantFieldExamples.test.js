const test = require('node:test');
const assert = require('node:assert/strict');
const { assistLeaveField } = require('../src/services/dtrAssistant/leaveFieldAssistant');
const { getLeaveFormFieldGuidance } = require('../src/services/dtrAssistant/leaveFilingGuidelines');
const { getLocatorFormFieldGuidance } = require('../src/services/dtrAssistant/locatorFilingGuidelines');

const leaves = [
  ['vacationLeave', 'Vacation Leave', /family|pamilya/],
  ['mandatoryForcedLeave', 'Mandatory/Forced Leave', /mandatory leave/],
  ['sickLeave', 'Sick Leave', /illness|gibati|karamdaman/],
  ['maternityLeave', 'Maternity Leave', /childbirth|pagpanganak|panganganak/],
  ['paternityLeave', 'Paternity Leave', /spouse|asawa/],
  ['specialPrivilegeLeave', 'Special Privilege Leave', /occasion|okasyon/],
  ['soloParentLeave', 'Solo Parent Leave', /school|eskwelahan|paaralan/],
  ['studyLeave', 'Study Leave', /board examination/],
  ['tenDayVawcLeave', '10-Day VAWC Leave', /case|kaso/],
  ['rehabilitationPrivilege', 'Rehabilitation Privilege', /injury|kadaot|pinsala/],
  ['specialLeaveBenefitsForWomen', 'Special Leave Benefits for Women', /gynecological procedure/],
  ['specialEmergencyCalamityLeave', 'Special Emergency/Calamity Leave', /calamity|kalamidad/],
  ['adoptionLeave', 'Adoption Leave', /adopted|gisagop|inampon/],
  ['others', 'Others', /personal/],
];
const languages = ['english', 'bisaya', 'tagalog'];
const sentencePrefix = { english: /^I (?:would like|am requesting)/, bisaya: /^(?:Mangayo|Mogamit)/, tagalog: /^(?:Humihiling|Nais)/ };

test('examples with supplied facts remain personal drafting requests', () => {
  const { isExampleOnlyRequest, isWritingRequest } = require('../src/services/dtrAssistant/dtrAssistantQuestion');
  const message = 'Give me an example reason using these facts: attend a project meeting.';
  assert.equal(isExampleOnlyRequest(message), false);
  assert.equal(isWritingRequest(message), true);
});

for (const [name, display_name, relevant] of leaves) {
  for (const language of languages) {
    test(`${display_name}: reason examples are relevant complete sentences in ${language}`, async () => {
      const row = { name, display_name };
      const guidance = getLeaveFormFieldGuidance('reason field', row, language);
      assert.ok(guidance.examples.length > 0);
      assert.match(guidance.examples[0], relevant);
      assert.match(guidance.examples[0], sentencePrefix[language]);
      const result = await assistLeaveField({ query: async () => ({ rows: [row] }) }, {
        leaveType: name, fieldKey: 'reason', task: 'help', language,
      });
      assert.ok(result.content.includes(guidance.examples[0]));
      assert.doesNotMatch(result.content, /\[[^\]]+\]|already approved|doctor has advised|\b\d{4}-\d{2}-\d{2}\b/i);
      assert.deepEqual(result.actions, []);
      assert.equal(result.draft, undefined);
    });
  }
}

for (const code of ['locator', 'work_from_home', 'pass_slip']) {
  for (const language of languages) {
    for (const fieldKey of ['reason', 'office']) {
      test(`${code}: ${fieldKey} examples are localized in ${language}`, async () => {
        const row = { name: code, display_name: code, location_label: 'Destination' };
        const examples = getLocatorFormFieldGuidance(fieldKey === 'office' ? 'destination field' : 'reason field', code, language).examples;
        assert.ok(examples.length > 0);
        if (fieldKey === 'reason') assert.match(examples[0], sentencePrefix[language]);
        const reply = await assistLeaveField({ query: async () => ({ rows: [row] }) }, {
          module: 'locator', locatorType: code, fieldKey, language, task: 'help',
        });
        assert.ok(reply.content.includes(examples[0]));
        assert.doesNotMatch(reply.content, /\[[^\]]+\]|approved office arrangement|\b2 hours\b/i);
        assert.deepEqual(reply.actions, []);
      });
    }
  }
}

for (const language of languages) {
  test(`purpose-labelled locator field explains activity rather than a destination in ${language}`, async () => {
    const row = { name: 'locator', display_name: 'Official Business', location_label: 'Purpose / Activity' };
    const result = await assistLeaveField({ query: async () => ({ rows: [row] }) }, {
      module: 'locator', locatorType: 'locator', fieldKey: 'office', language,
    });
    assert.match(result.content, /activity|Aktibidad/i);
    assert.ok(result.content.includes(getLocatorFormFieldGuidance('reason field', 'locator', language).examples[0]));
  });
}

test('unknown types do not borrow a built-in purpose, even from their descriptions', async () => {
  for (const module of ['leave', 'locator']) {
    const row = { name: 'newCommunityType', display_name: 'Community Request', description: 'Vacation Leave' };
    assert.deepEqual(module === 'leave'
      ? getLeaveFormFieldGuidance('reason field', row).examples
      : getLocatorFormFieldGuidance('reason field', row.name).examples, []);
    for (const language of languages) {
      const result = await assistLeaveField({ query: async () => ({ rows: [row] }) }, {
        module, leaveType: row.name, locatorType: row.name, fieldKey: 'reason', language,
      });
      assert.match(result.content, /actual purpose or details|imong tuyo o detalye|layunin o detalye/);
      assert.doesNotMatch(result.content, /\[your actual purpose\]|coordination meeting|board examination|gynecological/i);
      assert.deepEqual(result.actions, []);
    }
  }
});

test('new leave and locator custom fields follow live examples, instructions, templates and choices', async () => {
  for (const module of ['leave', 'locator']) {
    const row = { name: 'newCommunityType', display_name: 'Community Request', employee_detail_schema: [
      { key: 'activity', label: 'Community activity', type: 'long_text', required: true, max_length: 180,
        instruction: 'Describe your planned community activity.', example: 'I will attend a community clean-up.',
        sentence_template: 'I will attend [activity] at [venue].' },
      { key: 'category', label: 'Category', type: 'select', options: ['Volunteer', 'Training'] },
      { key: 'unexplained', label: 'Project information', type: 'text' },
    ] };
    const pool = { query: async () => ({ rows: [row] }) };
    for (const language of languages) {
      const form = { module, leaveType: row.name, locatorType: row.name, language };
      const result = await assistLeaveField(pool, { ...form, fieldKey: 'activity' });
      assert.match(result.content, /planned community activity/);
      assert.match(result.content, /I will attend a community clean-up/);
      assert.match(result.content, /I will attend \[activity\] at \[venue\]/);
      assert.match(result.content, /180 characters/);
      assert.doesNotMatch(result.content, /coordination meeting|vacation leave to spend/i);
      const options = await assistLeaveField(pool, { ...form, fieldKey: 'category' });
      assert.match(options.content, /Volunteer, Training/);
      const missing = await assistLeaveField(pool, { ...form, fieldKey: 'unexplained' });
      assert.match(missing.content, /actual purpose or details|imong tuyo o detalye|layunin o detalye/);
      assert.doesNotMatch(missing.content, /No example is configured|naka-configure/);
      assert.doesNotMatch(missing.content, /\[Your factual information\]/);
    }
  }
});

test('full chat pipeline returns examples across every leave and locator type in three languages', async (t) => {
  const { clearModule, withMockedModule } = require('./helpers/moduleMocks');
  let current;
  const restoreData = withMockedModule('../src/services/dtrAssistant/dtrAssistantDataService', {
    loadEmployeeAssistantContext: async (_pool, { userId, dateRange }) => ({
      scope: 'employee_self', date_range: dateRange,
      employee: { id: userId, role: 'employee', full_name: 'Example Tester' },
      leave_types: current.module === 'leave' ? [current.row] : [],
      locator_types: current.module === 'locator' ? [current.row] : [],
      leave_balances: [], recent_leave_requests: [], recent_locator_slips: [],
      dtr_records: [], dtr_calendar_days: [], dtr_policies: [], locator_policies: [],
    }),
  });
  const restoreLlm = withMockedModule('../src/services/llm/llmClient', {
    chatCompletion: async () => { throw new Error('Examples must not depend on an AI provider'); },
  });
  clearModule('../src/services/dtrAssistant/dtrAssistantService');
  clearModule('../src/services/dtrAssistant/leaveFieldAssistant');
  const { chatWithDtrAssistant } = require('../src/services/dtrAssistant/dtrAssistantService');
  t.after(() => {
    clearModule('../src/services/dtrAssistant/dtrAssistantService');
    clearModule('../src/services/dtrAssistant/leaveFieldAssistant');
    restoreData(); restoreLlm();
  });
  const pool = { query: async () => ({ rows: [current.row] }) };
  const cases = leaves.map(([name, display_name]) => ({ module: 'leave', row: { name, display_name, is_active: true }, field: 'reason' }));
  for (const [code, label] of [['locator', 'Official Business'], ['work_from_home', 'Work From Home'], ['pass_slip', 'Pass Slip']]) {
    for (const field of ['reason', 'office']) cases.push({ module: 'locator', row: { code, name: code, label, display_name: label, is_active: true }, field });
  }
  for (const module of ['leave', 'locator']) cases.push({ module, field: 'activity', row: {
    name: 'newCommunityType', code: 'newCommunityType', display_name: 'Community Service Request', label: 'Community Service Request', is_active: true,
    employee_detail_schema: [{ key: 'activity', label: 'Community activity', type: 'long_text',
      instruction: 'Describe the community activity.', example: 'I will join the community clean-up.' }],
  } });
  let checked = 0;
  for (const scenario of cases) {
    current = scenario;
    for (const language of languages) {
      const typeName = `${scenario.row.display_name}${scenario.module === 'locator' ? ' locator' : ''}`;
      const fieldName = scenario.field === 'office' ? 'destination' : scenario.field;
      const message = language === 'bisaya'
        ? `Sa ${fieldName} field sa ${typeName}, unsay ibutang? Hatagi kog example.`
        : language === 'tagalog'
          ? `Ano ilalagay sa ${fieldName} field ng ${typeName}? Bigyan mo ako ng halimbawa.`
          : `Give me an example for the ${fieldName} field of ${typeName}.`;
      const expected = scenario.field === 'activity' ? 'I will join the community clean-up.'
        : scenario.module === 'leave' ? getLeaveFormFieldGuidance('reason field', scenario.row, language).examples[0]
          : getLocatorFormFieldGuidance(scenario.field === 'office' ? 'destination field' : 'reason field', scenario.row.code, language).examples[0];
      const result = await chatWithDtrAssistant(pool, { user: { id: `all-example-${checked++}`, role: 'employee' }, message });
      assert.ok(result.message.content.includes(expected), `${message}\nActual: ${result.message.content}`);
      assert.deepEqual(result.message.actions.filter(action => action.type === 'apply_field_suggestion'), []);
    }
  }
  t.diagnostic(`Verified ${checked} full chat exchanges with the AI provider disabled.`);
});

test('personalized drafting preserves employee facts for every type when AI is offline', async (t) => {
  const { clearModule, withMockedModule } = require('./helpers/moduleMocks');
  const restore = withMockedModule('../src/services/llm/llmClient', {
    chatCompletion: async () => { throw Object.assign(new Error('offline'), { code: 'AI_LOCAL_UNAVAILABLE' }); },
  });
  clearModule('../src/services/dtrAssistant/leaveFieldAssistant');
  const { assistLeaveField: offlineAssist } = require('../src/services/dtrAssistant/leaveFieldAssistant');
  t.mock.method(console, 'warn', () => {});
  t.after(() => { clearModule('../src/services/dtrAssistant/leaveFieldAssistant'); restore(); });
  const rows = leaves.map(([name, display_name]) => ({ module: 'leave', name, display_name }));
  for (const code of ['locator', 'pass_slip', 'work_from_home']) rows.push({ module: 'locator', name: code, display_name: code });
  for (const module of ['leave', 'locator']) rows.push({ module, name: 'newCommunityType', display_name: 'Community Request' });
  let checked = 0;
  for (const row of rows) for (const language of languages) {
    const reply = await offlineAssist({ query: async () => ({ rows: [row] }) }, {
      module: row.module, leaveType: row.name, locatorType: row.name, fieldKey: 'reason', task: 'draft',
      facts: 'I need time to attend an appointment.', language,
    });
    assert.match(reply.draft, /appointment/);
    assert.doesNotMatch(reply.draft, /diagnos|fever|board examination|approved|coordination meeting|\d{4}-\d{2}-\d{2}/i);
    assert.equal(reply.actions[0].payload.value, reply.draft);
    assert.equal(reply.actions[0].payload[row.module === 'leave' ? 'leaveType' : 'locatorType'], row.name);
    checked++;
  }
  t.diagnostic(`Verified ${checked} drafts preserve supplied facts without borrowing sample purposes.`);
});
