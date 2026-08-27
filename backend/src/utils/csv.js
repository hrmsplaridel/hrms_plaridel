const SPREADSHEET_FORMULA_PREFIX = /^[\s]*[=+\-@]/;

function neutralizeSpreadsheetFormula(value) {
  const text = String(value);
  return SPREADSHEET_FORMULA_PREFIX.test(text) ? `'${text}` : text;
}

function csvEscape(value) {
  if (value == null) return '';
  const text = neutralizeSpreadsheetFormula(value);
  if (/[",\n\r\t]/.test(text)) return `"${text.replace(/"/g, '""')}"`;
  return text;
}

module.exports = {
  csvEscape,
  neutralizeSpreadsheetFormula,
};
