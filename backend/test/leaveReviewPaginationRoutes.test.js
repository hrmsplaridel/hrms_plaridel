const test = require('node:test');
const assert = require('node:assert/strict');

const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

function responseRecorder() {
  return {
    statusCode: 200,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
  };
}

test('HR and department-head queues page past 200 and expose complete filter choices', async () => {
  const rows = Array.from({ length: 251 }, (_, index) => ({
    id: `request-${index}`,
    user_id: `employee-${index}`,
    employee_full_name: `Employee ${index}`,
    assignment_department_name: index === 250 ? 'Records' : 'Finance',
    leave_type_name: 'vacationLeave',
    status: 'pending_hr',
  }));
  const seen = [];
  const query = async (sql, params = []) => {
    const statement = String(sql).replace(/\s+/g, ' ').trim();
    if (statement.startsWith('SELECT lr.*')) {
      seen.push({ statement, params });
      const departmentHead = statement.includes('dhh.department_head_reviewer_id IS NOT NULL');
      const userId = params[departmentHead ? 3 : 2];
      const department = params[departmentHead ? 8 : 7];
      let matching = rows;
      if (userId) matching = matching.filter((row) => row.user_id === userId);
      if (department) matching = matching.filter(
        (row) => row.assignment_department_name === department
      );
      const limit = Number(statement.match(/LIMIT (\d+) (?:OFFSET|$)/)?.[1] || matching.length);
      const offset = Number(statement.match(/OFFSET (\d+)$/)?.[1] || 0);
      return { rows: matching.slice(offset, offset + limit) };
    }
    if (statement.startsWith('SELECT COUNT(*)::int AS total')) {
      const departmentHead = statement.includes('dhh.department_head_reviewer_id IS NOT NULL');
      const userId = params[departmentHead ? 3 : 2];
      const department = params[departmentHead ? 8 : 7];
      const total = rows.filter((row) =>
        (!userId || row.user_id === userId) &&
        (!department || row.assignment_department_name === department)
      ).length;
      return { rows: [{ total }] };
    }
    if (statement.startsWith('SELECT DISTINCT COALESCE(')) {
      return { rows: rows.map((row) => ({
        user_id: row.user_id,
        employee_name: row.employee_full_name,
        department: row.assignment_department_name,
      })) };
    }
    return { rows: [] }; // Router startup schema checks.
  };
  const pool = { query, connect: async () => ({ query, release() {} }) };
  const restoreDb = withMockedModule('../src/config/db', { pool });
  clearModule('../src/routes/leaveRoutes');
  try {
    const router = require('../src/routes/leaveRoutes');
    const handler = (path) => router.stack.find(
      (entry) => entry.route?.path === path && entry.route.methods.get
    ).route.stack.at(-1).handle;
    for (const departmentHead of [false, true]) {
      const path = departmentHead ? '/department-head' : '/';
      const run = async (queryParams) => {
        const res = responseRecorder();
        await handler(path)({
          user: { id: 'reviewer', role: 'admin' },
          query: queryParams,
        }, res);
        assert.equal(res.statusCode, 200);
        return res.body;
      };

      const first = await run({ paginated: 'true', limit: '200', offset: '0' });
      assert.equal(first.items.length, 200);
      assert.equal(first.total, 251);
      assert.equal(first.has_more, true);

      const second = await run({ paginated: 'true', limit: '200', offset: '200' });
      assert.equal(second.items.length, 51);
      assert.equal(second.items.at(-1).id, 'request-250');
      assert.equal(second.has_more, false);

      const filtered = await run({
        paginated: 'true', limit: '200', offset: '0',
        user_id: 'employee-250', department: 'Records',
      });
      assert.equal(filtered.total, 1);
      assert.equal(filtered.items[0].id, 'request-250');
      assert.match(seen.at(-1).statement, /AND \(\$\d+::text IS NULL OR d.name = \$\d+\)/);

      const legacy = await run({ limit: '200' });
      assert.ok(Array.isArray(legacy));

      const optionsPath = departmentHead
        ? '/department-head/filter-options'
        : '/filter-options';
      const optionsRes = responseRecorder();
      await handler(optionsPath)({ user: { id: 'reviewer' } }, optionsRes);
      assert.equal(optionsRes.body.length, 251);
      assert.equal(optionsRes.body.at(-1).user_id, 'employee-250');
    }
  } finally {
    clearModule('../src/routes/leaveRoutes');
    restoreDb();
  }
});
