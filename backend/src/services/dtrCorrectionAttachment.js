const path = require('node:path');
const MAX_SIZE = 5 * 1024 * 1024;
function validateAttachment(file) {
  if (!file) return null;
  const b = file.buffer;
  const ext = path.extname(file.originalname || '').toLowerCase();
  let mime;
  if (!Buffer.isBuffer(b) || !b.length || b.length > MAX_SIZE) {
    throw Object.assign(new Error('Attachment must be between 1 byte and 5 MB.'), { status: 400 });
  }
  if (ext === '.pdf' && b.subarray(0, 5).toString() === '%PDF-') mime = 'application/pdf';
  if (['.jpg', '.jpeg'].includes(ext) && b[0] === 255 && b[1] === 216 && b[2] === 255) mime = 'image/jpeg';
  if (ext === '.png' && b.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) mime = 'image/png';
  if (!mime) throw Object.assign(new Error('Upload a PDF, JPG or PNG matching its file extension.'), { status: 400 });
  return { name: path.basename(file.originalname.replace(/\\/g, '/')).replace(/[\x00-\x1f\x7f]/g, '').slice(0, 200) || 'attachment', mime, content: b };
}
module.exports = { MAX_SIZE, validateAttachment };
