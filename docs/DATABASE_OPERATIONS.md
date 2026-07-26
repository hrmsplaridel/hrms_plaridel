# HRMS Plaridel PostgreSQL Operations Guide

This runbook contains common queries for inspecting and maintaining the HRMS
database in development and production. The application uses PostgreSQL and
connects through `DATABASE_URL`.

> **Production safety**
>
> 1. Confirm the connected server and database before changing anything.
> 2. Take and verify a backup before schema changes or permanent deletion.
> 3. Run the matching `SELECT` before every `UPDATE` or `DELETE`.
> 4. Use an explicit transaction and inspect `RETURNING` output before `COMMIT`.
> 5. Use UUIDs for changes. Never use the row number displayed by pgAdmin.
> 6. Never disable foreign-key checks or run an unqualified `DELETE`.
> 7. Prefer application endpoints for normal business operations because they
>    enforce authorization, validation, audit, and workflow rules.

Replace every value wrapped in angle brackets, such as `<USER_UUID>`, before
running a query. Do not include the angle brackets.

## 1. Confirm the connection

Run this first in every pgAdmin Query Tool session:

```sql
SELECT
  current_database() AS database_name,
  current_user AS database_user,
  inet_server_addr() AS server_address,
  inet_server_port() AS server_port,
  current_schema() AS current_schema,
  current_setting('TimeZone') AS timezone,
  now() AS server_time,
  version() AS postgres_version;
```

Show the search path:

```sql
SHOW search_path;
```

`public.users` means the `users` table inside the `public` schema. Using the
schema name explicitly prevents accidentally targeting a same-named table in a
different schema.

## 2. Safe transaction pattern

Start a transaction, make one narrowly scoped change, inspect the returned row,
and then choose exactly one of `COMMIT` or `ROLLBACK`.

```sql
BEGIN;

UPDATE public.users
SET updated_at = now()
WHERE id = '<USER_UUID>'::uuid
RETURNING id, employee_number, email, full_name, updated_at;

-- If the returned row is correct:
COMMIT;

-- If anything is unexpected, use this instead of COMMIT:
-- ROLLBACK;
```

For a long or potentially blocking maintenance transaction:

```sql
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

-- Put the narrowly scoped statement here.

ROLLBACK; -- Change to COMMIT only after verification.
```

If pgAdmin loses its connection before `COMMIT`, PostgreSQL rolls back the open
transaction.

## 3. Inspect tables, columns, sizes, and constraints

List application tables:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;
```

Inspect a table's columns:

```sql
SELECT
  ordinal_position,
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = '<TABLE_NAME>'
ORDER BY ordinal_position;
```

Find the largest tables:

```sql
SELECT
  schemaname,
  relname AS table_name,
  n_live_tup AS estimated_rows,
  pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
```

Show foreign keys that reference `public.users(id)`:

```sql
SELECT
  tc.table_schema,
  tc.table_name,
  kcu.column_name,
  tc.constraint_name,
  rc.delete_rule,
  rc.update_rule
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON kcu.constraint_schema = tc.constraint_schema
 AND kcu.constraint_name = tc.constraint_name
JOIN information_schema.referential_constraints rc
  ON rc.constraint_schema = tc.constraint_schema
 AND rc.constraint_name = tc.constraint_name
JOIN information_schema.constraint_column_usage ccu
  ON ccu.constraint_schema = rc.unique_constraint_schema
 AND ccu.constraint_name = rc.unique_constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND ccu.table_schema = 'public'
  AND ccu.table_name = 'users'
  AND ccu.column_name = 'id'
ORDER BY tc.table_name, kcu.column_name;
```

Delete behavior:

- `CASCADE`: the referencing rows are deleted automatically.
- `SET NULL`: the row remains and its user reference becomes `NULL`.
- `NO ACTION` or `RESTRICT`: PostgreSQL blocks deletion while references exist.

## 4. Users and employees

List users without exposing password hashes:

```sql
SELECT
  id,
  employee_number,
  email,
  full_name,
  role,
  is_active,
  employment_status,
  biometric_user_id,
  date_hired,
  separation_date,
  created_at
FROM public.users
ORDER BY employee_number NULLS LAST, full_name;
```

Find one user by email:

```sql
SELECT
  id,
  employee_number,
  email,
  full_name,
  role,
  is_active,
  employment_status,
  biometric_user_id
FROM public.users
WHERE lower(email) = lower('<EMAIL>');
```

Find users by name:

```sql
SELECT id, employee_number, email, full_name, is_active
FROM public.users
WHERE full_name ILIKE '%' || '<NAME_FRAGMENT>' || '%'
ORDER BY full_name;
```

Count users by state:

```sql
SELECT role, is_active, employment_status, COUNT(*) AS user_count
FROM public.users
GROUP BY role, is_active, employment_status
ORDER BY role, is_active DESC, employment_status;
```

### Deactivate a user (preferred)

The existing application delete endpoint performs this soft deletion:

```sql
BEGIN;

SELECT id, email, full_name, role, is_active
FROM public.users
WHERE id = '<USER_UUID>'::uuid
FOR UPDATE;

UPDATE public.users
SET
  is_active = false,
  employment_status = 'inactive',
  updated_at = now()
WHERE id = '<USER_UUID>'::uuid
RETURNING id, email, full_name, is_active, employment_status;

COMMIT;
```

Reactivate:

```sql
BEGIN;

UPDATE public.users
SET
  is_active = true,
  employment_status = 'active',
  separation_date = NULL,
  updated_at = now()
WHERE id = '<USER_UUID>'::uuid
RETURNING id, email, full_name, is_active, employment_status;

COMMIT;
```

### Preview a user's related records

This covers the main DTR and leave tables. The foreign-key inspection query
above remains the authoritative check for the currently deployed schema.

```sql
SELECT 'assignments' AS table_name, COUNT(*) AS row_count
FROM public.assignments WHERE employee_id = '<USER_UUID>'::uuid
UNION ALL
SELECT 'policy_assignments', COUNT(*)
FROM public.policy_assignments WHERE employee_id = '<USER_UUID>'::uuid
UNION ALL
SELECT 'biometric_attendance_logs', COUNT(*)
FROM public.biometric_attendance_logs WHERE user_id = '<USER_UUID>'::uuid
UNION ALL
SELECT 'dtr_logs', COUNT(*)
FROM public.dtr_logs WHERE employee_id = '<USER_UUID>'::uuid
UNION ALL
SELECT 'dtr_daily_summary', COUNT(*)
FROM public.dtr_daily_summary WHERE employee_id = '<USER_UUID>'::uuid
UNION ALL
SELECT 'leave_requests.employee_id', COUNT(*)
FROM public.leave_requests WHERE employee_id = '<USER_UUID>'::uuid
UNION ALL
SELECT 'leave_requests.user_id', COUNT(*)
FROM public.leave_requests WHERE user_id = '<USER_UUID>'::uuid
UNION ALL
SELECT 'leave_balances', COUNT(*)
FROM public.leave_balances WHERE user_id = '<USER_UUID>'::uuid
ORDER BY table_name;
```

### Permanently delete one user

Only use this for an intentionally permanent deletion. DTR rows linked by
`employee_id` and biometric rows linked by `user_id` use `ON DELETE CASCADE` in
the project schema. Audit/reviewer references commonly use `ON DELETE SET NULL`.
Any restrictive foreign key causes the entire statement to fail.

```sql
BEGIN;
SET LOCAL lock_timeout = '5s';

-- Lock and verify exactly one target.
SELECT id, employee_number, email, full_name, role
FROM public.users
WHERE id = '<USER_UUID>'::uuid
FOR UPDATE;

-- Review related counts using the preview query above before continuing.

DELETE FROM public.users
WHERE id = '<USER_UUID>'::uuid
RETURNING id, employee_number, email, full_name;

-- Verify that the target is gone inside this transaction.
SELECT id, email, full_name
FROM public.users
WHERE id = '<USER_UUID>'::uuid;

-- Use COMMIT only after checking the DELETE RETURNING output.
COMMIT;
-- ROLLBACK;
```

Do not delete by a partial name. If using email, first confirm it is unique:

```sql
SELECT COUNT(*) AS matches
FROM public.users
WHERE lower(email) = lower('<EMAIL>');
```

Then:

```sql
BEGIN;

DELETE FROM public.users
WHERE lower(email) = lower('<EMAIL>')
RETURNING id, employee_number, email, full_name;

COMMIT;
```

The number on the left side of a pgAdmin result grid is not a database ID.

## 5. DTR and biometric data

### Query saved DTR summaries

By user UUID:

```sql
SELECT
  id,
  attendance_date,
  time_in,
  break_out,
  break_in,
  time_out,
  total_hours,
  late_minutes,
  undertime_minutes,
  overtime_minutes,
  status,
  source,
  remarks
FROM public.dtr_daily_summary
WHERE employee_id = '<USER_UUID>'::uuid
ORDER BY attendance_date DESC;
```

By email and date range:

```sql
SELECT
  u.employee_number,
  u.full_name,
  d.attendance_date,
  d.time_in,
  d.time_out,
  d.total_hours,
  d.late_minutes,
  d.undertime_minutes,
  d.status,
  d.source
FROM public.dtr_daily_summary d
JOIN public.users u ON u.id = d.employee_id
WHERE lower(u.email) = lower('<EMAIL>')
  AND d.attendance_date BETWEEN DATE '<START_DATE>' AND DATE '<END_DATE>'
ORDER BY d.attendance_date;
```

Stored absences:

```sql
SELECT u.employee_number, u.full_name, d.*
FROM public.dtr_daily_summary d
JOIN public.users u ON u.id = d.employee_id
WHERE d.status = 'absent'
  AND d.attendance_date BETWEEN DATE '<START_DATE>' AND DATE '<END_DATE>'
ORDER BY d.attendance_date, u.full_name;
```

Important: this project can inject synthetic `absent` rows in API responses for
past scheduled workdays with no saved record. Therefore, SQL that filters
`status = 'absent'` only returns explicitly stored absences. A missing summary
row is not sufficient by itself to prove absence; schedules, assignments,
holidays, leave, hire/separation dates, and biometric synchronization must also
be considered.

### Query raw biometric logs

```sql
SELECT
  b.id,
  u.employee_number,
  u.full_name,
  b.biometric_user_id,
  b.logged_at,
  b.punch_code,
  b.verify_code,
  b.source_file_name,
  b.imported_at
FROM public.biometric_attendance_logs b
JOIN public.users u ON u.id = b.user_id
WHERE b.user_id = '<USER_UUID>'::uuid
  AND b.logged_at >= TIMESTAMPTZ '<START_TIMESTAMP>'
  AND b.logged_at <  TIMESTAMPTZ '<END_TIMESTAMP>'
ORDER BY b.logged_at;
```

Find duplicate biometric identifiers on users:

```sql
SELECT biometric_user_id, COUNT(*) AS user_count
FROM public.users
WHERE biometric_user_id IS NOT NULL
GROUP BY biometric_user_id
HAVING COUNT(*) > 1;
```

The schema's unique constraint should normally make this query return no rows.

### Delete one DTR summary safely

Prefer a correction through the application. For an intentional maintenance
deletion:

```sql
BEGIN;

SELECT d.id, d.employee_id, u.full_name, d.attendance_date, d.status, d.source
FROM public.dtr_daily_summary d
JOIN public.users u ON u.id = d.employee_id
WHERE d.id = '<DTR_SUMMARY_UUID>'::uuid
FOR UPDATE;

DELETE FROM public.dtr_daily_summary
WHERE id = '<DTR_SUMMARY_UUID>'::uuid
RETURNING id, employee_id, attendance_date, status, source;

COMMIT;
```

Delete one employee's DTR summary for exactly one date:

```sql
BEGIN;

DELETE FROM public.dtr_daily_summary
WHERE employee_id = '<USER_UUID>'::uuid
  AND attendance_date = DATE '<ATTENDANCE_DATE>'
RETURNING id, employee_id, attendance_date, status, source;

COMMIT;
```

Deleting a summary does not necessarily delete the underlying biometric logs.
The summary may be recreated when biometric processing runs again.

## 6. Assignments and schedules

Show an employee's assignment history:

```sql
SELECT
  a.id,
  a.effective_from,
  a.effective_to,
  a.is_active,
  d.name AS department,
  p.name AS position,
  s.name AS shift,
  a.override_start_time,
  a.override_end_time,
  a.remarks
FROM public.assignments a
LEFT JOIN public.departments d ON d.id = a.department_id
LEFT JOIN public.positions p ON p.id = a.position_id
LEFT JOIN public.shifts s ON s.id = a.shift_id
WHERE a.employee_id = '<USER_UUID>'::uuid
ORDER BY a.effective_from DESC;
```

Find users without an active assignment:

```sql
SELECT u.id, u.employee_number, u.full_name, u.email
FROM public.users u
LEFT JOIN public.assignments a
  ON a.employee_id = u.id
 AND a.is_active = true
WHERE u.is_active = true
  AND u.role = 'employee'
  AND a.id IS NULL
ORDER BY u.full_name;
```

Find users with more than one active assignment:

```sql
SELECT u.id, u.full_name, COUNT(*) AS active_assignments
FROM public.users u
JOIN public.assignments a ON a.employee_id = u.id
WHERE a.is_active = true
GROUP BY u.id, u.full_name
HAVING COUNT(*) > 1;
```

The partial unique index should normally prevent this condition.

## 7. Leave data

List leave requests for one employee:

```sql
SELECT
  lr.id,
  lt.name AS leave_type,
  lr.start_date,
  lr.end_date,
  COALESCE(lr.number_of_days, lr.total_days) AS days,
  lr.status,
  lr.reason,
  lr.created_at,
  lr.approved_at
FROM public.leave_requests lr
LEFT JOIN public.leave_types lt ON lt.id = lr.leave_type_id
WHERE lr.employee_id = '<USER_UUID>'::uuid
ORDER BY lr.created_at DESC;
```

List pending workflow requests:

```sql
SELECT
  lr.id,
  u.employee_number,
  u.full_name,
  lt.name AS leave_type,
  lr.start_date,
  lr.end_date,
  lr.status,
  lr.created_at
FROM public.leave_requests lr
JOIN public.users u ON u.id = lr.employee_id
LEFT JOIN public.leave_types lt ON lt.id = lr.leave_type_id
WHERE lr.status IN ('pending', 'pending_department_head', 'pending_hr')
ORDER BY lr.created_at;
```

Inspect leave balances:

```sql
SELECT
  u.employee_number,
  u.full_name,
  lb.leave_type,
  lb.earned_days,
  lb.used_days,
  lb.pending_days,
  lb.adjusted_days,
  (
    lb.earned_days + lb.adjusted_days
    - lb.used_days - lb.pending_days
  ) AS available_days,
  lb.as_of_date,
  lb.last_accrual_date
FROM public.leave_balances lb
JOIN public.users u ON u.id = lb.user_id
WHERE lb.user_id = '<USER_UUID>'::uuid
ORDER BY lb.leave_type;
```

Do not directly approve leave with a simple `UPDATE`: the application also
maintains workflow history, balances, and DTR effects.

## 8. Holidays and templates

Active holidays in a date range:

```sql
SELECT id, date_from, date_to, name, holiday_type, coverage, recurring
FROM public.holidays
WHERE is_active = true
  AND date_to >= DATE '<START_DATE>'
  AND date_from <= DATE '<END_DATE>'
ORDER BY date_from, name;
```

Show templates and their items:

```sql
SELECT
  t.id AS template_id,
  t.country_code,
  t.year,
  t.label,
  t.is_active AS template_active,
  i.id AS item_id,
  i.date_from,
  i.date_to,
  i.name,
  i.holiday_type,
  i.coverage,
  i.is_active AS item_active
FROM public.holiday_default_templates t
LEFT JOIN public.holiday_default_template_items i ON i.template_id = t.id
ORDER BY t.country_code, t.year, i.sort_order, i.date_from;
```

Insert one operational holiday:

```sql
BEGIN;

INSERT INTO public.holidays (
  date_from,
  date_to,
  name,
  holiday_type,
  description,
  is_active,
  recurring,
  coverage
)
VALUES (
  DATE '<DATE_FROM>',
  DATE '<DATE_TO>',
  '<HOLIDAY_NAME>',
  'regular', -- regular | special | local | work_suspension
  '<DESCRIPTION>',
  true,
  false,
  'whole_day' -- whole_day | am_only | pm_only
)
RETURNING *;

COMMIT;
```

Deactivate a holiday instead of deleting it:

```sql
BEGIN;

UPDATE public.holidays
SET is_active = false
WHERE id = '<HOLIDAY_UUID>'::uuid
RETURNING id, date_from, date_to, name, is_active;

COMMIT;
```

Deleting a default template automatically deletes its template items because
`holiday_default_template_items.template_id` uses `ON DELETE CASCADE`. It does
not delete rows from `holidays`.

```sql
BEGIN;

SELECT id, country_code, year, label
FROM public.holiday_default_templates
WHERE id = '<TEMPLATE_UUID>'::uuid
FOR UPDATE;

DELETE FROM public.holiday_default_templates
WHERE id = '<TEMPLATE_UUID>'::uuid
RETURNING id, country_code, year, label;

COMMIT;
```

## 9. Data-quality checks

Check for orphan-like dual IDs in leave requests:

```sql
SELECT id, employee_id, user_id, start_date, end_date, status
FROM public.leave_requests
WHERE employee_id IS DISTINCT FROM user_id;
```

Check duplicate daily summaries:

```sql
SELECT employee_id, attendance_date, COUNT(*) AS row_count
FROM public.dtr_daily_summary
GROUP BY employee_id, attendance_date
HAVING COUNT(*) > 1;
```

The unique constraint should normally make this return no rows.

Check DTR summaries outside known users:

```sql
SELECT d.*
FROM public.dtr_daily_summary d
LEFT JOIN public.users u ON u.id = d.employee_id
WHERE u.id IS NULL;
```

Foreign keys should normally make this return no rows.

Check invalid attendance time order:

```sql
SELECT id, employee_id, attendance_date, time_in, time_out
FROM public.dtr_daily_summary
WHERE time_in IS NOT NULL
  AND time_out IS NOT NULL
  AND time_out < time_in;
```

Check recent failed/pending raw DTR synchronization:

```sql
SELECT sync_status, COUNT(*) AS row_count
FROM public.dtr_logs
WHERE created_at >= now() - INTERVAL '7 days'
GROUP BY sync_status
ORDER BY sync_status;
```

## 10. Activity and lock diagnostics

Show active sessions for the current database:

```sql
SELECT
  pid,
  usename,
  application_name,
  client_addr,
  state,
  wait_event_type,
  wait_event,
  query_start,
  now() - query_start AS duration,
  left(query, 200) AS query
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
ORDER BY query_start;
```

Show non-idle transactions:

```sql
SELECT
  pid,
  usename,
  state,
  xact_start,
  now() - xact_start AS transaction_age,
  wait_event_type,
  wait_event,
  left(query, 200) AS query
FROM pg_stat_activity
WHERE datname = current_database()
  AND xact_start IS NOT NULL
  AND pid <> pg_backend_pid()
ORDER BY xact_start;
```

Show table health statistics:

```sql
SELECT
  relname AS table_name,
  n_live_tup,
  n_dead_tup,
  last_analyze,
  last_autoanalyze,
  last_vacuum,
  last_autovacuum
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;
```

Do not terminate production sessions merely because they appear here. Identify
the owning application or operator and determine impact first.

## 11. Backup and restore

Backups are shell commands, not SQL. Run them from a secured administration
host with PostgreSQL client tools installed. Avoid putting passwords directly
in command history; use `.pgpass`, a protected environment, or your platform's
secret manager.

Custom-format backup:

```powershell
pg_dump --dbname="$env:DATABASE_URL" --format=custom --verbose --file="hrms_YYYYMMDD_HHMM.dump"
```

Schema-only backup:

```powershell
pg_dump --dbname="$env:DATABASE_URL" --schema-only --format=plain --file="hrms_schema_YYYYMMDD.sql"
```

Restore a custom-format dump into an empty recovery/test database:

```powershell
pg_restore --dbname="<RECOVERY_DATABASE_URL>" --clean --if-exists --no-owner --verbose "hrms_YYYYMMDD_HHMM.dump"
```

`--clean` drops objects in the restore target. Never point a restore test at the
production database.

A backup is not verified until it has been restored successfully into an
isolated database and critical row counts and application workflows have been
checked.

Useful post-restore counts:

```sql
SELECT 'users' AS table_name, COUNT(*) AS row_count FROM public.users
UNION ALL
SELECT 'dtr_daily_summary', COUNT(*) FROM public.dtr_daily_summary
UNION ALL
SELECT 'biometric_attendance_logs', COUNT(*) FROM public.biometric_attendance_logs
UNION ALL
SELECT 'leave_requests', COUNT(*) FROM public.leave_requests
UNION ALL
SELECT 'holidays', COUNT(*) FROM public.holidays
ORDER BY table_name;
```

## 12. Schema migrations and maintenance rules

- Apply versioned scripts from `backend/scripts` and
  `backend/scripts/migrations`; do not edit production tables manually when a
  repeatable migration is appropriate.
- Test migrations against a recent sanitized restore first.
- Record the migration filename, operator, timestamp, target database, runtime,
  and result.
- Review locks and table size before an `ALTER TABLE` on a busy table.
- Run one migration from one operator/session at a time.
- Keep DDL and data backfills separate when that reduces lock duration.
- Do not rerun the entire `init-schema.sql` as a substitute for controlled
  production migrations.
- Never store or paste `password_hash`, reset tokens, JWTs, `DATABASE_URL`, or
  personal data into tickets, chat, or logs.

## 13. Emergency checklist

Before changing data:

```text
[ ] Correct server and database confirmed
[ ] Target row selected by UUID
[ ] Related records and foreign-key behavior reviewed
[ ] Recent restorable backup available
[ ] Transaction, lock timeout, and rollback plan ready
[ ] Application owner informed if production behavior may change
```

After changing data:

```text
[ ] RETURNING output matched the intended row
[ ] Relevant row counts and application workflow verified
[ ] No transaction left idle
[ ] Change and reason recorded
[ ] Backup/retention or audit implications reviewed
```

