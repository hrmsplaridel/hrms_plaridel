const test = require('node:test');
const assert = require('node:assert/strict');
const { formChatContext } = require('../src/services/dtrAssistant/dtrAssistantRequestFocus');
const { loadEmployeeAssistantContext } = require('../src/services/dtrAssistant/dtrAssistantDataService');
test('active field routes help and drafting without hijacking status questions', () => {
 const form = {module:'locator',locatorType:'visit',fieldKey:'reason',task:'chat',bindingId:'one',facts:'submit reports'};
 assert.equal(formChatContext(form, 'What do I put here?', null).task,'explain');
 assert.equal(formChatContext(form, 'Draft a sentence', null).task,'draft');
 const memory = {formFocus:{module:'locator',type:'visit',key:'reason',bindingId:'one'}};
 assert.match(formChatContext(form, 'Treasury office', memory).facts,/Treasury/);
 assert.equal(formChatContext(form, 'Is it approved?', memory),null);
 assert.equal(formChatContext({...form,bindingId:'new'}, 'Treasury office', memory),null);
});
test('selected request queries keep employee ownership and filter by ID', async () => {
 for (const module of ['leave','locator']) {
  const calls=[];
  const pool={query:async (query,params)=>{calls.push({sql:query.text||query,params:query.values||params});return {rows:[]};}};
  await loadEmployeeAssistantContext(pool,{userId:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',message:'Is it approved?',intents:[module==='leave'?'latest_leave_request':'locator_status'],requestReference:{module,id:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'}});
  const query=calls.find(c=>c.sql.includes(module==='leave'?'FROM leave_requests lr':'FROM locator_slips ls'));
  assert.match(query.sql,/AND (lr|ls)\.id = \$4::uuid/);
  assert.match(query.sql,/employee_id = \$1::uuid/);
  assert.equal(query.params[0],'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  assert.equal(query.params[3],'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
 }
});
