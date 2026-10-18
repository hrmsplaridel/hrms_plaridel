'use strict';
module.exports = function createLocatorComponent({}) {
  async function getLocatorTypeByCode(client, code, { activeOnly = false } = {}) {
    const result = await client.query(
      `SELECT *
     FROM locator_request_types
     WHERE code = $1::text
       AND ($2::boolean = false OR is_active = true)
     LIMIT 1`,
      [code, activeOnly]
    );
    return result.rows[0] || null;
  }
  return { getLocatorTypeByCode };
};
