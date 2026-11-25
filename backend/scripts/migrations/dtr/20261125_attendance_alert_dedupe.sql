-- Attendance alerts: at most one alert per employee per attendance date. Idempotent.
-- Run: psql -v ON_ERROR_STOP=1 -d <db> -f backend/scripts/migrations/dtr/20261125_attendance_alert_dedupe.sql

CREATE UNIQUE INDEX IF NOT EXISTS user_notifications_attendance_alert_idx
  ON user_notifications (user_id, (metadata->>'attendance_date'))
  WHERE type = 'attendance_alert';
