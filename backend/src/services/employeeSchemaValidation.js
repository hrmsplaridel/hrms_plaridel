const REQUIRED_EMPLOYEE_COLUMNS = Object.freeze([
  'first_name',
  'last_name',
  'middle_name',
  'suffix',
  'sex',
  'civil_status',
  'nationality',
  'date_of_birth',
  'contact_number',
  'address',
  'leave_credit_eligible',
  'leave_credit_eligible_until',
  'updated_at',
]);

const REQUIRED_EMPLOYEE_INDEXES = Object.freeze([
  'idx_users_leave_credit_eligible',
]);

const EMPLOYEE_SCHEMA_SOURCE = 'backend/scripts/init-schema.sql';

class EmployeeSchemaValidationError extends Error {
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
      `Employee database schema is outdated (${missing}). Align the database with ${EMPLOYEE_SCHEMA_SOURCE}.`
    );
    this.name = 'EmployeeSchemaValidationError';
    this.code = 'EMPLOYEE_SCHEMA_OUTDATED';
    this.missingColumns = missingColumns;
    this.missingIndexes = missingIndexes;
  }
}

async function validateEmployeeSchema(db) {
  const [columnResult, indexResult] = await Promise.all([
    db.query(
      `SELECT column_name
         FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'users'
          AND column_name = ANY($1::text[])`,
      [REQUIRED_EMPLOYEE_COLUMNS]
    ),
    db.query(
      `SELECT indexname
         FROM pg_indexes
        WHERE schemaname = 'public'
          AND tablename = 'users'
          AND indexname = ANY($1::text[])`,
      [REQUIRED_EMPLOYEE_INDEXES]
    ),
  ]);

  const existingColumns = new Set(
    columnResult.rows.map((row) => row.column_name)
  );
  const existingIndexes = new Set(
    indexResult.rows.map((row) => row.indexname)
  );
  const missingColumns = REQUIRED_EMPLOYEE_COLUMNS.filter(
    (column) => !existingColumns.has(column)
  );
  const missingIndexes = REQUIRED_EMPLOYEE_INDEXES.filter(
    (index) => !existingIndexes.has(index)
  );

  if (missingColumns.length > 0 || missingIndexes.length > 0) {
    throw new EmployeeSchemaValidationError({
      missingColumns,
      missingIndexes,
    });
  }

  return {
    columns: REQUIRED_EMPLOYEE_COLUMNS.length,
    indexes: REQUIRED_EMPLOYEE_INDEXES.length,
  };
}

module.exports = {
  EMPLOYEE_SCHEMA_SOURCE,
  EmployeeSchemaValidationError,
  REQUIRED_EMPLOYEE_COLUMNS,
  REQUIRED_EMPLOYEE_INDEXES,
  validateEmployeeSchema,
};
