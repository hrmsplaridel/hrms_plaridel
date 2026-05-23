/**
 * Stable display title for DocuTracker API DTOs (matches Flutter DocuTrackerDocument.fromJson).
 * Prefer DB `title`; otherwise source-linked label, file name, document number, or first line of description.
 */
function firstDescriptionLine(text) {
  if (text == null) return '';
  const s = String(text).trim();
  if (!s) return '';
  const line = s.split('\n')[0].trim();
  if (!line) return '';
  return line.length > 200 ? `${line.slice(0, 200)}…` : line;
}

function coalesceDocumentTitle(row) {
  if (!row || typeof row !== 'object') return 'Untitled document';
  const pick = (v) => {
    if (v == null) return '';
    const s = String(v).trim();
    return s !== '' ? s : '';
  };
  return (
    pick(row.title) ||
    pick(row.source_title) ||
    pick(row.file_name) ||
    pick(row.document_number) ||
    firstDescriptionLine(row.description) ||
    'Untitled document'
  );
}

module.exports = { coalesceDocumentTitle };
