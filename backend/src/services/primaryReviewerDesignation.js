const { todayInHrmsTimezone } = require('../utils/dateRangeParser');
const { broadcastAppEvent } = require('../websockets/appEvents');

function invalid(message, statusCode = 400) {
  return Object.assign(new Error(message), { statusCode });
}
function date(value, field) {
  const text = String(value || '');
  const parsed = new Date(`${text}T00:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text) || !Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== text) {
    throw invalid(`${field} must be a valid YYYY-MM-DD date`);
  }
  return text;
}

async function savePrimaryReviewer(pool, { departmentId = null, employeeId, effectiveFrom, effectiveTo, actorId }) {
  const from = date(effectiveFrom || todayInHrmsTimezone(), 'effective_from');
  const to = effectiveTo == null || effectiveTo === '' ? null : date(effectiveTo, 'effective_to');
  if (to && to < from) throw invalid('effective_to cannot be before effective_from');
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (departmentId !== null && (typeof departmentId !== 'string' || !uuid.test(departmentId))) throw invalid('Select a valid department');
  if (typeof departmentId === 'string') departmentId = departmentId.toLowerCase();
  if (typeof employeeId === 'string') employeeId = employeeId.toLowerCase();
  if (employeeId !== null && (typeof employeeId !== 'string' || !uuid.test(employeeId))) throw invalid('Select a valid employee or explicitly clear the designation');
  const scope = departmentId ? `department:${departmentId}` : 'final_hr';
  const client = await pool.connect();
  let designation = null;
  const affected = new Set();
  try {
    await client.query('BEGIN');
    if (departmentId) {
      const department = await client.query('SELECT id FROM departments WHERE id = $1::uuid AND is_active = true FOR UPDATE', [departmentId]);
      if (!department.rows.length) throw invalid('Active department not found', 404);
    } else {
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', ['primary-reviewer:final_hr']);
    }
    let employee = null;
    if (employeeId) {
      const result = await client.query(
        `SELECT u.id, u.role, a.department_id, a.position_id, a.position_title
         FROM users u LEFT JOIN LATERAL (
           SELECT a.department_id, a.position_id, p.name AS position_title
           FROM assignments a JOIN positions p ON p.id = a.position_id
           WHERE a.employee_id = u.id AND a.is_active = true AND p.is_active = true
             AND a.effective_from <= $2::date AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
             AND ($3::uuid IS NULL OR a.department_id = $3::uuid)
           ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC LIMIT 1
         ) a ON true WHERE u.id = $1::uuid AND u.is_active = true FOR UPDATE OF u`,
        [employeeId, from, departmentId]
      );
      employee = result.rows[0];
      if (!employee || (departmentId && employee.department_id !== departmentId)) throw invalid('Select an active employee assigned to this department on the effective date', 409);
      if (!departmentId && !['admin', 'hr'].includes(employee.role)) throw invalid('Final reviewers must be active HR or admin employees', 409);
      if (!departmentId && employee.role === 'admin') {
        const access = await client.query('SELECT leave_allowed, locator_allowed FROM dtr_admin_access WHERE admin_user_id = $1::uuid', [employeeId]);
        if (!access.rows[0]?.leave_allowed || !access.rows[0]?.locator_allowed) throw invalid('Enable Leave and Locator access before assigning this admin reviewer', 409);
      }
      const backup = await client.query(
        `SELECT id FROM ${departmentId ? 'department_reviewer_backups' : 'leave_final_reviewer_backups'}
         WHERE employee_id = $1::uuid AND is_active = true
           AND daterange(effective_from, effective_to, '[]') && daterange($2::date, $3::date, '[]')
           ${departmentId ? 'AND department_id = $4::uuid' : ''} LIMIT 1`,
        [employeeId, from, to, ...(departmentId ? [departmentId] : [])]
      );
      if (backup.rows.length) throw invalid('Remove this employee from backups for the selected period before designating them as primary', 409);
      affected.add(employeeId);
    }
    const overlaps = await client.query(
      `SELECT *, effective_from::text AS effective_from, effective_to::text AS effective_to
       FROM primary_reviewer_designations WHERE scope_key = $1 AND is_active = true
       AND daterange(effective_from, effective_to, '[]') && daterange($2::date, $3::date, '[]') FOR UPDATE`,
      [scope, from, to]
    );
    for (const old of overlaps.rows) {
      affected.add(old.employee_id);
      // Retain the old designation before, and where applicable after, the replacement.
      await client.query(
        `UPDATE primary_reviewer_designations SET
          effective_to = CASE WHEN effective_from < $2::date THEN $2::date - 1 ELSE effective_to END,
          is_active = (effective_from < $2::date), updated_at = now() WHERE id = $1::uuid`,
        [old.id, from]
      );
      const oldTo = old.effective_to == null ? null : String(old.effective_to).slice(0, 10);
      if (to && (oldTo == null || oldTo > to)) {
        await client.query(
          `INSERT INTO primary_reviewer_designations(scope_key, department_id, employee_id, position_id,
            position_title_snapshot, effective_from, effective_to, created_by)
           VALUES ($1, $2::uuid, $3::uuid, $4::uuid, $5, $6::date + 1, $7::date, $8::uuid)`,
          [scope, departmentId, old.employee_id, old.position_id, old.position_title_snapshot, to, oldTo, actorId]
        );
      }
    }
    if (employee) {
      const created = await client.query(
        `INSERT INTO primary_reviewer_designations(scope_key, department_id, employee_id, position_id,
          position_title_snapshot, effective_from, effective_to, created_by)
         VALUES ($1, $2::uuid, $3::uuid, $4::uuid, $5, $6::date, $7::date, $8::uuid) RETURNING *`,
        [scope, departmentId, employeeId, employee.position_id, employee.position_title, from, to, actorId]
      );
      designation = created.rows[0];
    }
    await client.query(
      `INSERT INTO audit_logs(user_id, action, entity_type, entity_id, details)
       VALUES ($1::uuid, 'primary_reviewer_configured', 'reviewer_configuration', $2::uuid, $3::jsonb)`,
      [actorId, departmentId || employeeId || actorId, JSON.stringify({ scope, employee_id: employeeId, effective_from: from, effective_to: to })]
    );
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    if (error.code === '23P01') throw invalid('Another primary designation overlaps these dates. Refresh and retry.', 409);
    throw error;
  } finally { client.release(); }
  try { broadcastAppEvent('admin_access_changed', {}, { userIds: [...affected] }); } catch (_) {}
  return { designation, effective_date: from };
}

module.exports = { savePrimaryReviewer };
