const FIELDS=new Set(['employee_name','date','request_type','office','reason','time_segments']);
const SIGNATURES=new Set(['applicant','department_head','hr_approver']);
function invalid(message){throw Object.assign(new Error(message),{status:400});}
function normalizeLocatorPrintLayout(value) {
  if(value==null || value==='null')return null;
  if(typeof value==='string'){try{value=JSON.parse(value);}catch(_){invalid('Printed layout must be valid JSON');}}
  if(!value || Array.isArray(value) || value.version!==1 || !['portrait','landscape'].includes(value.orientation))invalid('Invalid printed layout or orientation');
  if(!Array.isArray(value.elements)||value.elements.length<1||value.elements.length>60)invalid('Printed layout needs 1 to 60 elements');
  const [pageWidth,pageHeight]=value.orientation==='portrait'?[595.28,841.89]:[841.89,595.28];
  const ids=new Set();
  const elements=value.elements.map(item=>{
    if(!item || typeof item!=='object')invalid('Invalid layout element');
    const id=String(item.id||'');
    if(!/^[a-zA-Z0-9_-]{1,64}$/.test(id)||ids.has(id))invalid('Layout element IDs must be unique');ids.add(id);
    if(!['field','text','signature','line'].includes(item.kind))invalid('Unknown layout element');
    for(const key of ['x','y','width','height','font_size'])if(typeof item[key]!=='number'||!Number.isFinite(item[key]))invalid('Layout dimensions must be numbers');
    if(item.x<0||item.y<0||item.width<20||item.height<2||item.x+item.width>pageWidth+.1||item.y+item.height>pageHeight+.1||item.font_size<8||item.font_size>28)invalid('Keep layout elements within the page and use fonts from 8 to 28 points');
    const align=item.align??'left';if(!['left','center','right'].includes(align))invalid('Invalid text alignment');
    const label=String(item.label??'').trim();if(label.length>100)invalid('Field labels must not exceed 100 characters');
    const base={id,kind:item.kind,x:item.x,y:item.y,width:item.width,height:item.height,font_size:item.font_size,align,bold:item.bold===true};
    if(item.kind==='text'){
      if(item.height<12)invalid('Text boxes need at least 12 points of height');
      const text=String(item.text??'').trim();if(!text||text.length>500)invalid('Text elements need 1 to 500 characters');return {...base,text};
    }
    if(item.kind==='field'){
      if(item.height<20)invalid('Field boxes need at least 20 points of height');
      if(!FIELDS.has(item.source)&&!/^custom:[a-z][a-z0-9_]{0,63}$/.test(item.source||''))invalid('Invalid printed field source');
      return {...base,source:item.source,label,show_label:item.show_label!==false};
    }
    if(item.kind==='signature'){
      if(!SIGNATURES.has(item.source)||item.height<60||item.width<100)invalid('Signature blocks need a valid signer and at least 100 by 60 points');
      return {...base,source:item.source,label};
    }
    return base;
  });
  return {version:1,orientation:value.orientation,elements};
}
module.exports={normalizeLocatorPrintLayout};
