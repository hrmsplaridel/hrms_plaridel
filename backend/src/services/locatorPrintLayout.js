const {printLayoutPageSize}=require('./printLayoutPageSettings');
const FIELDS=new Set(['employee_name','date','request_type','office','reason','time_segments']);
const SIGNATURES=new Set(['applicant','department_head','hr_approver']);
function invalid(message){throw Object.assign(new Error(message),{status:400});}
function normalizeLocatorPrintLayout(value, {fields=FIELDS, signatures=SIGNATURES}={}) {
  if(value==null || value==='null')return null;
  if(typeof value==='string'){try{value=JSON.parse(value);}catch(_){invalid('Printed layout must be valid JSON');}}
  if(!value || Array.isArray(value) || value.version!==1 || !['portrait','landscape'].includes(value.orientation))invalid('Invalid printed layout or orientation');
  if(!Array.isArray(value.elements)||value.elements.length<1||value.elements.length>60)invalid('Printed layout needs 1 to 60 elements');
  const [pageWidth,pageHeight]=printLayoutPageSize(value);
  const fontFamilies=new Set(['sans','serif','mono']);
  if(value.font_family!=null&&!fontFamilies.has(value.font_family))invalid('Unsupported font family');
  if(value.default_font_size!==undefined&&(typeof value.default_font_size!=='number'||!Number.isFinite(value.default_font_size)||value.default_font_size<6||value.default_font_size>72))invalid('Default font size must be 6 to 72 points');
  const margins=value.margins??{top:0,right:0,bottom:0,left:0};
  if(!margins||Array.isArray(margins)||typeof margins!=='object'||['top','right','bottom','left'].some(k=>typeof margins[k]!=='number'||!Number.isFinite(margins[k])||margins[k]<0)||margins.left+margins.right>pageWidth-100||margins.top+margins.bottom>pageHeight-100)invalid('Margins must leave at least 100 points of usable page width and height');
  const ids=new Set();
  const elements=value.elements.map(item=>{
    if(!item || typeof item!=='object')invalid('Invalid layout element');
    const id=String(item.id||'');
    if(!/^[a-zA-Z0-9_-]{1,64}$/.test(id)||ids.has(id))invalid('Layout element IDs must be unique');ids.add(id);
    if(!['field','text','signature','line','table'].includes(item.kind))invalid('Unknown layout element');
    for(const key of ['x','y','width','height','font_size'])if(typeof item[key]!=='number'||!Number.isFinite(item[key]))invalid('Layout dimensions must be numbers');
    if(item.x<margins.left||item.y<margins.top||item.width<20||item.height<2||item.x+item.width>pageWidth-margins.right+.1||item.y+item.height>pageHeight-margins.bottom+.1||item.font_size<6||item.font_size>72)invalid('Keep layout elements within the page margins and use fonts from 6 to 72 points');
    const align=item.align??'left';if(!['left','center','right'].includes(align))invalid('Invalid text alignment');
    const label=String(item.label??'').trim();if(label.length>100)invalid('Field labels must not exceed 100 characters');
    if(item.font_family!=null&&!fontFamilies.has(item.font_family))invalid('Unsupported element font family');
    const base={...(item.font_family!=null?{font_family:item.font_family}:{}),id,kind:item.kind,x:item.x,y:item.y,width:item.width,height:item.height,font_size:item.font_size,align,bold:item.bold===true};
    if(item.kind==='table'){
      if(!Array.isArray(item.cells)||item.cells.length<1||item.cells.length>12||!Array.isArray(item.cells[0])||item.cells[0].length<1||item.cells[0].length>6)invalid('Tables need 1 to 12 rows and 1 to 6 columns');
      const columns=item.cells[0].length;
      if(!Array.isArray(item.column_widths)||item.column_widths.length!==columns||item.column_widths.some(w=>typeof w!=='number'||!Number.isFinite(w)||w<.1||w>10))invalid('Each table column needs a width weight from 0.1 to 10');
      const total=item.column_widths.reduce((a,b)=>a+b,0);
      if(item.height<item.cells.length*(item.font_size*1.5+8)||item.column_widths.some(w=>item.width*w/total<20))invalid('Table rows need enough height for their font and columns need 20 points of width');
      const cells=item.cells.map(row=>{
        if(!Array.isArray(row)||row.length!==columns)invalid('Table rows must have the same number of columns');
        return row.map(cell=>{
          if(!cell||typeof cell!=='object'||Array.isArray(cell))invalid('Invalid table cell');
          if(cell.kind==='text'){
            const text=String(cell.text??'');if(text.length>500)invalid('Table cell text must not exceed 500 characters');return {kind:'text',text};
          }
          if(cell.kind==='field'){
            if(typeof cell.source!=='string'||(!fields.has(cell.source)&&!/^custom:[a-z][a-z0-9_]{0,63}$/.test(cell.source)))invalid('Invalid table field source');return {kind:'field',source:cell.source};
          }
          invalid('Table cells must contain text or a field');
        });
      });
      return {...base,column_widths:item.column_widths,cells,header_row:item.header_row!==false,borders:item.borders!==false};
    }
    if(item.kind==='text'){
      if(item.height<12)invalid('Text boxes need at least 12 points of height');
      const text=String(item.text??'').trim();if(!text||text.length>500)invalid('Text elements need 1 to 500 characters');return {...base,text};
    }
    if(item.kind==='field'){
      if(item.height<20)invalid('Field boxes need at least 20 points of height');
      if(!fields.has(item.source)&&!/^custom:[a-z][a-z0-9_]{0,63}$/.test(item.source||''))invalid('Invalid printed field source');
      return {...base,source:item.source,label,show_label:item.show_label!==false};
    }
    if(item.kind==='signature'){
      const style=item.signature_style??'standard';if(!['standard','csc'].includes(style))invalid('Invalid signature style');const minHeight=style==='csc'?(item.source==='applicant'?18:32):60;
      if((item.font_family!=null||value.font_family!=null)&&item.height<Math.max(minHeight,item.font_size*3.5+12))invalid('Signature blocks need enough height for their font size. Increase the height or reduce the font size.');
      if((!signatures.has(item.source)&&!/^workflow_step_([1-9]|1[0-9]|20)$/.test(item.source||''))||item.height<minHeight||item.width<100)invalid('Signature blocks need a valid signer and at least 100 by 60 points');
      return {...base,source:item.source,label,...(item.signature_style!==undefined?{signature_style:style}:{})};
    }
    return base;
  });
  const normalized={version:1,orientation:value.orientation,...(value.paper_size!==undefined?{paper_size:value.paper_size}:{}),...(value.margins!==undefined?{margins:{top:margins.top,right:margins.right,bottom:margins.bottom,left:margins.left}}:{}),...(value.font_family!=null?{font_family:value.font_family}:{}),...(value.default_font_size!==undefined?{default_font_size:value.default_font_size}:{}),elements};
  if(Buffer.byteLength(JSON.stringify(normalized,null,1),'utf8')>100000)invalid('Printed layout must fit within 100 KB');
  return normalized;
}
module.exports={normalizeLocatorPrintLayout};
