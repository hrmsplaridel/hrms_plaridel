-- Adds composite/expression indexes used by common HRMS hot paths:
-- login, DTR/time logs, biometric processing, and assignment lookups.
-- Safe to run more than once.

CREATE INDEX IF NOT EXISTS idx_users_lower_email
ON users(LOWER(email));

CREATE INDEX IF NOT EXISTS idx_dtr_daily_summary_date_time
ON dtr_daily_summary(attendance_date DESC, time_in DESC);

CREATE INDEX IF NOT EXISTS idx_dtr_daily_summary_date_employee
ON dtr_daily_summary(attendance_date, employee_id);

CREATE INDEX IF NOT EXISTS idx_biometric_logs_user_logged
ON biometric_attendance_logs(user_id, logged_at);

CREATE INDEX IF NOT EXISTS idx_assignments_employee_active_dates
ON assignments(employee_id, is_active, effective_from DESC, effective_to);

CREATE INDEX IF NOT EXISTS idx_assignments_department_active_dates
ON assignments(department_id, is_active, effective_from, effective_to, employee_id);

CREATE INDEX IF NOT EXISTS idx_leave_requests_status_employee_dates
ON leave_requests(status, employee_id, start_date, end_date);

CREATE INDEX IF NOT EXISTS idx_locator_slips_status_employee_date
ON locator_slips(status, employee_id, slip_date);

ANALYZE;
