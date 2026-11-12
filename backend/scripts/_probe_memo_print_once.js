const path = require('path');
require('dotenv').config({
  path: path.resolve(__dirname, '../.env'),
  override: true,
});
const { Pool } = require('pg');

(async () => {
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    connectionTimeoutMillis: 10000,
  });
  const client = await pool.connect();
  try {
    const db = await client.query('SELECT current_database() AS db');
    console.log('db', db.rows[0].db);
    const type = await client.query(
      `SELECT document_type, print_template_version_id
       FROM docutracker_document_types WHERE document_type = 'memo'`,
    );
    console.log('memo type', type.rows[0]);
    if (type.rows[0]?.print_template_version_id) {
      const v = await client.query(
        `SELECT id,
                background_name,
                (background_pdf IS NOT NULL) AS has_bg,
                jsonb_typeof(print_layout) AS layout_type,
                jsonb_array_length(COALESCE(print_layout->'elements','[]'::jsonb)) AS elements
         FROM docutracker_print_template_versions WHERE id = $1`,
        [type.rows[0].print_template_version_id],
      );
      console.log('memo version', v.rows[0]);
      const sources = await client.query(
        `SELECT e->>'kind' AS kind, e->>'source' AS source, e->>'label' AS label
         FROM docutracker_print_template_versions v,
              LATERAL jsonb_array_elements(COALESCE(v.print_layout->'elements','[]'::jsonb)) e
         WHERE v.id = $1
         ORDER BY 1,2`,
        [type.rows[0].print_template_version_id],
      );
      console.log('elements', sources.rows);
    }
    const docs = await client.query(
      `SELECT id, title, print_form_selection, print_template_version_id, created_at
       FROM docutracker_documents
       WHERE document_type = 'memo' AND deleted_at IS NULL
       ORDER BY created_at DESC NULLS LAST
       LIMIT 8`,
    );
    console.log('recent memos', docs.rows);
  } finally {
    client.release();
    await pool.end();
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
