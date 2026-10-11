const test = require('node:test');
const assert = require('node:assert/strict');
const {withMockedModule, clearModule} = require('./helpers/moduleMocks');

for (const filtered of [true, false]) {
  test(`employee list applies Leave Card eligibility only when requested: ${filtered}`, async () => {
    const queries = [];
    const restore = withMockedModule('../src/config/db', {pool: {query: async sql => {
      queries.push(sql);
      return {rows: sql.includes('COUNT(*)') ? [{c: 0}] : []};
    }}});
    clearModule('../src/routes/employees');
    try {
      const handler = require('../src/routes/employees').stack.find(l => l.route?.path === '/' && l.route.methods.get).route.stack.at(-1).handle;
      const res = {code:200,status(c){this.code=c;return this;},json(b){this.body=b;}};
      await handler({user:{id:'admin',role:'admin'},query:{limit:'100',status:'Active',...(filtered?{leave_card:'true'}:{})}},res);
      assert.equal(res.code,200);
      assert.equal(queries.length,2);
      for(const sql of queries) {
        assert.equal(sql.includes('card_balance'),filtered);
        assert.equal(sql.includes('card_assignment'),filtered);
      }
    } finally {clearModule('../src/routes/employees');restore();}
  });
}
