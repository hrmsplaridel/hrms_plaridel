const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

const invalidRanges = [
  ['2027-02-30', '2027-03-01', /start_date/],
  ['2027-02-29', '2027-03-01', /start_date/],
  ['2027-13-01', '2027-13-02', /start_date/],
  ['2027-01-00', '2027-01-01', /start_date/],
  ['2027-01-01', '2027-02-30', /end_date/],
  ['2027-01-01garbage', '2027-01-02', /start_date/],
  ['2027-01-01', '2027-01-02T10:00:00Z', /end_date/],
  ['2027-01-02', '2027-01-01', /earlier/],
  ['', '2027-01-01', /required/],
  [['2027-01-01'], '2027-01-02', /start_date/],
];
for (const routePath of ['/submit', '/submit-with-attachment', '/working-days']) {
  test(`${routePath} rejects malformed calendar dates before database work`, async () => {
    let connects = 0;
    let reads = 0;
    const restore = withMockedModule('../src/config/db', { pool: {
      async connect() { connects++; throw new Error('Unexpected database connection'); },
      async query(sql) {
        if (sql.includes('FROM holidays') || sql.includes('FROM generate_series')) { reads++; throw new Error('Unexpected date query'); }
        return { rows: [] };
      },
    } });
    const path = '../src/routes/leaveRoutes'; clearModule(path);
    try {
      const route = require(path).stack.find(l => l.route?.path === routePath).route;
      for (const [start_date, end_date, message] of invalidRanges) {
        const values = { leave_type: 'vacationLeave', start_date, end_date };
        const req = { user: { id: 'employee' }, body: values, query: values, file: { buffer: Buffer.from('%PDF-test'), originalname: 'test.pdf', mimetype: 'application/pdf' } };
        const res = { code: 200, status(n) { this.code = n; return this; }, json(v) { this.body = v; } };
        await route.stack.at(-1).handle(req, res);
        assert.equal(res.code, 400, JSON.stringify(values));
        assert.match(res.body.error, message);
      }
      assert.equal(connects, 0);
      assert.equal(reads, 0);
    } finally { clearModule(path); restore(); }
  });
}

test('working-days accepts genuine leap-day and same-day dates', async () => {
  const restore = withMockedModule('../src/config/db', { pool: { async query(sql, params = []) {
    if (sql.includes('FROM generate_series')) return { rows: [{
      attendance_date: params[1], working_days: [1,2,3,4,5,6,7], has_assignment: true, has_shift: true,
    }] };
    return { rows: [] };
  } } });
  const path = '../src/routes/leaveRoutes'; clearModule(path);
  try {
    const route = require(path).stack.find(l => l.route?.path === '/working-days').route;
    for (const date of ['2028-02-29', '2027-11-02']) {
      const res = { code: 200, status(n) { this.code = n; return this; }, json(v) { this.body = v; } };
      await route.stack.at(-1).handle({ user: { id: 'employee' }, query: { start_date: date, end_date: date } }, res);
      assert.equal(res.code, 200);
      assert.equal(res.body.start_date, date);
      assert.equal(res.body.end_date, date);
      assert.equal(res.body.working_days_applied, 1);
    }
  } finally { clearModule(path); restore(); }
});
