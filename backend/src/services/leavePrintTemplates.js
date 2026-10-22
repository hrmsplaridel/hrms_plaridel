const {PDFDocument} = require('pdf-lib');
const {PAPER_SIZES}=require('./printLayoutPageSettings');
function invalid(message) {return Object.assign(new Error(message),{status:400});}
function validateLayout(layout) {
 if(!['csc','wellness','custom'].includes(layout)) throw invalid('Unsupported printed form layout');
 return layout;
}
async function validateBackground(bytes,mime,{allowLandscape=false,allowPaperSizes=false}={}) {
 if(!bytes?.length || bytes.length>5242880)throw invalid('Background must be at most 5 MB');
 const sizes=Object.values(allowPaperSizes?PAPER_SIZES:{a4:PAPER_SIZES.a4}).flatMap(size=>allowLandscape?[size,[size[1],size[0]]]:[size]);
 const message=allowPaperSizes?'Use an A4, Letter, Long Bond or Legal background':allowLandscape?'Use an A4 background':'Use a portrait A4 background';
 try{
  let doc;
  if(mime==='application/pdf')doc=await PDFDocument.load(bytes);
  else if(['image/png','image/jpeg'].includes(mime)){
   doc=await PDFDocument.create();const img=mime==='image/png'?await doc.embedPng(bytes):await doc.embedJpg(bytes);
   const size=sizes.reduce((a,b)=>Math.abs(img.width/img.height-a[0]/a[1])<=Math.abs(img.width/img.height-b[0]/b[1])?a:b);
   if(Math.abs(img.width/img.height-size[0]/size[1])>0.025)throw invalid(message);
   doc.addPage(size).drawImage(img,{x:0,y:0,width:size[0],height:size[1]});
  }else throw invalid('Use PDF, PNG or JPEG');
  if(doc.getPageCount()!==1)throw invalid('Use a single-page background');
  const page=doc.getPage(0),{width,height}=page.getSize();
  const size=sizes.find(size=>Math.abs(width-size[0])<=3&&Math.abs(height-size[1])<=3);
  if(!size||page.getRotation().angle!==0)throw invalid(message);
  if(!page.node.Contents())page.drawRectangle({x:0,y:0,width:1,height:1,opacity:0});
  const clean=await PDFDocument.create();const artwork=await clean.embedPage(page);
  clean.addPage(size).drawPage(artwork,{x:0,y:0,width:size[0],height:size[1]});
  return Buffer.from(await clean.save());
 }catch(e){if(e.status)throw e;throw invalid('Could not read background PDF or image');}
}
async function mergeBackground(background,overlay,{layout='wellness',printLayout=null}={}) {
 if(layout==='custom') {
  if(!printLayout)throw invalid('Custom printed layout is required');
  return require('./locatorPrintTemplates').mergeLocatorBackground(background,overlay,printLayout);
 }
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
