const test = require('node:test');
const assert = require('node:assert/strict');
const { normalizeLocatorPrintLayout } = require('../src/services/locatorPrintLayout');
const { normalizeLeavePrintLayout } = require('../src/services/leavePrintLayout');

const layout = () => ({ version: 1, orientation: 'portrait', elements: [{
  id: 'section', kind: 'rectangle', x: 40, y: 60, width: 400, height: 90,
  font_size: 11, group_id: 'group_1', locked: true,
  decoration: { border_sides: ['top', 'bottom'], border_width: 1.5,
    border_color: '#123456', border_style: 'dashed', fill_color: '#EEEEEE' },
}] });

for (const [name, normalize] of [['Locator', normalizeLocatorPrintLayout], ['Leave', normalizeLeavePrintLayout]]) {
  test(`${name} preserves boxes, borders, fills, groups, locks, and layer order`, () => {
    const value = layout();
    value.elements.push({ id: 'heading', kind: 'text', text: 'Details', x: 50, y: 65,
      width: 200, height: 20, font_size: 11, group_id: 'group_1' });
    const result = normalize(JSON.stringify(value));
    assert.deepEqual(result.elements.map((e) => e.id), ['section', 'heading']);
    assert.deepEqual(result.elements[0].decoration, value.elements[0].decoration);
    assert.equal(result.elements[0].locked, true);
    assert.equal(result.elements[1].group_id, 'group_1');
  });
  test(`${name} rejects unsafe or invalid drawing settings`, () => {
    for (const mutate of [
      (e) => e.decoration.border_width = -1,
      (e) => e.decoration.border_width = 21,
      (e) => e.decoration.border_color = 'url(external)',
      (e) => e.decoration.fill_color = '#bad',
      (e) => e.decoration.border_style = 'unknown',
      (e) => e.decoration.border_sides = ['middle'],
      (e) => e.decoration.border_sides = ['top', 'top'],
      (e) => e.locked = 'true',
      (e) => e.group_id = 'invalid group',
    ]) {
      const value = layout(); mutate(value.elements[0]);
      assert.throws(() => normalize(value), { status: 400 });
    }
  });
}
