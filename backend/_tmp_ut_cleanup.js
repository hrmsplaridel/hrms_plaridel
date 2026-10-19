/**
 * Cleanup AFTER usability sessions complete.
 * Deletes only UT-* docs DOC-2026-000042/043/044 and the temporary
 * Kristoffer release permission + Dann HR Office primary designation
 * created for this pass.
 *
 * Does NOT touch DOC-2026-000041.
 * Does NOT drop primary_reviewer_designations (shared prerequisite table).
 *
 * Usage: node _tmp_ut_cleanup.js
 */
require('dotenv').config();
const { pool } = require('./src/config/db');

const DOC_IDS = [
  'c385644d-4b0b-4ec5-b867-841a07852e34', // UT-REV-QUEUE-DEMO / DOC-2026-000042
  '69e2575f-df1b-4941-adbe-13ee9717106a', // UT-HR-AWAITING-RELEASE / DOC-2026-000043
  '841d9f95-5679-4e34-8d77-789191947151', // UT-EMP-RELEASED-DEMO / DOC-2026-000044
];
const PERM_ID = 'f590038b-aaf6-4938-8630-4819459047d5';
const DESIGNATION_ID = '4349809b-12c4-4a26-915a-f7f3c48069f2';
const PROTECTED = 'DOC-2026-000041';

(async () => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const protected = await client.query(
      `SELECT document_number, updated_at FROM docutracker_documents
       WHERE document_number = $1`,
      [PROTECTED]
    );
    console.log('protected before', protected.rows[0]);

    for (const id of DOC_IDS) {
      await client.query(`DELETE FROM docutracker_notifications WHERE document_id = $1`, [id]);
      await client.query(`DELETE FROM docutracker_document_history WHERE document_id = $1`, [id]);
      await client.query(`DELETE FROM docutracker_transition_requests WHERE document_id = $1`, [id]);
      await client.query(
        `DELETE FROM docutracker_routing_record_assignees
         WHERE routing_record_id IN (
           SELECT id FROM docutracker_routing_records WHERE document_id = $1
         )`,
        [id]
      );
      await client.query(`DELETE FROM docutracker_routing_records WHERE document_id = $1`, [id]);
      await client.query(`DELETE FROM docutracker_signature_fields WHERE document_id = $1`, [id]);
      await client.query(`DELETE FROM docutracker_document_contents WHERE document_id = $1`, [id]);
      await client.query(`DELETE FROM docutracker_document_files WHERE document_id = $1`, [id]);
      await client.query(`DELETE FROM docutracker_documents WHERE id = $1`, [id]);
      console.log('deleted document', id);
    }

    await client.query(`DELETE FROM docutracker_permissions WHERE id = $1`, [PERM_ID]);
    console.log('deleted temp release permission', PERM_ID);

    await client.query(`DELETE FROM primary_reviewer_designations WHERE id = $1`, [
      DESIGNATION_ID,
    ]);
    console.log('deleted temp primary designation', DESIGNATION_ID);

    const after = await client.query(
      `SELECT document_number, updated_at FROM docutracker_documents
       WHERE document_number = $1`,
      [PROTECTED]
    );
    console.log('protected after', after.rows[0]);
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
    await pool.end();
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
