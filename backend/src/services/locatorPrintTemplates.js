const {PDFDocument}=require('pdf-lib');
const {validateBackground}=require('./leavePrintTemplates');
const validateLocatorBackground=(bytes,mime)=>validateBackground(bytes,mime,{allowLandscape:true});
async function mergeLocatorBackground(background,overlay) {
  const doc=await PDFDocument.load(overlay);
  if(doc.getPageCount()!==1)throw Object.assign(new Error('Use a single-page locator form'),{status:400});
  if(!background)return Buffer.from(overlay);
  const bgDoc=await PDFDocument.load(await validateLocatorBackground(background,'application/pdf'));
  const {width,height}=bgDoc.getPage(0).getSize();
  const out=await PDFDocument.create();const [bg]=await out.embedPdf(bgDoc,[0]);
  const source=doc.getPage(0);
  if(!source.node.Contents())source.drawRectangle({x:0,y:0,width:1,height:1,opacity:0});
  const fg=await out.embedPage(source);const page=out.addPage([width,height]);
  page.drawPage(bg,{x:0,y:0,width,height});
  // Reserve letterhead/footer space; preserve the locator form's aspect ratio.
  const scale=Math.min((width-64)/fg.width,(height-220)/fg.height);
  page.drawPage(fg,{x:(width-fg.width*scale)/2,y:110+(height-220-fg.height*scale)/2,
    width:fg.width*scale,height:fg.height*scale});
  return Buffer.from(await out.save());
}
module.exports={validateLocatorBackground,mergeLocatorBackground};
