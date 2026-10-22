const PAPER_SIZES=Object.freeze({a4:[595.28,841.89],letter:[612,792],long:[612,936],legal:[612,1008]});
function printLayoutPageSize(layout={}){const paper=layout.paper_size===undefined?'a4':layout.paper_size;if(typeof paper!=='string'||!Object.hasOwn(PAPER_SIZES,paper))throw Object.assign(new Error('Unsupported paper size'),{status:400});const size=PAPER_SIZES[paper];return layout.orientation==='landscape'?[size[1],size[0]]:size;}
function checkPrintBackgroundSize(width,height,layout){if(!layout)return;const size=printLayoutPageSize(layout);if(Math.abs(width-size[0])>2||Math.abs(height-size[1])>2)throw Object.assign(new Error('Choose the same paper size and orientation as the background'),{status:400});}
module.exports={PAPER_SIZES,printLayoutPageSize,checkPrintBackgroundSize};
