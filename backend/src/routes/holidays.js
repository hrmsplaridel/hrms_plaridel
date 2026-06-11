const express = require('express');
const { pool } = require('../config/db');
const { authMiddleware } = require('../middleware/auth');
const { requireAdmin } = require('../middleware/rbac');
const {
  deleteHolidayDefaultTemplate,
  getHolidayDefaultTemplate,
  getHolidayDefaultTemplateYears,
  listHolidayDefaultTemplates,
  upsertHolidayDefaultTemplate,
} = require('../services/holidayDefaultTemplates');

const router = express.Router();
const protect = [authMiddleware];

/** Return date as YYYY-MM-DD to avoid timezone shift when pg returns Date (serializes to ISO UTC). */
function toDateString(v) {
  if (v == null) return null;
  if (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}/.test(v)) return v.split('T')[0];
  if (v instanceof Date) {
    const y = v.getFullYear();
    const m = String(v.getMonth() + 1).padStart(2, '0');
    const d = String(v.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }
  return String(v).split('T')[0];
}

/** Normalize create/update body: date_from, date_to, or legacy holiday_date (single day). */
function normalizeRange(body) {
  let dateFrom = body.date_from ?? body.dateFrom;
  let dateTo = body.date_to ?? body.dateTo;
  const legacy = body.holiday_date ?? body.holidayDate;
  if ((!dateFrom || !dateTo) && legacy) {
    const d = String(legacy).split('T')[0];
    dateFrom = dateFrom || d;
    dateTo = dateTo || d;
  }
  return {
    dateFrom: dateFrom ? String(dateFrom).split('T')[0] : null,
    dateTo: dateTo ? String(dateTo).split('T')[0] : null,
  };
}

function rowToJson(r) {
  const dateFrom = toDateString(r.date_from);
  const dateTo = toDateString(r.date_to);
  return {
    id: r.id,
    date_from: dateFrom,
    date_to: dateTo,
    holiday_date: dateFrom,
    name: r.name,
    holiday_type: r.holiday_type || 'regular',
    description: r.description,
    is_active: r.is_active ?? true,
    recurring: r.recurring ?? false,
    coverage: r.coverage || 'whole_day',
    created_at: r.created_at,
  };
}

function holidayDefaultKey(item) {
  return [
    String(item.name || '').trim().toLowerCase(),
    toDateString(item.date_from),
    toDateString(item.date_to),
  ].join('|');
}

async function existingHolidayKeyMap(holidays, client = pool) {
  if (!holidays.length) return new Map();
  const minDate = holidays.reduce(
    (min, item) => (item.date_from < min ? item.date_from : min),
    holidays[0].date_from
  );
  const maxDate = holidays.reduce(
    (max, item) => (item.date_to > max ? item.date_to : max),
    holidays[0].date_to
  );
  const result = await client.query(
    `SELECT id, name, date_from, date_to
       FROM holidays
      WHERE date_from <= $1::date
        AND date_to >= $2::date`,
    [maxDate, minDate]
  );
  const map = new Map();
  for (const row of result.rows) {
    map.set(holidayDefaultKey(row), row.id);
  }
  return map;
}

async function templateOr404(req, res) {
  const year = Number(req.query.year ?? req.body?.year);
  const template = await getHolidayDefaultTemplate(year);
  if (!template) {
    res.status(404).json({
      error: 'No Philippine holiday template is available for that year.',
      supported_years: await getHolidayDefaultTemplateYears(),
    });
    return null;
  }
  return template;
}

// GET /api/holidays - list (?year=YYYY optional, ?is_active=true). Tolerates missing coverage column (pre-migration).
router.get('/', protect, async (req, res) => {
  try {
    const year = req.query.year;
    const isActive = req.query.is_active;
    const params = [];
    const conditions = [];
    if (year) {
      conditions.push(
        `(date_from <= $${params.length + 1}::date AND date_to >= $${params.length + 2}::date OR recurring = true)`
      );
      params.push(`${year}-12-31`, `${year}-01-01`);
    }
    if (isActive === 'true' || isActive === true) { conditions.push(`(is_active IS NULL OR is_active = true)`); }
    else if (isActive === 'false' || isActive === false) { conditions.push(`is_active = false`); }
    const where = conditions.length ? ' WHERE ' + conditions.join(' AND ') : '';
    const order = ' ORDER BY date_from, date_to';

    let result;
    try {
      result = await pool.query(
        `SELECT id, date_from, date_to, name, holiday_type, description, is_active, recurring, coverage, created_at FROM holidays${where}${order}`,
        params
      );
    } catch (err) {
      if (err.message && /coverage|column.*does not exist/i.test(err.message)) {
        result = await pool.query(
          `SELECT id, date_from, date_to, name, holiday_type, description, is_active, recurring, created_at FROM holidays${where}${order}`,
          params
        );
        for (const r of result.rows) r.coverage = 'whole_day';
      } else throw err;
    }
    res.json(result.rows.map((r) => rowToJson(r)));
  } catch (err) {
    console.error('[holidays GET]', err);
    res.status(500).json({ error: 'Failed to fetch holidays' });
  }
});

// GET /api/holidays/ph-defaults/templates - list available PH default templates.
router.get('/ph-defaults/templates', protect, requireAdmin, async (_req, res) => {
  try {
    const templates = await listHolidayDefaultTemplates();
    res.json({
      supported_years: templates
        .filter((template) => template.is_active !== false)
        .map((template) => template.year),
      templates,
    });
  } catch (err) {
    console.error('[holiday default templates GET]', err);
    res.status(500).json({ error: 'Failed to list holiday templates' });
  }
});

// POST /api/holidays/ph-defaults/templates - add or replace a PH default template.
router.post('/ph-defaults/templates', protect, requireAdmin, async (req, res) => {
  try {
    const template = await upsertHolidayDefaultTemplate(req.body || {});
    res.status(201).json(template);
  } catch (err) {
    const status = err.statusCode || 500;
    if (status >= 500) console.error('[holiday default templates POST]', err);
    res.status(status).json({
      error: err.message || 'Failed to save holiday template',
    });
  }
});

// DELETE /api/holidays/ph-defaults/templates/:year - remove an admin-maintained PH template.
router.delete('/ph-defaults/templates/:year', protect, requireAdmin, async (req, res) => {
  try {
    const deleted = await deleteHolidayDefaultTemplate(req.params.year);
    if (!deleted) return res.status(404).json({ error: 'Template not found' });
    res.status(204).send();
  } catch (err) {
    const status = err.statusCode || 500;
    if (status >= 500) console.error('[holiday default templates DELETE]', err);
    res.status(status).json({
      error: err.message || 'Failed to delete holiday template',
    });
  }
});

// GET /api/holidays/ph-defaults?year=YYYY - preview maintained Philippine national holiday defaults.
router.get('/ph-defaults', protect, requireAdmin, async (req, res) => {
  try {
    const template = await templateOr404(req, res);
    if (!template) return;
    const existing = await existingHolidayKeyMap(template.holidays);
    res.json({
      year: template.year,
      country: template.country,
      label: template.label,
      source: template.source,
      note: template.note,
      source_mode: template.source_mode,
      supported_years: template.supported_years,
      holidays: template.holidays.map((item) => {
        const existingId = existing.get(holidayDefaultKey(item)) || null;
        return {
          ...item,
          exists: existingId != null,
          existing_id: existingId,
        };
      }),
    });
  } catch (err) {
    console.error('[holidays PH defaults GET]', err);
    res.status(500).json({ error: 'Failed to load Philippine holiday defaults' });
  }
});

// POST /api/holidays/ph-defaults/import - insert missing Philippine defaults for a supported year.
router.post('/ph-defaults/import', protect, requireAdmin, async (req, res) => {
  const client = await pool.connect();
  try {
    const template = await templateOr404(req, res);
    if (!template) return;
    await client.query('BEGIN');
    const existing = await existingHolidayKeyMap(template.holidays, client);
    const created = [];
    const skipped = [];

    for (const item of template.holidays) {
      const key = holidayDefaultKey(item);
      if (existing.has(key)) {
        skipped.push({ ...item, exists: true, existing_id: existing.get(key) });
        continue;
      }
      const result = await client.query(
        `INSERT INTO holidays
          (date_from, date_to, name, holiday_type, description, is_active, recurring, coverage)
         VALUES ($1::date, $2::date, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (name, date_from, date_to) DO NOTHING
         RETURNING id, date_from, date_to, name, holiday_type, description, is_active, recurring, coverage, created_at`,
        [
          item.date_from,
          item.date_to,
          item.name,
          item.holiday_type,
          item.description,
          item.is_active,
          item.recurring,
          item.coverage,
        ]
      );
      if (result.rowCount === 0) {
        skipped.push({ ...item, exists: true, existing_id: null });
      } else {
        created.push(rowToJson(result.rows[0]));
      }
    }

    await client.query('COMMIT');
    res.status(201).json({
      year: template.year,
      source: template.source,
      created_count: created.length,
      skipped_count: skipped.length,
      created,
      skipped,
    });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('[holidays PH defaults import POST]', err);
    res.status(500).json({ error: 'Failed to import Philippine holiday defaults' });
  } finally {
    client.release();
  }
});

// POST /api/holidays - create (admin only)
router.post('/', protect, requireAdmin, async (req, res) => {
  try {
    const { name, holiday_type = 'regular', description, is_active = true, recurring = false, coverage: bodyCoverage } = req.body;
    const { dateFrom, dateTo } = normalizeRange(req.body);
    if (!dateFrom || !dateTo || !name || !name.trim()) {
      return res.status(400).json({ error: 'date_from, date_to, and name are required' });
    }
    if (dateTo < dateFrom) {
      return res.status(400).json({ error: 'date_to must be on or after date_from' });
    }
    const type = ['regular', 'special', 'local', 'work_suspension'].includes(holiday_type) ? holiday_type : 'regular';
    const coverageAllowed = ['whole_day', 'am_only', 'pm_only'];
    let coverage = coverageAllowed.includes(bodyCoverage) ? bodyCoverage : 'whole_day';
    if (type !== 'work_suspension') coverage = 'whole_day';

    const result = await pool.query(
      `INSERT INTO holidays (date_from, date_to, name, holiday_type, description, is_active, recurring, coverage)
       VALUES ($1::date, $2::date, $3, $4, $5, $6, $7, $8)
       RETURNING id, date_from, date_to, name, holiday_type, description, is_active, recurring, coverage, created_at`,
      [dateFrom, dateTo, name.trim(), type, description?.trim() || null, !!is_active, !!recurring, coverage]
    );
    const row = result.rows[0];
    res.status(201).json(rowToJson(row));
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'A holiday with this name and date range already exists.' });
    console.error('[holidays POST]', err);
    res.status(500).json({ error: 'Failed to create holiday' });
  }
});

// PUT /api/holidays/:id - update (admin only)
router.put('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const { name, holiday_type, description, is_active, recurring, coverage: bodyCoverage } = req.body;
    const hasRangeKey = ['date_from', 'date_to', 'holiday_date', 'dateFrom', 'dateTo', 'holidayDate'].some(
      (k) => req.body[k] !== undefined
    );
    const range = normalizeRange(req.body);

    const updates = [];
    const values = [];
    let i = 1;
    if (hasRangeKey) {
      if (!range.dateFrom || !range.dateTo) {
        return res.status(400).json({ error: 'Provide both date_from and date_to (or holiday_date for a single day).' });
      }
      if (range.dateTo < range.dateFrom) {
        return res.status(400).json({ error: 'date_to must be on or after date_from' });
      }
      updates.push(`date_from = $${i++}::date`); values.push(range.dateFrom);
      updates.push(`date_to = $${i++}::date`); values.push(range.dateTo);
    }
    if (name !== undefined) { updates.push(`name = $${i++}`); values.push(name.trim()); }
    if (holiday_type !== undefined) {
      const type = ['regular', 'special', 'local', 'work_suspension'].includes(holiday_type) ? holiday_type : 'regular';
      updates.push(`holiday_type = $${i++}`);
      values.push(type);
    }
    if (description !== undefined) { updates.push(`description = $${i++}`); values.push(description?.trim() || null); }
    if (is_active !== undefined) { updates.push(`is_active = $${i++}`); values.push(!!is_active); }
    if (recurring !== undefined) { updates.push(`recurring = $${i++}`); values.push(!!recurring); }
    if (bodyCoverage !== undefined) {
      const coverageAllowed = ['whole_day', 'am_only', 'pm_only'];
      const coverage = coverageAllowed.includes(bodyCoverage) ? bodyCoverage : 'whole_day';
      updates.push(`coverage = $${i++}`); values.push(coverage);
    }
    if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });
    values.push(id);

    const result = await pool.query(
      `UPDATE holidays SET ${updates.join(', ')} WHERE id = $${i}
       RETURNING id, date_from, date_to, name, holiday_type, description, is_active, recurring, coverage, created_at`,
      values
    );
    if (result.rowCount === 0) return res.status(404).json({ error: 'Holiday not found' });
    const row = result.rows[0];
    res.json(rowToJson(row));
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'A holiday with this name and date range already exists.' });
    console.error('[holidays PUT]', err);
    res.status(500).json({ error: 'Failed to update holiday' });
  }
});

// DELETE /api/holidays/:id (admin only)
router.delete('/:id', protect, requireAdmin, async (req, res) => {
  try {
    const result = await pool.query('DELETE FROM holidays WHERE id = $1 RETURNING id', [req.params.id]);
    if (result.rowCount === 0) return res.status(404).json({ error: 'Holiday not found' });
    res.status(204).send();
  } catch (err) {
    console.error('[holidays DELETE]', err);
    res.status(500).json({ error: 'Failed to delete holiday' });
  }
});

module.exports = router;
