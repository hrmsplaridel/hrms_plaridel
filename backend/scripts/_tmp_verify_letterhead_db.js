const path = require('path');
require('dotenv').config({
  path: path.resolve(__dirname, '../.env'),
  override: true,
});
const { Pool } = require('pg');
const { buildPoolOptions } = require('../src/config/databasePoolOptions');

(async () => {
  const pool = new Pool(buildPoolOptions());
  const client = await pool.connect();
  try {
    const who = await client.query(`
      SELECT current_database() AS database,
             inet_server_addr() AS server_addr,
             inet_server_port() AS server_port,
             current_user AS db_user
    `);
    const letterhead = await client.query(`
      SELECT document_type, source_name,
             octet_length(background_pdf) AS pdf_bytes,
             octet_length(letterhead_png) AS png_bytes,
             encode(substring(background_pdf FROM 1 FOR 8), 'escape') AS pdf_start,
             encode(substring(letterhead_png FROM 1 FOR 8), 'escape') AS png_start,
             (SELECT count(*) FROM docutracker_letterheads) AS row_count
      FROM docutracker_letterheads
    `);
    const print = await client.query(`
      SELECT document_type, print_template_version_id IS NOT NULL AS has_custom_print
      FROM docutracker_document_types
      WHERE document_type IN ('memo', 'purchaseRequest')
      ORDER BY document_type
    `);
    console.log(JSON.stringify({ who: who.rows, letterhead: letterhead.rows, print: print.rows }, null, 2));
  } finally {
    client.release();
    await pool.end();
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
