const test = require('node:test');
const assert = require('node:assert/strict');

const { withMockedModule, clearModule } = require('./helpers/moduleMocks');

function responseRecorder() {
  return {
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}

for (const firstAction of ['reject', 'return']) {
  test(`simultaneous HR ${firstAction} and opposing decision release credits once`, async () => {
    const secondAction = firstAction === 'reject' ? 'return' : 'reject';
    const requestId = '11111111-1111-4111-8111-111111111111';
    const employeeId = '22222222-2222-4222-8222-222222222222';
    const row = {
      id: requestId,
      user_id: employeeId,
      status: 'pending_hr',
      number_of_days: 3,
      reserved_credit_days: 3,
      leave_type_name: 'vacationLeave',
    };
    let pendingDays = 5; // Includes two days reserved by another request.
    let lockOwner = null;
    const lockWaiters = [];
    const history = [];
    const ledger = [];
    const updates = [];
    const lockedReads = [];

    async function acquire(client) {
      if (lockOwner) {
        await new Promise((resolve) => lockWaiters.push(resolve));
      }
      lockOwner = client;
    }

    function unlock(client) {
      if (lockOwner !== client) return;
      lockOwner = null;
      lockWaiters.shift()?.();
    }

    const pool = {
      async connect() {
        const client = {
          async query(sql, params = []) {
            const statement = String(sql).replace(/\s+/g, ' ').trim();
            if (statement === 'BEGIN') return { rows: [] };
            if (statement === 'COMMIT' || statement === 'ROLLBACK') {
              unlock(client);
              return { rows: [] };
            }
            if (statement.startsWith('SELECT lr.status, COALESCE(')) {
              lockedReads.push(statement);
              assert.match(statement, /FOR UPDATE OF lr$/);
              await acquire(client);
              return { rows: [{ ...row, days: row.number_of_days }] };
            }
            if (statement.includes('FROM positions p')) {
              return { rows: [{ id: '33333333-3333-4333-8333-333333333333', name: 'Primary' }] };
            }
            if (statement.includes('FROM leave_final_reviewer_backups')) {
              return { rows: [{ id: '44444444-4444-4444-8444-444444444444', name: 'Backup' }] };
            }
            if (statement.startsWith('UPDATE leave_requests')) {
              assert.equal(lockOwner, client);
              row.status = statement.includes("status = 'returned'")
                ? 'returned'
                : params[3];
              row.reserved_credit_days = 0;
              updates.push(row.status);
              return { rows: [] };
            }
            if (statement.startsWith('INSERT INTO leave_request_history')) {
              history.push(params[1]);
              return { rows: [] };
            }
            if (statement.startsWith('SELECT balance_ledger_type')) {
              return { rows: [{ balance_ledger_type: 'vacationLeave' }] };
            }
            if (statement.includes('FROM leave_balances')) {
              return { rows: [{
                earned_days: 10,
                used_days: 0,
                pending_days: pendingDays,
                adjusted_days: 0,
              }] };
            }
            if (statement.startsWith('UPDATE leave_balances')) {
              pendingDays = Math.max(0, pendingDays - Number(params[2]));
              return { rows: [] };
            }
            if (statement.startsWith('INSERT INTO leave_balance_ledger')) {
              ledger.push(params[4]);
              return { rows: [] };
            }
            throw new Error(`Unexpected SQL: ${statement}`);
          },
          release() {},
        };
        return client;
      },
      async query(sql) {
        if (String(sql).includes('FROM leave_requests lr')) {
          return { rows: [{ ...row }] };
        }
        // The leave router ensures supporting tables when it is imported.
        return { rows: [] };
      },
    };

    const restoreDb = withMockedModule('../src/config/db', { pool });
    const restoreNotifications = withMockedModule('../src/services/leaveNotifications', {
      notifyEmployee: async () => {},
    });
    const restoreAppEvents = withMockedModule('../src/websockets/appEvents', {
      broadcastAppEvent: () => {},
    });
    const restoreBiometric = withMockedModule('../src/websockets/biometricStream', {
      broadcastBiometricUpdate: () => {},
    });
    clearModule('../src/routes/leaveRoutes');
    const originalConsoleError = console.error;
    console.error = () => {}; // The losing reviewer receives an expected 400.
    try {
      const router = require('../src/routes/leaveRoutes');
      const handlerFor = (action) => router.stack.find(
        (entry) => entry.route?.path === `/:id/${action}` && entry.route.methods.patch
      ).route.stack.at(-1).handle;
      const requestFor = (reviewerId) => ({
        params: { id: requestId },
        user: { id: reviewerId, role: 'admin' },
        body: { reason: 'Reviewed' },
      });
      const firstResponse = responseRecorder();
      const secondResponse = responseRecorder();

      await Promise.all([
        handlerFor(firstAction)(requestFor('33333333-3333-4333-8333-333333333333'), firstResponse),
        handlerFor(secondAction)(requestFor('44444444-4444-4444-8444-444444444444'), secondResponse),
      ]);

      assert.equal(firstResponse.statusCode, 200);
      assert.equal(secondResponse.statusCode, 400);
      assert.equal(row.status, firstAction === 'reject' ? 'rejected_by_hr' : 'returned');
      assert.equal(pendingDays, 2);
      assert.equal(updates.length, 1);
      assert.equal(history.length, 1);
      assert.deepEqual(ledger, [-3]);
      assert.equal(lockedReads.length, 2);
    } finally {
      console.error = originalConsoleError;
      clearModule('../src/routes/leaveRoutes');
      restoreBiometric();
      restoreAppEvents();
      restoreNotifications();
      restoreDb();
    }
  });
}
