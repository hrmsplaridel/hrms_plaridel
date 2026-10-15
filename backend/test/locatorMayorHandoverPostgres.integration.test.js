'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');
const { getLocatorSourceSignatures, signLocatorSourceSlot, persistLocatorSignature } = require('../src/services/locatorSignatureService');

const pending = '11111111-1111-4111-8111-111111111111';
const employee = '22222222-2222-4222-8222-222222222222';
const former = '33333333-3333-4333-8333-333333333333';
const current = '44444444-4444-4444-8444-444444444444';
const asset = '55555555-5555-4555-8555-555555555555';
const oldAsset = '66666666-6666-4666-8666-666666666666';
const approved = '77777777-7777-4777-8777-777777777777';
const failed = '88888888-8888-4888-8888-888888888888';
const applicantAsset = '99999999-9999-4999-8999-999999999999';

// Only pg_temp fixtures/functions are written; all changes roll back on completion.
test('one-active-Mayor handover persists matching approval ink and history without changing approved forms',
  { skip: !process.env.LOCATOR_MAYOR_HANDOVER_TEST_DATABASE_URL }, async () => {
    const db = new Client({ connectionString: process.env.LOCATOR_MAYOR_HANDOVER_TEST_DATABASE_URL });
    await db.connect();
    try {
      await db.query('BEGIN');
      await db.query('CREATE TEMP TABLE fixture_anchor(id int); SET LOCAL search_path = pg_temp');
      await db.query(`
        CREATE TEMP TABLE users(id uuid PRIMARY KEY, full_name text, role text, is_active boolean,
          employment_status text DEFAULT 'active', date_hired date, separation_date date, created_at timestamptz DEFAULT now());
        CREATE UNIQUE INDEX fixture_single_active_mayor ON users(role) WHERE role='mayor' AND is_active=true;
        CREATE TEMP TABLE assignments(id uuid, employee_id uuid, position_id uuid, department_id uuid,
          is_active boolean, effective_from date, effective_to date, created_at timestamptz);
        CREATE TEMP TABLE positions(id uuid, name text);
        CREATE TEMP TABLE departments(id uuid, name text);
        CREATE TEMP TABLE locator_slips(id uuid PRIMARY KEY, employee_id uuid REFERENCES users(id),
          slip_date date, office text, reason text, request_type text, am_in boolean, am_out boolean,
          pm_in boolean, pm_out boolean, department_id uuid, attachment_path text, attachment_uploaded_at timestamptz,
          status text, final_review_route text, final_reviewer_user_id uuid REFERENCES users(id),
          request_type_label_snapshot text, request_type_location_label_snapshot text,
          print_signatories jsonb, signature_revision integer DEFAULT 1, print_template_version_id uuid,
          assigned_department_head_id uuid, dept_head_reviewer_id uuid, hr_reviewer_id uuid);
        CREATE TEMP TABLE locator_request_types(code text, label text, location_label text);
        CREATE TEMP TABLE locator_print_template_versions(id uuid, background_pdf bytea, print_layout jsonb);
        CREATE TEMP TABLE locator_slip_department_reviewers(locator_slip_id uuid, reviewer_id uuid, reviewer_role text);
        CREATE TEMP TABLE docutracker_signature_assets(id uuid PRIMARY KEY,owner_user_id uuid REFERENCES users(id),mime_type text,image_bytes bytea);
        CREATE TEMP TABLE docutracker_locator_signatures(id uuid DEFAULT gen_random_uuid(),
          locator_slip_id uuid REFERENCES locator_slips(id), revision integer, slot_key text,
          signature_asset_id uuid REFERENCES docutracker_signature_assets(id), signed_by uuid REFERENCES users(id),
          signer_name_snapshot text, signed_at timestamptz DEFAULT now(), UNIQUE(locator_slip_id,revision,slot_key));
        CREATE TEMP TABLE locator_slip_history(id uuid DEFAULT gen_random_uuid(),locator_slip_id uuid REFERENCES locator_slips(id),
          action text,from_status text,to_status text,actor_id uuid,actor_name_snapshot text,actor_role text,
          remarks text,metadata jsonb,created_at timestamptz);
      `);
      const migration = fs.readFileSync(path.join(__dirname, '../scripts/migrations/dtr/20261001_locator_signatures.sql'), 'utf8');
      const revisionFunction = migration.match(/CREATE OR REPLACE FUNCTION invalidate_locator_signatures\(\)[\s\S]*?\$\$ LANGUAGE plpgsql;/)[0]
        .replace('FUNCTION invalidate_locator_signatures()', 'FUNCTION pg_temp.invalidate_locator_signatures()');
      await db.query(revisionFunction);
      await db.query('CREATE TRIGGER fixture_revision BEFORE UPDATE ON locator_slips FOR EACH ROW EXECUTE FUNCTION pg_temp.invalidate_locator_signatures()');
      await db.query(`INSERT INTO users(id,full_name,role,is_active) VALUES
        ($1,'Employee','employee',true),($2,'Former Mayor','mayor',true),($3,'Replacement Mayor','mayor',false)`, [employee, former, current]);
      const officials = { applicant: { id: employee, name: 'Employee', position_title: 'Administrative Aide' },
        department_head: { id: null, name: '', position_title: '' },
        hr_approver: { id: former, name: 'Former Mayor', position_title: 'Municipal Mayor' } };
      await db.query(`INSERT INTO locator_slips(id,employee_id,slip_date,status,final_review_route,final_reviewer_user_id,print_signatories,hr_reviewer_id)
        VALUES($1,$3,'2026-10-15','pending_mayor','mayor_direct',$4,$5,null),
              ($2,$3,'2026-10-14','approved','mayor_direct',$4,$5,$4)`, [pending, approved, employee, former, officials]);
      for (const [assetId, owner, image] of [[asset, current, 'new ink'], [oldAsset, former, 'old ink'], [applicantAsset, employee, 'applicant ink']]) {
        await db.query("INSERT INTO docutracker_signature_assets VALUES($1,$2,'image/png',$3)", [assetId, owner, Buffer.from(image)]);
      }
      await db.query(`INSERT INTO docutracker_locator_signatures(locator_slip_id,revision,slot_key,signature_asset_id,signed_by,signer_name_snapshot)
        VALUES($1,1,'hr_approver',$4,$3,'Former Mayor'),($2,1,'hr_approver',$4,$3,'Former Mayor'),
        ($1,1,'applicant',$6,$5,'Employee')`, [pending, approved, former, oldAsset, employee, applicantAsset]);
      const historicalBefore = (await db.query('SELECT to_jsonb(s) AS record FROM locator_slips s WHERE id=$1', [approved])).rows[0].record;
      const read = requestId => getLocatorSourceSignatures(db, { id: employee, role: 'employee' }, 'dtr', 'locator_slips', requestId);
      const historicalPrint = await read(approved);

      // Replacement is sequential: a second active Mayor is prohibited even in these fixtures.
      await db.query('SAVEPOINT duplicate_mayor');
      await assert.rejects(db.query('UPDATE users SET is_active=true WHERE id=$1', [current]), { code: '23505' });
      await db.query('ROLLBACK TO SAVEPOINT duplicate_mayor');
      await db.query('UPDATE users SET is_active=false WHERE id=$1', [former]);
      await db.query('UPDATE users SET is_active=true WHERE id=$1', [current]);
      assert.equal((await db.query("SELECT count(*)::int AS n FROM users WHERE role='mayor' AND is_active=true")).rows[0].n, 1);
      assert.equal((await read(pending)).print_signatories.hr_approver.name, 'Former Mayor', 'reads do not perform a handover');
      const actor = { id: current, role: 'mayor' };
      await assert.rejects(persistLocatorSignature(db, actor, pending, 'hr_approver', null), { code: 'CONFLICT' });
      await assert.rejects(persistLocatorSignature(db, actor, pending, 'hr_approver', { signature_asset_id: oldAsset }), { code: 'FORBIDDEN' });
      assert.equal((await db.query('SELECT count(*)::int AS n FROM locator_slip_history')).rows[0].n, 0);

      // Keep the service's transaction/savepoint behavior inside this disposable outer transaction.
      const pool = { query: db.query.bind(db), connect: async () => ({
        async query(sql, params) {
          if (sql === 'BEGIN') return db.query('SAVEPOINT signature_write');
          if (sql === 'COMMIT') return db.query('RELEASE SAVEPOINT signature_write');
          if (sql === 'ROLLBACK') {
            await db.query('ROLLBACK TO SAVEPOINT signature_write');
            return db.query('RELEASE SAVEPOINT signature_write');
          }
          return db.query(sql, params);
        }, release() {},
      }) };
      await signLocatorSourceSlot(pool, actor, 'dtr', 'locator_slips', pending, 'hr_approver', { signature_asset_id: asset });
      const row = (await db.query('SELECT * FROM locator_slips WHERE id=$1', [pending])).rows[0];
      assert.equal(row.final_reviewer_user_id, current);
      assert.equal(row.print_signatories.hr_approver.id, current);
      assert.deepEqual(row.print_signatories.applicant, officials.applicant);
      assert.equal(row.signature_revision, 1);
      const history = (await db.query("SELECT * FROM locator_slip_history WHERE action='mayor_reassigned'")).rows[0];
      assert.equal(history.actor_id, current);
      assert.equal(history.metadata.previous_final_reviewer_user_id, former);
      assert.equal(history.metadata.previous_printed_approver.id, former);
      assert.equal(history.metadata.new_printed_approver.id, current);
      await persistLocatorSignature(db, actor, pending, 'hr_approver', null);
      assert.equal((await db.query("SELECT count(*)::int AS n FROM locator_slip_history WHERE action='mayor_reassigned'")).rows[0].n, 1);
      await db.query("UPDATE locator_slips SET status='approved',hr_reviewer_id=$2 WHERE id=$1", [pending, current]);
      const printed = await read(pending);
      assert.deepEqual(printed.print_signatories.hr_approver, { name: 'Replacement Mayor', position_title: 'Municipal Mayor',
        signature_image_base64: Buffer.from('new ink').toString('base64') });
      assert.equal(printed.print_signatories.applicant.signature_image_base64, Buffer.from('applicant ink').toString('base64'));

      // A DB write failure after reassignment must roll back the identity and audit together.
      await db.query(`INSERT INTO locator_slips(id,employee_id,slip_date,status,final_review_route,final_reviewer_user_id,print_signatories)
        VALUES($1,$2,'2026-10-15','pending_mayor','mayor_direct',$3,$4)`, [failed, employee, former, officials]);
      await db.query(`CREATE FUNCTION pg_temp.fail_fixture_signature() RETURNS trigger AS $$ BEGIN
        IF NEW.locator_slip_id='${failed}'::uuid THEN RAISE EXCEPTION 'Simulated signature storage failure'; END IF;
        RETURN NEW; END; $$ LANGUAGE plpgsql;
        CREATE TRIGGER fixture_signature_failure BEFORE INSERT ON docutracker_locator_signatures
        FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_fixture_signature();`);
      await assert.rejects(signLocatorSourceSlot(pool, actor, 'dtr', 'locator_slips', failed, 'hr_approver', { signature_asset_id: asset }), /Simulated signature storage failure/);
      assert.equal((await db.query('SELECT final_reviewer_user_id FROM locator_slips WHERE id=$1', [failed])).rows[0].final_reviewer_user_id, former);
      assert.equal((await db.query('SELECT count(*)::int AS n FROM locator_slip_history WHERE locator_slip_id=$1', [failed])).rows[0].n, 0);

      await db.query('UPDATE users SET is_active=false WHERE id=$1', [current]);
      await db.query('UPDATE users SET is_active=true WHERE id=$1', [former]);
      await assert.rejects(signLocatorSourceSlot(pool, { id: former, role: 'mayor' }, 'dtr', 'locator_slips', pending,
        'hr_approver', { signature_asset_id: oldAsset }), { code: 'FORBIDDEN' });
      assert.deepEqual(await read(pending), printed, 'another handover cannot relabel an approved form');
      assert.deepEqual(await read(approved), historicalPrint);
      assert.deepEqual((await db.query('SELECT to_jsonb(s) AS record FROM locator_slips s WHERE id=$1', [approved])).rows[0].record, historicalBefore);
    } finally {
      await db.query('ROLLBACK');
      await db.end();
    }
  });
