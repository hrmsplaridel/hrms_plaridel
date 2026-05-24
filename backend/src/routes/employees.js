const express = require('express');
const bcrypt = require('bcrypt');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

const SALT_ROUNDS = 10;
const EMPLOYEE_ID_MIN = 100000;
const EMPLOYEE_ID_MAX = 999999;

function randomEmployeeNumber() {
  return (
    Math.floor(Math.random() * (EMPLOYEE_ID_MAX - EMPLOYEE_ID_MIN + 1)) +
    EMPLOYEE_ID_MIN
  );
}

async function allocateEmployeeNumber() {
  // Try a few times to avoid collisions; fall back to sequence if needed.
  for (let attempt = 0; attempt < 12; attempt++) {
    const candidate = randomEmployeeNumber();
    const exists = await pool.query(
      'SELECT 1 FROM users WHERE employee_number = $1 LIMIT 1',
      [candidate]
    );
    if (exists.rowCount === 0) return candidate;
  }
  // last resort: keep system running even if random keeps colliding
  const seq = await pool.query("SELECT nextval('users_employee_number_seq') AS n");
  return parseInt(seq.rows[0].n, 10);
}

const MAX_PAGE_SIZE = 100;
const MAX_EXPORT_ROWS = 10000;
const MAX_BULK_STATUS_IDS = 200;

let usersOfficeColumnReady = null;

async function hasUsersOfficeIdColumn() {
  if (usersOfficeColumnReady !== null) return usersOfficeColumnReady;
  const result = await pool.query(
    `SELECT 1
     FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'users'
       AND column_name = 'office_id'
     LIMIT 1`
  );
  usersOfficeColumnReady = result.rowCount > 0;
  return usersOfficeColumnReady;
}

function mapEmployeeListRow(r) {
  return {
    id: r.id,
    employee_number: r.employee_number,
    full_name: r.full_name ?? 'Unknown',
    role: r.role ?? 'employee',
    email: r.email,
    biometric_user_id: r.biometric_user_id ?? null,
    is_active: r.is_active ?? true,
    avatar_path: r.avatar_path,
    middle_name: r.middle_name,
    suffix: r.suffix,
    sex: r.sex,
    date_of_birth: r.date_of_birth,
    contact_number: r.contact_number,
    address: r.address,
    employment_type: r.employment_type,
    salary_grade: r.salary_grade,
    date_hired: r.date_hired,
    employment_status: r.employment_status ?? 'active',
    current_department_name: r.current_department_name ?? null,
    current_position_name: r.current_position_name ?? null,
    ...(r.office_id !== undefined ? { office_id: r.office_id ?? null } : {}),
  };
}

function employeeListLateralCurSql() {
  return `
       LEFT JOIN LATERAL (
         SELECT d.name AS current_department_name, p.name AS current_position_name
         FROM assignments a
         LEFT JOIN departments d ON d.id = a.department_id
         LEFT JOIN positions p ON p.id = a.position_id
         WHERE a.employee_id = u.id
           AND (a.is_active IS NULL OR a.is_active = true)
           AND a.effective_from <= CURRENT_DATE
           AND (a.effective_to IS NULL OR a.effective_to >= CURRENT_DATE)
         ORDER BY a.effective_from DESC
         LIMIT 1
       ) cur ON true`;
}

/** Shared FROM + filters for employee list / export (excludes biometric_user_ids shortcut). */
function buildEmployeeListFromSql(req, options = {}) {
  const { deviceBiometricIds = null } = options;
  const conditions = [];
  const params = [];
  let i = 1;
  const status = req.query.status || 'Active';
  const roleFilter = req.query.role || 'All';
  const departmentId = req.query.department_id || null;
  const tbl = 'u';

  if (status === 'Active') {
    conditions.push(`(${tbl}.is_active IS NULL OR ${tbl}.is_active = true)`);
  } else if (status === 'Inactive') {
    conditions.push(`${tbl}.is_active = false`);
  }
  if (roleFilter === 'Admin') {
    conditions.push(`${tbl}.role = $${i++}`);
    params.push('admin');
  } else if (roleFilter === 'User' || roleFilter === 'Employee') {
    conditions.push(`${tbl}.role = $${i++}`);
    params.push('employee');
  }
  if (departmentId) {
    conditions.push(`${tbl}.id IN (
      SELECT DISTINCT a.employee_id FROM assignments a
      WHERE a.department_id = $${i}
        AND (a.is_active IS NULL OR a.is_active = true)
        AND a.effective_from <= CURRENT_DATE
        AND (a.effective_to IS NULL OR a.effective_to >= CURRENT_DATE)
    )`);
    params.push(departmentId);
    i++;
  }

  const bioFilterRaw =
    typeof req.query.biometric_filter === 'string' ? req.query.biometric_filter.trim().toLowerCase() : '';
  if (bioFilterRaw === 'set' || bioFilterRaw === 'has') {
    conditions.push(`(COALESCE(TRIM(${tbl}.biometric_user_id), '') <> '')`);
  } else if (bioFilterRaw === 'missing' || bioFilterRaw === 'none') {
    conditions.push(`(${tbl}.biometric_user_id IS NULL OR TRIM(${tbl}.biometric_user_id) = '')`);
  }

  if (deviceBiometricIds != null) {
    if (deviceBiometricIds.length === 0) {
      conditions.push('FALSE');
    } else {
      conditions.push(`${tbl}.biometric_user_id = ANY($${i}::text[])`);
      params.push(deviceBiometricIds);
      i++;
    }
  }

  const qRaw = typeof req.query.q === 'string' ? req.query.q.trim() : '';
  if (qRaw.length > 0) {
    const pattern = `%${qRaw}%`;
    conditions.push(`(
      u.full_name ILIKE $${i} OR
      u.email ILIKE $${i} OR
      CAST(u.employee_number AS TEXT) ILIKE $${i} OR
      COALESCE(cur.current_department_name, '') ILIKE $${i} OR
      COALESCE(cur.current_position_name, '') ILIKE $${i} OR
      COALESCE(u.employment_status, '') ILIKE $${i} OR
      COALESCE(u.biometric_user_id, '') ILIKE $${i}
    )`);
    params.push(pattern);
    i++;
  }

  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
  const fromSql = `
       FROM users u
       ${employeeListLateralCurSql()}
       ${where}`;

  return { fromSql, params, nextParamIndex: i };
}

const EMPLOYEE_SORT_COLUMNS = {
  full_name: 'u.full_name',
  employee_number: 'u.employee_number',
  role: 'u.role',
  email: 'u.email',
  department: 'cur.current_department_name',
  position: 'cur.current_position_name',
  employment_status: 'u.employment_status',
  is_active: 'u.is_active',
};

function resolveEmployeeOrderBy(sortRaw, orderRaw) {
  const key = typeof sortRaw === 'string' ? sortRaw.trim().toLowerCase() : '';
  const col = EMPLOYEE_SORT_COLUMNS[key] || EMPLOYEE_SORT_COLUMNS.full_name;
  const dir = String(orderRaw || 'asc').toLowerCase() === 'desc' ? 'DESC' : 'ASC';
  return `${col} ${dir} NULLS LAST, u.id ASC`;
}

function csvEscape(val) {
  if (val == null) return '';
  const s = String(val);
  if (/[",\n\r]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
  return s;
}

// GET /api/employees - list all (?status=Active|Inactive|All, ?role=admin|employee|All, ?department_id=uuid, ?biometric_user_ids=id1,id2,id3)
// Optional: ?biometric_device_id=<uuid> — admin only; restrict to employees whose biometric_user_id is enrolled on that ZKTeco (reads device; cached ~60s)
// Optional: ?biometric_filter=set|has|missing|none — filter by whether biometric_user_id is set (set/has = non-empty; missing/none = empty)
// Optional: ?q= search; ?sort= & ?order=asc|desc (sort whitelist: full_name, employee_number, role, email, department, position, employment_status, is_active)
// Optional: ?limit=&offset= — when limit is set, response is { employees, total } instead of a raw array.
router.get('/', protect, async (req, res) => {
  try {
    const biometricUserIdsRaw = req.query.biometric_user_ids;

    // When biometric_user_ids is provided, return only matching users (exact match).
    if (biometricUserIdsRaw && typeof biometricUserIdsRaw === 'string') {
      const ids = biometricUserIdsRaw.split(',').map((s) => s.trim()).filter(Boolean);
      if (ids.length > 0) {
        const result = await pool.query(
          `SELECT u.id, u.employee_number, u.full_name, u.role, u.email, u.biometric_user_id, u.is_active, u.avatar_path,
                  u.middle_name, u.suffix, u.sex, u.date_of_birth, u.contact_number, u.address,
                  u.employment_type, u.salary_grade, u.date_hired, u.employment_status,
                  cur.current_department_name, cur.current_position_name
           FROM users u
           ${employeeListLateralCurSql()}
           WHERE u.biometric_user_id = ANY($1::text[])
           ORDER BY u.full_name`,
          [ids]
        );
        const rows = result.rows.map(mapEmployeeListRow);
        return res.json(rows);
      }
    }

    let deviceBiometricIds = null;
    const bioDeviceRaw =
      typeof req.query.biometric_device_id === 'string' ? req.query.biometric_device_id.trim() : '';
    if (bioDeviceRaw) {
      if (req.user?.role !== 'admin') {
        return res.status(403).json({ error: 'Admin access required' });
      }
      const { getDeviceUserBiometricIds } = require('../services/biometricDeviceUsers');
      const devRes = await getDeviceUserBiometricIds(bioDeviceRaw);
      if (!devRes.ok) {
        return res.status(devRes.statusCode).json({ error: devRes.message });
      }
      deviceBiometricIds = devRes.ids;
    }

    const { fromSql, params, nextParamIndex } = buildEmployeeListFromSql(req, { deviceBiometricIds });
    const orderBy = resolveEmployeeOrderBy(req.query.sort, req.query.order);
    let i = nextParamIndex;

    const limitRaw = req.query.limit;
    const usePaging = limitRaw !== undefined && limitRaw !== null && String(limitRaw).length > 0;
    let limit = 25;
    let offset = 0;
    if (usePaging) {
      const parsed = parseInt(String(limitRaw), 10);
      limit = Number.isFinite(parsed) ? Math.min(Math.max(parsed, 1), MAX_PAGE_SIZE) : 25;
      const offParsed = parseInt(String(req.query.offset ?? '0'), 10);
      offset = Number.isFinite(offParsed) && offParsed > 0 ? offParsed : 0;
    }

    let total = null;
    if (usePaging) {
      const countRes = await pool.query(`SELECT COUNT(*)::int AS c ${fromSql}`, params);
      total = countRes.rows[0]?.c ?? 0;
    }

    const limitIdx = i;
    const dataParams = usePaging ? [...params, limit, offset] : params;
    const limitSql = usePaging ? ` LIMIT $${limitIdx} OFFSET $${limitIdx + 1}` : '';

    const result = await pool.query(
      `SELECT u.id, u.employee_number, u.full_name, u.role, u.email, u.biometric_user_id, u.is_active, u.avatar_path, u.middle_name, u.suffix, u.sex, u.date_of_birth, u.contact_number, u.address,
              u.employment_type, u.salary_grade, u.date_hired, u.employment_status,
              cur.current_department_name, cur.current_position_name
       ${fromSql}
       ORDER BY ${orderBy}${limitSql}`,
      dataParams
    );

    const rows = result.rows.map(mapEmployeeListRow);
    if (usePaging) {
      return res.json({ employees: rows, total });
    }
    res.json(rows);
  } catch (err) {
    console.error('[employees GET]', err);
    res.status(500).json({ error: 'Failed to fetch employees' });
  }
});

// GET /api/employees/export/csv — same filters/search/sort as list; max MAX_EXPORT_ROWS rows (413 if exceeded).
router.get('/export/csv', protect, async (req, res) => {
  try {
    let deviceBiometricIds = null;
    const bioDeviceRaw =
      typeof req.query.biometric_device_id === 'string' ? req.query.biometric_device_id.trim() : '';
    if (bioDeviceRaw) {
      if (req.user?.role !== 'admin') {
        return res.status(403).json({ error: 'Admin access required' });
      }
      const { getDeviceUserBiometricIds } = require('../services/biometricDeviceUsers');
      const devRes = await getDeviceUserBiometricIds(bioDeviceRaw);
      if (!devRes.ok) {
        return res.status(devRes.statusCode).json({ error: devRes.message });
      }
      deviceBiometricIds = devRes.ids;
    }

    const { fromSql, params } = buildEmployeeListFromSql(req, { deviceBiometricIds });
    const orderBy = resolveEmployeeOrderBy(req.query.sort, req.query.order);
    const result = await pool.query(
      `SELECT u.employee_number, u.full_name, u.email, u.role, u.is_active, u.employment_status,
              u.biometric_user_id, cur.current_department_name, cur.current_position_name
       ${fromSql}
       ORDER BY ${orderBy}
       LIMIT ${MAX_EXPORT_ROWS + 1}`,
      params
    );
    if (result.rows.length > MAX_EXPORT_ROWS) {
      return res.status(413).json({
        error: `Too many rows for one export (max ${MAX_EXPORT_ROWS}). Narrow filters or search.`,
      });
    }

    const header = [
      'Employee No',
      'Full Name',
      'Email',
      'Department',
      'Position',
      'Privilege',
      'Account Active',
      'Employment Status',
      'Biometric ID',
    ];
    const lines = [header.map(csvEscape).join(',')];
    for (const r of result.rows) {
      const empNo = r.employee_number != null
        ? `EMP-${String(r.employee_number).padStart(3, '0')}`
        : '';
      const priv = r.role === 'admin' ? 'Admin' : 'Employee';
      const acct = (r.is_active !== false && r.is_active != null) ? 'Active' : 'Inactive';
      lines.push([
        csvEscape(empNo),
        csvEscape(r.full_name ?? ''),
        csvEscape(r.email ?? ''),
        csvEscape(r.current_department_name ?? ''),
        csvEscape(r.current_position_name ?? ''),
        csvEscape(priv),
        csvEscape(acct),
        csvEscape(r.employment_status ?? ''),
        csvEscape(r.biometric_user_id ?? ''),
      ].join(','));
    }

    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename="employees_export.csv"');
    res.send(`\uFEFF${lines.join('\n')}`);
  } catch (err) {
    console.error('[employees GET /export/csv]', err);
    res.status(500).json({ error: 'Failed to export employees' });
  }
});

// POST /api/employees/bulk-status — set is_active for many users (admin only).
router.post('/bulk-status', protect, requireAdmin, async (req, res) => {
  try {
    const { employee_ids: idsRaw, is_active: isActive } = req.body;
    if (!Array.isArray(idsRaw) || idsRaw.length === 0) {
      return res.status(400).json({ error: 'employee_ids non-empty array required' });
    }
    if (typeof isActive !== 'boolean') {
      return res.status(400).json({ error: 'is_active boolean required' });
    }
    if (idsRaw.length > MAX_BULK_STATUS_IDS) {
      return res.status(400).json({ error: `Maximum ${MAX_BULK_STATUS_IDS} employees per request` });
    }
    const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    const ids = [...new Set(idsRaw.map((x) => String(x).trim()).filter((x) => uuidRe.test(x)))];
    if (ids.length === 0) {
      return res.status(400).json({ error: 'No valid employee IDs' });
    }
    const result = await pool.query(
      'UPDATE users SET is_active = $2, updated_at = now() WHERE id = ANY($1::uuid[]) RETURNING id',
      [ids, isActive],
    );
    res.json({ updated: result.rowCount });
  } catch (err) {
    console.error('[employees POST /bulk-status]', err);
    res.status(500).json({ error: 'Failed to update employees' });
  }
});

// GET /api/employees/:id - get one employee (matches profiles + list row department/position)
router.get('/:id', protect, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT u.id, u.employee_number, u.full_name, u.role, u.email, u.is_active, u.avatar_path, u.middle_name, u.suffix, u.sex, u.date_of_birth, u.contact_number, u.address,
              u.employment_type, u.salary_grade, u.date_hired, u.employment_status,
              cur.current_department_name, cur.current_position_name
       FROM users u
       ${employeeListLateralCurSql()}
       WHERE u.id = $1`,
      [req.params.id]
    );
    const r = result.rows[0];
    if (!r) return res.status(404).json({ error: 'Employee not found' });

    res.json({
      id: r.id,
      employee_number: r.employee_number,
      full_name: r.full_name ?? 'Unknown',
      role: r.role ?? 'employee',
      email: r.email,
      is_active: r.is_active ?? true,
      avatar_path: r.avatar_path,
      middle_name: r.middle_name,
      suffix: r.suffix,
      sex: r.sex,
      date_of_birth: r.date_of_birth,
      contact_number: r.contact_number,
      address: r.address,
      employment_type: r.employment_type,
      salary_grade: r.salary_grade,
      date_hired: r.date_hired,
      employment_status: r.employment_status ?? 'active',
      current_department_name: r.current_department_name ?? null,
      current_position_name: r.current_position_name ?? null,
    });
  } catch (err) {
    console.error('[employees GET :id]', err);
    res.status(500).json({ error: 'Failed to fetch employee' });
  }
});

// POST /api/employees - create employee (admin only); same as auth/register but admin creates
router.post('/', protect, requireAdmin, async (req, res) => {
  try {
    const { email, password, full_name, role = 'employee', middle_name, suffix, sex, date_of_birth, contact_number, address, employment_type, salary_grade, date_hired, employment_status, biometric_user_id } = req.body;
    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }
    if (!['admin', 'employee'].includes(role)) {
      return res.status(400).json({ error: 'Role must be admin or employee' });
    }

    const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);
    const empNo = await allocateEmployeeNumber();

    const result = await pool.query(
      `INSERT INTO users (email, password_hash, role, full_name, middle_name, suffix, sex, date_of_birth, contact_number, address, is_active, employee_number, employment_type, salary_grade, date_hired, employment_status, biometric_user_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8::date, $9, $10, true, $11, $12, $13, COALESCE($14::date, CURRENT_DATE), $15, $16)
       RETURNING id, employee_number, email, role, full_name, avatar_path, is_active, middle_name, suffix, sex, date_of_birth, contact_number, address, employment_type, salary_grade, date_hired, employment_status, biometric_user_id`,
      [
        email.trim().toLowerCase(),
        passwordHash,
        role,
        full_name?.trim() || null,
        middle_name?.trim() || null,
        suffix?.trim() || null,
        sex?.trim() || null,
        date_of_birth || null,
        contact_number?.trim() || null,
        address?.trim() || null,
        empNo,
        (employment_type && ['regular', 'contractual', 'job_order', 'casual'].includes(employment_type)) ? employment_type : null,
        salary_grade?.trim() || null,
        date_hired || null,
        (employment_status && ['active', 'inactive', 'resigned', 'retired', 'terminated'].includes(employment_status)) ? employment_status : 'active',
        biometric_user_id?.trim() || null,
      ]
    );

    try {
      // VL/SL: earned credits come from monthly accrual only; no static 15-day seed.
      await pool.query(
        `INSERT INTO leave_balances (user_id, leave_type, earned_days, used_days, pending_days, adjusted_days)
         VALUES ($1::uuid, 'vacationLeave', 0, 0, 0, 0), ($1::uuid, 'sickLeave', 0, 0, 0, 0)
         ON CONFLICT (user_id, leave_type) DO NOTHING`,
        [result.rows[0].id]
      );
    } catch (lbErr) {
      console.warn('[employees POST] Could not create default leave balances:', lbErr.message);
    }

    res.status(201).json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') {
      const constraint = String(err.constraint || '');
      if (constraint.includes('biometric_user_id')) {
        return res.status(409).json({ error: 'Biometric User ID is already assigned to another employee' });
      }
      return res.status(409).json({ error: 'Email already registered' });
    }
    console.error('[employees POST]', err);
    res.status(500).json({ error: 'Failed to create employee' });
  }
});

// PUT /api/employees/:id - update employee (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const {
      full_name,
      role,
      email,
      is_active,
      middle_name,
      suffix,
      sex,
      date_of_birth,
      contact_number,
      address,
      avatar_path,
      employment_type,
      salary_grade,
      date_hired,
      employment_status,
      biometric_user_id,
      office_id,
    } = req.body;

    const existingRes = await pool.query(
      'SELECT biometric_user_id FROM users WHERE id = $1::uuid',
      [id]
    );
    if (existingRes.rowCount === 0) {
      return res.status(404).json({ error: 'Employee not found' });
    }
    const currentBioRaw = existingRes.rows[0].biometric_user_id;
    const currentBioStr = currentBioRaw != null ? String(currentBioRaw).trim() : '';

    if (biometric_user_id !== undefined) {
      const newBioStr =
        biometric_user_id === null || biometric_user_id === ''
          ? ''
          : String(biometric_user_id).trim();
      if (currentBioStr !== '' && newBioStr !== currentBioStr) {
        return res.status(400).json({
          error:
            'Biometric User ID cannot be changed or cleared once it is set; it must stay aligned with the time clock.',
        });
      }
    }

    const updates = [];
    const values = [];
    let i = 1;
    const canUseOfficeId = office_id !== undefined
      ? await hasUsersOfficeIdColumn()
      : false;

    const fields = [
      ['full_name', full_name],
      ['role', role],
      ['email', email],
      ['is_active', is_active],
      ['middle_name', middle_name],
      ['suffix', suffix],
      ['sex', sex],
      ['date_of_birth', date_of_birth],
      ['contact_number', contact_number],
      ['address', address],
      ['avatar_path', avatar_path],
      ['employment_type', employment_type],
      ['salary_grade', salary_grade],
      ['date_hired', date_hired],
      ['employment_status', employment_status],
      ['biometric_user_id', biometric_user_id],
      ...(canUseOfficeId ? [['office_id', office_id]] : []),
    ];
    for (const [col, val] of fields) {
      if (val !== undefined) {
        if (col === 'role' && !['admin', 'employee'].includes(val)) continue;
        if (col === 'employment_type' && val && !['regular', 'contractual', 'job_order', 'casual'].includes(val)) continue;
        if (col === 'employment_status' && val && !['active', 'inactive', 'resigned', 'retired', 'terminated'].includes(val)) continue;
        if (col === 'office_id') {
          const raw = val === null || val === '' ? null : String(val).trim();
          updates.push(`office_id = $${i++}::uuid`);
          values.push(raw);
          continue;
        }
        if (col === 'date_of_birth' || col === 'date_hired') {
          updates.push(`${col} = $${i++}::date`);
          values.push(val || null);
        } else {
          updates.push(`${col} = $${i++}`);
          values.push(typeof val === 'string' ? val.trim() : val);
        }
      }
    }

    if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });
    updates.push('updated_at = now()');
    values.push(id);

    const returningColumns = [
      'id',
      'employee_number',
      'email',
      'role',
      'full_name',
      'avatar_path',
      'is_active',
      'middle_name',
      'suffix',
      'sex',
      'date_of_birth',
      'contact_number',
      'address',
      'employment_type',
      'salary_grade',
      'date_hired',
      'employment_status',
      'biometric_user_id',
      ...(canUseOfficeId ? ['office_id'] : []),
    ];

    const result = await pool.query(
      `UPDATE users SET ${updates.join(', ')} WHERE id = $${i}
       RETURNING ${returningColumns.join(', ')}`,
      values
    );
    if (result.rowCount === 0) return res.status(404).json({ error: 'Employee not found' });
    res.json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'Email already exists' });
    console.error('[employees PUT]', err);
    res.status(500).json({ error: 'Failed to update employee' });
  }
});

// DELETE /api/employees/:id - deactivate (or soft-delete); optional hard delete
router.delete('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const result = await pool.query(
      'UPDATE users SET is_active = false, updated_at = now() WHERE id = $1 RETURNING id',
      [req.params.id]
    );
    if (result.rowCount === 0) return res.status(404).json({ error: 'Employee not found' });
    res.status(204).send();
  } catch (err) {
    console.error('[employees DELETE]', err);
    res.status(500).json({ error: 'Failed to deactivate employee' });
  }
});

module.exports = router;
