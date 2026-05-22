const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdminOrHr } = require('../middleware/rbac');
const {
  getDepartmentHeadForEmployee,
  getEmployeeDepartment,
  isDepartmentHead,
} = require('../services/departmentHeadService');
const locatorNotifications = require('../services/locatorNotifications');
const { broadcastAppEvent } = require('../websockets/appEvents');

const router = express.Router();
const protect = [authMiddleware];
const LOCATOR_REQUEST_TYPES = new Set(['locator', 'pass_slip', 'work_from_home']);

function notifySafe(fn) {
  Promise.resolve()
    .then(() => fn())
    .catch((e) => console.error('[locator notification]', e));
}

function broadcastLocatorUpdated(action, row = {}, extra = {}) {
  try {
    const slipId = row.id || extra.slipId || null;
    broadcastAppEvent('locator_updated', {
      action,
      slipId,
      locatorSlipId: slipId,
      userId: row.employee_id || row.userId || extra.userId || null,
      status: row.status || extra.status || null,
      updatedAt: new Date().toISOString(),
      ...extra,
    });
  } catch (e) {
    console.error('[locator websocket]', e);
  }
}

function normalizeRequestType(value) {
  const type = (value || 'locator').toString().trim().toLowerCase();
  return LOCATOR_REQUEST_TYPES.has(type) ? type : null;
}

pool
  .query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`)
  .then(() =>
    pool.query(`
      CREATE TABLE IF NOT EXISTS locator_slips (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
        slip_date DATE NOT NULL,
        am_in BOOLEAN NOT NULL DEFAULT false,
        am_out BOOLEAN NOT NULL DEFAULT false,
        pm_in BOOLEAN NOT NULL DEFAULT false,
        pm_out BOOLEAN NOT NULL DEFAULT false,
        request_type TEXT NOT NULL DEFAULT 'locator'
          CONSTRAINT locator_slips_request_type_check
          CHECK (request_type IN ('locator', 'pass_slip', 'work_from_home')),
        office TEXT NOT NULL,
        reason TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending_department_head',
        dept_head_reviewer_id UUID REFERENCES users(id) ON DELETE SET NULL,
        dept_head_reviewed_at TIMESTAMPTZ,
        dept_head_remarks TEXT,
        hr_reviewer_id UUID REFERENCES users(id) ON DELETE SET NULL,
        hr_reviewed_at TIMESTAMPTZ,
        hr_remarks TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
      );

      CREATE INDEX IF NOT EXISTS idx_locator_slips_employee
        ON locator_slips(employee_id, updated_at DESC);
      CREATE INDEX IF NOT EXISTS idx_locator_slips_status
        ON locator_slips(status, updated_at DESC);
      CREATE INDEX IF NOT EXISTS idx_locator_slips_department
        ON locator_slips(department_id, updated_at DESC);
      CREATE INDEX IF NOT EXISTS idx_locator_slips_date
        ON locator_slips(slip_date DESC);

      ALTER TABLE locator_slips
        ADD COLUMN IF NOT EXISTS request_type TEXT NOT NULL DEFAULT 'locator';
      ALTER TABLE locator_slips
        DROP CONSTRAINT IF EXISTS locator_slips_request_type_check;
      ALTER TABLE locator_slips
        ADD CONSTRAINT locator_slips_request_type_check
        CHECK (request_type IN ('locator', 'pass_slip', 'work_from_home'));
      CREATE INDEX IF NOT EXISTS idx_locator_slips_request_type
        ON locator_slips(request_type);
    `)
  )
  .catch((err) =>
    console.error('[locator] failed to ensure locator_slips table', err)
  );

function mapLocatorRow(row) {
  return {
    id: row.id,
    employee_id: row.employee_id,
    employee_name: row.employee_name || null,
    department_id: row.department_id || null,
    department_name: row.department_name || null,
    slip_date: row.slip_date ? String(row.slip_date).slice(0, 10) : null,
    am_in: row.am_in === true,
    am_out: row.am_out === true,
    pm_in: row.pm_in === true,
    pm_out: row.pm_out === true,
    request_type: normalizeRequestType(row.request_type) || 'locator',
    office: row.office || '',
    reason: row.reason || '',
    status: row.status,
    dept_head_reviewer_id: row.dept_head_reviewer_id || null,
    dept_head_reviewer_name: row.dept_head_reviewer_name || null,
    dept_head_reviewed_at: row.dept_head_reviewed_at || null,
    dept_head_remarks: row.dept_head_remarks || null,
    hr_reviewer_id: row.hr_reviewer_id || null,
    hr_reviewer_name: row.hr_reviewer_name || null,
    hr_reviewed_at: row.hr_reviewed_at || null,
    hr_remarks: row.hr_remarks || null,
    created_at: row.created_at || null,
    updated_at: row.updated_at || null,
  };
}

function isValidStatus(status) {
  return [
    'pending',
    'pending_department_head',
    'pending_hr',
    'approved',
    'rejected_by_department_head',
    'rejected_by_hr',
    'cancelled',
  ].includes(status);
}

// GET /api/locator-slips/department-head/check
router.get('/department-head/check', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const client = await pool.connect();
  try {
    const result = await isDepartmentHead(client, userId);
    res.json(result);
  } catch (err) {
    console.error('[locator GET /department-head/check]', err);
    res.status(500).json({ error: 'Failed to check department head status' });
  } finally {
    client.release();
  }
});

// GET /api/locator-slips/my
router.get('/my', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  try {
    const status = (req.query?.status || '').toString().trim() || null;
    if (status && !isValidStatus(status)) {
      return res.status(400).json({ error: 'Invalid status filter' });
    }
    const rows = await pool.query(
      `SELECT ls.*,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       WHERE ls.employee_id = $1::uuid
         AND ($2::text IS NULL OR ls.status = $2::text)
       ORDER BY ls.updated_at DESC, ls.created_at DESC
       LIMIT 500`,
      [userId, status]
    );
    res.json(rows.rows.map(mapLocatorRow));
  } catch (err) {
    console.error('[locator GET /my]', err);
    res.status(500).json({ error: 'Failed to fetch locator slips' });
  }
});

// POST /api/locator-slips/submit
router.post('/submit', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });

  const slipDate = (req.body?.slip_date || '').toString().trim();
  const office = (req.body?.office || '').toString().trim();
  const reason = (req.body?.reason || '').toString().trim();
  const requestType = normalizeRequestType(req.body?.request_type);
  const amIn = req.body?.am_in === true;
  const amOut = req.body?.am_out === true;
  const pmIn = req.body?.pm_in === true;
  const pmOut = req.body?.pm_out === true;

  if (!slipDate) return res.status(400).json({ error: 'slip_date is required' });
  if (!requestType) return res.status(400).json({ error: 'Invalid request_type' });
  if (!office) return res.status(400).json({ error: 'office is required' });
  if (!reason) return res.status(400).json({ error: 'reason is required' });
  if (!amIn && !amOut && !pmIn && !pmOut) {
    return res.status(400).json({ error: 'At least one AM/PM IN/OUT marker is required' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const deptInfo = await getDepartmentHeadForEmployee(client, userId);
    const ownDept = await getEmployeeDepartment(client, userId);
    const submitStatus = deptInfo ? 'pending_department_head' : 'pending_hr';
    const departmentId = deptInfo?.departmentId || ownDept?.departmentId || null;

    const inserted = await client.query(
      `INSERT INTO locator_slips (
        employee_id, department_id, slip_date, am_in, am_out, pm_in, pm_out,
        request_type, office, reason, status, created_at, updated_at
      ) VALUES (
        $1::uuid, $2::uuid, $3::date, $4::boolean, $5::boolean, $6::boolean, $7::boolean,
        $8::text, $9::text, $10::text, $11::text, now(), now()
      )
      RETURNING *`,
      [
        userId,
        departmentId,
        slipDate,
        amIn,
        amOut,
        pmIn,
        pmOut,
        requestType,
        office,
        reason,
        submitStatus,
      ]
    );
    await client.query('COMMIT');

    const out = await pool.query(
      `SELECT ls.*,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       WHERE ls.id = $1::uuid`,
      [inserted.rows[0].id]
    );

    const nameQ = await pool.query('SELECT full_name FROM users WHERE id = $1::uuid', [userId]);
    const employeeName = nameQ.rows[0]?.full_name || 'Employee';
    notifySafe(() =>
      locatorNotifications.notifyAfterSubmit(pool, {
        slipId: inserted.rows[0].id,
        status: submitStatus,
        employeeUserId: userId,
        employeeName,
        slipDate,
        amIn,
        amOut,
        pmIn,
        pmOut,
        requestType,
        departmentHeadUserId: deptInfo?.departmentHeadUserId || null,
      })
    );

    const mapped = mapLocatorRow(out.rows[0]);
    broadcastLocatorUpdated('submitted', mapped);
    res.status(201).json(mapped);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    console.error('[locator POST /submit]', err);
    res.status(500).json({ error: 'Failed to submit locator slip' });
  } finally {
    client.release();
  }
});

// PATCH /api/locator-slips/:id/cancel
router.patch('/:id/cancel', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await client.query(
      `SELECT id, status
       FROM locator_slips
       WHERE id = $1::uuid AND employee_id = $2::uuid
       FOR UPDATE`,
      [id, userId]
    );
    if (current.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Locator slip not found' });
    }
    const status = current.rows[0].status;
    if (!['pending', 'pending_department_head', 'pending_hr'].includes(status)) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: `Cannot cancel locator slip with status '${status}'` });
    }
    await client.query(
      `UPDATE locator_slips
       SET status = 'cancelled', updated_at = now()
       WHERE id = $1::uuid`,
      [id]
    );
    await client.query('COMMIT');
    const out = await pool.query(
      `SELECT ls.*,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       WHERE ls.id = $1::uuid`,
      [id]
    );
    const mapped = mapLocatorRow(out.rows[0]);
    broadcastLocatorUpdated('cancelled', mapped, { previousStatus: status });
    res.json(mapped);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    console.error('[locator PATCH /:id/cancel]', err);
    res.status(500).json({ error: 'Failed to cancel locator slip' });
  } finally {
    client.release();
  }
});

// GET /api/locator-slips/department-head
router.get('/department-head', protect, async (req, res) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Not authenticated' });
  const client = await pool.connect();
  try {
    const deptInfo = await isDepartmentHead(client, userId);
    if (!deptInfo.isDeptHead || !deptInfo.departmentId) {
      return res.status(403).json({ error: 'You are not a department head' });
    }
    const status = (req.query?.status || '').toString().trim() || null;
    if (status && !isValidStatus(status)) {
      return res.status(400).json({ error: 'Invalid status filter' });
    }
    const rows = await client.query(
      `SELECT ls.*,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       WHERE ls.department_id = $1::uuid
         AND (
           ls.status = 'pending_department_head'
           OR ls.dept_head_reviewer_id = $2::uuid
         )
         AND ($3::text IS NULL OR ls.status = $3::text)
       ORDER BY ls.updated_at DESC, ls.created_at DESC
       LIMIT 500`,
      [deptInfo.departmentId, userId, status]
    );
    res.json(rows.rows.map(mapLocatorRow));
  } catch (err) {
    console.error('[locator GET /department-head]', err);
    res.status(500).json({ error: 'Failed to fetch department-head locator slips' });
  } finally {
    client.release();
  }
});

// PATCH /api/locator-slips/:id/department-head-approve
router.patch('/:id/department-head-approve', protect, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (req.body?.reviewer_remarks || '').toString().trim() || null;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const deptInfo = await isDepartmentHead(client, reviewerId);
    if (!deptInfo.isDeptHead || !deptInfo.departmentId) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'You are not a department head' });
    }
    const current = await client.query(
      `SELECT id, status, employee_id, slip_date
       FROM locator_slips
       WHERE id = $1::uuid
         AND department_id = $2::uuid
       FOR UPDATE`,
      [id, deptInfo.departmentId]
    );
    if (current.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Locator slip not found or not in your department' });
    }
    if (current.rows[0].status !== 'pending_department_head') {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: `Cannot approve locator slip with status '${current.rows[0].status}'`,
      });
    }
    await client.query(
      `UPDATE locator_slips
       SET status = 'pending_hr',
           dept_head_reviewer_id = $2::uuid,
           dept_head_reviewed_at = now(),
           dept_head_remarks = $3::text,
           updated_at = now()
       WHERE id = $1::uuid`,
      [id, reviewerId, remarks]
    );
    await client.query('COMMIT');

    const out = await pool.query(
      `SELECT ls.*,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       WHERE ls.id = $1::uuid`,
      [id]
    );
    const mapped = mapLocatorRow(out.rows[0]);
    notifySafe(() =>
      locatorNotifications.notifyDepartmentHeadApprovedForHr(pool, {
        slipId: id,
        employeeName: mapped.employee_name,
        slipDate: mapped.slip_date,
        requestType: mapped.request_type,
      })
    );
    broadcastLocatorUpdated('department_head_approved', mapped);
    res.json(mapped);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    console.error('[locator PATCH /:id/department-head-approve]', err);
    res.status(500).json({ error: 'Failed to approve locator slip (department head)' });
  } finally {
    client.release();
  }
});

// PATCH /api/locator-slips/:id/department-head-reject
router.patch('/:id/department-head-reject', protect, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (req.body?.reviewer_remarks || req.body?.reason || '').toString().trim() || null;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const deptInfo = await isDepartmentHead(client, reviewerId);
    if (!deptInfo.isDeptHead || !deptInfo.departmentId) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'You are not a department head' });
    }
    const current = await client.query(
      `SELECT id, status, employee_id
       FROM locator_slips
       WHERE id = $1::uuid
         AND department_id = $2::uuid
       FOR UPDATE`,
      [id, deptInfo.departmentId]
    );
    if (current.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Locator slip not found or not in your department' });
    }
    if (current.rows[0].status !== 'pending_department_head') {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: `Cannot reject locator slip with status '${current.rows[0].status}'`,
      });
    }
    await client.query(
      `UPDATE locator_slips
       SET status = 'rejected_by_department_head',
           dept_head_reviewer_id = $2::uuid,
           dept_head_reviewed_at = now(),
           dept_head_remarks = $3::text,
           updated_at = now()
       WHERE id = $1::uuid`,
      [id, reviewerId, remarks]
    );
    await client.query('COMMIT');
    notifySafe(() =>
      locatorNotifications.notifyEmployee(pool, {
        employeeUserId: current.rows[0].employee_id,
        slipId: id,
        type: 'locator_rejected_department_head',
        title: 'Locator request not approved by department head',
        body: remarks
          ? `Your locator request was not approved. ${remarks}`
          : 'Your locator request was not approved by your department head.',
        metadata: { reviewer_remarks: remarks },
      })
    );
    const out = await pool.query(
      `SELECT ls.*,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       WHERE ls.id = $1::uuid`,
      [id]
    );
    const mapped = mapLocatorRow(out.rows[0]);
    broadcastLocatorUpdated('department_head_rejected', mapped);
    res.json(mapped);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    console.error('[locator PATCH /:id/department-head-reject]', err);
    res.status(500).json({ error: 'Failed to reject locator slip (department head)' });
  } finally {
    client.release();
  }
});

// GET /api/locator-slips/admin
router.get('/admin', protect, requireAdminOrHr, async (req, res) => {
  try {
    const status = (req.query?.status || '').toString().trim() || null;
    if (status && !isValidStatus(status)) {
      return res.status(400).json({ error: 'Invalid status filter' });
    }
    const rows = await pool.query(
      `SELECT ls.*,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       WHERE ($1::text IS NULL OR ls.status = $1::text)
       ORDER BY ls.updated_at DESC, ls.created_at DESC
       LIMIT 500`,
      [status]
    );
    res.json(rows.rows.map(mapLocatorRow));
  } catch (err) {
    console.error('[locator GET /admin]', err);
    res.status(500).json({ error: 'Failed to fetch locator slips (admin)' });
  }
});

// PATCH /api/locator-slips/:id/approve
router.patch('/:id/approve', protect, requireAdminOrHr, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (req.body?.reviewer_remarks || req.body?.hr_remarks || '').toString().trim() || null;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await client.query(
      `SELECT id, status, employee_id
       FROM locator_slips
       WHERE id = $1::uuid
       FOR UPDATE`,
      [id]
    );
    if (current.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Locator slip not found' });
    }
    if (!['pending_hr', 'pending'].includes(current.rows[0].status)) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: `Cannot approve locator slip with status '${current.rows[0].status}'`,
      });
    }
    await client.query(
      `UPDATE locator_slips
       SET status = 'approved',
           hr_reviewer_id = $2::uuid,
           hr_reviewed_at = now(),
           hr_remarks = $3::text,
           updated_at = now()
       WHERE id = $1::uuid`,
      [id, reviewerId, remarks]
    );
    await client.query('COMMIT');

    notifySafe(() =>
      locatorNotifications.notifyEmployee(pool, {
        employeeUserId: current.rows[0].employee_id,
        slipId: id,
        type: 'locator_approved_hr',
        title: 'Locator request approved',
        body: remarks
          ? `Your locator request was approved. ${remarks}`
          : 'Your locator request was approved by HR.',
        metadata: { reviewer_remarks: remarks },
      })
    );

    const out = await pool.query(
      `SELECT ls.*,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       WHERE ls.id = $1::uuid`,
      [id]
    );
    const mapped = mapLocatorRow(out.rows[0]);
    broadcastLocatorUpdated('approved', mapped);
    res.json(mapped);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    console.error('[locator PATCH /:id/approve]', err);
    res.status(500).json({ error: 'Failed to approve locator slip' });
  } finally {
    client.release();
  }
});

// PATCH /api/locator-slips/:id/reject
router.patch('/:id/reject', protect, requireAdminOrHr, async (req, res) => {
  const reviewerId = req.user?.id;
  if (!reviewerId) return res.status(401).json({ error: 'Not authenticated' });
  const { id } = req.params;
  const remarks = (req.body?.reviewer_remarks || req.body?.reason || req.body?.hr_remarks || '').toString().trim() || null;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const current = await client.query(
      `SELECT id, status, employee_id
       FROM locator_slips
       WHERE id = $1::uuid
       FOR UPDATE`,
      [id]
    );
    if (current.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Locator slip not found' });
    }
    if (!['pending_hr', 'pending'].includes(current.rows[0].status)) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: `Cannot reject locator slip with status '${current.rows[0].status}'`,
      });
    }
    await client.query(
      `UPDATE locator_slips
       SET status = 'rejected_by_hr',
           hr_reviewer_id = $2::uuid,
           hr_reviewed_at = now(),
           hr_remarks = $3::text,
           updated_at = now()
       WHERE id = $1::uuid`,
      [id, reviewerId, remarks]
    );
    await client.query('COMMIT');

    notifySafe(() =>
      locatorNotifications.notifyEmployee(pool, {
        employeeUserId: current.rows[0].employee_id,
        slipId: id,
        type: 'locator_rejected_hr',
        title: 'Locator request not approved',
        body: remarks
          ? `HR did not approve this locator request. ${remarks}`
          : 'HR did not approve this locator request.',
        metadata: { reviewer_remarks: remarks },
      })
    );

    const out = await pool.query(
      `SELECT ls.*,
              u.full_name AS employee_name,
              d.name AS department_name,
              dh.full_name AS dept_head_reviewer_name,
              hr.full_name AS hr_reviewer_name
       FROM locator_slips ls
       LEFT JOIN users u ON u.id = ls.employee_id
       LEFT JOIN departments d ON d.id = ls.department_id
       LEFT JOIN users dh ON dh.id = ls.dept_head_reviewer_id
       LEFT JOIN users hr ON hr.id = ls.hr_reviewer_id
       WHERE ls.id = $1::uuid`,
      [id]
    );
    const mapped = mapLocatorRow(out.rows[0]);
    broadcastLocatorUpdated('rejected', mapped);
    res.json(mapped);
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    console.error('[locator PATCH /:id/reject]', err);
    res.status(500).json({ error: 'Failed to reject locator slip' });
  } finally {
    client.release();
  }
});

module.exports = router;
