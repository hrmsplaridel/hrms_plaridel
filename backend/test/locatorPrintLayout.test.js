const test=require('node:test');const assert=require('node:assert/strict');
const {normalizeLocatorPrintLayout}=require('../src/services/locatorPrintLayout');
const layout=()=>({version:1,orientation:'portrait',elements:[
  {id:'title',kind:'text',text:'TRAVEL ORDER',x:40,y:140,width:515,height:35,font_size:20,bold:true,align:'center'},
  {id:'destination',kind:'field',source:'custom:destination',label:'Destination',x:40,y:200,width:515,height:50,font_size:11},
  {id:'mayor',kind:'signature',source:'hr_approver',label:'Municipal Mayor',x:300,y:600,width:250,height:80,font_size:11},
]});
test('layout accepts draft JSON and binds custom fields and signatures',()=>{
  const value=normalizeLocatorPrintLayout(JSON.stringify(layout()));
  assert.equal(value.elements[1].source,'custom:destination');assert.equal(value.elements[2].source,'hr_approver');
  assert.equal(normalizeLocatorPrintLayout(null),null);
});
test('layout rejects invalid positions, sources, duplicate IDs and oversized content',()=>{
  for(const mutate of [v=>v.elements[0].x=-1,v=>v.elements[0].width=1000,v=>v.elements[0].font_size=0,
    v=>v.elements[1].source='password_hash',v=>v.elements[2].height=10,v=>v.elements[1].height=10,v=>v.elements[1].id='title',
    v=>v.elements[0].text='x'.repeat(501),v=>v.orientation='custom',v=>v.elements=Array(61).fill(v.elements[0])]) {
    const value=layout();mutate(value);assert.throws(()=>normalizeLocatorPrintLayout(value),{status:400});
  }
});
