const test=require('node:test');
const assert=require('node:assert/strict');
const {normalizeLocatorFieldSchema,locatorDetailValues}=require('../src/services/locatorCustomFields');
test('leave and locator schemas retain bounded field guidance across normalization', () => {
  const {normalizeEmployeeDetailSchema} = require('../src/services/leaveRequestDetailsPolicy');
  const field = {key:'purpose',label:'Purpose',type:'text',instruction:' Describe your purpose. ',example:'A sample activity.',sentence_template:'I will [activity].'};
  for (const normalize of [normalizeEmployeeDetailSchema, normalizeLocatorFieldSchema]) {
    const saved = normalize([field], {strict:true});
    assert.equal(saved[0].instruction, 'Describe your purpose.');
    assert.equal(saved[0].example, field.example);
    assert.equal(saved[0].sentence_template, field.sentence_template);
    assert.deepEqual(normalize(saved, {strict:true}), saved);
    for (const property of ['instruction', 'example', 'sentence_template']) {
      assert.throws(() => normalize([{...field,[property]:'x'.repeat(1001)}],{strict:true}), /1000/);
      assert.throws(() => normalize([{...field,[property]:{text:'bad'}}],{strict:true}), /must be text/);
    }
    const legacy = normalize([{key:'purpose',label:'Purpose',type:'text'}], {strict:true});
    assert.equal(legacy[0].instruction, undefined);
  }
});
test('locator custom values validate dates, numbers, dropdown choices and booleans',()=>{
  const schema=normalizeLocatorFieldSchema([
    {key:'date',label:'Visit date',type:'date',required:true},
    {key:'distance',label:'Distance',type:'number'},
    {key:'transport',label:'Transport',type:'select',options:['Car','Bus']},
    {key:'provided',label:'Provided',type:'boolean'},
  ],{strict:true});
  assert.deepEqual(locatorDetailValues({date:'2026-10-13',distance:'2.5',transport:'Bus',provided:false,extra:'discard'},schema),
    {date:'2026-10-13',distance:2.5,transport:'Bus',provided:false});
  for(const value of [{date:'2026-02-30'},{date:'2026-10-13',distance:'abc'},
    {date:'2026-10-13',transport:'Plane'},{date:'2026-10-13',provided:'maybe'}]) {
    assert.throws(()=>locatorDetailValues(value,schema),{statusCode:400});
  }
  assert.throws(()=>locatorDetailValues('{invalid}',schema),{statusCode:400});
  assert.throws(()=>locatorDetailValues([],schema),{statusCode:400});
});
test('empty schemas keep existing locators unchanged and reject duplicate field definitions',()=>{
  assert.deepEqual(locatorDetailValues(undefined,[]),{});
  assert.throws(()=>normalizeLocatorFieldSchema([
    {key:'contact',label:'Contact',type:'text'},{key:'contact',label:'Other contact',type:'text'},
  ],{strict:true}),/duplicated/);
});
