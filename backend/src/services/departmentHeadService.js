// Compatibility facade for shared employee-based reviewer designations.

const { todayInHrmsTimezone } = require('../utils/dateRangeParser');
const {
  getEmployeeDepartmentForDate,
  getEmployeeReviewSnapshot,
  resolveDepartmentReviewers,
} = require('./departmentReviewerService');

/**
 * Get the department_id effective today for an employee.
 * @param {import('pg').PoolClient} client
 * @param {string} employeeUserId
 * @returns {Promise<{departmentId: string, departmentName: string|null} | null>}
 */
async function getEmployeeDepartment(client, employeeUserId) {
  return getEmployeeDepartmentForDate(
    client,
    employeeUserId,
    todayInHrmsTimezone()
  );
}

/**
 * Resolve the employee department that was effective on a historical date.
 * Closed assignments remain valid history and must not be filtered by is_active.
 */
/**
 * Find the department head for a given department.
 *
 * Authority comes from an explicit employee designation effective on the date.
 *
 * @param {import('pg').PoolClient} client
 * @param {string} departmentId
 * @returns {Promise<string|null>} employee (user) ID of the department head, or null.
 */
async function findDepartmentHeadUserId(
  client,
  departmentId,
  effectiveDate = todayInHrmsTimezone()
) {
  const resolved = await resolveDepartmentReviewers(client, {
    departmentId,
    effectiveDate,
  });
  return resolved.primary?.reviewerId || null;
}

/**
 * High-level: given an employee user ID, find their department head.
 * Returns null if:
 *  - employee has no assignment effective today / no department
 *  - no primary employee designated for that department
 *  - employee IS the department head (self-approval prevention)
 *
 * @param {import('pg').PoolClient} client
 * @param {string} employeeUserId
 * @returns {Promise<{departmentHeadUserId: string, departmentId: string, departmentName: string|null} | null>}
 */
async function getDepartmentHeadForEmployee(client, employeeUserId) {
  const snapshot = await getDepartmentReviewSnapshot(client, employeeUserId);
  if (!snapshot?.departmentHeadUserId) return null;
  return snapshot;
}

/**
 * Resolve and snapshot the employee's current reviewing department and head.
 * Unlike getDepartmentHeadForEmployee, the department is retained when the
 * department has no designated head so HR-only routing is still auditable.
 */
async function getDepartmentReviewSnapshot(
  client,
  employeeUserId,
  effectiveDate = todayInHrmsTimezone()
) {
  return getEmployeeReviewSnapshot(client, {
    employeeUserId,
    effectiveDate,
  });
}

/**
 * Freeze locator review routing using the employee department effective on the
 * locator date and the department head assigned when the request is submitted.
 */
async function getDepartmentReviewSnapshotForDate(
  client,
  employeeUserId,
  effectiveDate
) {
  return getEmployeeReviewSnapshot(client, {
    employeeUserId,
    effectiveDate,
  });
}

/**
 * Check if a given user is a department head (in any department).
 * @param {import('pg').PoolClient} client
 * @param {string} userId
 * @returns {Promise<{isDeptHead: boolean, departmentId: string|null, departmentName: string|null}>}
 */
async function isDepartmentHead(client, userId) {
  const q = await client.query(
    `SELECT head_period.department_id, d.name AS department_name
     FROM primary_reviewer_designations head_period
     JOIN users u ON u.id = head_period.employee_id
     JOIN departments d ON d.id = head_period.department_id
     WHERE head_period.employee_id = $1::uuid AND u.is_active = true
       AND head_period.department_id IS NOT NULL AND head_period.is_active = true
       AND head_period.effective_from <= $2::date
       AND (head_period.effective_to IS NULL OR head_period.effective_to >= $2::date)
     ORDER BY head_period.effective_from DESC, head_period.id DESC LIMIT 1`,
    [userId, todayInHrmsTimezone()]
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
  getEmployeeDepartment,
  getEmployeeDepartmentForDate,
  getDepartmentReviewSnapshot,
  getDepartmentReviewSnapshotForDate,
  findDepartmentHeadUserId,
  getDepartmentHeadForEmployee,
  isDepartmentHead,
};
