const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

const scenarios = [
  ...['/submit', '/submit-with-attachment', '/:id'].map(secondPath => ({
    label: `annual quota JSON versus ${secondPath}`, secondPath, limit: 2,
    firstDates: ['2026-11-02', '2026-11-03'], secondDates: ['2026-11-04', '2026-11-05'], allowed: false,
  })),
  { label: 'cross-year filing counts prior usage in next year', secondPath: '/submit', limit: 2,
    firstDates: ['2026-12-31', '2027-01-01'], secondDates: ['2027-01-04', '2027-01-05'], allowed: false },
  { label: 'enough annual allowance permits both filings', secondPath: '/submit', limit: 4,
    firstDates: ['2026-11-02', '2026-11-03'], secondDates: ['2026-11-04', '2026-11-05'], allowed: true },
  { label: 'cross-year request uses separate calendar-year allowances', secondPath: '/submit', limit: 2,
    firstDates: ['2026-12-31', '2027-01-01'], secondDates: ['2027-01-04', '2027-01-04'], allowed: true },
];
for (const { label, secondPath, limit, firstDates, secondDates, allowed } of scenarios) {
  test(label, async () => {
    const rows = new Map([['draft-2', { id: 'draft-2', status: 'draft', user_id: 'employee', employee_id: 'employee' }]]);
    let owner = null;
    const waiters = [];
    let inserts = 0;
    let committed = false;
    const checkReads = [];
    const pool = {
      async query(sql) { return { rows: sql.includes('FROM leave_requests') ? [{ ...rows.get('draft-2') }] : [] }; },
      async connect() {
        const client = {
          release() {},
          async query(sql, params = []) {
            if (sql === 'COMMIT' || sql === 'ROLLBACK') {
              if (sql === 'COMMIT') committed = true;
              if (owner === client) { owner = null; waiters.shift()?.(); }
              return { rows: [] };
            }
            if (sql.includes('pg_advisory_xact_lock')) {
              assert.equal(params[0], 'employee');
              if (owner) await new Promise(resolve => waiters.push(resolve));
              owner = client;
              return { rows: [] };
            }
            if (sql.includes('FROM leave_requests') && sql.includes('FOR UPDATE')) return { rows: [{ ...rows.get(params[0]) }] };
            if (sql.startsWith('SELECT id FROM leave_types')) return { rows: [{ id: 'type' }] };
            if (sql.includes('SELECT *') && sql.includes('FROM leave_types')) return { rows: [{ id: 'type', name: 'testAnnualLeave', display_name: 'Test Annual Leave', employee_can_file: true, requires_attachment: false, minimum_advance_days: 0, balance_ledger_type: 'none', entitlement_basis: 'annual', max_days: limit }] };
            if (sql.includes('FROM generate_series')) {
              const days = [];
              for (let date = new Date(params[1] + 'T12:00:00Z'); date.toISOString().slice(0,10) <= params[2]; date.setUTCDate(date.getUTCDate()+1)) {
                days.push({ attendance_date: date.toISOString().slice(0,10), working_days: [1,2,3,4,5], has_assignment: true, has_shift: true });
              }
              return { rows: days };
            }
            if (sql.includes('SELECT 1') && sql.includes('FROM leave_requests')) return { rows: [] }; // Disjoint ranges.
            if (sql.includes('max_days') && sql.includes('FROM leave_types')) {
              return { rows: [{ display_name: 'Test Annual Leave', max_days: limit, entitlement_basis: 'annual' }] };
            }
            if (sql.includes('SELECT lr.id, lr.start_date, lr.end_date, lr.status')) {
              const usage = committed ? [...rows.values()].filter(r => r.status === 'pending_hr' && r.id !== params[5]) : [];
              checkReads.push({ locked: owner === client, usage: usage.length });
              await new Promise(resolve => setImmediate(resolve));
              return { rows: usage.map(r => ({ ...r })) };
            }
            if (sql.startsWith('INSERT INTO leave_requests')) {
              inserts++;
              const row = { id: `new-${inserts}`, status: 'draft', user_id: 'employee', employee_id: 'employee', start_date: params[2], end_date: params[3] };
              rows.set(row.id, row);
              return { rows: [{ ...row }] };
            }
            if (sql.startsWith('UPDATE leave_requests') && sql.includes('leave_type_id =')) {
              const row = rows.get(params[6]); row.status = params[8]; row.start_date = params[1]; row.end_date = params[2]; return { rows: [{ ...row }] };
            }
            if (sql.startsWith('UPDATE leave_requests') && sql.includes('SET status =')) rows.get(params[3]).status = params[0];
            if (sql.startsWith('SELECT balance_ledger_type')) return { rows: [{ balance_ledger_type: 'none' }] };
            return { rows: [] };
          },
        };
        return client;
      },
    };
    const restores = [];
    const mock = (path, value) => restores.push(withMockedModule(path, value));
    mock('../src/config/db', { pool });
    mock('fs', { ...require('node:fs'), writeFileSync: () => {} });
    mock('../src/services/leaveFinalReviewerService', { assertLeaveSubmissionReviewer: async () => {} });
    mock('../src/services/departmentHeadService', { getDepartmentReviewSnapshot: async () => null });
    mock('../src/services/departmentReviewerService', { replaceRequestReviewerSnapshot: async () => {} });
    mock('../src/services/leaveRequestDetailsPolicy', { ...require('../src/services/leaveRequestDetailsPolicy'), loadEmployeeOfficialSnapshot: async () => ({}) });
    mock('../src/services/leaveRequestHistory', { initLeaveRequestHistory: async () => {}, insertLeaveRequestHistory: async () => {} });
    mock('../src/services/leaveBalanceLedger', { ...require('../src/services/leaveBalanceLedger'), initLeaveBalanceLedger: async () => {} });
    mock('../src/services/leaveNotifications', { notifyAfterSubmit: async () => {} });
    const path = '../src/routes/leaveRoutes';
    clearModule(path);
    try {
      const router = require(path);
      const handler = p => router.stack.find(l => l.route?.path === p && l.route.methods[p === '/:id' ? 'put' : 'post']).route.stack.at(-1).handle;
      const res = () => ({ code: 200, status(n) { this.code = n; return this; }, json(v) { this.body = v; } });
      const req = () => ({ user: { id: 'employee' }, params: { id: 'draft-2' }, body: { status: 'pending', leave_type: 'testAnnualLeave', start_date: firstDates[0], end_date: firstDates[1], details: { location_option: 'withinPhilippines', location_details: 'Test' } }, file: { originalname: 'test.pdf', mimetype: 'application/pdf', buffer: Buffer.from('%PDF-1.4 test') } });
      const first = res(), second = res();
      const secondRequest = req();
      secondRequest.body.start_date = secondDates[0]; secondRequest.body.end_date = secondDates[1];
      await Promise.all([handler('/submit')(req(), first), handler(secondPath)(secondRequest, second)]);
      assert.equal(first.code, 201, JSON.stringify(first.body));
      assert.equal(second.code, allowed ? 201 : 400);
      if (!allowed) assert.match(second.body.error, /limited to .* days per calendar year/);
      assert.equal(inserts, allowed ? 2 : 1);
      assert.deepEqual(checkReads, [{ locked: true, usage: 0 }, { locked: true, usage: 1 }]);
    } finally { clearModule(path); restores.reverse().forEach(restore => restore()); }
  });
}


