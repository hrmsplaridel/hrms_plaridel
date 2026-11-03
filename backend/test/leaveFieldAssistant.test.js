const test = require('node:test');
const assert = require('node:assert/strict');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');

test('leave field help uses live configuration and drafts only on request', async (t) => {
  const calls = [];
  let output = JSON.stringify({ draft: 'I would like to attend my mother’s birthday celebration in Cebu.' });
  const restore = withMockedModule('../src/services/llm/llmClient', {
    chatCompletion: async (options) => {
      calls.push(options);
      if (output instanceof Error) throw output;
      return { content: output };
    },
  });
  clearModule('../src/services/dtrAssistant/leaveFieldAssistant');
  const { assistLeaveField } = require('../src/services/dtrAssistant/leaveFieldAssistant');
  t.after(() => {
    restore();
    clearModule('../src/services/dtrAssistant/leaveFieldAssistant');
  });
  const queries = [];
  const pool = { query: async (sql, params) => {
    queries.push({ sql, params });
    return { rows: [{ name: 'newLeave', display_name: 'New Leave', employee_detail_schema: [
      { key: 'activity', label: 'Activity details', type: 'long_text', required: true, max_length: 200,
        instruction: 'State your actual destination and purpose.',
        example: 'Visit the sample office to submit sample documents.',
        sentence_template: 'I am requesting permission to visit [office] to [purpose].' },
      { key: 'category', label: 'Category', type: 'select', options: ['Local', 'Overseas'] },
    ] }] };
  } };
  const form = { leaveType: 'newLeave', fieldKey: 'activity', task: 'explain' };
  const help = await assistLeaveField(pool, form);
  assert.match(help.content, /New Leave.*Activity details/);
  assert.match(help.content, /Required field.*200 characters/);
  assert.match(help.content, /Example template/);
  assert.match(help.content, /State your actual destination and purpose/);
  assert.match(help.content, /Sentence template: I am requesting permission/);
  assert.equal(calls.length, 0);
  assert.deepEqual(queries[0].params, ['newLeave']);
  assert.match(queries[0].sql, /employee_can_file IS NOT FALSE/);
  const empty = await assistLeaveField(pool, { ...form, task: 'draft' });
  assert.match(empty.content, /Tell me the actual details/);
  assert.equal(calls.length, 0);
  const draft = await assistLeaveField(pool, { ...form, task: 'draft', facts: 'mother birthday Cebu' });
  assert.equal(draft.actions[0].payload.fieldKey, 'activity');
  assert.equal(draft.actions[0].payload.leaveType, 'newLeave');
  assert.equal(calls[0].provider, 'ollama');
  assert.equal(JSON.parse(calls[0].messages[1].content).facts, 'mother birthday Cebu');
  assert.equal(JSON.parse(calls[0].messages[1].content).example, 'Visit the sample office to submit sample documents.');
  assert.equal(draft.actions[0].autoExecute, undefined);
  const choice = await assistLeaveField(pool, { ...form, fieldKey: 'category', task: 'draft', facts: 'Local' });
  assert.match(choice.content, /Local, Overseas/);
  assert.deepEqual(choice.actions, []);
  assert.equal(calls.length, 1);
  await assert.rejects(assistLeaveField(pool, { ...form, fieldKey: 'deletedField' }), /no longer configured/);
  await assert.rejects(assistLeaveField({ query: async () => ({ rows: [] }) }, form), /no longer available/);
  output = JSON.stringify({ draft: 'x'.repeat(201) });
  assert.deepEqual((await assistLeaveField(pool, { ...form, task: 'draft', facts: 'actual details' })).actions, []);
  output = new Error('offline');
  const offline = await assistLeaveField(pool, { ...form, task: 'draft', facts: 'actual details' });
  assert.match(offline.content, /actual purpose or details/);
  assert.deepEqual(offline.actions, []);
  output = JSON.stringify({ draft: null, question: 'What activity are you attending?' });
  assert.match((await assistLeaveField(pool, { ...form, task: 'draft', facts: 'help me' })).content, /actual purpose or details/);
  output = JSON.stringify({ draft: 'I am visiting the treasury to submit reports.' });
  const locatorForm = { module: 'locator', locatorType: 'newLeave', fieldKey: 'activity', task: 'draft', facts: 'treasury submit reports' };
  const locatorDraft = await assistLeaveField(pool, locatorForm);
  assert.match(queries.at(-1).sql, /FROM locator_request_types/);
  assert.match(queries.at(-1).sql, /filing_access/);
  assert.deepEqual(locatorDraft.actions[0].payload, { module: 'locator', locatorType: 'newLeave', fieldKey: 'activity', value: 'My purpose: treasury submit reports.' });
  assert.equal(JSON.parse(calls.at(-1).messages[1].content).module, 'locator');
  output = JSON.stringify({ draft: 'I am visiting [office].' });
  assert.equal((await assistLeaveField(pool, locatorForm)).actions[0].payload.value, 'My purpose: treasury submit reports.');
  await assert.rejects(assistLeaveField(pool, { ...locatorForm, module: 'invalid' }), /Select a request type/);
});
