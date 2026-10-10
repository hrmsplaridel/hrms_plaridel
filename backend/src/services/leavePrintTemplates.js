const {PDFDocument} = require('pdf-lib');
function invalid(message) {return Object.assign(new Error(message),{status:400});}
function validateLayout(layout) {
 if(!['csc','wellness'].includes(layout)) throw invalid('Unsupported printed form layout');
 return layout;
}
async function validateBackground(bytes,mime) {
 if(!bytes?.length || bytes.length>5242880) throw invalid('Background must be at most 5 MB');
 try {
  let doc;
  if(mime==='application/pdf') doc=await PDFDocument.load(bytes);
  else if(['image/png','image/jpeg'].includes(mime)) {
   doc=await PDFDocument.create();
   const img=mime==='image/png'?await doc.embedPng(bytes):await doc.embedJpg(bytes);
   if(Math.abs(img.width/img.height-595.28/841.89)>0.025) throw invalid('Use a portrait A4 background');
   doc.addPage([595.28,841.89]).drawImage(img,{x:0,y:0,width:595.28,height:841.89});
  } else throw invalid('Use PDF, PNG or JPEG');
  if(doc.getPageCount()!==1) throw invalid('Use a single-page background');
  const page=doc.getPage(0), {width,height}=page.getSize();
  if(Math.abs(width-595.28)>3 || Math.abs(height-841.89)>3 || page.getRotation().angle!==0)
   throw invalid('Use a portrait A4 background');
  // Rebuild using embedded artwork; interactive content is not copied.
  if(!page.node.Contents()) page.drawRectangle({x:0,y:0,width:1,height:1,opacity:0});
  const clean=await PDFDocument.create(); const artwork=await clean.embedPage(page);
  clean.addPage([595.28,841.89]).drawPage(artwork);
  return Buffer.from(await clean.save());
 } catch(e) {if(e.status) throw e; throw invalid('Could not read background PDF or image');}
}
async function mergeBackground(background,overlay,{layout='wellness'}={}) {
 const doc=await PDFDocument.load(overlay);
 if(doc.getPageCount()>10) throw invalid('Printed form exceeds 10 pages');
 if(!background) return Buffer.from(overlay);
 const out=await PDFDocument.create();
 const bg=await out.embedPdf(await validateBackground(background,'application/pdf'),[0]);
 for(const source of doc.getPages()) {
  if(!source.node.Contents())source.drawRectangle({x:0,y:0,width:1,height:1,opacity:0});
  const fg=await out.embedPage(source);const page=out.addPage([595.28,841.89]);
  page.drawPage(bg[0],{x:0,y:0,width:595.28,height:841.89});
  if(layout==='csc') {
   const scale=Math.min(491.28/fg.width,611.89/fg.height);
   page.drawPage(fg,{x:(595.28-fg.width*scale)/2,y:120,width:fg.width*scale,height:fg.height*scale});
  } else page.drawPage(fg,{x:0,y:0,width:595.28,height:841.89});
 }
 return Buffer.from(await out.save());
}
module.exports={validateLayout,validateBackground,mergeBackground};
