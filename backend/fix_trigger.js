require('dotenv').config();
const { Pool } = require('pg');
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

async function run() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    
    // Fix the trigger
    await client.query(`
      CREATE OR REPLACE FUNCTION docutracker_enforce_step_assignees_invariants()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        sid uuid;
        enabled_count int;
        enabled_primary_count int;
      BEGIN
        sid := COALESCE(NEW.step_id, OLD.step_id);
        IF sid IS NULL THEN
          RETURN NULL;
        END IF;

        -- If the parent step has been deleted (or is being deleted), we don't need to enforce this.
        IF NOT EXISTS (SELECT 1 FROM docutracker_workflow_steps WHERE id = sid) THEN
          RETURN NULL;
        END IF;

        SELECT
          COUNT(*) FILTER (WHERE a.is_enabled = true) AS enabled_count,
          COUNT(*) FILTER (WHERE a.is_enabled = true AND a.is_primary = true) AS enabled_primary_count
        INTO enabled_count, enabled_primary_count
        FROM docutracker_workflow_step_assignees a
        WHERE a.step_id = sid;

        IF enabled_count < 1 THEN
          RAISE EXCEPTION 'Workflow step % must have at least one enabled assignee', sid
            USING ERRCODE = '23514';
        END IF;

        IF enabled_primary_count <> 1 THEN
          RAISE EXCEPTION 'Workflow step % must have exactly one enabled primary assignee', sid
            USING ERRCODE = '23514';
        END IF;

        RETURN NULL;
      END;
      $$;
    `);

    await client.query('COMMIT');
    console.log("Trigger fixed.");
  } catch (e) {
    await client.query('ROLLBACK');
    console.error("Error:", e.message);
  } finally {
    client.release();
    pool.end();
  }
}
run();
