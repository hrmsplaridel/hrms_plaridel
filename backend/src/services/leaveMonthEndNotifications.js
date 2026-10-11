const { insertNotification, publishNotification } = require('./notificationService');
const { resolveFinalLeaveReviewers } = require('./leaveFinalReviewerService');
const { parseTargetMonth, completedMonthStartInTimeZone } = require('./leaveMonthlyAccrual');

function notificationMonthForTarget(target) {
  try {
    const completed = completedMonthStartInTimeZone(new Date(), 'Asia/Manila');
    const date = target == null ? completed : parseTargetMonth(target);
    if (date > completed) return null;
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
  } catch (_) { return null; }
}

const round = value => Math.round(Number(value || 0) * 1000) / 1000;
const days = value => `${Math.abs(value)} ${Math.abs(value) === 1 ? 'day' : 'days'}`;
const label = type => ({ vacationLeave: 'Vacation Leave', sickLeave: 'Sick Leave' }[type] || type);
function monthLabel(month) {
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month || '')) throw Error('Invalid notification service month');
  return new Date(`${month}-01T00:00:00Z`).toLocaleDateString('en-US', { month: 'long', year: 'numeric', timeZone: 'UTC' });
}

function buildMonthEndMessage(month, totals, previous) {
  const changes = {};
  const lines = [];
  for (const type of [...new Set([...Object.keys(totals || {}), ...Object.keys(previous || {})])].sort()) {
    const earned = round(round(totals?.[type]?.earned) - round(previous?.[type]?.earned));
    const deducted = round(round(totals?.[type]?.deducted) - round(previous?.[type]?.deducted));
    if (earned === 0 && deducted === 0) continue;
    changes[type] = { earned, deducted };
    const amounts = [];
    if (earned) amounts.push(earned > 0 ? `+${days(earned)} earned` : `${days(earned)} earned credits reversed`);
    if (deducted) amounts.push(deducted > 0 ? `${days(deducted)} deducted` : `${days(deducted)} deduction reversed`);
    lines.push(`${label(type)}: ${amounts.join(', ')}.`);
  }
  if (!lines.length) return null;
  return {
    category: 'leave',
    type: previous ? 'leave_month_end_balance_corrected' : 'leave_month_end_balance_updated',
    title: previous ? `${monthLabel(month)} leave balance correction` : `${monthLabel(month)} leave balance updated`,
    body: `${lines.join('\n')} View credit history for details.`,
    referenceType: 'leave_balance_history',
    metadata: { service_month: month, changes, totals },
  };
}

// Read durable postings, rather than only this run's changes: a retry can recover
// a failed notification write even when accrual/deduction services now skip it.
async function notifyLeaveMonthEnd(pool, { targetYearMonth, dryRun = false, publish = publishNotification }) {
  if (dryRun) return { sent: 0 };
  let client;
  const notifications = [];
  try {
    monthLabel(targetYearMonth);
    client = await pool.connect();
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', ['leave-month-end-notifications']);
    const result = await client.query(
      `WITH notification_months AS (
         SELECT $1::date AS service_month
         UNION
         SELECT DISTINCT service_month FROM leave_monthly_accrual_postings
         WHERE metadata_json->>'target_year_month' = $2::text AND service_month <= $1::date
       ), monthly_totals AS (
         SELECT user_id, service_month, leave_type, credited_days AS earned, 0::numeric AS deducted
         FROM leave_monthly_accrual_postings WHERE service_month IN (SELECT service_month FROM notification_months)
         UNION ALL
         SELECT user_id, service_month, leave_type, 0::numeric, deducted_days
         FROM leave_attendance_deductions WHERE service_month IN (SELECT service_month FROM notification_months)
       ), grouped AS (
         SELECT user_id, service_month, leave_type, SUM(earned) AS earned, SUM(deducted) AS deducted
         FROM monthly_totals GROUP BY user_id, service_month, leave_type
       ), totals AS (
         SELECT user_id, service_month, jsonb_object_agg(leave_type,
           jsonb_build_object('earned', earned, 'deducted', deducted)) AS totals
         FROM grouped GROUP BY user_id, service_month
       ), keys AS (
         SELECT user_id, service_month FROM totals
         UNION
         SELECT user_id, service_month FROM leave_month_end_notification_state
         WHERE service_month IN (SELECT service_month FROM notification_months)
       )
       SELECT u.id AS user_id, k.service_month::text AS service_month,
              COALESCE(t.totals, '{}'::jsonb) AS totals, s.totals AS previous_totals
       FROM keys k JOIN users u ON u.id = k.user_id
       LEFT JOIN totals t ON t.user_id = k.user_id AND t.service_month = k.service_month
       LEFT JOIN leave_month_end_notification_state s
         ON s.user_id = k.user_id AND s.service_month = k.service_month
       WHERE u.is_active = true ORDER BY k.service_month, u.id`,
      [`${targetYearMonth}-01`, targetYearMonth]
    );
    for (const row of result.rows) {
      const serviceMonth = row.service_month?.slice(0, 7) || targetYearMonth;
      const message = buildMonthEndMessage(serviceMonth, row.totals, row.previous_totals);
      if (!message) continue;
      notifications.push(await insertNotification(client, { ...message, userId: row.user_id, deferDelivery: true }));
      await client.query(
        `INSERT INTO leave_month_end_notification_state(user_id, service_month, totals)
         VALUES ($1::uuid, $2::date, $3::jsonb)
         ON CONFLICT (user_id, service_month) DO UPDATE
         SET totals = EXCLUDED.totals, updated_at = now()`,
        [row.user_id, `${serviceMonth}-01`, JSON.stringify(row.totals)]
      );
    }
    await client.query('COMMIT');
  } catch (error) {
    if (client) await client.query('ROLLBACK').catch(() => {});
    console.error('[leaveMonthEndNotifications] summary deferred until retry', error.message);
    return { sent: 0, deferred: true };
  } finally { client?.release(); }
  for (const row of notifications) {
    try { await publish(pool, row); } catch (error) { console.error('[leaveMonthEndNotifications] delivery', error.message); }
  }
  return { sent: notifications.length };
}

async function notifyLeaveMonthEndFailure(pool, { targetYearMonth, actorId }) {
  try {
    const month = monthLabel(targetYearMonth);
    const reviewers = await resolveFinalLeaveReviewers(pool);
    const targets = [...new Set([...reviewers.map(row => row.id), actorId].filter(Boolean))];
    for (const userId of targets) {
      const result = await pool.query(
        `INSERT INTO user_notifications(user_id, category, type, title, body, metadata)
         VALUES ($1::uuid, 'leave', 'leave_month_end_failed', $2, $3, $4::jsonb)
         ON CONFLICT DO NOTHING RETURNING *`,
        [userId, `${month} month-end processing needs attention`,
          `Month-end processing for ${month} did not finish. Review the processing logs before retrying.`,
          JSON.stringify({ service_month: targetYearMonth })]
      );
      if (result.rows[0]) publishNotification(pool, result.rows[0]);
    }
  } catch (error) { console.error('[leaveMonthEndNotifications] failure alert unavailable', error.message); }
}

module.exports = { notifyLeaveMonthEnd, notifyLeaveMonthEndFailure, buildMonthEndMessage, notificationMonthForTarget };
