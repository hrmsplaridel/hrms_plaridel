-- HRMS Plaridel initial schema
-- Core HR + DTR Module
-- Run: psql -d hrms_plaridel -f scripts/init-schema.sql

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =========================
-- USERS
-- =========================
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'employee'
    CHECK (role IN ('admin', 'hr', 'employee', 'supervisor')),
  full_name TEXT NOT NULL,
  avatar_path TEXT,
  is_active BOOLEAN DEFAULT true,

  middle_name TEXT,
  suffix TEXT,
  sex TEXT,
  date_of_birth DATE,
  contact_number TEXT,
  address TEXT,

  biometric_user_id TEXT UNIQUE,

  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- =========================
-- DEPARTMENTS
-- =========================
CREATE TABLE IF NOT EXISTS departments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- =========================
-- POSITIONS
-- =========================
CREATE TABLE IF NOT EXISTS positions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  description TEXT,
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- =========================
-- SHIFTS / SCHEDULES
-- =========================
CREATE TABLE IF NOT EXISTS shifts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  grace_period_minutes INT DEFAULT 0,
  break_start TIME,
  break_end TIME,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- =========================
-- EMPLOYEE ASSIGNMENTS
-- =========================
CREATE TABLE IF NOT EXISTS assignments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  position_id UUID REFERENCES positions(id) ON DELETE SET NULL,
  shift_id UUID REFERENCES shifts(id) ON DELETE SET NULL,

  date_assigned DATE NOT NULL,
  is_active BOOLEAN DEFAULT true,

  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- =========================
-- HOLIDAYS
-- =========================
CREATE TABLE IF NOT EXISTS holidays (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  holiday_date DATE NOT NULL UNIQUE,
  name TEXT NOT NULL,
  holiday_type TEXT DEFAULT 'regular'
    CHECK (holiday_type IN ('regular', 'special', 'local')),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- =========================
-- LEAVE TYPES
-- =========================
CREATE TABLE IF NOT EXISTS leave_types (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- =========================
-- LEAVE REQUESTS
-- =========================
CREATE TABLE IF NOT EXISTS leave_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  leave_type_id UUID REFERENCES leave_types(id) ON DELETE SET NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  approved_by UUID REFERENCES users(id) ON DELETE SET NULL,
  approved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  CHECK (end_date >= start_date)
);

-- =========================
-- RAW DTR LOGS
-- =========================
CREATE TABLE IF NOT EXISTS dtr_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  local_uuid TEXT UNIQUE,

  biometric_user_id TEXT,
  log_time TIMESTAMPTZ NOT NULL,
  log_type TEXT NOT NULL
    CHECK (log_type IN ('time_in', 'time_out', 'break_in', 'break_out')),

  source TEXT NOT NULL DEFAULT 'biometric'
    CHECK (source IN ('biometric', 'manual', 'mobile', 'import')),

  sync_status TEXT DEFAULT 'synced'
    CHECK (sync_status IN ('pending', 'synced', 'failed')),

  remarks TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- =========================
-- DAILY DTR SUMMARY
-- =========================
CREATE TABLE IF NOT EXISTS dtr_daily_summary (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  attendance_date DATE NOT NULL,

  shift_id UUID REFERENCES shifts(id) ON DELETE SET NULL,

  time_in TIMESTAMPTZ,
  time_out TIMESTAMPTZ,
  break_in TIMESTAMPTZ,
  break_out TIMESTAMPTZ,

  late_minutes INT DEFAULT 0,
  undertime_minutes INT DEFAULT 0,
  total_hours NUMERIC(6,2) DEFAULT 0,

  status TEXT NOT NULL DEFAULT 'incomplete'
    CHECK (status IN ('present', 'late', 'absent', 'on_leave', 'holiday', 'incomplete')),

  remarks TEXT,

  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),

  UNIQUE(employee_id, attendance_date)
);

-- =========================
-- DTR CORRECTION REQUESTS
-- =========================
CREATE TABLE IF NOT EXISTS dtr_corrections (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  attendance_date DATE NOT NULL,

  requested_time_in TIMESTAMPTZ,
  requested_time_out TIMESTAMPTZ,
  reason TEXT NOT NULL,

  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),

  reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  review_notes TEXT,

  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- =========================
-- AUDIT LOGS
-- =========================
CREATE TABLE IF NOT EXISTS audit_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id UUID,
  details TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- =========================
-- INDEXES
-- =========================
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_biometric_user_id ON users(biometric_user_id);

CREATE INDEX IF NOT EXISTS idx_departments_is_active ON departments(is_active);
CREATE INDEX IF NOT EXISTS idx_positions_department_id ON positions(department_id);

CREATE INDEX IF NOT EXISTS idx_assignments_employee_id ON assignments(employee_id);
CREATE INDEX IF NOT EXISTS idx_assignments_shift_id ON assignments(shift_id);

CREATE INDEX IF NOT EXISTS idx_leave_requests_employee_id ON leave_requests(employee_id);
CREATE INDEX IF NOT EXISTS idx_leave_requests_status ON leave_requests(status);
CREATE INDEX IF NOT EXISTS idx_leave_requests_dates ON leave_requests(start_date, end_date);

CREATE INDEX IF NOT EXISTS idx_dtr_logs_employee_id ON dtr_logs(employee_id);
CREATE INDEX IF NOT EXISTS idx_dtr_logs_log_time ON dtr_logs(log_time);
CREATE INDEX IF NOT EXISTS idx_dtr_logs_biometric_user_id ON dtr_logs(biometric_user_id);

CREATE INDEX IF NOT EXISTS idx_dtr_daily_summary_employee_id ON dtr_daily_summary(employee_id);
CREATE INDEX IF NOT EXISTS idx_dtr_daily_summary_date ON dtr_daily_summary(attendance_date);

CREATE INDEX IF NOT EXISTS idx_dtr_corrections_employee_id ON dtr_corrections(employee_id);
CREATE INDEX IF NOT EXISTS idx_dtr_corrections_status ON dtr_corrections(status);
