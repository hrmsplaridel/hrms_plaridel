const test = require('node:test');
const assert = require('node:assert/strict');
const {withMockedModule,clearModule} = require('./helpers/moduleMocks');
const {isWritingRequest,isDraftRestyle} = require('../src/services/dtrAssistant/dtrAssistantQuestion');
const {draftSentence,groundedDraft,extractDraftFacts} = require('../src/services/dtrAssistant/sentenceDraft');
const {formChatContext}=require('../src/services/dtrAssistant/dtrAssistantRequestFocus');

test('Bisaya writing and restyling requests are instructions rather than employee facts',()=>{
  for(const text of ['tabangi kog himo sa sentence','tabangi ko paghimo sa sentence for reason in wellness leave','Mas pormal','Mas mubo']) {
    assert.equal(isWritingRequest(text),true,text);
    assert.equal(extractDraftFacts(text),'',text);
  }
  assert.equal(isDraftRestyle('Mas pormal'),true);
  assert.equal(extractDraftFacts('Mas pormal','Para makapahulay.'),'Para makapahulay.');
});

test('an active field cannot rewrite facts from a previously bound form',()=>{
  const form={module:'locator',locatorType:'travel_order',fieldKey:'office',bindingId:'new',task:'chat'};
  const memory={formFocus:{module:'locator',type:'travel_order',key:'office',bindingId:'new'},
    draftFocus:{module:'locator',type:'travel_order',fieldKey:'office',bindingId:'old',facts:'Old destination',draft:'Old destination'}};
  assert.equal(formChatContext(form,'Mas pormal',memory).facts,'');
});

test('natural multilingual rest wording is accepted while invented details remain rejected',async()=>{
  assert.equal(groundedDraft('Mangayo ko og leave aron makapahulay.','Pahulay'),true);
  assert.equal(groundedDraft('I would like to request leave to rest.','Para makapahulay.'),true);
  assert.equal(groundedDraft('I need surgery in Manila on November 15.','Pahulay'),false);
  assert.equal(groundedDraft('I will attend a meeting.','I will submit payroll documents.'),false);
  assert.equal(groundedDraft('I will attend a meeting.','I will not attend a meeting.'),false);
  assert.equal(groundedDraft('I will attend a meeting.','I will attend a meeting in Cebu.'),false);
  let options;
  const reply=await draftSentence({facts:'Pahulay',language:'bisaya',complete:async input=>{
    options=input;return {content:JSON.stringify({draft:'Mangayo ko og leave aron makapahulay.',question:null})};
  }});
  assert.equal(reply.draft,'Mangayo ko og leave aron makapahulay.');
  assert.equal(reply.fallback,false);
  assert.equal(options.format.type,'object');
  assert.equal(options.think,false,'Sentence drafting should spend its bounded token budget on the answer');
  const offline=await draftSentence({facts:'Para makapahulay.',language:'bisaya',complete:async()=>{throw new Error('offline');}});
  assert.match(offline.draft,/^Mangayo ko og leave aron makapahulay\.$/);
  const formal=await draftSentence({facts:'Para makapahulay.',language:'bisaya',instruction:'Mas pormal',complete:async()=>{throw new Error('offline');}});
  assert.notEqual(formal.draft,offline.draft);
  assert.match(formal.draft,/makapahulay/);
});

test('offline destination drafting returns the supplied destination without a reason prefix',async()=>{
  const result=await draftSentence({facts:'Municipal Treasury Office',field:'Office / Destination',module:'locator',language:'english',complete:async()=>{throw new Error('offline');}});
  assert.equal(result.draft,'Municipal Treasury Office');
});

test('a model that only echoes a short purpose uses a complete factual sentence instead',async()=>{
  const result=await draftSentence({facts:'Pahulay',language:'bisaya',complete:async()=>({content:'{"draft":"Pahulay","question":null}'})});
  assert.equal(result.draft,'Mangayo ko og leave aron makapahulay.');
  assert.equal(result.fallback,true);
});

test('polite acknowledgments and uncertainty are not drafted as personal reasons',async()=>{
  for(const facts of ['please','palihug','salamat','not sure','ambot','hmm']) {
    let called=false;
    const result=await draftSentence({facts,complete:async()=>{called=true;return {content:'{"draft":"My purpose: please."}'};}});
    assert.equal(called,false,facts);
    assert.equal(result.draft,undefined,facts);
    assert.ok(result.question,facts);
  }
});

async function harness(t) {
  const leaves=[{name:'wellness',display_name:'Wellness Leave',employee_detail_schema:[]},
    {name:'community_leave',display_name:'Community Leave',employee_detail_schema:[{key:'activity',label:'Community activity',type:'long_text',max_length:120}]}];
  const locators=[{code:'travel_order',label:'Travel Order',name:'travel_order',display_name:'Travel Order',location_label:'Destination',employee_detail_schema:[]},
    {code:'official_visit',label:'Official Visit',name:'official_visit',display_name:'Official Visit',employee_detail_schema:[{key:'activity',label:'Visit activity',type:'text',max_length:120}]}];
  const writes=[],modelCalls=[],fieldQueries=[];
  const restores=[withMockedModule('../src/services/dtrAssistant/dtrAssistantDataService',{loadEmployeeAssistantContext:async(_,options)=>({
    scope:'employee_self',employee:{id:options.userId,role:'employee'},date_range:options.dateRange,
    leave_types:leaves,locator_types:locators,leave_balances:[],recent_leave_requests:[],recent_locator_slips:[],dtr_records:[],dtr_calendar_days:[],
  })}),withMockedModule('../src/services/llm/llmClient',{chatCompletion:async options=>{
    modelCalls.push(options);throw Object.assign(new Error('offline'),{code:'AI_LOCAL_UNAVAILABLE'});
  }})];
  for(const name of ['leaveFieldAssistant','dtrAssistantService','sentenceDraft'])clearModule(`../src/services/dtrAssistant/${name}`);
  const service=require('../src/services/dtrAssistant/dtrAssistantService');
  t.mock.method(console,'warn',()=>{});
  t.after(()=>{for(const name of ['leaveFieldAssistant','dtrAssistantService','sentenceDraft'])clearModule(`../src/services/dtrAssistant/${name}`);restores.reverse().forEach(r=>r());});
  const pool={query:async(sql,values)=>{
    if(!/^\s*SELECT/i.test(sql))writes.push(sql);
    fieldQueries.push(values?.[0]);
    return {rows:[...leaves,...locators].filter(row=>row.name===values?.[0] || row.code===values?.[0])};
  }};
  let sequence=0;
  const userId=require('node:crypto').randomUUID();
  return {writes,modelCalls,fieldQueries,ask:async(message,options={})=>(await service.chatWithDtrAssistant(pool,{
    user:{id:userId,role:'employee'},conversationId:'shared-draft',message,...options,
  })).message,newConversation:()=>`draft-${++sequence}`};
}

for(const scenario of [
  {module:'leave',type:'wellness',field:'reason',question:'Sa reason field sa Wellness Leave, unsay ibutang?',facts:'Para makapahulay.',keyword:/makapahulay/i},
  {module:'leave',type:'community_leave',field:'activity',question:'Explain Community activity field for Community Leave.',facts:'To submit payroll documents.',keyword:/submit payroll documents/i},
  {module:'locator',type:'travel_order',field:'office',question:'Explain destination field for Travel Order locator.',facts:'Municipal Treasury Office',keyword:/Municipal Treasury Office/i},
  {module:'locator',type:'official_visit',field:'activity',question:'Explain Visit activity field for Official Visit locator.',facts:'To submit payroll documents.',keyword:/submit payroll documents/i},
]) test(`chat retains ${scenario.module}/${scenario.type}/${scenario.field} from help through drafting and rewrites`,async t=>{
  const h=await harness(t);
  const conversationId=h.newConversation();
  const ask=(text,options={})=>h.ask(text,{conversationId,...options});
  await ask(scenario.question);
  h.modelCalls.length=0;
  const clarification=await ask('tabangi ko paghimo sa sentence');
  assert.equal(clarification.intent,'form_sentence_suggestion');
  assert.doesNotMatch(clarification.content,/Maximum|Optional|configured|naka-configure|Akong rason:|My purpose:/i);
  assert.ok(clarification.content.length<300,clarification.content);
  assert.equal(h.modelCalls.length,0,'No provider call is needed without employee details');
  const draft=await ask(scenario.facts);
  assert.match(draft.content,scenario.keyword);
  assert.equal(h.fieldQueries.at(-1),scenario.type);
  assert.equal(draft.suggestions.length,3);
  assert.ok(draft.suggestions.some(s=>/formal|pormal/i.test(s.text)));
  assert.ok(draft.suggestions.some(s=>/shorter|mubo|maikli/i.test(s.text)));
  assert.doesNotMatch(draft.suggestions.map(s=>s.text).join(' '),/attachment|location field/);
  assert.deepEqual(draft.actions.map(a=>a.type),['copy_text'],'Standalone chat may copy wording but must not apply values to a form');
  assert.equal(draft.actions[0].autoExecute,false);
  assert.match(draft.actions[0].payload.value,scenario.keyword);
  const rewritten=await ask('Mas pormal',{intent:'form_sentence_suggestion'});
  assert.match(rewritten.content,scenario.keyword);
  assert.equal(h.fieldQueries.at(-1),scenario.type);
  const translated=await ask('English');
  assert.doesNotMatch(translated.content,/I-review ang facts|Maximum|Optional/);
  assert.deepEqual(h.writes,[]);
});

test('draft details do not leak across request types, conversations, users or a new status question',async t=>{
  const h=await harness(t);
  await h.ask('Draft a sentence for Wellness Leave because I need time to rest.');
  const switched=await h.ask('Help me draft a reason for Travel Order locator.');
  assert.doesNotMatch(switched.content,/request.*rest|to rest|makapahulay/i);
  const separate=await h.ask('Make that sentence more formal.',{conversationId:'another'});
  assert.doesNotMatch(separate.content,/request leave to rest/i);
  const otherUser=await h.ask('Make that sentence more formal.',{user:{id:'different-user',role:'employee'}});
  assert.doesNotMatch(otherUser.content,/request leave to rest/i);
  const status=await h.ask('What is the status of my latest locator?');
  assert.notEqual(status.intent,'form_sentence_suggestion');
  const afterStatus=await h.ask('Make that sentence shorter.');
  assert.doesNotMatch(afterStatus.content,/request leave to rest/i);
});

test('a direct answer to a field clarification drafts without another writing command',async t=>{
  const h=await harness(t);
  await h.ask('Explain Community activity field for Community Leave.');
  const answer=await h.ask('To submit payroll documents.');
  assert.match(answer.content,/submit payroll documents/);
  assert.equal(h.fieldQueries.at(-1),'community_leave');
  assert.ok(answer.suggestions.some(s=>/formal|pormal/i.test(s.text)));
});

test('active form drafts preserve the binding and only offer explicit field application',async t=>{
  const h=await harness(t);
  const formContext={module:'locator',locatorType:'travel_order',fieldKey:'reason',task:'chat',bindingId:'open-one'};
  const first=await h.ask('Help me write a sentence.',{formContext});
  assert.doesNotMatch(first.content,/Maximum|Optional/);
  const draft=await h.ask('To submit payroll documents.',{formContext});
  const apply=draft.actions.find(a=>a.type==='apply_field_suggestion');
  assert.equal(apply.payload.locatorType,'travel_order');assert.equal(apply.payload.fieldKey,'reason');
  assert.equal(apply.autoExecute,undefined);
  const newField=await h.ask('Help me write a sentence.',{formContext:{...formContext,bindingId:'open-two'}});
  assert.doesNotMatch(newField.content,/submit payroll documents/);
});

test('a destination mentioned in locator reason facts does not switch the active field',async t=>{
  const h=await harness(t);
  await h.ask('Explain the reason field for Travel Order locator.');
  await h.ask('Help me write a sentence.');
  const reply=await h.ask('I will submit payroll documents at the Municipal Treasury Office.');
  assert.match(reply.content,/I am requesting permission to submit payroll documents at the Municipal Treasury Office\./);
  assert.equal(h.fieldQueries.at(-1),'travel_order');
});
