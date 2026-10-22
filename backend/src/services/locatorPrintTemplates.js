const {printLayoutPageSize,checkPrintBackgroundSize}=require('./printLayoutPageSettings');
const {PDFDocument}=require('pdf-lib');
const {validateBackground}=require('./leavePrintTemplates');
const validateLocatorBackground=(bytes,mime)=>validateBackground(bytes,mime,{allowLandscape:true,allowPaperSizes:true});
async function mergeLocatorBackground(background,overlay,layout=null) {
  const doc=await PDFDocument.load(overlay);
  if(doc.getPageCount()<1 || doc.getPageCount()>100)throw Object.assign(new Error('Locator form must contain 1 to 100 pages'),{status:400});
  const expected=printLayoutPageSize(layout||{});
  if(layout) {
    const first=doc.getPage(0).getSize();
    if(Math.abs(first.width-expected[0])>2||Math.abs(first.height-expected[1])>2)
      throw Object.assign(new Error('Generated form paper size or orientation does not match its saved layout'),{status:400});
  }
  if(!background)return Buffer.from(overlay);
  const bgDoc=await PDFDocument.load(await validateLocatorBackground(background,'application/pdf'));
  const {width,height}=bgDoc.getPage(0).getSize();
  checkPrintBackgroundSize(width,height,layout);
  const out=await PDFDocument.create();const [bg]=await out.embedPdf(bgDoc,[0]);
  const source=doc.getPage(0);
  if(!source.node.Contents())source.drawRectangle({x:0,y:0,width:1,height:1,opacity:0});
  const fg=await out.embedPage(source);const page=out.addPage([width,height]);
  page.drawPage(bg,{x:0,y:0,width,height});
  // Reserve letterhead/footer space; preserve the locator form's aspect ratio.
  const scale=layout?1:Math.min((width-64)/fg.width,(height-220)/fg.height);
  page.drawPage(fg,{x:layout?0:(width-fg.width*scale)/2,y:layout?0:110+(height-220-fg.height*scale)/2,
    width:fg.width*scale,height:fg.height*scale});
  // Keep supplemental answers at their original size; the letterhead applies
  // to the locator slip only, so long answers remain readable.
  if(doc.getPageCount()>1) {
    const pages=await out.copyPages(doc,Array.from({length:doc.getPageCount()-1},(_,i)=>i+1));
    for(const extra of pages)out.addPage(extra);
  }
  return Buffer.from(await out.save());
}
module.exports={validateLocatorBackground,mergeLocatorBackground};
