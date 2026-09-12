const REQUIRED_ADDITIONAL_POSITION_COLUMNS = Object.freeze([
  'id',
  'employee_id',
  'department_id',
  'position_id',
  'effective_from',
  'effective_to',
  'is_active',
  'remarks',
  'created_by',
  'created_at',
  'updated_at',
]);

const REQUIRED_ADDITIONAL_POSITION_INDEXES = Object.freeze([
  'idx_employee_other_positions_employee',
  'idx_employee_other_positions_position',
]);

const ASSIGNMENT_SCHEMA_SOURCE = 'backend/scripts/init-schema.sql';

class AssignmentSchemaValidationError extends Error {
  constructor({ missingColumns = [], missingIndexes = [] } = {}) {
    const missing = [
      ...(missingColumns.length > 0
        ? [`columns: ${missingColumns.join(', ')}`]
        : []),
      ...(missingIndexes.length > 0
        ? [`indexes: ${missingIndexes.join(', ')}`]
        : []),
    ].join('; ');
    super(
      `Assignment database schema is outdated (${missing}). Align the database with ${ASSIGNMENT_SCHEMA_SOURCE}.`
    );
    this.name = 'AssignmentSchemaValidationError';
    this.code = 'ASSIGNMENT_SCHEMA_OUTDATED';
    this.missingColumns = missingColumns;
    this.missingIndexes = missingIndexes;
  }
}

async function validateAssignmentSchema(db) {
  const [columnResult, indexResult] = await Promise.all([
    db.query(
      `SELECT column_name
         FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'employee_other_positions'
          AND column_name = ANY($1::text[])`,
      [REQUIRED_ADDITIONAL_POSITION_COLUMNS]
    ),
    db.query(
      `SELECT indexname
         FROM pg_indexes
        WHERE schemaname = 'public'
          AND tablename = 'employee_other_positions'
          AND indexname = ANY($1::text[])`,
      [REQUIRED_ADDITIONAL_POSITION_INDEXES]
    ),
  ]);

  const existingColumns = new Set(
    columnResult.rows.map((row) => row.column_name)
  );
  const existingIndexes = new Set(
    indexResult.rows.map((row) => row.indexname)
  );
  const missingColumns = REQUIRED_ADDITIONAL_POSITION_COLUMNS.filter(
    (column) => !existingColumns.has(column)
  );
  const missingIndexes = REQUIRED_ADDITIONAL_POSITION_INDEXES.filter(
    (index) => !existingIndexes.has(index)
  );

  if (missingColumns.length > 0 || missingIndexes.length > 0) {
    throw new AssignmentSchemaValidationError({ missingColumns, missingIndexes });
  }

  return {
    columns: REQUIRED_ADDITIONAL_POSITION_COLUMNS.length,
    indexes: REQUIRED_ADDITIONAL_POSITION_INDEXES.length,
  };
}

module.exports = {
  ASSIGNMENT_SCHEMA_SOURCE,
  AssignmentSchemaValidationError,
  REQUIRED_ADDITIONAL_POSITION_COLUMNS,
  REQUIRED_ADDITIONAL_POSITION_INDEXES,
  validateAssignmentSchema,
};
