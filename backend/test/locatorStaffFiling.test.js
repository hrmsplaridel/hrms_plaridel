const test=require('node:test');
const assert=require('node:assert/strict');
const {validateStaffBatch,runStaffBatch}=require('../src/services/locatorStaffFiling');
test('batch is bounded, unique, and requires valid employee UUIDs',()=>{
  const id='11111111-1111-4111-8111-111111111111';
  assert.deepEqual(validateStaffBatch([id,id]),[id]);
  for(const ids of [[],['bad'],Array(101).fill(id)])assert.throws(()=>validateStaffBatch(ids));
});
test('staff batch is sequential and reports individual failures without replay',async()=>{
  let active=0,max=0;const calls=[];
  const results=await runStaffBatch(['a','b','c'],async id=>{calls.push(id);active++;max=Math.max(max,active);await Promise.resolve();active--;if(id==='b')throw Object.assign(new Error('No assignment'),{statusCode:400});return {id,status:'approved'};});
  assert.equal(max,1);assert.deepEqual(calls,['a','b','c']);
  assert.equal(results[1].error,'No assignment');assert.equal(results[0].request.status,'approved');
});
