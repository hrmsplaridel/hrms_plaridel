'use strict';
const id = n => `44444444-4444-4444-8444-${String(n).padStart(12, '0')}`;
async function seed(db, {users = 50, requests = 2000} = {}) {
  await db.query(`CREATE TABLE users(id uuid PRIMARY KEY,email text,full_name text,role text,
    is_active boolean DEFAULT true,employment_status text DEFAULT 'active',auth_version int DEFAULT 0);
    CREATE TABLE departments(id uuid PRIMARY KEY,name text);
    CREATE TABLE leave_types(id uuid PRIMARY KEY,name text);
    CREATE TABLE dtr_admin_access(admin_user_id uuid, reports_allowed boolean DEFAULT true,
      manage_allowed boolean DEFAULT true,employees_allowed boolean DEFAULT true,leave_allowed boolean DEFAULT true,
      approvals_allowed boolean DEFAULT true,locator_allowed boolean DEFAULT true);
    CREATE TABLE leave_requests(id uuid PRIMARY KEY,employee_id uuid,user_id uuid,status text,
      created_at timestamptz,workflow_snapshot jsonb,discarded_at timestamptz,leave_type_id uuid,
      signature_revision integer DEFAULT 1,department_id uuid,start_date date,end_date date,number_of_days numeric);
    CREATE TABLE locator_slips(LIKE leave_requests INCLUDING ALL);
    ALTER TABLE locator_slips ADD COLUMN slip_date date;
    CREATE INDEX ON leave_requests(created_at DESC,id DESC);
    CREATE INDEX ON locator_slips(created_at DESC,id DESC);`);
  const reviewers = Array.from({length: users}, (_, i) => id(i + 1));
  await db.query(`INSERT INTO users(id,email,full_name,role)
    SELECT value, 'synthetic-'||ordinality||'@load.invalid','Synthetic reviewer '||ordinality,
      CASE WHEN ordinality%5=0 THEN 'hr' WHEN ordinality%5=1 THEN 'admin' ELSE 'employee' END
    FROM unnest($1::uuid[]) WITH ORDINALITY AS t(value,ordinality)`, [reviewers]);
  await db.query("INSERT INTO users(id,email,full_name,role) VALUES($1,'applicant@load.invalid','Synthetic applicant','employee')", [id(999)]);
  await db.query("INSERT INTO leave_types VALUES($1,'Test Leave')", [id(900)]);
  await db.query('INSERT INTO dtr_admin_access(admin_user_id) SELECT id FROM users WHERE role=\'admin\'');
  const groups = [];
  for (let i = 0; i < reviewers.length; i += 6) groups.push(reviewers.slice(i, i + 6));
  for (const [kind, table] of [['leave', 'leave_requests'], ['locator', 'locator_slips']]) {
    for (let group = 0; group < groups.length; group++) {
      const snapshot = {name: 'Synthetic workflow', version: 1, current_step: 0,
        steps: [{assignee_source: 'specific_users', assignee_type: 'user', user_ids: groups[group],
          label: 'Department Review', allowed_actions: ['approve', 'return', 'reject']}], decisions: []};
      const amount = Math.ceil(requests / groups.length);
      const base = (kind === 'leave' ? 10000 : 100000) + group * amount;
      await db.query(`INSERT INTO ${table}(id,employee_id,user_id,status,created_at,workflow_snapshot,leave_type_id,start_date,end_date,number_of_days)
        SELECT ('44444444-4444-4444-8444-'||lpad(($1::int+i)::text,12,'0'))::uuid,$2::uuid,$2::uuid,
          CASE WHEN i%5=0 THEN 'approved' ELSE 'pending_hr' END,
          '2026-10-23 00:00:00.123456+00'::timestamptz-(i/2)*interval '1 second',
          CASE WHEN i%5=0 THEN $3::jsonb||jsonb_build_object('current_step',1,'outcome','approved',
            'decisions',jsonb_build_array(jsonb_build_object('step',0,'actor_id',$4::text,'action','approve')))
            ELSE $3::jsonb END,$5::uuid,'2026-10-23','2026-10-23',1
        FROM generate_series(1,$6::int) i`, [base, id(999), JSON.stringify(snapshot), groups[group][0], id(900), amount]);
    }
  }
  await db.query('ANALYZE');
  return (await db.query('SELECT id,role FROM users WHERE id=ANY($1::uuid[]) ORDER BY id', [reviewers])).rows;
}
module.exports = {id, seed};
