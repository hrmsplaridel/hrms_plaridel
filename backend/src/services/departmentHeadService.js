// Department Head detection service.
//
// Determines whether a user is a department head by inspecting their
// active assignment + position name.  Uses EXACT match against known
// position names first, then falls back to case-insensitive LIKE.

/**
 * Known exact position names that indicate "Department Head".
 * Add entries here as your organisation's position catalog grows.
 * Checked case-insensitively (lowered before comparison).
 */
const DEPARTMENT_HEAD_POSITION_NAMES = [
  'department head',
];

/**
 * Get the active department_id for an employee.
 * @param {import('pg').PoolClient} client
 * @param {string} employeeUserId
 * @returns {Promise<{departmentId: string, departmentName: string|null} | null>}
 */
async function getEmployeeDepartment(client, employeeUserId) {
  const q = await client.query(
    `SELECT a.department_id, d.name AS department_name
     FROM assignments a
     LEFT JOIN departments d ON d.id = a.department_id
     WHERE a.employee_id = $1
       AND (a.is_active IS NULL OR a.is_active = true)
       AND a.department_id IS NOT NULL
     ORDER BY a.effective_from DESC
     LIMIT 1`,
    [employeeUserId]
  );
  if (q.rows.length === 0) return null;
  return {
    departmentId: q.rows[0].department_id,
    departmentName: q.rows[0].department_name || null,
  };
}

/**
 * Find the department head for a given department.
 *
 * Strategy:
 *  1. Try exact match (case-insensitive) against DEPARTMENT_HEAD_POSITION_NAMES.
 *  2. Fallback: ILIKE '%department head%' on position name.
 *
 * @param {import('pg').PoolClient} client
 * @param {string} departmentId
 * @returns {Promise<string|null>} employee (user) ID of the department head, or null.
 */
async function findDepartmentHeadUserId(client, departmentId) {
  // 1. Exact match against known names
  if (DEPARTMENT_HEAD_POSITION_NAMES.length > 0) {
    const lowerNames = DEPARTMENT_HEAD_POSITION_NAMES.map((n) => n.toLowerCase());
    const exact = await client.query(
      `SELECT a.employee_id
       FROM assignments a
       JOIN positions p ON a.position_id = p.id
       WHERE a.department_id = $1
         AND (a.is_active IS NULL OR a.is_active = true)
         AND (p.is_active IS NULL OR p.is_active = true)
         AND LOWER(p.name) = ANY($2::text[])
       LIMIT 1`,
      [departmentId, lowerNames]
    );
    if (exact.rows.length > 0) return exact.rows[0].employee_id;
  }

  // 2. Fallback: ILIKE pattern
  const fallback = await client.query(
    `SELECT a.employee_id
     FROM assignments a
     JOIN positions p ON a.position_id = p.id
     WHERE a.department_id = $1
       AND (a.is_active IS NULL OR a.is_active = true)
       AND (p.is_active IS NULL OR p.is_active = true)
       AND p.name ILIKE '%department head%'
     LIMIT 1`,
    [departmentId]
  );
  if (fallback.rows.length > 0) return fallback.rows[0].employee_id;

  return null;
}

/**
 * High-level: given an employee user ID, find their department head.
 * Returns null if:
 *  - employee has no active assignment / no department
 *  - no department head position found in that department
 *  - employee IS the department head (self-approval prevention)
 *
 * @param {import('pg').PoolClient} client
 * @param {string} employeeUserId
 * @returns {Promise<{departmentHeadUserId: string, departmentId: string, departmentName: string|null} | null>}
 */
async function getDepartmentHeadForEmployee(client, employeeUserId) {
  const dept = await getEmployeeDepartment(client, employeeUserId);
  if (!dept) return null;

  const headUserId = await findDepartmentHeadUserId(client, dept.departmentId);
  if (!headUserId) return null;

  // Self-approval prevention: if the employee IS the dept head, skip.
  if (headUserId === employeeUserId) return null;

  return {
    departmentHeadUserId: headUserId,
    departmentId: dept.departmentId,
    departmentName: dept.departmentName,
  };
}

/**
 * Check if a given user is a department head (in any department).
 * @param {import('pg').PoolClient} client
 * @param {string} userId
 * @returns {Promise<{isDeptHead: boolean, departmentId: string|null, departmentName: string|null}>}
 */
async function isDepartmentHead(client, userId) {
  // 1. Exact match
  const lowerNames = DEPARTMENT_HEAD_POSITION_NAMES.map((n) => n.toLowerCase());
  let q = await client.query(
    `SELECT a.department_id, d.name AS department_name
     FROM assignments a
     JOIN positions p ON a.position_id = p.id
     LEFT JOIN departments d ON d.id = a.department_id
     WHERE a.employee_id = $1
       AND (a.is_active IS NULL OR a.is_active = true)
       AND (p.is_active IS NULL OR p.is_active = true)
       AND LOWER(p.name) = ANY($2::text[])
     LIMIT 1`,
    [userId, lowerNames]
  );
  if (q.rows.length > 0) {
    return {
      isDeptHead: true,
      departmentId: q.rows[0].department_id,
      departmentName: q.rows[0].department_name || null,
    };
  }

  // 2. Fallback ILIKE
  q = await client.query(
    `SELECT a.department_id, d.name AS department_name
     FROM assignments a
     JOIN positions p ON a.position_id = p.id
     LEFT JOIN departments d ON d.id = a.department_id
     WHERE a.employee_id = $1
       AND (a.is_active IS NULL OR a.is_active = true)
       AND (p.is_active IS NULL OR p.is_active = true)
       AND p.name ILIKE '%department head%'
     LIMIT 1`,
    [userId]
  );
  if (q.rows.length > 0) {
    return {
      isDeptHead: true,
      departmentId: q.rows[0].department_id,
      departmentName: q.rows[0].department_name || null,
    };
  }

  return { isDeptHead: false, departmentId: null, departmentName: null };
}

module.exports = {
  DEPARTMENT_HEAD_POSITION_NAMES,
  getEmployeeDepartment,
  findDepartmentHeadUserId,
  getDepartmentHeadForEmployee,
  isDepartmentHead,
};
