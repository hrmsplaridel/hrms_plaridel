'use strict';
module.exports = function createLeaveComponent({ leaveTypeRowToApi }) {
  async function getLeaveTypeDefinition(client, name) {
    const trimmed = (name || '').toString().trim();
    if (!trimmed) return null;
    const found = await client.query(
      `SELECT *
     FROM leave_types
     WHERE name = $1 AND (is_active IS NULL OR is_active = true)
     LIMIT 1`,
      [trimmed],
    );
    if (found.rows.length === 0) return null;
    return leaveTypeRowToApi(found.rows[0]);
  }

  async function getUserSexForLeaveValidation(client, userId) {
    if (!userId) return null;
    const result = await client.query('SELECT sex FROM users WHERE id = $1 LIMIT 1', [userId]);
    return result.rows[0]?.sex || null;
  }

  async function ensureLeaveTypeIdByName(client, name) {
    const trimmed = (name || '').toString().trim();
    if (!trimmed) return null;
    const found = await client.query(
      'SELECT id FROM leave_types WHERE name = $1 AND (is_active IS NULL OR is_active = true) LIMIT 1',
      [trimmed],
    );
    if (found.rows.length > 0) return found.rows[0].id;
    return null;
  }
  return { getLeaveTypeDefinition, getUserSexForLeaveValidation, ensureLeaveTypeIdByName };
};
