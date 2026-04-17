const { pool } = require('../config/db');

let timer = null;
let running = false;
const ESCALATION_LOCK_KEY = 907531;

function parseSteps(steps) {
  if (!Array.isArray(steps)) return [];
  return steps
    .map((step) => ({
      step_order: Number(step.step_order ?? step.stepOrder ?? 0),
      user_ids: Array.isArray(step.user_ids)
        ? step.user_ids
        : Array.isArray(step.userIds)
          ? step.userIds
          : [],
    }))
    .filter((step) => step.step_order > 0)
    .sort((a, b) => a.step_order - b.step_order);
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

async function resolveEscalationRecipient(client, doc, configSteps) {
  const currentStep = Number(doc.current_step || 1);
  const nextStep = configSteps.find((step) => step.step_order === currentStep + 1);
  if (!nextStep) {
    return { assigneeId: null, nextStepOrder: null, reason: 'NO_NEXT_STEP' };
  }
  const explicit = nextStep.user_ids.find(Boolean) || null;
  if (!explicit) {
    return { assigneeId: null, nextStepOrder: nextStep.step_order, reason: 'NO_ASSIGNEE_CONFIGURED' };
  }
  const valid = await isActiveUser(client, explicit);
  if (!valid) {
    return { assigneeId: null, nextStepOrder: nextStep.step_order, reason: 'INVALID_ASSIGNEE' };
  }
  return { assigneeId: explicit, nextStepOrder: nextStep.step_order, reason: null };
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
      `SELECT d.*, c.escalation_delay_minutes, c.max_escalation_level, c.notify_original_sender, rc.steps AS routing_steps
       FROM docutracker_documents d
       LEFT JOIN LATERAL (
         SELECT escalation_delay_minutes, max_escalation_level, notify_original_sender
         FROM docutracker_escalation_configs c
         WHERE c.document_type = d.document_type
         ORDER BY c.created_at DESC
         LIMIT 1
       ) c ON true
       LEFT JOIN LATERAL (
         SELECT steps
         FROM docutracker_routing_configs rc
         WHERE rc.document_type = d.document_type
         LIMIT 1
       ) rc ON true
       WHERE d.deadline_time IS NOT NULL
         AND d.deadline_time < now()
         AND d.status IN ('pending', 'in_review', 'forwarded', 'escalated')
       FOR UPDATE OF d SKIP LOCKED`
    );

    for (const doc of docsRes.rows) {
      const maxLevel = Number(doc.max_escalation_level || 3);
      const delayMinutes = Number(doc.escalation_delay_minutes || 60);
      const nextLevel = Number(doc.escalation_level || 0) + 1;
      const now = new Date();
      const nextDeadline = new Date(now.getTime() + delayMinutes * 60 * 1000);
      const configSteps = parseSteps(doc.routing_steps || []);

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

        await insertNotificationIfNotRecent(client, {
          document_id: doc.id,
          user_id: doc.current_holder_id,
          type: 'overdue',
          escalation_level: doc.escalation_level,
          event_key: `overdue:doc:${doc.id}:level:${doc.escalation_level ?? 0}`,
          title: 'Document overdue',
          body: 'This document reached max escalation level and requires admin intervention.',
        });
        await notifyAdminsForIntervention(
          client,
          doc.id,
          'Admin intervention required',
          `Document "${doc.title}" reached max escalation level and needs manual action.`
        );
      } else {
        const escalationRecipient = await resolveEscalationRecipient(client, doc, configSteps);
        if (!escalationRecipient.assigneeId) {
          const currentHolderStillValid = await isActiveUser(client, doc.current_holder_id);
          if (currentHolderStillValid) {
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
              [doc.id, nextLevel, doc.current_step, doc.current_holder_id, nextDeadline]
            );
            await insertHistoryIfMissing(client, {
              document_id: doc.id,
              action: 'escalated',
              from_step: doc.current_step,
              to_step: doc.current_step,
              from_status: doc.status,
              to_status: 'escalated',
              remarks: `Escalated on current step (${escalationRecipient.reason || 'SAME_STEP_FALLBACK'})`,
              is_overdue_log: true,
              is_escalation_log: true,
              escalation_level: nextLevel,
            });
            await insertNotificationIfNotRecent(client, {
              document_id: doc.id,
              user_id: doc.current_holder_id,
              type: 'escalated',
              escalation_level: nextLevel,
              event_key: `escalated:doc:${doc.id}:level:${nextLevel}:holder:${doc.current_holder_id}`,
              title: 'Document escalated',
              body: 'This document remains assigned to you and has been escalated due to overdue review.',
            });
            if (doc.notify_original_sender && doc.created_by && doc.created_by !== doc.current_holder_id) {
              await insertNotificationIfNotRecent(client, {
                document_id: doc.id,
                user_id: doc.created_by,
                type: 'escalated',
                escalation_level: nextLevel,
                event_key: `escalated:doc:${doc.id}:level:${nextLevel}:creator:${doc.created_by}`,
                title: 'Your document was escalated',
                body: 'A document you created has been escalated and remains in the current workflow step.',
              });
            }
            continue;
          }

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
            remarks: `Escalation fallback triggered: ${escalationRecipient.reason}`,
            is_overdue_log: true,
            is_escalation_log: true,
            escalation_level: doc.escalation_level,
          });
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
            escalationRecipient.nextStepOrder || doc.current_step,
            escalationRecipient.assigneeId,
            nextDeadline,
          ]
        );

        await insertHistoryIfMissing(client, {
          document_id: doc.id,
          action: 'escalated',
          from_step: doc.current_step,
          to_step: escalationRecipient.nextStepOrder || doc.current_step,
          from_status: doc.status,
          to_status: 'escalated',
          remarks: 'Automatically escalated because deadline was exceeded',
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
