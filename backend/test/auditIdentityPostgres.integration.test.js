const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { Pool } = require('pg');
const { clearModule, withMockedModule } = require('./helpers/moduleMocks');
require('dotenv').config({ path: path.join(__dirname, '../.env') });

test('audit identities survive renames and deletion; legacy rows stay explicitly current',
  { skip: !process.env.DATABASE_URL }, async () => {
    const pool = new Pool({ connectionString: process.env.DATABASE_URL });
    const client = await pool.connect();
    const schema = `audit_test_${randomUUID().replaceAll('-', '')}`;
    const actor = randomUUID(), target = randomUUID();
    let restore;
    const routePath = '../src/routes/systemAudit';
    try {
      await client.query('BEGIN');
      await client.query(`CREATE SCHEMA ${schema}; SET LOCAL search_path TO ${schema}, public;
        CREATE TABLE users (id uuid PRIMARY KEY, full_name text, email text);
        CREATE TABLE audit_logs (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id uuid REFERENCES users(id) ON DELETE SET NULL, action text, entity_type text,
          entity_id uuid, details text, created_at timestamptz DEFAULT now());`);
      await client.query('INSERT INTO users VALUES ($1, $2, $3), ($4, $5, $6)',
        [actor, 'Original Actor', 'actor@test', target, 'Original Target', 'target@test']);
      await client.query("INSERT INTO audit_logs (user_id, action, entity_type, entity_id) VALUES ($1, 'legacy', 'user', $2)", [actor, target]);
      const migration = path.join(__dirname, '../scripts/migrations/20261004_audit_identity_snapshots.sql');
      if (fs.existsSync(migration)) await client.query(fs.readFileSync(migration, 'utf8'));
      await client.query("INSERT INTO audit_logs (user_id, action, entity_type, entity_id) VALUES ($1, 'recorded', 'user', $2)", [actor, target]);
      const saved = await client.query("SELECT actor_snapshot, target_snapshot FROM audit_logs WHERE action = 'recorded'");
      assert.deepEqual(saved.rows[0].actor_snapshot, { id: actor, name: 'Original Actor', email: 'actor@test' });
      assert.deepEqual(saved.rows[0].target_snapshot, { id: target, name: 'Original Target', email: 'target@test' });
      for (const entityType of ['employee_account', 'auth', 'system_account']) {
        const result = await client.query("INSERT INTO audit_logs (user_id, action, entity_type, entity_id) VALUES ($1, 'audit_log_viewed', $2, $3) RETURNING target_snapshot", [actor, entityType, target]);
        assert.equal(result.rows[0].target_snapshot.name, 'Original Target');
      }
      await client.query("UPDATE users SET full_name = 'Renamed', email = 'new@test'");
      restore = withMockedModule('../src/config/db', { pool: client });
      clearModule(routePath);
      const handler = require(routePath).stack.find(e => e.route?.methods.get).route.stack.at(-1).handle;
      async function read(query = {}) {
        const res = { statusCode: 200, status(n) { this.statusCode = n; return this; }, json(body) { this.body = body; } };
        await handler({ user: { id: actor }, query: { hide_views: '1', ...query } }, res);
        assert.equal(res.statusCode, 200);
        return res.body;
      }
      const entries = (await read()).entries;
      assert.equal(entries.find(e => e.action === 'legacy').actor_identity_source, 'current');
      assert.equal(entries.find(e => e.action === 'legacy').actor_name, 'Renamed');
      assert.equal(entries.find(e => e.action === 'recorded').actor_name, 'Original Actor');
      assert.equal((await read({ actor: 'actor@test' })).total, 1);
      await client.query('DELETE FROM users');
      // No actor on this synthetic read: the deleted ID cannot pass the FK.
      const res = { statusCode: 200, status(n) { this.statusCode = n; return this; }, json(body) { this.body = body; } };
      await handler({ user: { id: null }, query: { hide_views: '1' } }, res);
      assert.equal(res.statusCode, 200);
      const recorded = res.body.entries.find(e => e.action === 'recorded');
      assert.equal(recorded.actor_name, 'Original Actor');
      assert.equal(recorded.target_name, 'Original Target');
      assert.equal(recorded.actor_snapshot.id, actor);
      assert.equal(recorded.actor_identity_source, 'recorded');
      assert.equal(res.body.entries.find(e => e.action === 'legacy').actor_identity_source, 'unavailable');
    } finally {
      clearModule(routePath);
      if (restore) restore();
      await client.query('ROLLBACK');
      client.release();
      await pool.end();
    }
  });
