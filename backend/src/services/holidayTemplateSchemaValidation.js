'use strict';

const REQUIRED_HOLIDAY_TEMPLATE_COLUMNS = Object.freeze({
  holiday_default_templates: Object.freeze([
    'id',
    'country_code',
    'year',
    'label',
    'source',
    'note',
    'is_active',
    'created_at',
    'updated_at',
  ]),
  holiday_default_template_items: Object.freeze([
    'id',
    'template_id',
    'date_from',
    'date_to',
    'name',
    'holiday_type',
    'description',
    'is_active',
    'recurring',
    'coverage',
    'sort_order',
    'created_at',
    'updated_at',
  ]),
});

const REQUIRED_HOLIDAY_TEMPLATE_INDEXES = Object.freeze([
  'idx_holiday_default_template_items_template',
]);

const HOLIDAY_TEMPLATE_SCHEMA_SOURCE =
  'backend/scripts/init-schema.sql or backend/scripts/migrate-holiday-default-templates.sql';

class HolidayTemplateSchemaValidationError extends Error {
  constructor({ missingColumns = [], missingIndexes = [] } = {}) {
    const missing = [
      ...(missingColumns.length > 0 ? [`columns: ${missingColumns.join(', ')}`] : []),
      ...(missingIndexes.length > 0 ? [`indexes: ${missingIndexes.join(', ')}`] : []),
    ].join('; ');
    super(
      `Holiday template database schema is outdated (${missing}). Align the database with ${HOLIDAY_TEMPLATE_SCHEMA_SOURCE}.`
    );
    this.name = 'HolidayTemplateSchemaValidationError';
    this.code = 'HOLIDAY_TEMPLATE_SCHEMA_OUTDATED';
    this.missingColumns = missingColumns;
    this.missingIndexes = missingIndexes;
  }
}

async function validateHolidayTemplateSchema(db) {
  const tableNames = Object.keys(REQUIRED_HOLIDAY_TEMPLATE_COLUMNS);
  const [columnResult, indexResult] = await Promise.all([
    db.query(
      `SELECT table_name, column_name
         FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = ANY($1::text[])`,
      [tableNames]
    ),
    db.query(
      `SELECT indexname
         FROM pg_indexes
        WHERE schemaname = 'public'
          AND indexname = ANY($1::text[])`,
      [REQUIRED_HOLIDAY_TEMPLATE_INDEXES]
    ),
  ]);

  const existingColumns = new Set(
    columnResult.rows.map((row) => `${row.table_name}.${row.column_name}`)
  );
  const missingColumns = Object.entries(REQUIRED_HOLIDAY_TEMPLATE_COLUMNS)
    .flatMap(([table, columns]) => columns.map((column) => `${table}.${column}`))
    .filter((column) => !existingColumns.has(column));
  const existingIndexes = new Set(indexResult.rows.map((row) => row.indexname));
  const missingIndexes = REQUIRED_HOLIDAY_TEMPLATE_INDEXES.filter(
    (index) => !existingIndexes.has(index)
  );

  if (missingColumns.length > 0 || missingIndexes.length > 0) {
    throw new HolidayTemplateSchemaValidationError({ missingColumns, missingIndexes });
  }

  return {
    columns: Object.values(REQUIRED_HOLIDAY_TEMPLATE_COLUMNS)
      .reduce((total, columns) => total + columns.length, 0),
    indexes: REQUIRED_HOLIDAY_TEMPLATE_INDEXES.length,
  };
}

module.exports = {
  HOLIDAY_TEMPLATE_SCHEMA_SOURCE,
  HolidayTemplateSchemaValidationError,
  REQUIRED_HOLIDAY_TEMPLATE_COLUMNS,
  REQUIRED_HOLIDAY_TEMPLATE_INDEXES,
  validateHolidayTemplateSchema,
};
