class EmployeeAccountSecurityError extends Error {
  constructor(message, statusCode = 400, code = 'EMPLOYEE_ACCOUNT_SECURITY_ERROR') {
    super(message);
    this.name = 'EmployeeAccountSecurityError';
    this.statusCode = statusCode;
    this.code = code;
  }
}

const ADMIN_SAFETY_LOCK_KEY = 'hrms-active-administrator-safety';

function sameId(left, right) {
  return String(left || '').toLowerCase() === String(right || '').toLowerCase();
}

function accountState(row) {
  return {
    role: String(row?.role || 'employee').toLowerCase(),
    is_active: row?.is_active !== false,
    employment_status: String(row?.employment_status || 'active').toLowerCase(),
  };
}

async function acquireAdministratorSafetyLock(db) {
  await db.query('SELECT pg_advisory_xact_lock(hashtext($1))', [
    ADMIN_SAFETY_LOCK_KEY,
  ]);
}

async function lockAndValidateAccountTransition(
  db,
  { actorId, targetId, nextRole, nextIsActive, nextEmploymentStatus }
) {
  await acquireAdministratorSafetyLock(db);
  const targetResult = await db.query(
    `SELECT id, full_name, email, role, is_active, employment_status
       FROM users
      WHERE id = $1::uuid
      FOR UPDATE`,
    [targetId]
  );
  if (targetResult.rowCount === 0) {
    throw new EmployeeAccountSecurityError(
      'Employee not found',
      404,
      'EMPLOYEE_NOT_FOUND'
    );
  }

  const target = targetResult.rows[0];
  const previous = accountState(target);
  const next = {
    role:
      nextRole === undefined || nextRole === null
        ? previous.role
        : String(nextRole).toLowerCase(),
    is_active:
      nextIsActive === undefined || nextIsActive === null
        ? previous.is_active
        : nextIsActive === true,
    employment_status:
      nextEmploymentStatus === undefined || nextEmploymentStatus === null
        ? previous.employment_status
        : String(nextEmploymentStatus).toLowerCase(),
  };

  if (sameId(actorId, targetId) && !next.is_active) {
    throw new EmployeeAccountSecurityError(
      'You cannot deactivate your own administrator account',
      400,
      'SELF_DEACTIVATION_BLOCKED'
    );
  }
  if (
    sameId(actorId, targetId) &&
    previous.role === 'admin' &&
    next.role !== 'admin'
  ) {
    throw new EmployeeAccountSecurityError(
      'You cannot remove your own administrator role',
      400,
      'SELF_DEMOTION_BLOCKED'
    );
  }

  const removesActiveAdministrator =
    previous.role === 'admin' &&
    previous.is_active &&
    (next.role !== 'admin' || !next.is_active);
  if (removesActiveAdministrator) {
    const remainingResult = await db.query(
      `SELECT COUNT(*)::int AS count
         FROM users
        WHERE role = 'admin'
          AND is_active = true
          AND id <> $1::uuid`,
      [targetId]
    );
    if (Number(remainingResult.rows[0]?.count || 0) === 0) {
      throw new EmployeeAccountSecurityError(
        'The last active administrator cannot be deactivated or demoted',
        409,
        'LAST_ACTIVE_ADMIN_BLOCKED'
      );
    }
  }

  return {
    target,
    previous,
    next,
    changed:
      previous.role !== next.role ||
      previous.is_active !== next.is_active ||
      previous.employment_status !== next.employment_status,
    revokeSessions:
      !next.is_active ||
      previous.role !== next.role ||
      previous.employment_status !== next.employment_status,
  };
}

async function lockAndValidateBulkAccountStatusTransition(
  db,
  { actorId, targetIds, isActive }
) {
  const plan = await lockAndPlanBulkAccountStatusTransition(db, {
    actorId,
    targetIds,
    isActive,
  });
  const rejected = plan.results.find((result) => result.outcome === 'rejected');
  if (rejected) {
    throw new EmployeeAccountSecurityError(
      rejected.reason,
      rejected.statusCode,
      rejected.code
    );
  }
  return plan.targets;
}

async function lockAndPlanBulkAccountStatusTransition(
  db,
  { actorId, targetIds, isActive }
) {
  await acquireAdministratorSafetyLock(db);
  const targetResult = await db.query(
    `SELECT id, full_name, email, role, is_active, employment_status
       FROM users
      WHERE id = ANY($1::uuid[])
      FOR UPDATE`,
    [targetIds]
  );
  const targets = targetResult.rows;
  const targetById = new Map(
    targets.map((target) => [String(target.id).toLowerCase(), target])
  );
  const results = [];
  const updateTargets = [];
  const candidateAdministrators = [];

  for (const requestedId of targetIds) {
    const target = targetById.get(String(requestedId).toLowerCase());
    if (!target) {
      results.push({
        employee_id: requestedId,
        outcome: 'not_found',
        code: 'EMPLOYEE_NOT_FOUND',
        reason: 'Employee not found',
        statusCode: 404,
      });
      continue;
    }

    const resultBase = {
      employee_id: target.id,
      employee_name: target.full_name || target.email || 'Employee',
    };
    const employmentStatus = String(
      target.employment_status || 'active'
    ).toLowerCase();

    if (isActive && employmentStatus !== 'active') {
      results.push({
        ...resultBase,
        outcome: 'rejected',
        code: 'EMPLOYMENT_STATUS_NOT_ACTIVE',
        reason: `Employment status is ${employmentStatus}; complete the rehire or reactivation workflow first`,
        statusCode: 409,
      });
      continue;
    }
    if (target.is_active === isActive) {
      results.push({
        ...resultBase,
        outcome: 'skipped',
        code: 'ACCOUNT_ALREADY_IN_REQUESTED_STATE',
        reason: `Account is already ${isActive ? 'active' : 'inactive'}`,
        statusCode: 200,
      });
      continue;
    }
    if (!isActive && sameId(target.id, actorId)) {
      results.push({
        ...resultBase,
        outcome: 'rejected',
        code: 'SELF_DEACTIVATION_BLOCKED',
        reason: 'You cannot deactivate your own administrator account',
        statusCode: 400,
      });
      continue;
    }

    if (!isActive && target.role === 'admin') {
      candidateAdministrators.push(target);
      continue;
    }

    updateTargets.push(target);
    results.push({
      ...resultBase,
      outcome: 'updated',
      code: isActive ? 'ACCOUNT_ACTIVATED' : 'ACCOUNT_DEACTIVATED',
      reason: isActive ? 'Account activated' : 'Account deactivated',
      statusCode: 200,
    });
  }

  if (candidateAdministrators.length > 0) {
    const candidateIds = candidateAdministrators.map((target) => target.id);
    const remainingResult = await db.query(
      `SELECT COUNT(*)::int AS count
         FROM users
        WHERE role = 'admin'
          AND is_active = true
          AND NOT (id = ANY($1::uuid[]))`,
      [candidateIds]
    );
    const canDeactivateAdministrators =
      Number(remainingResult.rows[0]?.count || 0) > 0;
    for (const target of candidateAdministrators) {
      const resultBase = {
        employee_id: target.id,
        employee_name: target.full_name || target.email || 'Administrator',
      };
      if (!canDeactivateAdministrators) {
        results.push({
          ...resultBase,
          outcome: 'rejected',
          code: 'LAST_ACTIVE_ADMIN_BLOCKED',
          reason: 'The last active administrator cannot be deactivated',
          statusCode: 409,
        });
        continue;
      }
      updateTargets.push(target);
      results.push({
        ...resultBase,
        outcome: 'updated',
        code: 'ACCOUNT_DEACTIVATED',
        reason: 'Account deactivated',
        statusCode: 200,
      });
    }
  }

  return { targets, updateTargets, results };
}

async function revokeActiveRefreshTokens(db, userIds) {
  const ids = [...new Set((Array.isArray(userIds) ? userIds : [userIds]).filter(Boolean))];
  if (ids.length === 0) return 0;
  const result = await db.query(
    `UPDATE auth_refresh_tokens
        SET revoked_at = now()
      WHERE user_id = ANY($1::uuid[])
        AND revoked_at IS NULL`,
    [ids]
  );
  return result.rowCount;
}

async function writeAccountSecurityAudit(
  db,
  { actorId, targetId, action, previous, next, source }
) {
  await db.query(
    `INSERT INTO audit_logs (
       user_id, action, entity_type, entity_id, details
     ) VALUES ($1::uuid, $2, 'employee_account', $3::uuid, $4)`,
    [
      actorId,
      action,
      targetId,
      JSON.stringify({ previous, next, source }),
    ]
  );
}

module.exports = {
  EmployeeAccountSecurityError,
  lockAndValidateAccountTransition,
  lockAndValidateBulkAccountStatusTransition,
  lockAndPlanBulkAccountStatusTransition,
  revokeActiveRefreshTokens,
  writeAccountSecurityAudit,
};
