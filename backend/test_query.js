require('dotenv').config();
const { Pool } = require('pg');
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

async function run() {
  const client = await pool.connect();
  try {
    const userRes = await client.query('SELECT id FROM users LIMIT 2');
    const u1 = userRes.rows[0].id;
    const u2 = userRes.rows[1].id;
    
    await client.query('BEGIN');
    const docType = 'memo';
    
    await client.query(`DELETE FROM docutracker_routing_config_versions WHERE document_type = $1`, [docType]);
    await client.query(`DELETE FROM docutracker_workflow_steps WHERE document_type = $1`, [docType]);
    
    const vRes = await client.query(
        `INSERT INTO docutracker_routing_config_versions
         (document_type, version, steps, review_deadline_hours, created_by)
         VALUES ($1, $2, $3::jsonb, COALESCE($4, 1), $5)
         RETURNING document_type, steps, review_deadline_hours, version`,
        [docType, 1, '[]', 1, null]
    );
    
    const s1 = await client.query(
        `INSERT INTO docutracker_workflow_steps
         (document_type, workflow_version, step_order, department_id, label, enabled)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id`,
        [docType, 1, 1, null, 'Step 1', true]
    );
    const stepId = s1.rows[0].id;
    
    await client.query(
        `INSERT INTO docutracker_workflow_step_assignees
         (step_id, user_id, is_primary, backup_rank, is_enabled, allowed_actions)
         VALUES ($1, $2, $3, $4, true, $5::text[])`,
        [stepId, u1, true, null, ['approve', 'forward', 'reject', 'return']]
    );
    
    await client.query(
        `INSERT INTO docutracker_workflow_step_assignees
         (step_id, user_id, is_primary, backup_rank, is_enabled, allowed_actions)
         VALUES ($1, $2, $3, $4, true, $5::text[])`,
        [stepId, u2, false, 1, ['approve', 'forward', 'reject', 'return']]
    );
    
    await client.query('COMMIT');
    console.log("Success with actual DB users");
  } catch (e) {
    await client.query('ROLLBACK');
    console.error("Error:", e.message);
  } finally {
    client.release();
    pool.end();
  }
}
run();
