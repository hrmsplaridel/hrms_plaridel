const { Pool } = require('pg');
const pool = new Pool({
  connectionString: 'postgresql://postgres:postgre123@localhost:5432/hrms_plaridel'
});

async function inspect() {
  try {
    const res = await pool.query(`
      SELECT column_name, data_type, is_nullable, column_default
      FROM information_schema.columns
      WHERE table_name = 'docutracker_documents'
      ORDER BY ordinal_position;
    `);
    console.log(JSON.stringify(res.rows, null, 2));
  } catch (err) {
    console.error(err);
  } finally {
    await pool.end();
  }
}

inspect();
