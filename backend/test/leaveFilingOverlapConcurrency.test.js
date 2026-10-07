const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

for (const { secondPath, overlaps } of [
  ...['/submit', '/submit-with-attachment', '/:id'].map(secondPath => ({ secondPath, overlaps: true })),
  { secondPath: '/submit', overlaps: false },
]) {
  test(`concurrent JSON filing and ${secondPath} ${overlaps ? "reject overlapping request" : "accept disjoint requests"}`, async () => {
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
            if (sql.includes('SELECT *') && sql.includes('FROM leave_types')) return { rows: [{ id: 'type', name: 'vacationLeave', employee_can_file: true, minimum_advance_days: 0, balance_ledger_type: 'none', entitlement_basis: 'unlimited' }] };
            if (sql.includes('FROM generate_series')) return { rows: [2, 3].map(day => ({ attendance_date: `2026-11-0${day}`, working_days: [1,2,3,4,5], has_assignment: true, has_shift: true })) };
            if (sql.includes('SELECT 1') && sql.includes('FROM leave_requests')) {
              // Snapshot the check and yield so concurrent unlocked reads both see empty.
              const overlap = committed && params[1] <= '2026-11-03';
              checkReads.push({ locked: owner === client, overlap });
              await new Promise(resolve => setImmediate(resolve));
              return { rows: overlap ? [{ exists: 1 }] : [] };
            }
            if (sql.startsWith('INSERT INTO leave_requests')) {
              inserts++;
              const row = { id: `new-${inserts}`, status: 'draft', user_id: 'employee', employee_id: 'employee', start_date: params[2], end_date: params[3] };
              rows.set(row.id, row);
              return { rows: [{ ...row }] };
            }
            if (sql.startsWith('UPDATE leave_requests') && sql.includes('leave_type_id =')) {
              const row = rows.get(params[6]); row.status = params[8]; return { rows: [{ ...row }] };
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
      const req = () => ({ user: { id: 'employee' }, params: { id: 'draft-2' }, body: { status: 'pending', leave_type: 'vacationLeave', start_date: '2026-11-02', end_date: '2026-11-03', details: { location_option: 'withinPhilippines', location_details: 'Test' } }, file: { originalname: 'test.pdf', mimetype: 'application/pdf', buffer: Buffer.from('%PDF-1.4 test') } });
      const first = res(), second = res();
      const secondRequest = req();
      if (!overlaps) { secondRequest.body.start_date = '2026-11-04'; secondRequest.body.end_date = '2026-11-05'; }
      await Promise.all([handler('/submit')(req(), first), handler(secondPath)(secondRequest, second)]);
      assert.equal(first.code, 201);
      assert.equal(second.code, overlaps ? 400 : 201);
      if (overlaps) assert.match(second.body.error, /Overlapping leave request/);
      assert.equal(inserts, overlaps ? 1 : 2);
      assert.deepEqual(checkReads, [{ locked: true, overlap: false }, { locked: true, overlap: overlaps }]);
    } finally { clearModule(path); restores.reverse().forEach(restore => restore()); }
  });
}
