const test = require('node:test');
const assert = require('node:assert/strict');

const {
  csvEscape,
  neutralizeSpreadsheetFormula,
} = require('../src/utils/csv');

test('neutralizes spreadsheet formula prefixes', () => {
  for (const value of [
    '=HYPERLINK("https://example.test","Employee")',
    '+1+1',
    '-1+1',
    '@SUM(A1:A2)',
  ]) {
    assert.equal(neutralizeSpreadsheetFormula(value), `'${value}`);
  }
});

test('neutralizes formulas hidden behind whitespace', () => {
  assert.equal(neutralizeSpreadsheetFormula('  =1+1'), "'  =1+1");
  assert.equal(neutralizeSpreadsheetFormula('\t@SUM(A1:A2)'), "'\t@SUM(A1:A2)");
  assert.equal(csvEscape('\t@SUM(A1:A2)'), '"\'\t@SUM(A1:A2)"');
});

test('preserves safe text and empty values', () => {
  assert.equal(csvEscape(null), '');
  assert.equal(csvEscape(undefined), '');
  assert.equal(csvEscape('Maria Santos'), 'Maria Santos');
  assert.equal(csvEscape('  Maria Santos'), '  Maria Santos');
});

test('quotes commas, quotes, tabs, and line breaks after neutralization', () => {
  assert.equal(csvEscape('Dela Cruz, Maria'), '"Dela Cruz, Maria"');
  assert.equal(csvEscape('Maria "May" Santos'), '"Maria ""May"" Santos"');
  assert.equal(csvEscape('Line 1\nLine 2'), '"Line 1\nLine 2"');
  assert.equal(csvEscape('Column\tValue'), '"Column\tValue"');
  assert.equal(csvEscape('=SUM(1,2)'), '"\'=SUM(1,2)"');
});
