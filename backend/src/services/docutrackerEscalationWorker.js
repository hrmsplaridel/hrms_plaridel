const { pool } = require('../config/db');

let timer = null;
let running = false;
const ESCALATION_LOCK_KEY = 907531;

function normalizeRole(role) {
  const r = String(role ?? '').trim().toLowerCase();
  if (!r) return '';
  if (r === 'hr_staff') return 'hr';
  if (r === 'dept_head') return 'supervisor';
  return r;
}

function roleEquivalentsForRead(role) {
  const n = normalizeRole(role);
  if (!n) return [];
  if (n === 'hr') return ['hr', 'hr_staff'];
  if (n === 'supervisor') return ['supervisor', 'dept_head'];
  return [n];
}

async function isActiveUser(client, userId) {
  if (!userId) return false;
  const result = await client.query(
    `SELECT id
     FROM users
     WHERE id = $1
       AND (is_active IS NULL OR is_active = true)`,
    [userId]
  );
  return result.rowCount > 0;
}

async function insertNotificationIfNotRecent(client, payload, dedupeMinutes = 30) {
  if (!payload.user_id) return false;
  const eventKey = payload.event_key || `${payload.type}:doc:${payload.document_id}:level:${payload.escalation_level ?? 'na'}`;
  if (eventKey) {
    const byKey = await client.query(
      `SELECT id
       FROM docutracker_notifications
       WHERE document_id = $1
         AND user_id = $2
         AND type = $3
         AND event_key = $4
       LIMIT 1`,
      [payload.document_id, payload.user_id, payload.type, eventKey]
    );
    if (byKey.rowCount > 0) return false;
  }
  const existing = await client.query(
    `SELECT id
     FROM docutracker_notifications
     WHERE document_id = $1
       AND user_id = $2
       AND type = $3
       AND COALESCE(title, '') = COALESCE($4, '')
       AND COALESCE(body, '') = COALESCE($5, '')
       AND created_at >= now() - make_interval(mins => $6::int)
     LIMIT 1`,
    [
      payload.document_id,
      payload.user_id,
      payload.type,
      payload.title || null,
      payload.body || null,
      dedupeMinutes,
    ]
  );
  if (existing.rowCount > 0) return false;
  await client.query(
    `INSERT INTO docutracker_notifications
     (document_id, user_id, type, event_key, title, body)
     VALUES ($1, $2, $3, $4, $5, $6)
     ON CONFLICT (document_id, user_id, type, event_key)
     WHERE event_key IS NOT NULL
     DO NOTHING`,
    [
      payload.document_id,
      payload.user_id,
      payload.type,
      eventKey,
      payload.title || null,
      payload.body || null,
    ]
  );
  return true;
}

async function insertHistoryIfMissing(client, payload) {
  const exists = await client.query(
    `SELECT id
     FROM docutracker_document_history
     WHERE document_id = $1
       AND action = $2
       AND COALESCE(escalation_level, -1) = COALESCE($3, -1)
       AND created_at >= now() - interval '1 hour'
     LIMIT 1`,
    [payload.document_id, payload.action, payload.escalation_level || null]
  );
  if (exists.rowCount > 0) return false;
  await client.query(
    `INSERT INTO docutracker_document_history
     (document_id, action, from_step, to_step, from_status, to_status, remarks, is_overdue_log, is_escalation_log, escalation_level)
     VALUES ($1, $2, $3, $4, $5, $6, $7, COALESCE($8, false), COALESCE($9, false), $10)`,
    [
      payload.document_id,
      payload.action,
      payload.from_step || null,
      payload.to_step || null,
      payload.from_status || null,
      payload.to_status || null,
      payload.remarks || null,
      payload.is_overdue_log || false,
      payload.is_escalation_log || false,
      payload.escalation_level || null,
    ]
  );
  return true;
}

async function upsertRoutingRecord(client, payload) {
  const {
    document_id,
    step_order,
    assignee_id,
    status,
    deadline_time,
    remarks,
  } = payload || {};
  if (!document_id || !step_order) return;
  if (!assignee_id) return;
  await client.query(
    `INSERT INTO docutracker_routing_records
       (document_id, step_order, assignee_id, sent_time, deadline_time, reviewed_time, status, remarks)
     VALUES ($1, $2, $3, now(), $4, NULL, $5, $6)
     ON CONFLICT (document_id, step_order)
     DO UPDATE SET assignee_id = EXCLUDED.assignee_id,
                   sent_time = EXCLUDED.sent_time,
                   deadline_time = EXCLUDED.deadline_time,
                   reviewed_time = NULL,
                   status = EXCLUDED.status,
                   remarks = EXCLUDED.remarks,
                   updated_at = now()`,
    [
      document_id,
      step_order,
      assignee_id,
      deadline_time ?? null,
      status ?? 'escalated',
      remarks ?? null,
    ]
  );
}

async function notifyAdminsForIntervention(client, documentId, title, body) {
  const admins = await client.query(
    `SELECT id
     FROM users
     WHERE role = 'admin'
       AND (is_active IS NULL OR is_active = true)`
  );
  for (const admin of admins.rows) {
    await insertNotificationIfNotRecent(client, {
      document_id: documentId,
      user_id: admin.id,
      type: 'overdue',
      title,
      body,
    });
  }
}

async function resolveEscalationRecipient(client, doc) {
  const targetRole = normalizeRole(doc.escalation_target_role);
  const roleCandidates = roleEquivalentsForRead(targetRole);
  const deptId = doc.document_department_id || null;

  if (!targetRole || roleCandidates.length === 0) {
    return { assigneeId: null, reason: 'NO_ESCALATION_TARGET_ROLE' };
  }

  // Choose the first active user in the target role for the document's department.
  // This keeps escalation within the same workflow step and enforces department-scoped configs.
  const r = await client.query(
    `SELECT u.id
     FROM users u
     WHERE u.role = ANY($1::text[])
       AND (u.is_active IS NULL OR u.is_active = true)
       AND EXISTS (
         SELECT 1
         FROM assignments a
         WHERE a.employee_id = u.id
           AND (a.is_active IS NULL OR a.is_active = true)
           AND a.effective_from <= CURRENT_DATE
           AND (a.effective_to IS NULL OR a.effective_to >= CURRENT_DATE)
           AND ($2::uuid IS NULL OR a.department_id = $2::uuid)
       )
     ORDER BY u.id
     LIMIT 1`,
    [roleCandidates, deptId]
  );

  if (!r.rowCount) {
    return { assigneeId: null, reason: 'NO_ACTIVE_TARGET_ROLE_USERS' };
  }
  const candidate = r.rows[0].id;
  return { assigneeId: candidate, reason: null };
}

async function processEscalationsOnce() {
  if (running) return;
  running = true;
  const client = await pool.connect();
  let hasAdvisoryLock = false;
  try {
    const lockRes = await client.query('SELECT pg_try_advisory_lock($1) AS locked', [
      ESCALATION_LOCK_KEY,
    ]);
    if (!lockRes.rows[0]?.locked) {
      return;
    }
    hasAdvisoryLock = true;

    await client.query('BEGIN');

    const docsRes = await client.query(
      `SELECT
         d.*,
         ad.department_id AS document_department_id,
         c.escalation_target_role,
         c.escalation_delay_minutes,
         c.max_escalation_level,
         c.notify_original_sender
       FROM docutracker_documents d
       -- infer current department from the current holder (fallback: creator)
       LEFT JOIN LATERAL (
         SELECT a.department_id
         FROM assignments a
         WHERE a.employee_id = COALESCE(d.current_holder_id, d.created_by)
           AND (a.is_active IS NULL OR a.is_active = true)
           AND a.effective_from <= CURRENT_DATE
           AND (a.effective_to IS NULL OR a.effective_to >= CURRENT_DATE)
         ORDER BY a.effective_from DESC
         LIMIT 1
       ) ad ON true
       LEFT JOIN LATERAL (
         SELECT escalation_target_role, escalation_delay_minutes, max_escalation_level, notify_original_sender
         FROM docutracker_escalation_configs c
         WHERE c.document_type = d.document_type
           AND (c.department_id = ad.department_id OR c.department_id IS NULL)
         ORDER BY (c.department_id IS NULL) ASC, c.created_at DESC
         LIMIT 1
       ) c ON true
       WHERE d.deadline_time IS NOT NULL
         AND d.deadline_time < now()
         AND d.status IN ('pending', 'in_review', 'escalated')
       FOR UPDATE OF d SKIP LOCKED`
    );

    for (const doc of docsRes.rows) {
      const maxLevel = Number(doc.max_escalation_level || 3);
      const delayMinutes = Number(doc.escalation_delay_minutes || 60);
      const nextLevel = Number(doc.escalation_level || 0) + 1;
      const now = new Date();
      const nextDeadline = new Date(now.getTime() + delayMinutes * 60 * 1000);
      if (nextLevel > maxLevel) {
        await client.query(
          `UPDATE docutracker_documents
           SET status = 'overdue',
               needs_admin_intervention = true,
               updated_at = now()
           WHERE id = $1`,
          [doc.id]
        );

        await insertHistoryIfMissing(client, {
          document_id: doc.id,
          action: 'overdue',
          from_step: doc.current_step,
          to_step: doc.current_step,
          from_status: doc.status,
          to_status: 'overdue',
          remarks: 'Max escalation level reached',
          is_overdue_log: true,
          is_escalation_log: true,
          escalation_level: doc.escalation_level,
        });

        const overdueRecipient = doc.current_holder_id ?? doc.created_by;
        if (overdueRecipient) {
          await upsertRoutingRecord(client, {
            document_id: doc.id,
            step_order: doc.current_step,
            assignee_id: overdueRecipient,
            status: 'overdue',
            deadline_time: doc.deadline_time ?? null,
            remarks: 'Overdue (max escalation level reached)',
          });
        }
        await insertNotificationIfNotRecent(client, {
          document_id: doc.id,
          user_id: overdueRecipient,
          type: 'overdue',
          escalation_level: doc.escalation_level,
          event_key: `overdue:doc:${doc.id}:level:${doc.escalation_level ?? 0}`,
          title: 'Document overdue',
          body: 'This document reached max escalation level and requires admin intervention.',
        });
        if (doc.notify_original_sender && doc.created_by && doc.created_by !== overdueRecipient) {
          await insertNotificationIfNotRecent(client, {
            document_id: doc.id,
            user_id: doc.created_by,
            type: 'overdue',
            escalation_level: doc.escalation_level,
            event_key: `overdue:doc:${doc.id}:level:${doc.escalation_level ?? 0}:creator:${doc.created_by}`,
            title: 'Your document is overdue',
            body: 'A document you created reached max escalation level and requires admin intervention.',
          });
        }
        await notifyAdminsForIntervention(
          client,
          doc.id,
          'Admin intervention required',
          `Document "${doc.title}" reached max escalation level and needs manual action.`
        );
      } else {
        const escalationRecipient = await resolveEscalationRecipient(client, doc);
        if (!escalationRecipient.assigneeId) {
          // Strict fallback: no escalation recipient means admin intervention required.
          const overdueRecipient = doc.current_holder_id ?? doc.created_by;
          await client.query(
            `UPDATE docutracker_documents
             SET status = 'overdue',
                 needs_admin_intervention = true,
                 deadline_time = null,
                 updated_at = now()
             WHERE id = $1`,
            [doc.id]
          );
          await insertHistoryIfMissing(client, {
            document_id: doc.id,
            action: 'overdue',
            from_step: doc.current_step,
            to_step: doc.current_step,
            from_status: doc.status,
            to_status: 'overdue',
            remarks: `Escalation fallback triggered: ${escalationRecipient.reason || 'NO_RECIPIENT'}`,
            is_overdue_log: true,
            is_escalation_log: true,
            escalation_level: doc.escalation_level,
          });
          if (overdueRecipient) {
            await upsertRoutingRecord(client, {
              document_id: doc.id,
              step_order: doc.current_step,
              assignee_id: overdueRecipient,
              status: 'overdue',
              deadline_time: null,
              remarks: 'Overdue (no escalation recipient)',
            });
            await insertNotificationIfNotRecent(client, {
              document_id: doc.id,
              user_id: overdueRecipient,
              type: 'overdue',
              escalation_level: doc.escalation_level,
              event_key: `overdue:doc:${doc.id}:level:${doc.escalation_level ?? 0}:no-target`,
              title: 'Document overdue',
              body: 'This document could not be auto-routed to an escalation recipient and requires admin intervention.',
            });
          }
          if (doc.notify_original_sender && doc.created_by && doc.created_by !== overdueRecipient) {
            await insertNotificationIfNotRecent(client, {
              document_id: doc.id,
              user_id: doc.created_by,
              type: 'overdue',
              escalation_level: doc.escalation_level,
              event_key: `overdue:doc:${doc.id}:level:${doc.escalation_level ?? 0}:creator`,
              title: 'Your document is overdue',
              body: 'Your document could not be auto-routed and needs admin intervention.',
            });
          }
          await notifyAdminsForIntervention(
            client,
            doc.id,
            'Admin intervention required',
            `Document "${doc.title}" cannot auto-route (${escalationRecipient.reason}).`
          );
          continue;
        }

        await client.query(
          `UPDATE docutracker_documents
           SET status = 'escalated',
               escalation_level = $2,
               current_step = $3,
               current_holder_id = $4,
               needs_admin_intervention = false,
               deadline_time = $5,
               sent_time = now(),
               updated_at = now()
           WHERE id = $1`,
          [
            doc.id,
            nextLevel,
            doc.current_step,
            escalationRecipient.assigneeId,
            nextDeadline,
          ]
        );

        await upsertRoutingRecord(client, {
          document_id: doc.id,
          step_order: doc.current_step,
          assignee_id: escalationRecipient.assigneeId,
          status: 'escalated',
          deadline_time: nextDeadline,
          remarks: `Escalated to ${normalizeRole(doc.escalation_target_role) || 'target role'}`,
        });

        await insertHistoryIfMissing(client, {
          document_id: doc.id,
          action: 'escalated',
          from_step: doc.current_step,
          to_step: doc.current_step,
          from_status: doc.status,
          to_status: 'escalated',
          remarks: `Automatically escalated to target role (${normalizeRole(doc.escalation_target_role)})`,
          is_overdue_log: true,
          is_escalation_log: true,
          escalation_level: nextLevel,
        });

        await insertNotificationIfNotRecent(client, {
          document_id: doc.id,
          user_id: escalationRecipient.assigneeId,
          type: 'escalated',
          escalation_level: nextLevel,
          event_key: `escalated:doc:${doc.id}:level:${nextLevel}:assignee:${escalationRecipient.assigneeId}`,
          title: 'Document escalated to you',
          body: 'A document has been escalated and assigned to you for immediate review.',
        });

        if (doc.notify_original_sender && doc.created_by && doc.created_by !== doc.current_holder_id) {
          await insertNotificationIfNotRecent(client, {
            document_id: doc.id,
            user_id: doc.created_by,
            type: 'escalated',
            escalation_level: nextLevel,
            event_key: `escalated:doc:${doc.id}:level:${nextLevel}:creator:${doc.created_by}`,
            title: 'Your document was escalated',
            body: 'A document you created has been escalated due to overdue review.',
          });
        }
      }
    }

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[docutracker escalation worker]', err);
  } finally {
    if (hasAdvisoryLock) {
      await client.query('SELECT pg_advisory_unlock($1)', [ESCALATION_LOCK_KEY]);
    }
    client.release();
    running = false;
  }
}

function startDocutrackerEscalationWorker() {
  if (timer) return;
  processEscalationsOnce();
  timer = setInterval(() => {
    processEscalationsOnce();
  }, 60 * 1000);
}

module.exports = { startDocutrackerEscalationWorker, processEscalationsOnce };
