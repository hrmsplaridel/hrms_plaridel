const test=require('node:test');
const assert=require('node:assert/strict');
const {normalizeLocatorFieldSchema,locatorDetailValues}=require('../src/services/locatorCustomFields');
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
