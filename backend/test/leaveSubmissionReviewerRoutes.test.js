'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

const applicant = '11111111-1111-4111-8111-111111111111';
const requestId = '22222222-2222-4222-8222-222222222222';
const head = '33333333-3333-4333-8333-333333333333';
const department = '44444444-4444-4444-8444-444444444444';

for (const [method, path] of [
  ['post', '/submit'],
  ['post', '/submit-with-attachment'],
  ['put', '/:id'],
]) {
 for (const configuration of ['missing', 'overlapping']) {
  for (const sourceStatus of method==='put' ? ['draft','returned','rejected_by_department_head','rejected_by_hr'] : ['draft']) {
  test(`${method.toUpperCase()} ${path} from ${sourceStatus} refuses submission with ${configuration} final reviewer configuration`, async () => {
    const queries = [];
    const client = {
      async query(sql) {
        const statement = String(sql);
        queries.push(statement);
        if (statement === 'BEGIN' || statement === 'ROLLBACK') return { rows: [] };
        if (statement.includes('pg_advisory_xact_lock')) return {rows:[]};
        if (statement.includes('FROM generate_series')) return {rows:[{
          attendance_date:'2026-09-22',working_days:[1,2,3,4,5],has_assignment:true,has_shift:true,
        }]};
        if (statement.startsWith('SELECT id FROM leave_types')) return {rows:[{id:requestId}]};
        if (statement.includes('SELECT *') && statement.includes('FROM leave_types')) return {rows:[{
          id:requestId,name:'vacationLeave',employee_can_file:true,is_active:true,
          minimum_advance_days:0,balance_ledger_type:'none',employee_detail_schema:[],
        }]};
        if (statement.includes('FROM leave_requests') && statement.includes('FOR UPDATE')) return {rows:[{id:requestId,status:sourceStatus}]};
        if (statement.includes('FROM assignments a')) return {rows:configuration==='overlapping' ? [{department_id:department}] : []};
        if (statement.includes('primary_reviewer_designations head_period')) return {rows:[{reviewer_id:head,reviewer_name:'Head'}]};
        if (statement.includes('primary_reviewer_designations designation')) return {rows:configuration==='overlapping' ? [{id:head}] : []};
        if (statement.includes('department_reviewer_backups') || statement.includes('FROM leave_final_reviewer_backups')) {
          return { rows: [] };
        }
        throw new Error(`Unexpected SQL: ${statement}`);
      },
      release() {},
    };
    const restoreDb = withMockedModule('../src/config/db', {
      pool: {
        connect: async () => client,
        query: async (sql) => {
          if (String(sql).includes('FROM leave_requests')) {
            return { rows: [{ id: requestId, status: sourceStatus }] };
          }
          return { rows: [] };
        },
      },
    });
    clearModule('../src/routes/leaveRoutes');
    try {
      const router = require('../src/routes/leaveRoutes');
      const route = router.stack.find((entry) => entry.route?.path === path && entry.route.methods[method]);
      const response = {
        statusCode: 200,
        status(code) { this.statusCode = code; return this; },
        json(body) { this.body = body; return this; },
      };
      const request = {
        user: { id: applicant, role: 'employee' },
        params: { id: requestId },
        body: { leave_type: 'Vacation Leave', start_date: '2026-09-22', end_date: '2026-09-22', status: 'pending' },
        file: method === 'post' && path.includes('attachment') ? { buffer: Buffer.from('test') } : undefined,
      };
      const originalError = console.error;
      console.error = () => {};
      try {
        await route.route.stack.at(-1).handle(request, response);
      } finally {
        console.error = originalError;
      }
      assert.equal(response.statusCode, 409);
      assert.match(response.body.error, /final leave reviewer|different final HR reviewer/i);
      assert.ok(queries.includes('ROLLBACK'));
      assert.equal(queries.some((sql) => /INSERT INTO leave_requests|UPDATE leave_requests/.test(sql)), false);
    } finally {
      clearModule('../src/routes/leaveRoutes');
      restoreDb();
    }
  });
  }
 }
}
