const { pool } = require('../config/db');

let ready = false;

async function ensureTrainingDailyReportColumns(db = pool) {
  if (ready) return;
  await db.query(
    `ALTER TABLE training_daily_reports
     ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ`,
  );
  ready = true;
}

module.exports = { ensureTrainingDailyReportColumns };
