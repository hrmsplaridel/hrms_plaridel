const { pool } = require('../config/db');
const { broadcastAppEvent } = require('../websockets/appEvents');

const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/**
 * Shared load/update helpers for non-DTR module access tables
 * (RSP / L&D). DTR keeps its own middleware and routes untouched.
 */
function createModuleAccessService({
  tableName,
  fields,
  auditAction,
  conflictCode,
  label,
}) {
  const falseDefaults = Object.fromEntries(fields.map((f) => [f, false]));
  let ensurePromise;

  async function ensureSchema(db = pool) {
    if (!ensurePromise) {
      ensurePromise = (async () => {
        await db.query(
          `CREATE TABLE IF NOT EXISTS ${tableName} (
             admin_user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
             ${fields.map((field) => `${field} BOOLEAN NOT NULL DEFAULT false`).join(',\n             ')},
             updated_by UUID REFERENCES users(id),
             updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
           )`
        );
        for (const field of fields) {
          await db.query(
            `ALTER TABLE ${tableName}
               ADD COLUMN IF NOT EXISTS ${field} BOOLEAN NOT NULL DEFAULT false`
          );
        }
        // Existing-admin preservation and legacy backfills belong to the
        // explicit rollout migrations. Reads must not grant or restore access.
      })().catch((error) => {
        ensurePromise = undefined;
        throw error;
      });
    }
    await ensurePromise;
  }

  async function loadAccess(userId, db = pool) {
    await ensureSchema(db);
    const selects = fields
      .map(
        (field) =>
          `COALESCE((SELECT ${field} FROM ${tableName} WHERE admin_user_id = $1::uuid), false) AS ${field}`
      )
      .join(',\n            ');
    const result = await db.query(
      `SELECT ${selects}`,
      [userId]
    );
    return result.rows[0] || { ...falseDefaults };
  }

  function anyAllowed(access) {
    return fields.some((field) => access?.[field] === true);
  }

  async function listAdmins(db = pool) {
    await ensureSchema(db);
    const result = await db.query(
      `SELECT u.id, u.full_name, u.email, u.is_active,
              COALESCE(a.updated_at::text, 'none') AS revision,
              ${fields
                .map((field) => `COALESCE(a.${field}, false) AS ${field}`)
                .join(', ')}
         FROM users u
         LEFT JOIN ${tableName} a ON a.admin_user_id = u.id
        WHERE u.role = 'admin'
        ORDER BY u.is_active DESC, u.full_name NULLS LAST, u.email`
    );
    return result.rows;
  }

  async function updateAccess({
    adminId,
    body,
    actorUserId,
    dbConnect = () => pool.connect(),
  }) {
    if (!uuid.test(adminId)) {
      return { status: 400, body: { error: `Valid admin ID and ${label} permissions are required` } };
    }
    const expectedRevision = body?.expected_revision;
    if (typeof expectedRevision !== 'string' || !expectedRevision || expectedRevision.length > 100) {
      return { status: 400, body: { error: 'Refresh Manage Access before saving permissions.' } };
    }

    for (const field of fields) {
      if (typeof body?.[field] !== 'boolean') {
        return { status: 400, body: { error: `Valid admin ID and ${label} permissions are required` } };
      }
    }

    let client;
    let releaseError;
    try {
      await ensureSchema();
      client = await dbConnect();
      await client.query('BEGIN');
      const target = await client.query(
        'SELECT role FROM users WHERE id = $1::uuid FOR UPDATE',
        [adminId]
      );
      if (target.rows[0]?.role !== 'admin') {
        await client.query('ROLLBACK');
        return { status: 404, body: { error: 'Administrator not found' } };
      }

      const previous = await client.query(
        `SELECT ${fields.join(', ')}, updated_at::text AS revision
           FROM ${tableName} WHERE admin_user_id = $1::uuid`,
        [adminId]
      );
      if (expectedRevision !== (previous.rows[0]?.revision ?? 'none')) {
        await client.query('ROLLBACK');
        return {
          status: 409,
          body: {
            code: conflictCode,
            error:
              'Permissions have changed since you opened this page. Refresh and review them before saving.',
          },
        };
      }

      const before = {
        ...falseDefaults,
        ...previous.rows[0],
      };
      delete before.revision;

      const after = {};
      for (const field of fields) {
        after[field] = body[field];
      }

      const updated = await client.query(
        `INSERT INTO ${tableName} (admin_user_id, ${fields.join(', ')}, updated_by)
         VALUES ($1::uuid, ${fields.map((_, i) => `$${i + 2}`).join(', ')}, $${fields.length + 2}::uuid)
         ON CONFLICT (admin_user_id) DO UPDATE SET
           ${fields.map((field) => `${field} = EXCLUDED.${field}`).join(',\n           ')},
           updated_by = EXCLUDED.updated_by,
           updated_at = GREATEST(clock_timestamp(), ${tableName}.updated_at + interval '1 microsecond')
         RETURNING updated_at::text AS revision`,
        [adminId, ...fields.map((field) => after[field]), actorUserId]
      );

      if (fields.some((field) => before[field] !== after[field])) {
        await client.query(
          `INSERT INTO audit_logs (user_id, action, entity_type, entity_id, details)
           VALUES ($1::uuid, $2, 'user', $3::uuid, $4)`,
          [actorUserId, auditAction, adminId, JSON.stringify({ before, after })]
        );
      }

      await client.query('COMMIT');
      try {
        broadcastAppEvent('admin_access_changed', {}, { userIds: [adminId] });
      } catch (error) {
        console.error('[admin access] live update failed', error);
      }
      return {
        status: 200,
        body: { admin_id: adminId, ...after, revision: updated.rows[0].revision },
      };
    } catch (error) {
      if (client) {
        try {
          await client.query('ROLLBACK');
        } catch (rollbackError) {
          releaseError = rollbackError;
          console.error(`[${label} access PUT rollback]`, rollbackError);
        }
      }
      console.error(`[${label} access PUT]`, error);
      return {
        status: client ? 500 : 503,
        body: {
          error: client
            ? `Failed to update ${label} access`
            : 'Database temporarily unavailable. Please try again.',
        },
      };
    } finally {
      if (client) client.release(releaseError);
    }
  }

  return { fields, falseDefaults, loadAccess, anyAllowed, listAdmins, updateAccess };
}

const RSP_RECRUITMENT_FIELDS = [
  'applications_allowed',
  'exam_results_allowed',
  'scheduling_allowed',
  'final_requirements_allowed',
];

const RSP_FORM_FIELDS = [
  'form_bi_allowed',
  'form_applicants_profile_allowed',
  'form_selection_lineup_allowed',
  'form_computation_of_points_allowed',
  'form_work_experience_allowed',
  'form_turn_around_time_allowed',
  'form_ojt_allowed',
];

const LD_FORM_FIELDS = [
  'form_tna_allowed',
  'form_action_brainstorming_allowed',
  'form_idp_allowed',
  'form_lap_allowed',
];

const rspAdminAccess = createModuleAccessService({
  tableName: 'rsp_admin_access',
  fields: [
    'vacancies_allowed',
    'recruitment_allowed',
    'exams_allowed',
    'forms_allowed',
    ...RSP_RECRUITMENT_FIELDS,
    ...RSP_FORM_FIELDS,
  ],
  auditAction: 'rsp_admin_access_changed',
  conflictCode: 'RSP_ACCESS_CONFLICT',
  label: 'RSP',
});

const ldAdminAccess = createModuleAccessService({
  tableName: 'ld_admin_access',
  fields: [
    'forms_allowed',
    'daily_reports_allowed',
    'requirements_allowed',
    ...LD_FORM_FIELDS,
  ],
  auditAction: 'ld_admin_access_changed',
  conflictCode: 'LD_ACCESS_CONFLICT',
  label: 'L&D',
});

module.exports = {
  createModuleAccessService,
  rspAdminAccess,
  ldAdminAccess,
  RSP_RECRUITMENT_FIELDS,
  RSP_FORM_FIELDS,
  LD_FORM_FIELDS,
};
