const { pool } = require('../config/db');
const {
  getPhilippineHolidayDefaults,
  supportedYears: supportedBuiltInYears,
} = require('./philippineHolidayDefaults');

const VALID_HOLIDAY_TYPES = new Set([
  'regular',
  'special',
  'local',
  'work_suspension',
]);

const VALID_COVERAGE = new Set(['whole_day', 'am_only', 'pm_only']);

function toDateString(value) {
  if (value == null) return null;
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}/.test(value)) {
    return value.split('T')[0];
  }
  if (value instanceof Date) {
    const y = value.getFullYear();
    const m = String(value.getMonth() + 1).padStart(2, '0');
    const d = String(value.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }
  return String(value).split('T')[0];
}

function badRequest(message) {
  const err = new Error(message);
  err.statusCode = 400;
  return err;
}

function normalizeYear(value) {
  const year = Number(value);
  if (!Number.isInteger(year) || year < 2000 || year > 2100) {
    throw badRequest('A valid template year from 2000 to 2100 is required.');
  }
  return year;
}

function normalizeDate(value, field) {
  const text = toDateString(value);
  if (!text || !/^\d{4}-\d{2}-\d{2}$/.test(text)) {
    throw badRequest(`${field} must be a YYYY-MM-DD date.`);
  }
  return text;
}

function normalizeTemplatePayload(payload = {}) {
  const year = normalizeYear(payload.year);
  const rawItems = Array.isArray(payload.holidays) ? payload.holidays : [];
  if (rawItems.length === 0) {
    throw badRequest('At least one holiday row is required.');
  }

  const holidays = rawItems.map((raw, index) => {
    const name = String(raw.name || '').trim();
    if (!name) throw badRequest(`Holiday row ${index + 1} needs a name.`);

    const dateFrom = normalizeDate(raw.date_from ?? raw.dateFrom, `Holiday row ${index + 1} date_from`);
    const dateTo = normalizeDate(raw.date_to ?? raw.dateTo ?? dateFrom, `Holiday row ${index + 1} date_to`);
    if (dateTo < dateFrom) {
      throw badRequest(`Holiday row ${index + 1} date_to must be on or after date_from.`);
    }

    const holidayType = VALID_HOLIDAY_TYPES.has(raw.holiday_type)
      ? raw.holiday_type
      : VALID_HOLIDAY_TYPES.has(raw.holidayType)
        ? raw.holidayType
        : 'regular';
    const coverage = holidayType === 'work_suspension' && VALID_COVERAGE.has(raw.coverage)
      ? raw.coverage
      : 'whole_day';

    return {
      date_from: dateFrom,
      date_to: dateTo,
      name,
      holiday_type: holidayType,
      description: String(raw.description || '').trim() || null,
      is_active: raw.is_active === undefined ? true : !!raw.is_active,
      recurring: raw.recurring === undefined ? false : !!raw.recurring,
      coverage,
      sort_order: Number.isInteger(Number(raw.sort_order)) ? Number(raw.sort_order) : index,
    };
  });

  return {
    country: 'PH',
    year,
    label:
      String(payload.label || '').trim() ||
      `Philippines ${year} national holidays`,
    source:
      String(payload.source || '').trim() ||
      'Admin-maintained Philippine holiday template',
    note: String(payload.note || '').trim() || null,
    holidays,
  };
}

async function ensureHolidayTemplateTables(client = pool) {
  await client.query('CREATE EXTENSION IF NOT EXISTS "uuid-ossp"');
  await client.query(`
    CREATE TABLE IF NOT EXISTS holiday_default_templates (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      country_code TEXT NOT NULL DEFAULT 'PH',
      year INTEGER NOT NULL,
      label TEXT NOT NULL,
      source TEXT,
      note TEXT,
      is_active BOOLEAN NOT NULL DEFAULT true,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT uq_holiday_default_templates_country_year UNIQUE (country_code, year)
    )
  `);
  await client.query(`
    CREATE TABLE IF NOT EXISTS holiday_default_template_items (
      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
      template_id UUID NOT NULL REFERENCES holiday_default_templates(id) ON DELETE CASCADE,
      date_from DATE NOT NULL,
      date_to DATE NOT NULL,
      name TEXT NOT NULL,
      holiday_type TEXT NOT NULL DEFAULT 'regular'
        CHECK (holiday_type IN ('regular', 'special', 'local', 'work_suspension')),
      description TEXT,
      is_active BOOLEAN NOT NULL DEFAULT true,
      recurring BOOLEAN NOT NULL DEFAULT false,
      coverage TEXT NOT NULL DEFAULT 'whole_day'
        CHECK (coverage IN ('whole_day', 'am_only', 'pm_only')),
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_holiday_default_template_items_date_range CHECK (date_to >= date_from),
      CONSTRAINT uq_holiday_default_template_items_row UNIQUE (template_id, name, date_from, date_to)
    )
  `);
  await client.query(`
    CREATE INDEX IF NOT EXISTS idx_holiday_default_template_items_template
      ON holiday_default_template_items(template_id, sort_order, date_from)
  `);
}

function rowToHolidayItem(row) {
  return {
    date_from: toDateString(row.date_from),
    date_to: toDateString(row.date_to),
    name: row.name,
    holiday_type: row.holiday_type || 'regular',
    description: row.description,
    is_active: row.is_active ?? true,
    recurring: row.recurring ?? false,
    coverage: row.coverage || 'whole_day',
  };
}

async function readDbTemplate(year, client = pool) {
  await ensureHolidayTemplateTables(client);
  const template = await client.query(
    `SELECT id, country_code, year, label, source, note, is_active, created_at, updated_at
       FROM holiday_default_templates
      WHERE country_code = 'PH'
        AND year = $1
        AND is_active = true`,
    [year]
  );
  if (template.rowCount === 0) return null;

  const row = template.rows[0];
  const items = await client.query(
    `SELECT date_from, date_to, name, holiday_type, description, is_active, recurring, coverage
       FROM holiday_default_template_items
      WHERE template_id = $1
      ORDER BY sort_order, date_from, date_to, name`,
    [row.id]
  );

  return {
    year: row.year,
    country: row.country_code,
    label: row.label,
    source: row.source || 'Admin-maintained Philippine holiday template',
    note: row.note,
    source_mode: 'database',
    holidays: items.rows.map(rowToHolidayItem),
  };
}

async function getHolidayDefaultTemplateYears() {
  await ensureHolidayTemplateTables();
  const result = await pool.query(
    `SELECT year
       FROM holiday_default_templates
      WHERE country_code = 'PH'
        AND is_active = true
      ORDER BY year`
  );
  return Array.from(
    new Set([
      ...supportedBuiltInYears(),
      ...result.rows.map((row) => Number(row.year)),
    ])
  ).sort((a, b) => a - b);
}

async function getHolidayDefaultTemplate(year) {
  const numericYear = Number(year);
  if (!Number.isInteger(numericYear)) return null;

  const dbTemplate = await readDbTemplate(numericYear);
  const supportedYears = await getHolidayDefaultTemplateYears();
  if (dbTemplate) {
    return { ...dbTemplate, supported_years: supportedYears };
  }

  const builtIn = getPhilippineHolidayDefaults(numericYear);
  if (!builtIn) return null;
  return {
    ...builtIn,
    source_mode: 'built_in',
    supported_years: supportedYears,
  };
}

async function listHolidayDefaultTemplates() {
  await ensureHolidayTemplateTables();
  const result = await pool.query(
    `SELECT t.year, t.label, t.source, t.note, t.is_active, COUNT(i.id)::int AS item_count
       FROM holiday_default_templates t
       LEFT JOIN holiday_default_template_items i ON i.template_id = t.id
      WHERE t.country_code = 'PH'
      GROUP BY t.id
      ORDER BY t.year`
  );

  const dbYears = new Set(result.rows.map((row) => Number(row.year)));
  const builtIns = supportedBuiltInYears()
    .filter((year) => !dbYears.has(year))
    .map((year) => {
      const template = getPhilippineHolidayDefaults(year);
      return {
        year,
        label: template.label,
        source: template.source,
        note: template.note,
        is_active: true,
        item_count: template.holidays.length,
        source_mode: 'built_in',
      };
    });

  return [
    ...result.rows.map((row) => ({
      year: Number(row.year),
      label: row.label,
      source: row.source,
      note: row.note,
      is_active: row.is_active,
      item_count: row.item_count,
      source_mode: 'database',
    })),
    ...builtIns,
  ].sort((a, b) => a.year - b.year);
}

async function upsertHolidayDefaultTemplate(payload) {
  const template = normalizeTemplatePayload(payload);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await ensureHolidayTemplateTables(client);
    const upsert = await client.query(
      `INSERT INTO holiday_default_templates (country_code, year, label, source, note, is_active, updated_at)
       VALUES ('PH', $1, $2, $3, $4, true, NOW())
       ON CONFLICT (country_code, year)
       DO UPDATE SET
         label = EXCLUDED.label,
         source = EXCLUDED.source,
         note = EXCLUDED.note,
         is_active = true,
         updated_at = NOW()
       RETURNING id`,
      [template.year, template.label, template.source, template.note]
    );
    const templateId = upsert.rows[0].id;
    await client.query(
      'DELETE FROM holiday_default_template_items WHERE template_id = $1',
      [templateId]
    );

    for (const item of template.holidays) {
      await client.query(
        `INSERT INTO holiday_default_template_items
          (template_id, date_from, date_to, name, holiday_type, description, is_active, recurring, coverage, sort_order)
         VALUES ($1, $2::date, $3::date, $4, $5, $6, $7, $8, $9, $10)`,
        [
          templateId,
          item.date_from,
          item.date_to,
          item.name,
          item.holiday_type,
          item.description,
          item.is_active,
          item.recurring,
          item.coverage,
          item.sort_order,
        ]
      );
    }

    await client.query('COMMIT');
    return getHolidayDefaultTemplate(template.year);
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

async function deleteHolidayDefaultTemplate(year) {
  const numericYear = normalizeYear(year);
  await ensureHolidayTemplateTables();
  const result = await pool.query(
    `DELETE FROM holiday_default_templates
      WHERE country_code = 'PH'
        AND year = $1
      RETURNING id`,
    [numericYear]
  );
  return result.rowCount > 0;
}

module.exports = {
  deleteHolidayDefaultTemplate,
  ensureHolidayTemplateTables,
  getHolidayDefaultTemplate,
  getHolidayDefaultTemplateYears,
  listHolidayDefaultTemplates,
  normalizeTemplatePayload,
  upsertHolidayDefaultTemplate,
};
