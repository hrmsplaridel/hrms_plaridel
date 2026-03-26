const express = require('express');
const bcrypt = require('bcrypt');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');

const router = express.Router();
const protect = [authMiddleware];

const SALT_ROUNDS = 10;

// GET /api/employees - list all (?status=Active|Inactive|All, ?role=admin|employee|All, ?department_id=uuid, ?biometric_user_ids=id1,id2,id3)
router.get('/', protect, async (req, res) => {
  try {
    const status = req.query.status || 'Active';
    const roleFilter = req.query.role || 'All';
    const departmentId = req.query.department_id || null;
    const biometricUserIdsRaw = req.query.biometric_user_ids;

    // When biometric_user_ids is provided, return only matching users (exact match).
    if (biometricUserIdsRaw && typeof biometricUserIdsRaw === 'string') {
      const ids = biometricUserIdsRaw.split(',').map((s) => s.trim()).filter(Boolean);
      if (ids.length > 0) {
        const result = await pool.query(
          `SELECT id, employee_number, full_name, role, email, biometric_user_id, is_active, avatar_path,
                  middle_name, suffix, sex, date_of_birth, contact_number, address,
                  employment_type, salary_grade, date_hired, employment_status
           FROM users
           WHERE biometric_user_id = ANY($1::text[])
           ORDER BY full_name`,
          [ids]
        );
        const rows = result.rows.map((r) => ({
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
        }));
        return res.json(rows);
      }
    }

    const conditions = [];
    const params = [];
    let i = 1;

    const tbl = departmentId ? 'u' : 'users';
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

    const fromClause = departmentId ? 'FROM users u' : 'FROM users';
    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

    const result = await pool.query(
      `SELECT ${tbl}.id, ${tbl}.employee_number, ${tbl}.full_name, ${tbl}.role, ${tbl}.email, ${tbl}.is_active, ${tbl}.avatar_path, ${tbl}.middle_name, ${tbl}.suffix, ${tbl}.sex, ${tbl}.date_of_birth, ${tbl}.contact_number, ${tbl}.address,
              ${tbl}.employment_type, ${tbl}.salary_grade, ${tbl}.date_hired, ${tbl}.employment_status
       ${fromClause}
       ${where}
       ORDER BY ${tbl}.full_name`,
      params
    );

    const rows = result.rows.map((r) => ({
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
    }));
    res.json(rows);
  } catch (err) {
    console.error('[employees GET]', err);
    res.status(500).json({ error: 'Failed to fetch employees' });
  }
});

// GET /api/employees/:id - get one employee (matches profiles)
router.get('/:id', protect, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, employee_number, full_name, role, email, is_active, avatar_path, middle_name, suffix, sex, date_of_birth, contact_number, address,
              employment_type, salary_grade, date_hired, employment_status
       FROM users WHERE id = $1`,
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
    });
  } catch (err) {
    console.error('[employees GET :id]', err);
    res.status(500).json({ error: 'Failed to fetch employee' });
  }
});

// POST /api/employees - create employee (admin only); same as auth/register but admin creates
router.post('/', protect, requireAdmin, async (req, res) => {
  try {
    const { email, password, full_name, role = 'employee', middle_name, suffix, sex, date_of_birth, contact_number, address, employment_type, salary_grade, date_hired, employment_status } = req.body;
    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }
    if (!['admin', 'employee'].includes(role)) {
      return res.status(400).json({ error: 'Role must be admin or employee' });
    }

    const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);

    const result = await pool.query(
      `INSERT INTO users (email, password_hash, role, full_name, middle_name, suffix, sex, date_of_birth, contact_number, address, is_active, employee_number, employment_type, salary_grade, date_hired, employment_status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8::date, $9, $10, true, nextval('users_employee_number_seq'), $11, $12, $13::date, $14)
       RETURNING id, employee_number, email, role, full_name, avatar_path, is_active, middle_name, suffix, sex, date_of_birth, contact_number, address, employment_type, salary_grade, date_hired, employment_status`,
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
        (employment_type && ['regular', 'contractual', 'job_order', 'casual'].includes(employment_type)) ? employment_type : null,
        salary_grade?.trim() || null,
        date_hired || null,
        (employment_status && ['active', 'inactive', 'resigned', 'retired', 'terminated'].includes(employment_status)) ? employment_status : 'active',
      ]
    );

    try {
      await pool.query(
        `INSERT INTO leave_balances (user_id, leave_type, earned_days, used_days, pending_days, adjusted_days)
         VALUES ($1::uuid, 'vacationLeave', 15, 0, 0, 0), ($1::uuid, 'sickLeave', 15, 0, 0, 0)
         ON CONFLICT (user_id, leave_type) DO NOTHING`,
        [result.rows[0].id]
      );
    } catch (lbErr) {
      console.warn('[employees POST] Could not create default leave balances:', lbErr.message);
    }

    res.status(201).json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'Email already registered' });
    console.error('[employees POST]', err);
    res.status(500).json({ error: 'Failed to create employee' });
  }
});

// PUT /api/employees/:id - update employee (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const { full_name, role, email, is_active, middle_name, suffix, sex, date_of_birth, contact_number, address, avatar_path, employment_type, salary_grade, date_hired, employment_status, biometric_user_id } = req.body;

    const updates = [];
    const values = [];
    let i = 1;

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
    ];
    for (const [col, val] of fields) {
      if (val !== undefined) {
        if (col === 'role' && !['admin', 'employee'].includes(val)) continue;
        if (col === 'employment_type' && val && !['regular', 'contractual', 'job_order', 'casual'].includes(val)) continue;
        if (col === 'employment_status' && val && !['active', 'inactive', 'resigned', 'retired', 'terminated'].includes(val)) continue;
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

    const result = await pool.query(
      `UPDATE users SET ${updates.join(', ')} WHERE id = $${i}
       RETURNING id, employee_number, email, role, full_name, avatar_path, is_active, middle_name, suffix, sex, date_of_birth, contact_number, address, biometric_user_id`,
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
