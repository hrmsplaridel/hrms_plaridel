'use strict';

class DepartmentLifecycleError extends Error {
  constructor(message, statusCode = 400, blockers = null) {
    super(message);
    this.name = 'DepartmentLifecycleError';
    this.statusCode = statusCode;
    this.blockers = blockers;
  }
}

const DEPARTMENT_DEPENDENCIES = Object.freeze([
  { key: 'positions', label: 'positions', table: 'positions', column: 'department_id' },
  { key: 'assignments', label: 'employee assignments', table: 'assignments', column: 'department_id' },
  { key: 'additional_positions', label: 'additional positions', table: 'employee_other_positions', column: 'department_id' },
  { key: 'policy_assignments', label: 'attendance policies', table: 'policy_assignments', column: 'department_id' },
  { key: 'leave_requests', label: 'leave requests', table: 'leave_requests', column: 'review_department_id' },
  { key: 'locator_slips', label: 'locator requests', table: 'locator_slips', column: 'department_id' },
  { key: 'workflow_steps', label: 'DocuTracker workflow steps', table: 'docutracker_workflow_steps', column: 'department_id' },
  { key: 'reviewer_backups', label: 'department reviewer backups', table: 'department_reviewer_backups', column: 'department_id' },
  { key: 'escalation_configs', label: 'DocuTracker escalation rules', table: 'docutracker_escalation_configs', column: 'department_id' },
]);

const DEPARTMENT_DEACTIVATION_DEPENDENCIES = Object.freeze([
  {
    key: 'primary_assignments',
    label: 'current or future primary assignments',
    countSql: (departmentPlaceholder, datePlaceholder) => `
      SELECT COUNT(*)::int
        FROM assignments a
       WHERE a.department_id = ${departmentPlaceholder}::uuid
         AND COALESCE(a.is_active, true) = true
         AND (a.effective_to IS NULL OR a.effective_to >= ${datePlaceholder}::date)`,
  },
  {
    key: 'additional_positions',
    label: 'current or future additional positions',
    countSql: (departmentPlaceholder, datePlaceholder) => `
      SELECT COUNT(*)::int
        FROM employee_other_positions eop
       WHERE eop.department_id = ${departmentPlaceholder}::uuid
         AND COALESCE(eop.is_active, true) = true
         AND (eop.effective_to IS NULL OR eop.effective_to >= ${datePlaceholder}::date)`,
  },
  {
    key: 'active_positions',
    label: 'active positions',
    countSql: (departmentPlaceholder) => `
      SELECT COUNT(*)::int
        FROM positions p
       WHERE p.department_id = ${departmentPlaceholder}::uuid
         AND COALESCE(p.is_active, true) = true`,
  },
  {
    key: 'policy_assignments',
    label: 'current or future attendance policies',
    countSql: (departmentPlaceholder, datePlaceholder) => `
      SELECT COUNT(*)::int
        FROM policy_assignments pa
       WHERE pa.department_id = ${departmentPlaceholder}::uuid
         AND COALESCE(pa.is_active, true) = true
         AND (pa.effective_to IS NULL OR pa.effective_to >= ${datePlaceholder}::date)`,
  },
  {
    key: 'pending_leave_requests',
    label: 'unresolved leave requests',
    countSql: (departmentPlaceholder) => `
      SELECT COUNT(*)::int
        FROM leave_requests lr
       WHERE lr.review_department_id = ${departmentPlaceholder}::uuid
         AND lr.status IN ('pending', 'pending_department_head', 'pending_hr', 'returned')`,
  },
  {
    key: 'pending_locator_requests',
    label: 'unresolved locator requests',
    countSql: (departmentPlaceholder) => `
      SELECT COUNT(*)::int
        FROM locator_slips ls
       WHERE ls.department_id = ${departmentPlaceholder}::uuid
         AND ls.status IN (
           'pending', 'pending_department_head', 'pending_hr',
           'returned_for_correction'
         )`,
  },
  {
    key: 'reviewer_backups',
    label: 'current or future department reviewer backups',
    countSql: (departmentPlaceholder, datePlaceholder) => `
      SELECT COUNT(*)::int
        FROM department_reviewer_backups drb
       WHERE drb.department_id = ${departmentPlaceholder}::uuid
         AND drb.is_active = true
         AND (drb.effective_to IS NULL OR drb.effective_to >= ${datePlaceholder}::date)`,
  },
  {
    key: 'workflow_steps',
    label: 'enabled DocuTracker workflow steps',
    countSql: (departmentPlaceholder) => `
      SELECT COUNT(*)::int
        FROM docutracker_workflow_steps ws
       WHERE ws.department_id = ${departmentPlaceholder}::uuid
         AND ws.enabled = true
         AND (
           ws.workflow_version = (
             SELECT MAX(v.version)
               FROM docutracker_routing_config_versions v
              WHERE v.document_type = ws.document_type
           )
           OR EXISTS (
             SELECT 1
               FROM docutracker_documents dd
              WHERE dd.document_type = ws.document_type
                AND dd.workflow_version = ws.workflow_version
                AND dd.status IN ('pending', 'in_review', 'returned', 'overdue', 'escalated')
           )
         )`,
  },
  {
    key: 'escalation_configs',
    label: 'DocuTracker escalation rules',
    countSql: (departmentPlaceholder) => `
      SELECT COUNT(*)::int
        FROM docutracker_escalation_configs dec
       WHERE dec.department_id = ${departmentPlaceholder}::uuid`,
  },
]);

function cleanReason(value) {
  const reason = String(value || '').trim();
  if (!reason) {
    throw new DepartmentLifecycleError(
      'A reason is required to delete a mistaken department'
    );
  }
  if (reason.length > 1000) {
    throw new DepartmentLifecycleError(
      'Department deletion reason must not exceed 1000 characters'
    );
  }
  return reason;
}

function departmentDependencyCountsSql(departmentAlias = 'd') {
  return DEPARTMENT_DEPENDENCIES.map(
    ({ key, table, column }) =>
      `(SELECT COUNT(*)::int FROM ${table} WHERE ${column} = ${departmentAlias}.id) AS dependency_${key}`
  ).join(',\n       ');
}

function dependencyCountsFromRow(row = {}) {
  return Object.fromEntries(
    DEPARTMENT_DEPENDENCIES.map(({ key }) => [
      key,
      Number(row[`dependency_${key}`] || 0),
    ])
  );
}

function dependencyBlockers(counts = {}) {
  return DEPARTMENT_DEPENDENCIES
    .map(({ key, label }) => ({ key, label, count: Number(counts[key] || 0) }))
    .filter((item) => item.count > 0);
}

function dependencyMessage(blockers) {
  const details = blockers
    .map((item) => `${item.count} ${item.label}`)
    .join(', ');
  return `Department cannot be permanently deleted because it is used by ${details}`;
}

function departmentDeactivationCountsSql(
  departmentPlaceholder = '$1',
  datePlaceholder = '$2'
) {
  return DEPARTMENT_DEACTIVATION_DEPENDENCIES.map(
    ({ key, countSql }) =>
      `(${countSql(departmentPlaceholder, datePlaceholder)}) AS deactivation_${key}`
  ).join(',\n       ');
}

function deactivationCountsFromRow(row = {}) {
  return Object.fromEntries(
    DEPARTMENT_DEACTIVATION_DEPENDENCIES.map(({ key }) => [
      key,
      Number(row[`deactivation_${key}`] || 0),
    ])
  );
}

function deactivationBlockers(counts = {}) {
  return DEPARTMENT_DEACTIVATION_DEPENDENCIES
    .map(({ key, label }) => ({ key, label, count: Number(counts[key] || 0) }))
    .filter((item) => item.count > 0);
}

function deactivationMessage(blockers) {
  const details = blockers
    .map((item) => `${item.count} ${item.label}`)
    .join(', ');
  return `Department cannot be deactivated until these active dependencies are resolved: ${details}`;
}

async function loadDepartmentDeactivationCounts(
  db,
  departmentId,
  officialDate
) {
  const result = await db.query(
    `SELECT ${departmentDeactivationCountsSql('$1', '$2')}`,
    [departmentId, officialDate]
  );
  return deactivationCountsFromRow(result.rows[0]);
}

async function previewDepartmentDeactivation(
  db,
  { departmentId, officialDate }
) {
  const existing = await db.query(
    `SELECT id, department_number, name, description, is_active
       FROM departments
      WHERE id = $1::uuid`,
    [departmentId]
  );
  if (existing.rowCount === 0) {
    throw new DepartmentLifecycleError('Department not found', 404);
  }

  const department = existing.rows[0];
  if (department.is_active === false) {
    return { department, blockers: [], canDeactivate: true };
  }

  const counts = await loadDepartmentDeactivationCounts(
    db,
    departmentId,
    officialDate
  );
  const blockers = deactivationBlockers(counts);
  return {
    department,
    blockers,
    canDeactivate: blockers.length === 0,
  };
}

async function ensureDepartmentCanDeactivate(
  db,
  { departmentId, officialDate }
) {
  const existing = await db.query(
    `SELECT id, department_number, name, description, is_active
       FROM departments
      WHERE id = $1::uuid
      FOR UPDATE`,
    [departmentId]
  );
  if (existing.rowCount === 0) {
    throw new DepartmentLifecycleError('Department not found', 404);
  }

  const department = existing.rows[0];
  if (department.is_active === false) {
    return { department, blockers: [] };
  }

  const counts = await loadDepartmentDeactivationCounts(
    db,
    departmentId,
    officialDate
  );
  const blockers = deactivationBlockers(counts);
  if (blockers.length > 0) {
    throw new DepartmentLifecycleError(
      deactivationMessage(blockers),
      409,
      blockers
    );
  }

  return { department, blockers: [] };
}

async function loadDepartmentDependencyCounts(db, departmentId) {
  const result = await db.query(
    `SELECT ${DEPARTMENT_DEPENDENCIES.map(
      ({ key, table, column }) =>
        `(SELECT COUNT(*)::int FROM ${table} WHERE ${column} = $1::uuid) AS dependency_${key}`
    ).join(',\n            ')}`,
    [departmentId]
  );
  return dependencyCountsFromRow(result.rows[0]);
}

async function deleteMistakenDepartment(
  db,
  { actorId, departmentId, reason }
) {
  const normalizedReason = cleanReason(reason);
  const existing = await db.query(
    `SELECT id, department_number, name, description, is_active,
            created_at, updated_at
       FROM departments
      WHERE id = $1::uuid
      FOR UPDATE`,
    [departmentId]
  );
  if (existing.rowCount === 0) {
    throw new DepartmentLifecycleError('Department not found', 404);
  }

  const department = existing.rows[0];
  const counts = await loadDepartmentDependencyCounts(db, departmentId);
  const blockers = dependencyBlockers(counts);
  if (blockers.length > 0) {
    throw new DepartmentLifecycleError(
      dependencyMessage(blockers),
      409,
      blockers
    );
  }

  await db.query('DELETE FROM departments WHERE id = $1::uuid', [departmentId]);
  await db.query(
    `INSERT INTO audit_logs (
       user_id, action, entity_type, entity_id, details
     ) VALUES ($1::uuid, 'department_mistake_deleted', 'department', $2::uuid, $3)`,
    [
      actorId || null,
      departmentId,
      JSON.stringify({ reason: normalizedReason, before: department }),
    ]
  );

  return { department, reason: normalizedReason };
}

module.exports = {
  DEPARTMENT_DEACTIVATION_DEPENDENCIES,
  DEPARTMENT_DEPENDENCIES,
  DepartmentLifecycleError,
  cleanReason,
  deactivationBlockers,
  deactivationCountsFromRow,
  deleteMistakenDepartment,
  departmentDeactivationCountsSql,
  departmentDependencyCountsSql,
  dependencyBlockers,
  dependencyCountsFromRow,
  ensureDepartmentCanDeactivate,
  loadDepartmentDeactivationCounts,
  loadDepartmentDependencyCounts,
  previewDepartmentDeactivation,
};
