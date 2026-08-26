const express = require('express');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const { sendSmtpMail, isSmtpConfigured } = require('../utils/smtpMail');
const {
  normalizeEmploymentStatus,
  accountIsActiveForEmploymentStatus,
  leaveCreditEligibleForEmploymentStatus,
} = require('../utils/employeeStatus');
const {
  validateCreateEmployeePayload,
  validateEmployeeSeparationDates,
  SEPARATION_EMPLOYMENT_STATUSES,
} = require('../utils/employeeAccountValidation');
const {
  EmployeeSetupValidationError,
  normalizeEmployeeSetup,
  applyEmployeeSetup,
} = require('../services/employeeSetupTransaction');
const {
  EmployeeAccountSecurityError,
  lockAndValidateAccountTransition,
  lockAndValidateBulkAccountStatusTransition,
  revokeActiveRefreshTokens,
  writeAccountSecurityAudit,
} = require('../services/employeeAccountSecurity');
const { todayInHrmsTimezone } = require('../utils/dateRangeParser');
const { csvEscape } = require('../utils/csv');

const router = express.Router();
const protect = [authMiddleware];

const SALT_ROUNDS = 10;

function employeeAccountEmailText({ name, email, password, role }) {
  const displayName = String(name || '').trim() || 'Employee';
  const privilege = role === 'admin' ? 'administrator' : 'employee';
  return (
    `Dear ${displayName},\n\n` +
    `Your LGU Plaridel HRMS ${privilege} account has been created.\n\n` +
    'Your login details:\n' +
    `Email: ${email}\n` +
    `Temporary password: ${password}\n\n` +
    'Please sign in to the HRMS and change your password after your first login.\n\n' +
    'Best regards,\n' +
    'Human Resources\n' +
    'LGU Plaridel'
  );
}

function generateTemporaryPassword(length = 12) {
  const lower = 'abcdefghijkmnopqrstuvwxyz';
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const numbers = '23456789';
  const symbols = '!@#$%';
  const all = lower + upper + numbers + symbols;
  const chars = [
    lower[crypto.randomInt(lower.length)],
    upper[crypto.randomInt(upper.length)],
    numbers[crypto.randomInt(numbers.length)],
    symbols[crypto.randomInt(symbols.length)],
  ];
  while (chars.length < length) {
    chars.push(all[crypto.randomInt(all.length)]);
  }
  for (let i = chars.length - 1; i > 0; i--) {
    const j = crypto.randomInt(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
}

async function allocateEmployeeNumber(db = pool) {
  // Allocate stable, ascending employee numbers. Keep advancing if an older
  // record already occupies a sequence value (for example after data import).
  while (true) {
    const seq = await db.query(
      "SELECT nextval('users_employee_number_seq') AS n"
    );
    const candidate = parseInt(seq.rows[0].n, 10);
    const exists = await db.query(
      'SELECT 1 FROM users WHERE employee_number = $1 LIMIT 1',
      [candidate]
    );
    if (exists.rowCount === 0) return candidate;
  }
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

async function ensureEmployeeProfileColumns() {
  await pool.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS first_name TEXT`);
  await pool.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS last_name TEXT`);
  await pool.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS civil_status TEXT`);
  await pool.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS nationality TEXT`);
  await pool.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS date_of_birth DATE`);
  await pool.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS leave_credit_eligible BOOLEAN NOT NULL DEFAULT true`);
  await pool.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS leave_credit_eligible_until DATE`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_users_leave_credit_eligible
    ON users (leave_credit_eligible)
    WHERE leave_credit_eligible = true`);
}

function boolField(value, fallback = true) {
  if (value === undefined) return fallback;
  if (value === null) return fallback;
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  const normalized = String(value).trim().toLowerCase();
  if (!normalized) return fallback;
  if (['false', '0', 'no', 'off'].includes(normalized)) return false;
  if (['true', '1', 'yes', 'on'].includes(normalized)) return true;
  return fallback;
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
    first_name: r.first_name,
    middle_name: r.middle_name,
    last_name: r.last_name,
    suffix: r.suffix,
    sex: r.sex,
    date_of_birth: r.date_of_birth,
    contact_number: r.contact_number,
    address: r.address,
    civil_status: r.civil_status,
    nationality: r.nationality,
    employment_type: r.employment_type,
    salary_grade: r.salary_grade,
    date_hired: r.date_hired,
    separation_date: r.separation_date,
    leave_credit_eligible_until: r.leave_credit_eligible_until,
    employment_status: r.employment_status ?? 'active',
    leave_credit_eligible: r.leave_credit_eligible !== false,
    current_department_id: r.current_department_id ?? null,
    current_department_name: r.current_department_name ?? null,
    current_position_id: r.current_position_id ?? null,
    current_position_name: r.current_position_name ?? null,
    current_shift_punch_mode: r.current_shift_punch_mode ?? 'auto',
    ...(r.office_id !== undefined ? { office_id: r.office_id ?? null } : {}),
  };
}

function employeeListLateralCurSql() {
  return `
       LEFT JOIN LATERAL (
         SELECT d.id AS current_department_id, d.name AS current_department_name,
                p.id AS current_position_id, p.name AS current_position_name,
                COALESCE(s.punch_mode, 'auto') AS current_shift_punch_mode
         FROM assignments a
         LEFT JOIN departments d ON d.id = a.department_id
         LEFT JOIN positions p ON p.id = a.position_id
         LEFT JOIN shifts s ON s.id = a.shift_id
         WHERE a.employee_id = u.id
           AND (a.is_active IS NULL OR a.is_active = true)
           AND a.effective_from <= CURRENT_DATE
           AND (a.effective_to IS NULL OR a.effective_to >= CURRENT_DATE)
         ORDER BY a.effective_from DESC
         LIMIT 1
       ) cur ON true`;
}

function resolveEmployeeListDateRange(query = {}) {
  const startDate = typeof query.start_date === 'string'
    ? query.start_date.trim()
    : '';
  const endDate = typeof query.end_date === 'string'
    ? query.end_date.trim()
    : '';
  if (!startDate && !endDate) {
    return { startDate: null, endDate: null, error: null };
  }
  if (!startDate || !endDate) {
    return {
      startDate: null,
      endDate: null,
      error: 'start_date and end_date must be provided together',
    };
  }
  const dateOnly = /^\d{4}-\d{2}-\d{2}$/;
  const start = dateOnly.test(startDate) ? new Date(`${startDate}T00:00:00Z`) : null;
  const end = dateOnly.test(endDate) ? new Date(`${endDate}T00:00:00Z`) : null;
  if (
    !start ||
    !end ||
    Number.isNaN(start.getTime()) ||
    Number.isNaN(end.getTime()) ||
    start.toISOString().slice(0, 10) !== startDate ||
    end.toISOString().slice(0, 10) !== endDate
  ) {
    return { startDate: null, endDate: null, error: 'Invalid employee date range' };
  }
  if (start > end) {
    return { startDate: null, endDate: null, error: 'start_date must not be after end_date' };
  }
  const inclusiveDays = Math.floor((end - start) / 86400000) + 1;
  if (inclusiveDays > 366) {
    return { startDate: null, endDate: null, error: 'Employee date range cannot exceed 366 days' };
  }
  return { startDate, endDate, error: null };
}

/** Shared FROM + filters for employee list / export (excludes biometric_user_ids shortcut). */
function buildEmployeeListFromSql(req, options = {}) {
  const { deviceBiometricIds = null, historicalRange = null } = options;
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
  if (historicalRange?.startDate && historicalRange?.endDate) {
    const startIdx = i++;
    const endIdx = i++;
    conditions.push(`(
      EXISTS (
        SELECT 1
        FROM assignments historical_presence_assignment
        WHERE historical_presence_assignment.employee_id = ${tbl}.id
          AND historical_presence_assignment.effective_from <= $${endIdx}::date
          AND (
            historical_presence_assignment.effective_to IS NULL
            OR historical_presence_assignment.effective_to >= $${startIdx}::date
          )
      )
      OR EXISTS (
        SELECT 1
        FROM dtr_daily_summary historical_presence_dtr
        WHERE historical_presence_dtr.employee_id = ${tbl}.id
          AND historical_presence_dtr.attendance_date BETWEEN $${startIdx}::date AND $${endIdx}::date
      )
    )`);
    params.push(historicalRange.startDate, historicalRange.endDate);
  }
  if (departmentId) {
    if (historicalRange?.startDate && historicalRange?.endDate) {
      const departmentIdx = i++;
      const startIdx = i++;
      const endIdx = i++;
      conditions.push(`EXISTS (
        SELECT 1
        FROM generate_series(
          $${startIdx}::date,
          $${endIdx}::date,
          INTERVAL '1 day'
        ) AS selected_date(attendance_date)
        CROSS JOIN LATERAL (
          SELECT a.department_id
          FROM assignments a
          WHERE a.employee_id = ${tbl}.id
            AND a.effective_from <= selected_date.attendance_date::date
            AND (a.effective_to IS NULL OR a.effective_to >= selected_date.attendance_date::date)
          ORDER BY a.effective_from DESC, a.created_at DESC, a.id DESC
          LIMIT 1
        ) historical_assignment
        WHERE historical_assignment.department_id = $${departmentIdx}::uuid
      )`);
      params.push(
        departmentId,
        historicalRange.startDate,
        historicalRange.endDate
      );
    } else {
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
      LPAD(CAST(u.employee_number AS TEXT), 3, '0') ILIKE $${i} OR
      ('EMP-' || LPAD(CAST(u.employee_number AS TEXT), 3, '0')) ILIKE $${i} OR
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

function employeeRowsForRequester(rows, requester) {
  const privileged = ['admin', 'hr', 'supervisor'].includes(requester?.role);
  if (privileged) return rows;
  return rows.map((row) => ({
    id: row.id,
    full_name: row.full_name,
    avatar_path: row.avatar_path,
    current_department_name: row.current_department_name,
    current_position_name: row.current_position_name,
  }));
}

// GET /api/employees - list all (?status=Active|Inactive|All, ?role=admin|employee|All, ?department_id=uuid, ?biometric_user_ids=id1,id2,id3)
// Optional: ?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD limits employees to those
// with an assignment or DTR record in the range and makes department membership historical.
// Optional: ?biometric_device_id=<uuid> — admin only; restrict to employees whose biometric_user_id is enrolled on that ZKTeco (reads device live)
// Optional: ?biometric_filter=set|has|missing|none — filter by whether biometric_user_id is set (set/has = non-empty; missing/none = empty)
// Optional: ?q= search; ?sort= & ?order=asc|desc (sort whitelist: full_name, employee_number, role, email, department, position, employment_status, is_active)
// Optional: ?limit=&offset= — when limit is set, response is { employees, total } instead of a raw array.
router.get('/', protect, async (req, res) => {
  try {
    await ensureEmployeeProfileColumns();
    const biometricUserIdsRaw = req.query.biometric_user_ids;

    // When biometric_user_ids is provided, return only matching users (exact match).
    if (biometricUserIdsRaw && typeof biometricUserIdsRaw === 'string') {
      const ids = biometricUserIdsRaw.split(',').map((s) => s.trim()).filter(Boolean);
      if (ids.length > 0) {
        const result = await pool.query(
          `SELECT u.id, u.employee_number, u.full_name, u.role, u.email, u.biometric_user_id, u.is_active, u.avatar_path,
                  u.first_name, u.middle_name, u.last_name, u.suffix, u.sex, u.date_of_birth, u.contact_number, u.address,
                  u.civil_status, u.nationality,
                  u.employment_type, u.salary_grade, u.date_hired, u.separation_date,
                  u.leave_credit_eligible_until,
                  u.employment_status, u.leave_credit_eligible,
                  cur.current_department_name, cur.current_position_name,
                  cur.current_shift_punch_mode
           FROM users u
           ${employeeListLateralCurSql()}
           WHERE u.biometric_user_id = ANY($1::text[])
           ORDER BY u.full_name`,
          [ids]
        );
        const rows = result.rows.map(mapEmployeeListRow);
        return res.json(employeeRowsForRequester(rows, req.user));
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

    const historicalRange = resolveEmployeeListDateRange(req.query);
    if (historicalRange.error) {
      return res.status(400).json({ error: historicalRange.error });
    }
    const { fromSql, params, nextParamIndex } = buildEmployeeListFromSql(req, {
      deviceBiometricIds,
      historicalRange,
    });
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
      `SELECT u.id, u.employee_number, u.full_name, u.role, u.email, u.biometric_user_id, u.is_active, u.avatar_path,
              u.first_name, u.middle_name, u.last_name, u.suffix, u.sex, u.date_of_birth, u.contact_number, u.address,
              u.civil_status, u.nationality,
              u.employment_type, u.salary_grade, u.date_hired, u.separation_date,
              u.leave_credit_eligible_until,
              u.employment_status, u.leave_credit_eligible,
              cur.current_department_name, cur.current_position_name,
              cur.current_shift_punch_mode
       ${fromSql}
       ORDER BY ${orderBy}${limitSql}`,
      dataParams
    );

    const rows = employeeRowsForRequester(result.rows.map(mapEmployeeListRow), req.user);
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
router.get('/export/csv', protect, requireAdmin, async (req, res) => {
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

    const historicalRange = resolveEmployeeListDateRange(req.query);
    if (historicalRange.error) {
      return res.status(400).json({ error: historicalRange.error });
    }
    const { fromSql, params } = buildEmployeeListFromSql(req, {
      deviceBiometricIds,
      historicalRange,
    });
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
  let client;
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
    client = await pool.connect();
    await client.query('BEGIN');
    const targets = await lockAndValidateBulkAccountStatusTransition(client, {
      actorId: req.user.id,
      targetIds: ids,
      isActive,
    });
    const result = await client.query(
      `UPDATE users
          SET is_active = $2,
              updated_at = now()
        WHERE id = ANY($1::uuid[])
        RETURNING id`,
      [ids, isActive]
    );
    if (!isActive) {
      await revokeActiveRefreshTokens(
        client,
        targets.map((target) => target.id)
      );
    }
    for (const target of targets) {
      if (target.is_active === isActive) continue;
      await writeAccountSecurityAudit(client, {
        actorId: req.user.id,
        targetId: target.id,
        action: isActive
          ? 'employee_account_reactivated'
          : 'employee_account_deactivated',
        previous: {
          role: target.role,
          is_active: target.is_active,
          employment_status: target.employment_status,
        },
        next: {
          role: target.role,
          is_active: isActive,
          employment_status: target.employment_status,
        },
        source: 'employee_bulk_status',
      });
    }
    await client.query('COMMIT');
    res.json({ updated: result.rowCount });
  } catch (err) {
    if (client) await client.query('ROLLBACK');
    if (err instanceof EmployeeAccountSecurityError) {
      return res.status(err.statusCode).json({ error: err.message, code: err.code });
    }
    console.error('[employees POST /bulk-status]', err);
    res.status(500).json({ error: 'Failed to update employees' });
  } finally {
    client?.release();
  }
});

// GET /api/employees/:id - get one employee (matches profiles + list row department/position)
router.get('/:id', protect, async (req, res) => {
  try {
    await ensureEmployeeProfileColumns();
    const result = await pool.query(
      `SELECT u.id, u.employee_number, u.full_name, u.role, u.email, u.is_active, u.avatar_path,
              u.first_name, u.middle_name, u.last_name, u.suffix, u.sex, u.date_of_birth, u.contact_number, u.address,
              u.civil_status, u.nationality,
              u.employment_type, u.salary_grade, u.date_hired, u.separation_date,
              u.leave_credit_eligible_until,
              u.employment_status, u.leave_credit_eligible,
              cur.current_department_name, cur.current_position_name,
              cur.current_shift_punch_mode
       FROM users u
       ${employeeListLateralCurSql()}
       WHERE u.id = $1`,
      [req.params.id]
    );
    const r = result.rows[0];
    if (!r) return res.status(404).json({ error: 'Employee not found' });

    const privileged = ['admin', 'hr', 'supervisor'].includes(req.user?.role);
    if (!privileged && String(req.user?.id) !== String(r.id)) {
      return res.json({
        id: r.id,
        full_name: r.full_name ?? 'Unknown',
        avatar_path: r.avatar_path,
        current_department_name: r.current_department_name ?? null,
        current_position_name: r.current_position_name ?? null,
      });
    }

    res.json({
      id: r.id,
      employee_number: r.employee_number,
      full_name: r.full_name ?? 'Unknown',
      role: r.role ?? 'employee',
      email: r.email,
      is_active: r.is_active ?? true,
      avatar_path: r.avatar_path,
      first_name: r.first_name,
      middle_name: r.middle_name,
      last_name: r.last_name,
      suffix: r.suffix,
      sex: r.sex,
      date_of_birth: r.date_of_birth,
      contact_number: r.contact_number,
      address: r.address,
      civil_status: r.civil_status,
      nationality: r.nationality,
      employment_type: r.employment_type,
      salary_grade: r.salary_grade,
      date_hired: r.date_hired,
      separation_date: r.separation_date,
      leave_credit_eligible_until: r.leave_credit_eligible_until,
      employment_status: r.employment_status ?? 'active',
      leave_credit_eligible: r.leave_credit_eligible !== false,
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
    await ensureEmployeeProfileColumns();
    const { email, password, first_name, full_name, last_name, role = 'employee', middle_name, suffix, sex, date_of_birth, contact_number, address, civil_status, nationality, employment_type, salary_grade, date_hired, separation_date, employment_status, biometric_user_id, leave_credit_eligible, setup } = req.body;
    const validationError = validateCreateEmployeePayload(req.body);
    if (validationError) {
      return res.status(400).json({ error: validationError });
    }
    if (!['admin', 'employee'].includes(role)) {
      return res.status(400).json({ error: 'Role must be admin or employee' });
    }

    const temporaryPassword =
      typeof password === 'string' && password.trim()
        ? password.trim()
        : generateTemporaryPassword();
    const passwordHash = await bcrypt.hash(temporaryPassword, SALT_ROUNDS);
    const normalizedEmploymentStatus =
      normalizeEmploymentStatus(employment_status);
    const accountIsActive = accountIsActiveForEmploymentStatus(
      normalizedEmploymentStatus
    );
    const normalizedLeaveCreditEligible =
      leaveCreditEligibleForEmploymentStatus(
        normalizedEmploymentStatus,
        boolField(leave_credit_eligible, true)
      );
    const leaveCreditEligibleUntil =
      SEPARATION_EMPLOYMENT_STATUSES.has(normalizedEmploymentStatus) &&
      boolField(leave_credit_eligible, true)
        ? separation_date
        : null;
    const normalizedSetup = normalizeEmployeeSetup(setup, {
      effectiveFrom: date_hired,
      effectiveTo: separation_date || null,
      isActive: accountIsActive,
    });

    const client = await pool.connect();
    let createdEmployee;
    let initialSetup = null;
    try {
      await client.query('BEGIN');
      const empNo = await allocateEmployeeNumber(client);
      const result = await client.query(
        `INSERT INTO users (
           email, password_hash, role, first_name, full_name, last_name, middle_name,
           suffix, sex, date_of_birth, contact_number, address, civil_status,
           nationality, is_active, employee_number, employment_type, salary_grade,
           date_hired, separation_date, employment_status, biometric_user_id,
           leave_credit_eligible, leave_credit_eligible_until
         )
         VALUES (
           $1, $2, $3, $4, $5, $6, $7,
           $8, $9, $10::date, $11, $12, $13,
           $14, $15, $16, $17, $18,
           $19::date, $20::date, $21, $22, $23, $24::date
         )
         RETURNING id, employee_number, email, role, first_name, full_name, last_name,
                   avatar_path, is_active, middle_name, suffix, sex, date_of_birth,
                   contact_number, address, civil_status, nationality, employment_type,
                   salary_grade, date_hired, separation_date, employment_status,
                   biometric_user_id, leave_credit_eligible,
                   leave_credit_eligible_until`,
        [
          email.trim().toLowerCase(),
          passwordHash,
          role,
          first_name?.trim() || null,
          full_name?.trim() || null,
          last_name?.trim() || null,
          middle_name?.trim() || null,
          suffix?.trim() || null,
          sex?.trim() || null,
          date_of_birth || null,
          contact_number?.trim() || null,
          address?.trim() || null,
          civil_status?.trim() || null,
          nationality?.trim() || null,
          accountIsActive,
          empNo,
          (employment_type && ['regular', 'contractual', 'job_order', 'casual'].includes(employment_type)) ? employment_type : null,
          salary_grade?.trim() || null,
          date_hired || null,
          separation_date || null,
          normalizedEmploymentStatus,
          biometric_user_id?.trim() || null,
          normalizedLeaveCreditEligible,
          leaveCreditEligibleUntil,
        ]
      );
      createdEmployee = result.rows[0];

      // VL/SL earned credits still come from month-end accrual; these are only
      // the required zero-value wallets for the new employee.
      await client.query(
        `INSERT INTO leave_balances (
           user_id, leave_type, earned_days, used_days, pending_days, adjusted_days
         )
         VALUES
           ($1::uuid, 'vacationLeave', 0, 0, 0, 0),
           ($1::uuid, 'sickLeave', 0, 0, 0, 0)
         ON CONFLICT (user_id, leave_type) DO NOTHING`,
        [createdEmployee.id]
      );

      initialSetup = await applyEmployeeSetup(client, {
        employeeId: createdEmployee.id,
        setup: normalizedSetup,
        remarks: 'Initial assignment from employee setup',
      });
      await client.query('COMMIT');
    } catch (transactionError) {
      await client.query('ROLLBACK');
      throw transactionError;
    } finally {
      client.release();
    }

    let accountEmailSent = false;
    let accountEmailError = null;

    if (createdEmployee.is_active && isSmtpConfigured()) {
      try {
        const employeeEmail = String(createdEmployee.email || '').trim();
        await sendSmtpMail({
          to: employeeEmail,
          subject: 'Your LGU Plaridel HRMS account is ready',
          text: employeeAccountEmailText({
            name: createdEmployee.full_name,
            email: employeeEmail,
            password: temporaryPassword,
            role: createdEmployee.role,
          }),
        });
        accountEmailSent = true;
      } catch (mailErr) {
        accountEmailError = mailErr?.message
          ? String(mailErr.message)
          : 'Failed to send account email';
        console.warn('[employees POST] Account email failed:', accountEmailError);
      }
    }

    res.status(201).json({
      ...createdEmployee,
      account_email_sent: accountEmailSent,
      account_email_configured: isSmtpConfigured(),
      temporary_password: temporaryPassword,
      initial_setup: initialSetup,
      ...(accountEmailError ? { account_email_error: accountEmailError } : {}),
    });
  } catch (err) {
    if (err instanceof EmployeeSetupValidationError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    if (err.code === '22P02' || err.code === '23503') {
      return res.status(400).json({ error: 'Invalid employee setup selection' });
    }
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
    await ensureEmployeeProfileColumns();
    const { id } = req.params;
    const {
      first_name,
      full_name,
      last_name,
      role,
      email,
      is_active,
      middle_name,
      suffix,
      sex,
      date_of_birth,
      contact_number,
      address,
      civil_status,
      nationality,
      avatar_path,
      employment_type,
      salary_grade,
      date_hired,
      separation_date,
      employment_status,
      biometric_user_id,
      leave_credit_eligible,
      office_id,
      setup,
    } = req.body;

    const existingRes = await pool.query(
      `SELECT biometric_user_id, employment_status, date_hired,
              separation_date::text AS separation_date,
              leave_credit_eligible, leave_credit_eligible_until::text
       FROM users WHERE id = $1::uuid`,
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
    const validEmploymentStatus =
      employment_status !== undefined &&
      normalizeEmploymentStatus(employment_status) === employment_status;
    const effectiveEmploymentStatus = validEmploymentStatus
      ? employment_status
      : normalizeEmploymentStatus(existingRes.rows[0].employment_status);
    const effectiveDateHired = date_hired !== undefined
      ? date_hired
      : existingRes.rows[0].date_hired?.toISOString?.().slice(0, 10) ||
        existingRes.rows[0].date_hired;
    const suppliedSeparationDate = separation_date === null || separation_date === ''
      ? null
      : separation_date;
    const effectiveSeparationDate = SEPARATION_EMPLOYMENT_STATUSES.has(
      effectiveEmploymentStatus
    )
      ? (separation_date !== undefined
          ? suppliedSeparationDate
          : existingRes.rows[0].separation_date)
      : null;
    const lifecycleError = validateEmployeeSeparationDates({
      dateHired: effectiveDateHired,
      employmentStatus: effectiveEmploymentStatus,
      separationDate: effectiveSeparationDate,
    });
    if (lifecycleError) {
      return res.status(400).json({ error: lifecycleError });
    }
    const nonActiveEmploymentStatus =
      effectiveEmploymentStatus !== 'active';
    const effectiveIsActive = nonActiveEmploymentStatus ? false : is_active;
    const requestedRole =
      role !== undefined && ['admin', 'employee'].includes(role)
        ? role
        : undefined;
    const requestedLeaveCreditEligible = leave_credit_eligible !== undefined
      ? boolField(leave_credit_eligible, true)
      : existingRes.rows[0].leave_credit_eligible !== false;
    const effectiveLeaveCreditEligible = nonActiveEmploymentStatus
      ? false
      : requestedLeaveCreditEligible;
    const wasEligibleForAccrual =
      existingRes.rows[0].leave_credit_eligible !== false ||
      Boolean(existingRes.rows[0].leave_credit_eligible_until);
    const effectiveLeaveCreditEligibleUntil =
      SEPARATION_EMPLOYMENT_STATUSES.has(effectiveEmploymentStatus) &&
      (wasEligibleForAccrual || requestedLeaveCreditEligible)
        ? effectiveSeparationDate
        : null;
    const shouldUpdateSeparation =
      separation_date !== undefined || employment_status !== undefined;
    const canUseOfficeId = office_id !== undefined
      ? await hasUsersOfficeIdColumn()
      : false;
    const normalizedSetup = normalizeEmployeeSetup(setup, {
      effectiveFrom: todayInHrmsTimezone(),
      effectiveTo: effectiveSeparationDate,
      isActive: !nonActiveEmploymentStatus,
    });
    if (nonActiveEmploymentStatus && normalizedSetup?.isActive) {
      return res.status(400).json({
        error: 'Inactive or separated employees cannot receive an active setup',
      });
    }

    const fields = [
      ['first_name', first_name],
      ['full_name', full_name],
      ['last_name', last_name],
      ['role', role],
      ['email', email],
      ['is_active', effectiveIsActive],
      ['middle_name', middle_name],
      ['suffix', suffix],
      ['sex', sex],
      ['date_of_birth', date_of_birth],
      ['contact_number', contact_number],
      ['address', address],
      ['civil_status', civil_status],
      ['nationality', nationality],
      ['avatar_path', avatar_path],
      ['employment_type', employment_type],
      ['salary_grade', salary_grade],
      ['date_hired', date_hired],
      [
        'separation_date',
        shouldUpdateSeparation ? effectiveSeparationDate : undefined,
      ],
      ['employment_status', employment_status],
      ['biometric_user_id', biometric_user_id],
      ['leave_credit_eligible', effectiveLeaveCreditEligible],
      [
        'leave_credit_eligible_until',
        shouldUpdateSeparation
          ? effectiveLeaveCreditEligibleUntil
          : undefined,
      ],
      ...(canUseOfficeId ? [['office_id', office_id]] : []),
    ];
    for (const [col, val] of fields) {
      if (val !== undefined) {
        if (col === 'role' && !['admin', 'employee'].includes(val)) continue;
        if (col === 'employment_type' && val && !['regular', 'contractual', 'job_order', 'casual'].includes(val)) continue;
        if (col === 'employment_status' && val && !['active', 'inactive', 'resigned', 'retired', 'terminated'].includes(val)) continue;
        if (col === 'leave_credit_eligible') {
          updates.push(`${col} = $${i++}`);
          values.push(boolField(val, true));
          continue;
        }
        if (col === 'office_id') {
          const raw = val === null || val === '' ? null : String(val).trim();
          updates.push(`office_id = $${i++}::uuid`);
          values.push(raw);
          continue;
        }
        if (
          col === 'date_of_birth' ||
          col === 'date_hired' ||
          col === 'separation_date' ||
          col === 'leave_credit_eligible_until'
        ) {
          updates.push(`${col} = $${i++}::date`);
          values.push(val || null);
        } else {
          updates.push(`${col} = $${i++}`);
          values.push(typeof val === 'string' ? val.trim() : val);
        }
      }
    }

    if (updates.length === 0 && !normalizedSetup) {
      return res.status(400).json({ error: 'No fields to update' });
    }
    updates.push('updated_at = now()');
    values.push(id);

    const returningColumns = [
      'id',
      'employee_number',
      'email',
      'role',
      'first_name',
      'full_name',
      'last_name',
      'avatar_path',
      'is_active',
      'middle_name',
      'suffix',
      'sex',
      'date_of_birth',
      'contact_number',
      'address',
      'civil_status',
      'nationality',
      'employment_type',
      'salary_grade',
      'date_hired',
      'separation_date',
      'employment_status',
      'biometric_user_id',
      'leave_credit_eligible',
      'leave_credit_eligible_until',
      ...(canUseOfficeId ? ['office_id'] : []),
    ];

    const client = await pool.connect();
    let result;
    let updatedSetup = null;
    let accountTransition;
    try {
      await client.query('BEGIN');
      accountTransition = await lockAndValidateAccountTransition(client, {
        actorId: req.user.id,
        targetId: id,
        nextRole: requestedRole,
        nextIsActive: effectiveIsActive,
        nextEmploymentStatus: effectiveEmploymentStatus,
      });
      result = await client.query(
        `UPDATE users SET ${updates.join(', ')} WHERE id = $${i}
         RETURNING ${returningColumns.join(', ')}`,
         values
       );

      updatedSetup = await applyEmployeeSetup(client, {
        employeeId: id,
        setup: normalizedSetup,
        remarks: 'Updated from employee edit',
      });

      if (
        shouldUpdateSeparation &&
        SEPARATION_EMPLOYMENT_STATUSES.has(effectiveEmploymentStatus)
      ) {
        await client.query(
          `UPDATE assignments
              SET is_active = false,
                  updated_at = now()
            WHERE employee_id = $1::uuid
              AND is_active = true
              AND effective_from > $2::date`,
          [id, effectiveSeparationDate]
        );
        await client.query(
          `WITH target AS (
             SELECT id
               FROM assignments
              WHERE employee_id = $1::uuid
                AND effective_from <= $2::date
                AND (
                  effective_to IS NULL
                  OR effective_to >= $2::date
                  OR effective_to = $3::date
                )
              ORDER BY effective_from DESC, created_at DESC, id DESC
              LIMIT 1
           )
           UPDATE assignments a
              SET effective_to = $2::date,
                  updated_at = now()
             FROM target
            WHERE a.id = target.id`,
          [id, effectiveSeparationDate, existingRes.rows[0].separation_date]
        );
        await client.query(
          `UPDATE policy_assignments
              SET is_active = false,
                  effective_to = CASE
                    WHEN effective_from <= $2::date THEN $2::date
                    ELSE effective_to
                  END,
                  updated_at = now()
            WHERE employee_id = $1::uuid
              AND is_active = true`,
          [id, effectiveSeparationDate]
        );
      }

      if (accountTransition.revokeSessions) {
        await revokeActiveRefreshTokens(client, id);
      }
      if (accountTransition.changed) {
        await writeAccountSecurityAudit(client, {
          actorId: req.user.id,
          targetId: id,
          action: 'employee_account_security_updated',
          previous: accountTransition.previous,
          next: accountTransition.next,
          source: 'employee_update',
        });
      }

      await client.query('COMMIT');
    } catch (transactionError) {
      await client.query('ROLLBACK');
      throw transactionError;
    } finally {
      client.release();
    }
    if (result.rowCount === 0) return res.status(404).json({ error: 'Employee not found' });
    res.json({ ...result.rows[0], updated_setup: updatedSetup });
  } catch (err) {
    if (err instanceof EmployeeAccountSecurityError) {
      return res.status(err.statusCode).json({ error: err.message, code: err.code });
    }
    if (err instanceof EmployeeSetupValidationError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    if (err.code === '22P02' || err.code === '23503') {
      return res.status(400).json({ error: 'Invalid employee setup selection' });
    }
    if (err.code === '23505') return res.status(409).json({ error: 'Email already exists' });
    console.error('[employees PUT]', err);
    res.status(500).json({ error: 'Failed to update employee' });
  }
});

// DELETE /api/employees/:id - deactivate (or soft-delete); optional hard delete
router.delete('/:id', protect, requireAdmin, async (req, res) => {
  let client;
  try {
    client = await pool.connect();
    await client.query('BEGIN');
    const transition = await lockAndValidateAccountTransition(client, {
      actorId: req.user.id,
      targetId: req.params.id,
      nextIsActive: false,
    });
    await client.query(
      'UPDATE users SET is_active = false, updated_at = now() WHERE id = $1::uuid',
      [req.params.id]
    );
    await revokeActiveRefreshTokens(client, req.params.id);
    if (transition.changed) {
      await writeAccountSecurityAudit(client, {
        actorId: req.user.id,
        targetId: req.params.id,
        action: 'employee_account_deactivated',
        previous: transition.previous,
        next: transition.next,
        source: 'employee_delete',
      });
    }
    await client.query('COMMIT');
    res.status(204).send();
  } catch (err) {
    if (client) await client.query('ROLLBACK');
    if (err instanceof EmployeeAccountSecurityError) {
      return res.status(err.statusCode).json({ error: err.message, code: err.code });
    }
    console.error('[employees DELETE]', err);
    res.status(500).json({ error: 'Failed to deactivate employee' });
  } finally {
    client?.release();
  }
});

module.exports = router;
