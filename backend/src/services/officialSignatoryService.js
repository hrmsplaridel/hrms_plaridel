const { writeGovernanceAudit } = require('./docutrackerGovernanceAudit');

const ROLE_KEYS = Object.freeze({
  LEAVE_CREDIT_CERTIFIER: 'leave_credit_certifier',
});
const VALID_ROLE_KEYS = new Set(Object.values(ROLE_KEYS));
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

class OfficialSignatoryError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.name = 'OfficialSignatoryError';
    this.status = status;
  }
}

function normalizeRoleKey(value) {
  const roleKey = String(value || '').trim().toLowerCase();
  if (!VALID_ROLE_KEYS.has(roleKey)) {
    throw new OfficialSignatoryError('Official signatory role is invalid.');
  }
  return roleKey;
}

function normalizeDate(value, label, { optional = false } = {}) {
  const date = String(value || '').trim();
  if (!date && optional) return null;
  if (!ISO_DATE_RE.test(date) || Number.isNaN(Date.parse(`${date}T00:00:00Z`))) {
    throw new OfficialSignatoryError(`${label} must be a valid YYYY-MM-DD date.`);
  }
  return date;
}

function normalizeEmployeeId(value) {
  const employeeId = String(value || '').trim();
  if (!UUID_RE.test(employeeId)) {
    throw new OfficialSignatoryError('Employee is required.');
  }
  return employeeId;
}

function mapRow(row) {
  if (!row) return null;
  return {
    id: row.id,
    role_key: row.role_key,
    employee_id: row.employee_id,
    name: row.employee_name_snapshot,
    position_title: row.position_title_snapshot,
    department_name: row.department_name_snapshot,
    effective_from: row.effective_from,
    effective_to: row.effective_to,
    remarks: row.remarks,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

async function loadEmployeeProfile(db, employeeId, effectiveDate) {
  const result = await db.query(
    `SELECT u.id,
            u.full_name,
            LOWER(COALESCE(u.role, 'employee')) AS role,
            u.is_active,
            assignment.position_title,
            assignment.department_name
     FROM users u
     LEFT JOIN LATERAL (
       SELECT p.name AS position_title, d.name AS department_name
       FROM assignments a
       LEFT JOIN positions p ON p.id = a.position_id
       LEFT JOIN departments d ON d.id = a.department_id
       WHERE a.employee_id = u.id
         AND (a.effective_from IS NULL OR a.effective_from <= $2::date)
         AND (a.effective_to IS NULL OR a.effective_to >= $2::date)
       ORDER BY a.effective_from DESC NULLS LAST,
                a.created_at DESC NULLS LAST,
                a.id DESC
       LIMIT 1
     ) assignment ON true
     WHERE u.id = $1::uuid
     LIMIT 1`,
    [employeeId, effectiveDate]
  );
  const employee = result.rows[0];
  if (!employee) throw new OfficialSignatoryError('Employee was not found.', 404);
  if (employee.is_active === false) {
    throw new OfficialSignatoryError('An inactive employee cannot be assigned as an official signatory.');
  }
  return employee;
}

async function resolveOfficialSignatory(db, roleKey, effectiveDate) {
  const normalizedRole = normalizeRoleKey(roleKey);
  const normalizedDate = normalizeDate(effectiveDate, 'Effective date');
  const result = await db.query(
    `SELECT *
     FROM docutracker_official_signatories
     WHERE role_key = $1
       AND effective_from <= $2::date
       AND (effective_to IS NULL OR effective_to >= $2::date)
     ORDER BY effective_from DESC, created_at DESC
     LIMIT 1`,
    [normalizedRole, normalizedDate]
  );
  return mapRow(result.rows[0]);
}

async function listOfficialSignatories(db, { effectiveDate = null } = {}) {
  const params = [];
  let currentSql = 'false';
  if (effectiveDate) {
    params.push(normalizeDate(effectiveDate, 'Effective date'));
    currentSql = `effective_from <= $1::date AND (effective_to IS NULL OR effective_to >= $1::date)`;
  }
  const result = await db.query(
    `SELECT *, (${currentSql}) AS is_effective
     FROM docutracker_official_signatories
     ORDER BY role_key, effective_from DESC, created_at DESC`,
    params
  );
  return result.rows.map((row) => ({ ...mapRow(row), is_effective: row.is_effective === true }));
}

async function configureOfficialSignatory(pool, {
  roleKey,
  employeeId,
  effectiveFrom,
  effectiveTo = null,
  remarks = null,
  actorId,
}) {
  const role = normalizeRoleKey(roleKey);
  const employee = normalizeEmployeeId(employeeId);
  const from = normalizeDate(effectiveFrom, 'Effective from');
  const to = normalizeDate(effectiveTo, 'Effective to', { optional: true });
  if (to && to < from) {
    throw new OfficialSignatoryError('Effective to cannot be before Effective from.');
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [
      `docutracker_official_signatory:${role}`,
    ]);
    const profile = await loadEmployeeProfile(client, employee, from);

    const sameStart = await client.query(
      `SELECT * FROM docutracker_official_signatories
       WHERE role_key = $1 AND effective_from = $2::date
       FOR UPDATE`,
      [role, from]
    );
    let before = sameStart.rows[0] || null;

    if (!before) {
      const previous = await client.query(
        `SELECT * FROM docutracker_official_signatories
         WHERE role_key = $1
           AND effective_from < $2::date
           AND (effective_to IS NULL OR effective_to >= $2::date)
         ORDER BY effective_from DESC
         LIMIT 1
         FOR UPDATE`,
        [role, from]
      );
      if (previous.rowCount) {
        await client.query(
          `UPDATE docutracker_official_signatories
           SET effective_to = $2::date - 1, updated_by = $3::uuid, updated_at = now()
           WHERE id = $1::uuid`,
          [previous.rows[0].id, from, actorId]
        );
      }
    }

    let saved;
    try {
      const result = await client.query(
        `INSERT INTO docutracker_official_signatories
           (role_key, employee_id, employee_name_snapshot,
            position_title_snapshot, department_name_snapshot,
            effective_from, effective_to, remarks, created_by, updated_by)
         VALUES ($1, $2::uuid, $3, $4, $5, $6::date, $7::date, $8, $9::uuid, $9::uuid)
         ON CONFLICT (role_key, effective_from) DO UPDATE SET
           employee_id = EXCLUDED.employee_id,
           employee_name_snapshot = EXCLUDED.employee_name_snapshot,
           position_title_snapshot = EXCLUDED.position_title_snapshot,
           department_name_snapshot = EXCLUDED.department_name_snapshot,
           effective_to = EXCLUDED.effective_to,
           remarks = EXCLUDED.remarks,
           updated_by = EXCLUDED.updated_by,
           updated_at = now()
         RETURNING *`,
        [
          role,
          employee,
          profile.full_name,
          profile.position_title,
          profile.department_name,
          from,
          to,
          String(remarks || '').trim() || null,
          actorId,
        ]
      );
      saved = result.rows[0];
    } catch (error) {
      if (error?.code === '23P01') {
        throw new OfficialSignatoryError(
          'This effective period overlaps another assignment for the same official role.',
          409
        );
      }
      throw error;
    }

    await writeGovernanceAudit(client, {
      actorId,
      eventType: before ? 'official_signatory_corrected' : 'official_signatory_configured',
      entityType: 'official_signatory',
      entityId: saved.id,
      targetUserId: employee,
      beforeState: before ? mapRow(before) : null,
      afterState: mapRow(saved),
      reason: String(remarks || '').trim() || null,
    });
    await client.query('COMMIT');
    return mapRow(saved);
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {
      // Preserve the original error.
    }
    throw error;
  } finally {
    client.release();
  }
}

async function resolveActiveMayor(db, effectiveDate) {
  const date = normalizeDate(effectiveDate, 'Effective date');
  const result = await db.query(
    `SELECT u.id AS employee_id,
            u.full_name AS name,
            COALESCE(NULLIF(p.name, ''), 'Municipal Mayor') AS position_title,
            d.name AS department_name
     FROM users u
     LEFT JOIN LATERAL (
       SELECT a.position_id, a.department_id
       FROM assignments a
       WHERE a.employee_id = u.id
         AND a.is_active = true
         AND a.effective_from <= $1::date
         AND (a.effective_to IS NULL OR a.effective_to >= $1::date)
       ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC
       LIMIT 1
     ) assignment ON true
     LEFT JOIN positions p ON p.id = assignment.position_id
     LEFT JOIN departments d ON d.id = assignment.department_id
     WHERE LOWER(COALESCE(u.role, '')) = 'mayor'
       AND u.is_active = true
       AND COALESCE(u.employment_status, 'active') = 'active'
       AND (u.date_hired IS NULL OR u.date_hired <= $1::date)
       AND (u.separation_date IS NULL OR u.separation_date >= $1::date)
     ORDER BY u.created_at DESC, u.id DESC
     LIMIT 1`,
    [date]
  );
  return result.rows[0] || null;
}

module.exports = {
  ROLE_KEYS,
  OfficialSignatoryError,
  configureOfficialSignatory,
  listOfficialSignatories,
  resolveOfficialSignatory,
  resolveActiveMayor,
};
