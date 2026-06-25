-- HRMS Plaridel Schema v2
-- Core HR + DTR + L&D + RSP + DocuTracker modules
-- PostgreSQL
-- Run: psql -d hrms_plaridel -f scripts/init-schema.sql
--
-- DocuTracker tables, constraints, functions, and seeds are included below.
-- For existing databases that predate this file, use backend/scripts/docutracker-install-*.sql instead.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =========================================
-- SEQUENCES
-- =========================================
CREATE SEQUENCE IF NOT EXISTS users_employee_number_seq;
CREATE SEQUENCE IF NOT EXISTS departments_department_number_seq;
CREATE SEQUENCE IF NOT EXISTS offices_office_number_seq;
CREATE SEQUENCE IF NOT EXISTS positions_position_number_seq;
CREATE SEQUENCE IF NOT EXISTS shifts_shift_number_seq;

-- =========================================
-- GENERIC updated_at TRIGGER
-- =========================================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =========================================
-- USERS / EMPLOYEES
-- =========================================
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_number INT UNIQUE DEFAULT nextval('users_employee_number_seq'),

  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'employee'
    CHECK (role IN ('admin', 'hr', 'employee', 'supervisor')),

  full_name TEXT NOT NULL,
  avatar_path TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,

  middle_name TEXT,
  suffix TEXT,
  sex TEXT,
  date_of_birth DATE,
  contact_number TEXT,
  address TEXT,

  employment_type TEXT
    CHECK (employment_type IN ('regular', 'contractual', 'job_order', 'casual')),
  salary_grade TEXT,
  date_hired DATE,
  employment_status TEXT DEFAULT 'active'
    CHECK (employment_status IN ('active', 'inactive', 'resigned', 'retired', 'terminated')),

  biometric_user_id TEXT UNIQUE,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================
-- AUTH REFRESH TOKENS (PERSISTENT SESSIONS)
-- =========================================
CREATE TABLE IF NOT EXISTS auth_refresh_tokens (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  device_info TEXT,
  ip_address INET,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================
-- AUTH PASSWORD RESET OTPs (SEMAPHORE SMS)
-- =========================================
CREATE TABLE IF NOT EXISTS auth_password_reset_otps (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL,
  sent_to TEXT,
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  failed_attempts INT NOT NULL DEFAULT 0,
  ip_address INET,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================
-- DEPARTMENTS
-- =========================================
CREATE TABLE IF NOT EXISTS departments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  department_number INT UNIQUE DEFAULT nextval('departments_department_number_seq'),
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================
-- OFFICES (branch / site; DocuTracker office routing + users.office_id)
-- =========================================
CREATE TABLE IF NOT EXISTS offices (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  office_number INT UNIQUE DEFAULT nextval('offices_office_number_seq'),
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS office_id UUID REFERENCES offices(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_users_office_id ON users(office_id) WHERE office_id IS NOT NULL;

-- =========================================
-- POSITIONS
-- =========================================
CREATE TABLE IF NOT EXISTS positions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  position_number INT UNIQUE DEFAULT nextval('positions_position_number_seq'),
  name TEXT NOT NULL,
  description TEXT,
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT uq_positions_name_department UNIQUE (name, department_id)
);

-- =========================================
-- SHIFTS / SCHEDULES
-- =========================================
CREATE TABLE IF NOT EXISTS shifts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  shift_number INT UNIQUE DEFAULT nextval('shifts_shift_number_seq'),
  name TEXT NOT NULL UNIQUE,

  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  break_end TIME,
  punch_mode TEXT NOT NULL DEFAULT 'auto'
    CONSTRAINT shifts_punch_mode_check
    CHECK (punch_mode IN ('auto', 'full_day', 'am_only', 'pm_only', 'single_session')),

  grace_period_minutes INT NOT NULL DEFAULT 0 CHECK (grace_period_minutes >= 0),

  working_days INT[] NOT NULL DEFAULT ARRAY[1,2,3,4,5],
  is_active BOOLEAN NOT NULL DEFAULT true,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON COLUMN shifts.working_days IS 'ISO weekday: 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 7=Sun';
COMMENT ON COLUMN shifts.punch_mode IS 'Attendance punch interpretation: auto, full_day, am_only, pm_only, or single_session.';

-- =========================================
-- ATTENDANCE POLICIES
-- =========================================
CREATE TABLE IF NOT EXISTS attendance_policies (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL UNIQUE,
  description TEXT,

  -- Structured computation settings (Shift holds grace period; keep it out of policy)
  work_hours_per_day NUMERIC(4,2) NOT NULL DEFAULT 8 CHECK (work_hours_per_day > 0),
  use_equivalent_day_conversion BOOLEAN NOT NULL DEFAULT true,

  -- Late settings
  deduct_late BOOLEAN NOT NULL DEFAULT false,
  max_late_minutes_per_month INT CHECK (max_late_minutes_per_month IS NULL OR max_late_minutes_per_month >= 0),
  convert_late_to_equivalent_day BOOLEAN NOT NULL DEFAULT true,

  -- Undertime settings
  deduct_undertime BOOLEAN NOT NULL DEFAULT true,
  convert_undertime_to_equivalent_day BOOLEAN NOT NULL DEFAULT true,

  -- Absence settings
  absent_equals_full_day_deduction BOOLEAN NOT NULL DEFAULT true,

  -- Advanced
  combine_late_and_undertime BOOLEAN NOT NULL DEFAULT false,
  deduction_multiplier NUMERIC(6,3) NOT NULL DEFAULT 1.0 CHECK (deduction_multiplier > 0),

  is_default BOOLEAN NOT NULL DEFAULT false,
  is_active BOOLEAN NOT NULL DEFAULT true,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_attendance_policies_single_default
ON attendance_policies (is_default)
WHERE is_default = true;

-- =========================================
-- BIOMETRIC DEVICES
-- =========================================
CREATE TABLE IF NOT EXISTS biometric_devices (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  device_id TEXT UNIQUE,
  location TEXT,
  ip_address TEXT,
  vendor TEXT NOT NULL DEFAULT 'zkteco',
  last_sync_at TIMESTAMPTZ,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================
-- ASSIGNMENTS
-- =========================================
CREATE TABLE IF NOT EXISTS assignments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  position_id UUID REFERENCES positions(id) ON DELETE SET NULL,
  shift_id UUID REFERENCES shifts(id) ON DELETE SET NULL,

  override_start_time TIME,
  override_end_time TIME,
  override_break_end TIME,

  effective_from DATE NOT NULL,
  effective_to DATE,

  is_active BOOLEAN NOT NULL DEFAULT true,
  remarks TEXT,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_assignment_dates
    CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_assignments_one_active_per_employee
ON assignments (employee_id)
WHERE is_active = true;

-- =========================================
-- POLICY ASSIGNMENTS
-- =========================================
CREATE TABLE IF NOT EXISTS policy_assignments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  attendance_policy_id UUID NOT NULL REFERENCES attendance_policies(id) ON DELETE CASCADE,

  employee_id UUID REFERENCES users(id) ON DELETE CASCADE,
  department_id UUID REFERENCES departments(id) ON DELETE CASCADE,
  shift_id UUID REFERENCES shifts(id) ON DELETE CASCADE,

  effective_from DATE NOT NULL,
  effective_to DATE,
  is_active BOOLEAN NOT NULL DEFAULT true,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_policy_assignment_target
    CHECK (
      employee_id IS NOT NULL
      OR department_id IS NOT NULL
      OR shift_id IS NOT NULL
    ),

  CONSTRAINT chk_policy_assignment_dates
    CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

-- =========================================
-- HOLIDAYS
-- =========================================
CREATE TABLE IF NOT EXISTS holidays (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  date_from DATE NOT NULL,
  date_to DATE NOT NULL,
  name TEXT NOT NULL,
  holiday_type TEXT NOT NULL DEFAULT 'regular'
    CHECK (holiday_type IN ('regular', 'special', 'local', 'work_suspension')),
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  recurring BOOLEAN NOT NULL DEFAULT false,
  coverage TEXT NOT NULL DEFAULT 'whole_day'
    CHECK (coverage IN ('whole_day', 'am_only', 'pm_only')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_holidays_date_range CHECK (date_to >= date_from),
  CONSTRAINT uq_holidays_name_range UNIQUE (name, date_from, date_to)
);

CREATE TABLE IF NOT EXISTS holiday_default_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  country_code TEXT NOT NULL DEFAULT 'PH',
  year INTEGER NOT NULL,
  label TEXT NOT NULL,
  source TEXT,
  note TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT uq_holiday_default_templates_country_year UNIQUE (country_code, year)
);

CREATE TABLE IF NOT EXISTS holiday_default_template_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  template_id UUID NOT NULL REFERENCES holiday_default_templates(id) ON DELETE CASCADE,
  date_from DATE NOT NULL,
  date_to DATE NOT NULL,
  name TEXT NOT NULL,
  holiday_type TEXT NOT NULL DEFAULT 'regular'
    CHECK (holiday_type IN ('regular', 'special', 'local', 'work_suspension')),
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  recurring BOOLEAN NOT NULL DEFAULT false,
  coverage TEXT NOT NULL DEFAULT 'whole_day'
    CHECK (coverage IN ('whole_day', 'am_only', 'pm_only')),
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_holiday_default_template_items_date_range CHECK (date_to >= date_from),
  CONSTRAINT uq_holiday_default_template_items_row UNIQUE (template_id, name, date_from, date_to)
);

-- =========================================
-- LEAVE TYPES
-- =========================================
CREATE TABLE IF NOT EXISTS leave_types (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL UNIQUE,
  display_name TEXT,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  employee_can_file BOOLEAN NOT NULL DEFAULT true,
  admin_only BOOLEAN NOT NULL DEFAULT false,
  allows_past_dates BOOLEAN NOT NULL DEFAULT true,
  requires_attachment BOOLEAN NOT NULL DEFAULT false,
  requires_attachment_when_over_days NUMERIC,
  max_days NUMERIC,
  minimum_advance_days INTEGER,
  affects_dtr_normally BOOLEAN NOT NULL DEFAULT true,
  balance_ledger_type TEXT NOT NULL DEFAULT 'others',
  is_system BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed leave types (names must match Flutter LeaveType enum .value for API lookup).
INSERT INTO leave_types (name, description, is_active)
VALUES
  ('vacationLeave', 'Vacation Leave', true),
  ('mandatoryForcedLeave', 'Mandatory/Forced Leave', true),
  ('sickLeave', 'Sick Leave', true),
  ('maternityLeave', 'Maternity Leave', true),
  ('paternityLeave', 'Paternity Leave', true),
  ('specialPrivilegeLeave', 'Special Privilege Leave', true),
  ('soloParentLeave', 'Solo Parent Leave', true),
  ('studyLeave', 'Study Leave', true),
  ('tenDayVawcLeave', '10-Day VAWC Leave', true),
  ('rehabilitationPrivilege', 'Rehabilitation Privilege', true),
  ('specialLeaveBenefitsForWomen', 'Special Leave Benefits for Women', true),
  ('specialEmergencyCalamityLeave', 'Special Emergency (Calamity) Leave', true),
  ('adoptionLeave', 'Adoption Leave', true),
  ('others', 'Others', true)
ON CONFLICT (name) DO NOTHING;

UPDATE leave_types
SET display_name = COALESCE(NULLIF(display_name, ''), description, name),
    employee_can_file = CASE WHEN name = 'mandatoryForcedLeave' THEN false ELSE true END,
    admin_only = CASE WHEN name = 'mandatoryForcedLeave' THEN true ELSE false END,
    allows_past_dates = CASE WHEN name IN ('vacationLeave', 'specialPrivilegeLeave') THEN false ELSE true END,
    requires_attachment = CASE
      WHEN name IN (
        'maternityLeave',
        'paternityLeave',
        'soloParentLeave',
        'studyLeave',
        'tenDayVawcLeave',
        'rehabilitationPrivilege',
        'specialLeaveBenefitsForWomen',
        'specialEmergencyCalamityLeave',
        'adoptionLeave',
        'others'
      ) THEN true
      ELSE false
    END,
    requires_attachment_when_over_days = CASE WHEN name = 'sickLeave' THEN 5 ELSE NULL END,
    max_days = CASE
      WHEN name = 'mandatoryForcedLeave' THEN 5
      WHEN name = 'maternityLeave' THEN 105
      WHEN name = 'paternityLeave' THEN 7
      WHEN name = 'specialPrivilegeLeave' THEN 3
      WHEN name = 'soloParentLeave' THEN 7
      WHEN name = 'studyLeave' THEN 180
      WHEN name = 'tenDayVawcLeave' THEN 10
      WHEN name = 'rehabilitationPrivilege' THEN 180
      WHEN name = 'specialLeaveBenefitsForWomen' THEN 60
      WHEN name = 'specialEmergencyCalamityLeave' THEN 5
      ELSE NULL
    END,
    minimum_advance_days = CASE
      WHEN name IN ('vacationLeave', 'soloParentLeave', 'specialLeaveBenefitsForWomen') THEN 5
      WHEN name = 'specialPrivilegeLeave' THEN 7
      ELSE NULL
    END,
    affects_dtr_normally = true,
    is_system = name IN (
      'vacationLeave',
      'mandatoryForcedLeave',
      'sickLeave',
      'maternityLeave',
      'paternityLeave',
      'specialPrivilegeLeave',
      'soloParentLeave',
      'studyLeave',
      'tenDayVawcLeave',
      'rehabilitationPrivilege',
      'specialLeaveBenefitsForWomen',
      'specialEmergencyCalamityLeave',
      'adoptionLeave',
      'others'
    ),
    balance_ledger_type = CASE
      WHEN name = 'mandatoryForcedLeave' THEN 'vacationLeave'
      WHEN name IN (
        'vacationLeave',
        'sickLeave',
        'maternityLeave',
        'paternityLeave',
        'specialPrivilegeLeave',
        'soloParentLeave',
        'studyLeave',
        'tenDayVawcLeave',
        'rehabilitationPrivilege',
        'specialLeaveBenefitsForWomen',
        'specialEmergencyCalamityLeave',
        'adoptionLeave',
        'others'
      ) THEN name
      ELSE 'others'
    END;

-- =========================================
-- LEAVE REQUESTS
-- =========================================
CREATE TABLE IF NOT EXISTS leave_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- user_id mirrors employee_id. Both are written on every INSERT.
  -- NOT NULL enforced here so fresh installs match the Phase 3 migration constraint.
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  leave_type_id UUID REFERENCES leave_types(id) ON DELETE SET NULL,

  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  total_days NUMERIC(5,2),
  number_of_days NUMERIC(5,2),

  reason TEXT,
  -- Supporting document attachment (PDF, JPG, JPEG, PNG)
  attachment_name TEXT,
  attachment_path TEXT,
  attachment_mime_type TEXT,
  attachment_uploaded_at TIMESTAMPTZ,
  -- Flexible payload for form fields (office_department, position_title, commutation, etc.)
  details JSONB,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN (
      'draft',
      'pending',                       -- legacy alias for pending_hr
      'pending_department_head',       -- awaiting department head approval
      'pending_hr',                    -- awaiting HR/admin final approval
      'rejected_by_department_head',   -- department head rejected
      'rejected_by_hr',                -- HR/admin rejected
      'returned',                      -- sent back to employee for correction
      'approved',                      -- final approval by HR/admin
      'rejected',                      -- legacy single-stage rejection
      'cancelled'                      -- employee cancelled
    )),

  reviewer_id UUID REFERENCES users(id) ON DELETE SET NULL,
  reviewer_remarks TEXT,
  reviewed_at TIMESTAMPTZ,

  approved_by UUID REFERENCES users(id) ON DELETE SET NULL,
  approved_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_leave_dates CHECK (end_date >= start_date),
  CONSTRAINT chk_leave_total_days CHECK (
    (total_days IS NULL OR total_days >= 0)
    AND (number_of_days IS NULL OR number_of_days >= 0)
  )
);

-- =========================================
-- LEAVE BALANCES
-- =========================================
CREATE TABLE IF NOT EXISTS leave_balances (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- leave_type must match a value in leave_types(name).
  -- FK enforces referential integrity; CHECK is a belt-and-suspenders guard.
  leave_type TEXT NOT NULL,
  earned_days NUMERIC(8,2) NOT NULL DEFAULT 0 CHECK (earned_days >= 0),
  used_days NUMERIC(8,2) NOT NULL DEFAULT 0 CHECK (used_days >= 0),
  pending_days NUMERIC(8,2) NOT NULL DEFAULT 0 CHECK (pending_days >= 0),
  adjusted_days NUMERIC(8,2) NOT NULL DEFAULT 0,
  as_of_date DATE,
  last_accrual_date DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, leave_type),
  CONSTRAINT fk_leave_balances_leave_type
    FOREIGN KEY (leave_type) REFERENCES leave_types(name)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
    DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT chk_leave_balances_leave_type CHECK (
    leave_type IN (
      'vacationLeave',
      'mandatoryForcedLeave',
      'sickLeave',
      'maternityLeave',
      'paternityLeave',
      'specialPrivilegeLeave',
      'soloParentLeave',
      'studyLeave',
      'tenDayVawcLeave',
      'rehabilitationPrivilege',
      'specialLeaveBenefitsForWomen',
      'specialEmergencyCalamityLeave',
      'adoptionLeave',
      'others'
    )
  )
);
CREATE INDEX IF NOT EXISTS idx_leave_balances_user_id ON leave_balances(user_id);

-- =========================================
-- LEAVE REQUEST HISTORY (AUDIT TRAIL)
-- =========================================
CREATE TABLE IF NOT EXISTS leave_request_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  leave_request_id UUID NOT NULL REFERENCES leave_requests(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  from_status TEXT,
  to_status TEXT NOT NULL,
  acted_by UUID REFERENCES users(id) ON DELETE SET NULL,
  acted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  remarks TEXT,
  metadata_json JSONB
);
CREATE INDEX IF NOT EXISTS idx_leave_request_history_leave_request_id
  ON leave_request_history(leave_request_id);

-- =========================================
-- LEAVE BALANCE LEDGER (append-only audit of bucket changes)
-- =========================================
-- Distinct from leave_request_history (workflow). Records earned/pending/used/adjusted movements.
CREATE TABLE IF NOT EXISTS leave_balance_ledger (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  leave_type TEXT NOT NULL,
  action TEXT NOT NULL,
  affected_bucket TEXT NOT NULL,
  days_changed NUMERIC NOT NULL DEFAULT 0,
  old_value NUMERIC,
  new_value NUMERIC,
  related_leave_request_id UUID REFERENCES leave_requests(id) ON DELETE SET NULL,
  actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  actor_kind TEXT NOT NULL DEFAULT 'user',
  remarks TEXT,
  metadata_json JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_leave_balance_ledger_user_created
  ON leave_balance_ledger(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_leave_balance_ledger_action
  ON leave_balance_ledger(action);
CREATE INDEX IF NOT EXISTS idx_leave_balance_ledger_leave_request
  ON leave_balance_ledger(related_leave_request_id)
  WHERE related_leave_request_id IS NOT NULL;

-- =========================================
-- IN-APP NOTIFICATIONS (DTR / leave / future modules)
-- =========================================
CREATE TABLE IF NOT EXISTS user_notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category TEXT NOT NULL DEFAULT 'general',
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  read_at TIMESTAMPTZ,
  reference_type TEXT,
  reference_id UUID,
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_notifications_user_id ON user_notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_user_notifications_read_at ON user_notifications(user_id, read_at);
CREATE INDEX IF NOT EXISTS idx_user_notifications_created_at ON user_notifications(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS user_push_tokens (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'unknown',
  device_id TEXT,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_push_tokens_token_unique
  ON user_push_tokens(token);

CREATE INDEX IF NOT EXISTS idx_user_push_tokens_user_active
  ON user_push_tokens(user_id)
  WHERE revoked_at IS NULL;

-- =========================================
-- LOCATOR / PASS SLIP / WFH REQUESTS
-- =========================================
CREATE TABLE IF NOT EXISTS locator_request_types (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  code TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL,
  short_label TEXT NOT NULL,
  location_label TEXT NOT NULL DEFAULT 'Office / Destination',
  location_hint TEXT NOT NULL DEFAULT 'Enter office or destination',
  dtr_slot_label TEXT NOT NULL DEFAULT 'On Field',
  dtr_print_label TEXT NOT NULL DEFAULT 'ON FIELD',
  requires_attachment BOOLEAN NOT NULL DEFAULT false,
  coverage_mode TEXT NOT NULL DEFAULT 'manual'
    CONSTRAINT locator_request_types_coverage_mode_check
    CHECK (coverage_mode IN ('manual', 'wfh')),
  is_active BOOLEAN NOT NULL DEFAULT true,
  is_system BOOLEAN NOT NULL DEFAULT false,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO locator_request_types (
  code, label, short_label, location_label, location_hint,
  dtr_slot_label, dtr_print_label, requires_attachment,
  coverage_mode, is_active, is_system, sort_order
) VALUES
  ('locator', 'Locator / Official Business', 'Locator',
   'Office / Destination', 'Enter office or destination',
   'On Field', 'ON FIELD', false, 'manual', true, true, 10),
  ('pass_slip', 'Pass Slip', 'Pass Slip',
   'Destination / Location', 'Enter destination or location',
   'Pass Slip', 'PASS SLIP', false, 'manual', true, true, 20),
  ('work_from_home', 'Work From Home', 'WFH',
   'Work Location', 'Enter work location',
   'WFH', 'WFH', false, 'wfh', true, true, 30)
ON CONFLICT (code) DO UPDATE SET
  is_system = true,
  updated_at = now();

CREATE TABLE IF NOT EXISTS locator_slips (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  slip_date DATE NOT NULL,
  am_in BOOLEAN NOT NULL DEFAULT false,
  am_out BOOLEAN NOT NULL DEFAULT false,
  pm_in BOOLEAN NOT NULL DEFAULT false,
  pm_out BOOLEAN NOT NULL DEFAULT false,
  request_type TEXT NOT NULL DEFAULT 'locator',
  office TEXT NOT NULL,
  reason TEXT NOT NULL,
  attachment_name TEXT,
  attachment_path TEXT,
  attachment_mime_type TEXT,
  attachment_uploaded_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending_department_head'
    CHECK (status IN (
      'pending',
      'pending_department_head',
      'pending_hr',
      'approved',
      'rejected_by_department_head',
      'rejected_by_hr',
      'cancelled'
    )),
  dept_head_reviewer_id UUID REFERENCES users(id) ON DELETE SET NULL,
  dept_head_reviewed_at TIMESTAMPTZ,
  dept_head_remarks TEXT,
  hr_reviewer_id UUID REFERENCES users(id) ON DELETE SET NULL,
  hr_reviewed_at TIMESTAMPTZ,
  hr_remarks TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_locator_slips_employee
  ON locator_slips(employee_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_locator_slips_status
  ON locator_slips(status, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_locator_slips_department
  ON locator_slips(department_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_locator_slips_date
  ON locator_slips(slip_date DESC);
CREATE INDEX IF NOT EXISTS idx_locator_slips_request_type
  ON locator_slips(request_type);
CREATE INDEX IF NOT EXISTS idx_locator_request_types_active
  ON locator_request_types(is_active, sort_order, label);

-- =========================================
-- DTR ASSISTANT FEEDBACK
-- =========================================
CREATE TABLE IF NOT EXISTS dtr_assistant_feedback (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL,
  message_id UUID NOT NULL,
  rating TEXT NOT NULL
    CONSTRAINT dtr_assistant_feedback_rating_check
    CHECK (rating IN ('up', 'down')),
  intent TEXT,
  provider TEXT,
  model TEXT,
  model_profile TEXT,
  prompt_preview TEXT,
  prompt_hash TEXT,
  intent_confidence NUMERIC(5,4),
  intent_source TEXT,
  content_preview TEXT,
  comment TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, message_id)
);

CREATE INDEX IF NOT EXISTS idx_dtr_assistant_feedback_user_created
  ON dtr_assistant_feedback(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_dtr_assistant_feedback_rating_created
  ON dtr_assistant_feedback(rating, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_dtr_assistant_feedback_prompt_hash
  ON dtr_assistant_feedback(prompt_hash)
  WHERE prompt_hash IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_dtr_assistant_feedback_intent_source_created
  ON dtr_assistant_feedback(intent, intent_source, created_at DESC);

-- =========================================
-- BIOMETRIC ATTENDANCE LOGS (raw import from .dat files)
-- =========================================
CREATE TABLE IF NOT EXISTS biometric_attendance_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  biometric_user_id TEXT NOT NULL,
  logged_at TIMESTAMPTZ NOT NULL,
  verify_code TEXT,
  punch_code TEXT,
  work_code TEXT,
  raw_line TEXT NOT NULL,
  source_file_name TEXT,
  imported_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT uq_biometric_attendance_logs_user_time UNIQUE (biometric_user_id, logged_at)
);

-- =========================================
-- RAW DTR LOGS
-- =========================================
CREATE TABLE IF NOT EXISTS dtr_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_ref_id UUID REFERENCES biometric_devices(id) ON DELETE SET NULL,

  local_uuid TEXT UNIQUE,
  biometric_user_id TEXT,

  log_time TIMESTAMPTZ NOT NULL,

  log_type TEXT NOT NULL
    CHECK (log_type IN ('time_in', 'time_out', 'break_in', 'break_out')),

  source TEXT NOT NULL DEFAULT 'biometric'
    CHECK (source IN ('biometric', 'manual', 'mobile', 'import')),

  sync_status TEXT NOT NULL DEFAULT 'synced'
    CHECK (sync_status IN ('pending', 'synced', 'failed')),

  remarks TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================
-- DAILY DTR SUMMARY
-- =========================================
CREATE TABLE IF NOT EXISTS dtr_daily_summary (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  attendance_date DATE NOT NULL,

  assignment_id UUID REFERENCES assignments(id) ON DELETE SET NULL,
  shift_id UUID REFERENCES shifts(id) ON DELETE SET NULL,
  attendance_policy_id UUID REFERENCES attendance_policies(id) ON DELETE SET NULL,
  holiday_id UUID REFERENCES holidays(id) ON DELETE SET NULL,
  leave_request_id UUID REFERENCES leave_requests(id) ON DELETE SET NULL,

  time_in TIMESTAMPTZ,
  time_out TIMESTAMPTZ,
  break_in TIMESTAMPTZ,
  break_out TIMESTAMPTZ,

  late_minutes INT NOT NULL DEFAULT 0 CHECK (late_minutes >= 0),
  undertime_minutes INT NOT NULL DEFAULT 0 CHECK (undertime_minutes >= 0),
  overtime_minutes INT NOT NULL DEFAULT 0 CHECK (overtime_minutes >= 0),
  total_hours NUMERIC(6,2) NOT NULL DEFAULT 0 CHECK (total_hours >= 0),

  status TEXT NOT NULL DEFAULT 'incomplete'
    CHECK (status IN (
      'present',
      'late',
      'absent',
      'on_leave',
      'holiday',
      'rest_day',
      'incomplete'
    )),
  pm_status TEXT CHECK (pm_status IS NULL OR pm_status IN ('present', 'late')),

  source TEXT NOT NULL DEFAULT 'system'
    CHECK (source IN ('system', 'manual', 'adjusted')),

  remarks TEXT,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT uq_dtr_daily_summary_employee_date UNIQUE (employee_id, attendance_date)
);

-- =========================================
-- DTR CORRECTION REQUESTS
-- =========================================
CREATE TABLE IF NOT EXISTS dtr_corrections (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  attendance_date DATE NOT NULL,

  requested_time_in TIMESTAMPTZ,
  requested_time_out TIMESTAMPTZ,
  requested_break_in TIMESTAMPTZ,
  requested_break_out TIMESTAMPTZ,

  reason TEXT NOT NULL,

  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),

  reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  review_notes TEXT,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================
-- OVERTIME REQUESTS
-- =========================================
CREATE TABLE IF NOT EXISTS overtime_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  ot_date DATE NOT NULL,
  time_start TIME NOT NULL,
  time_end TIME NOT NULL,
  total_hours NUMERIC(5,2) NOT NULL CHECK (total_hours > 0),

  reason TEXT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),

  approved_by UUID REFERENCES users(id) ON DELETE SET NULL,
  approved_at TIMESTAMPTZ,
  review_notes TEXT,

  added_to_payroll BOOLEAN NOT NULL DEFAULT false,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================
-- AUDIT LOGS
-- =========================================
CREATE TABLE IF NOT EXISTS audit_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id UUID,
  details TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================
-- L&D — RSP SAVED FORMS
-- =========================================
CREATE TABLE IF NOT EXISTS bi_form_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  applicant_name TEXT NOT NULL,
  applicant_department TEXT,
  applicant_position TEXT,
  position_applied_for TEXT,
  respondent_name TEXT NOT NULL,
  respondent_position TEXT,
  respondent_relationship TEXT NOT NULL DEFAULT 'supervisor'
    CHECK (respondent_relationship IN ('supervisor', 'peer', 'subordinate')),
  rating_1 INT,
  rating_2 INT,
  rating_3 INT,
  rating_4 INT,
  rating_5 INT,
  rating_6 INT,
  rating_7 INT,
  rating_8 INT,
  rating_9 INT,
  functional_areas JSONB DEFAULT '[]'::JSONB,
  other_functional_area TEXT,
  performance_3_years TEXT,
  challenges_coping TEXT,
  compliance_attendance TEXT,
  other_relevant_information TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS performance_evaluation_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  applicant_name TEXT,
  functional_areas JSONB DEFAULT '[]'::JSONB,
  other_functional_area TEXT,
  performance_3_years TEXT,
  challenges_coping TEXT,
  compliance_attendance TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS training_need_analysis_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  cy_year TEXT,
  department TEXT,
  rows JSONB DEFAULT '[]'::JSONB,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS action_brainstorming_coaching_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  department TEXT,
  date TEXT,
  rows JSONB DEFAULT '[]'::JSONB,
  certified_by TEXT,
  certification_date TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS turn_around_time_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  position TEXT,
  office TEXT,
  no_of_vacant_position TEXT,
  date_of_publication TEXT,
  end_search TEXT,
  qs TEXT,
  applicants JSONB DEFAULT '[]'::JSONB,
  prepared_by_name TEXT,
  prepared_by_title TEXT,
  noted_by_name TEXT,
  noted_by_title TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS idp_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT,
  position TEXT,
  category TEXT,
  division TEXT,
  department TEXT,
  education TEXT,
  experience TEXT,
  training TEXT,
  eligibility TEXT,
  significant_accomplishments TEXT,
  target_position_1 TEXT,
  target_position_2 TEXT,
  avg_rating TEXT,
  opcr TEXT,
  ipcr TEXT,
  performance_rating TEXT,
  competency_description TEXT,
  competence_rating TEXT,
  succession_priority_score TEXT,
  succession_priority_rating TEXT,
  development_plan_rows JSONB DEFAULT '[]'::JSONB,
  prepared_by TEXT,
  reviewed_by TEXT,
  noted_by TEXT,
  approved_by TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- =========================================
-- L&D — TRAINING DAILY REPORTS
-- =========================================
CREATE TABLE IF NOT EXISTS training_daily_reports (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  attachment_path TEXT,
  attachment_name TEXT,
  attachment_type TEXT,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  status TEXT NOT NULL DEFAULT 'submitted'
    CHECK (status IN ('submitted', 'seen', 'reviewed', 'approved', 'needs_revision')),
  seen_by_admin UUID REFERENCES users(id) ON DELETE SET NULL,
  seen_at TIMESTAMPTZ,
  reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS training_report_attachments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  report_id UUID NOT NULL REFERENCES training_daily_reports(id) ON DELETE CASCADE,
  file_path TEXT NOT NULL,
  file_name TEXT,
  mime_type TEXT,
  uploaded_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================
-- L&D — TRAINING REQUIREMENTS (pre / post)
-- =========================================
CREATE TABLE IF NOT EXISTS ld_training_requirement_records (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  training_title TEXT,
  doc_invitation_letter_path TEXT,
  doc_invitation_letter_name TEXT,
  doc_lap_path TEXT,
  doc_lap_name TEXT,
  doc_training_certificate_path TEXT,
  doc_training_certificate_name TEXT,
  pre_requirements_approved BOOLEAN NOT NULL DEFAULT FALSE,
  post_requirements_approved BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_ld_training_requirement_employee UNIQUE (employee_id)
);

-- =========================================
-- RSP — RECRUITMENT
-- =========================================
CREATE TABLE IF NOT EXISTS recruitment_applications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  first_name TEXT,
  middle_name TEXT,
  last_name TEXT,
  suffix TEXT,
  sex TEXT,
  course TEXT,
  address TEXT,
  age TEXT,
  civil_status TEXT,
  full_name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT,
  resume_notes TEXT,
  position_applied_for TEXT,
  attachment_path TEXT,
  attachment_name TEXT,
  doc_application_letter_path TEXT,
  doc_application_letter_name TEXT,
  doc_resume_path TEXT,
  doc_resume_name TEXT,
  doc_tor_path TEXT,
  doc_tor_name TEXT,
  doc_eligibility_trainings_path TEXT,
  doc_eligibility_trainings_name TEXT,
  doc_medical_certificate_path TEXT,
  doc_medical_certificate_name TEXT,
  doc_drug_test_path TEXT,
  doc_drug_test_name TEXT,
  doc_nbi_clearance_path TEXT,
  doc_nbi_clearance_name TEXT,
  final_requirements_approved BOOLEAN NOT NULL DEFAULT FALSE,
  orientation_at TIMESTAMPTZ,
  orientation_attended BOOLEAN,
  status TEXT NOT NULL DEFAULT 'submitted'
    CHECK (
      status IN (
        'submitted',
        'document_approved',
        'document_declined',
        'exam_taken',
        'passed',
        'failed',
        'registered'
      )
    ),
  final_interview_at TIMESTAMPTZ,
  final_interview_passed BOOLEAN,
  hired_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  hr_account_setup_done BOOLEAN NOT NULL DEFAULT FALSE,
  hire_credentials_email_sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS recruitment_exam_results (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  application_id UUID NOT NULL REFERENCES recruitment_applications(id) ON DELETE CASCADE,
  score_percent NUMERIC(5,2) NOT NULL,
  passed BOOLEAN NOT NULL,
  answers_json JSONB,
  submitted_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS recruitment_exam_questions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  exam_type TEXT NOT NULL,
  sort_order INT NOT NULL,
  question_text TEXT NOT NULL,
  options_json JSONB,
  correct_index INT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS job_vacancy_announcement (
  id TEXT PRIMARY KEY DEFAULT 'default',
  has_vacancies BOOLEAN DEFAULT true,
  headline TEXT,
  body TEXT,
  vacancies JSONB DEFAULT '[]'::JSONB,
  updated_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO job_vacancy_announcement (id, has_vacancies, headline, body)
VALUES ('default', true, NULL, NULL)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS selection_lineup_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  date TEXT,
  name_of_agency_office TEXT,
  vacant_position TEXT,
  item_no TEXT,
  applicants JSONB DEFAULT '[]',
  prepared_by_name TEXT,
  prepared_by_title TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS computation_of_points_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  date TEXT,
  position_level TEXT,
  position TEXT,
  salary_grade TEXT,
  rate TEXT,
  office TEXT,
  min_education TEXT,
  min_training TEXT,
  min_experience TEXT,
  min_eligibility TEXT,
  candidates JSONB DEFAULT '[]',
  prepared_by_name TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS work_experience_sheet_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  position_applied_for TEXT,
  department TEXT,
  min_education TEXT,
  min_experience TEXT,
  min_training TEXT,
  min_eligibility TEXT,
  job_description_last_work TEXT,
  applicant_name TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS applicants_profile_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  position_applied_for TEXT,
  minimum_requirements TEXT,
  date_of_posting TEXT,
  closing_date TEXT,
  applicants JSONB DEFAULT '[]',
  prepared_by TEXT,
  checked_by TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS comparative_assessment_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  position_to_be_filled TEXT,
  min_req_education TEXT,
  min_req_experience TEXT,
  min_req_eligibility TEXT,
  min_req_training TEXT,
  candidates JSONB DEFAULT '[]',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS promotion_certification_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  position_for_promotion TEXT,
  candidates JSONB DEFAULT '[]',
  date_day TEXT,
  date_month TEXT,
  date_year TEXT,
  signatory_name TEXT,
  signatory_title TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS recruitment_exam_time_limits (
  exam_type TEXT PRIMARY KEY,
  time_limit_seconds INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO recruitment_exam_time_limits (exam_type, time_limit_seconds)
VALUES
  ('general', 2700),
  ('math', 2700),
  ('general_info', 600)
ON CONFLICT (exam_type) DO NOTHING;

-- One exam result row per application (idempotent for existing DBs).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_recruitment_exam_results_application'
  ) THEN
    ALTER TABLE recruitment_exam_results
      ADD CONSTRAINT uq_recruitment_exam_results_application
      UNIQUE (application_id);
  END IF;
END $$;

-- =========================================
-- DOCUTRACKER
-- =========================================
CREATE TABLE IF NOT EXISTS docutracker_roles (
  role_id TEXT PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO docutracker_roles(role_id)
VALUES ('admin'), ('hr'), ('supervisor'), ('employee')
ON CONFLICT (role_id) DO NOTHING;

CREATE TABLE IF NOT EXISTS docutracker_role_aliases (
  alias TEXT PRIMARY KEY,
  role_id TEXT NOT NULL REFERENCES docutracker_roles(role_id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO docutracker_role_aliases(alias, role_id)
VALUES ('hr_staff', 'hr'), ('dept_head', 'supervisor')
ON CONFLICT (alias) DO NOTHING;

CREATE TABLE IF NOT EXISTS docutracker_documents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_number TEXT UNIQUE,
  document_type TEXT NOT NULL DEFAULT 'memo',
  title TEXT NOT NULL,
  description TEXT,
  source_module TEXT,
  source_table TEXT,
  source_record_id UUID,
  source_title TEXT,
  file_path TEXT,
  file_name TEXT,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  current_holder_id UUID REFERENCES users(id) ON DELETE SET NULL,
  current_step INT DEFAULT 1,
  workflow_version INT,
  status TEXT NOT NULL DEFAULT 'pending',
  sent_time TIMESTAMPTZ,
  deadline_time TIMESTAMPTZ,
  reviewed_time TIMESTAMPTZ,
  escalation_level INT NOT NULL DEFAULT 0,
  needs_admin_intervention BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT docutracker_documents_status_check_prod_v2
    CHECK (status IN (
      'pending', 'in_review', 'approved', 'rejected', 'returned',
      'overdue', 'escalated', 'cancelled'
    )),
  CONSTRAINT docutracker_documents_current_step_check_prod_v1
    CHECK (current_step IS NULL OR current_step >= 1),
  CONSTRAINT docutracker_documents_escalation_level_check_prod_v1
    CHECK (escalation_level >= 0)
);

CREATE TABLE IF NOT EXISTS docutracker_routing_configs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_type TEXT NOT NULL UNIQUE,
  steps JSONB NOT NULL DEFAULT '[]',
  review_deadline_hours INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT docutracker_routing_configs_steps_is_array_check_prod_v1
    CHECK (jsonb_typeof(steps) = 'array'),
  CONSTRAINT docutracker_routing_configs_review_deadline_hours_check_prod_v1
    CHECK (review_deadline_hours > 0)
);

CREATE TABLE IF NOT EXISTS docutracker_routing_config_versions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_type TEXT NOT NULL,
  version INT NOT NULL,
  steps JSONB NOT NULL,
  review_deadline_hours INT NOT NULL DEFAULT 1,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (document_type, version)
);

CREATE TABLE IF NOT EXISTS docutracker_workflow_steps (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_type TEXT NOT NULL,
  workflow_version INT NOT NULL DEFAULT 1,
  step_order INT NOT NULL CHECK (step_order > 0),
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  label TEXT,
  enabled BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (document_type, workflow_version, step_order)
);

CREATE TABLE IF NOT EXISTS docutracker_workflow_step_assignees (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  step_id UUID NOT NULL REFERENCES docutracker_workflow_steps(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  is_primary BOOLEAN NOT NULL DEFAULT false,
  backup_rank INT NULL CHECK (backup_rank IS NULL OR backup_rank > 0),
  is_enabled BOOLEAN NOT NULL DEFAULT true,
  allowed_actions TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (step_id, user_id),
  CHECK (NOT is_primary OR backup_rank IS NULL),
  CHECK (is_primary OR backup_rank IS NOT NULL),
  UNIQUE (step_id, backup_rank),
  CHECK (allowed_actions <@ ARRAY['approve','forward','reject','return']::TEXT[])
);

CREATE TABLE IF NOT EXISTS docutracker_document_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  action TEXT,
  actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
  actor_name TEXT,
  from_step INT,
  to_step INT,
  from_status TEXT,
  to_status TEXT,
  remarks TEXT,
  is_overdue_log BOOLEAN DEFAULT false,
  is_escalation_log BOOLEAN DEFAULT false,
  escalation_level INT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS docutracker_routing_records (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  step_order INT NOT NULL,
  assignee_id UUID REFERENCES users(id) ON DELETE SET NULL,
  sent_time TIMESTAMPTZ,
  deadline_time TIMESTAMPTZ,
  reviewed_time TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending',
  remarks TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT docutracker_routing_records_status_check_prod_v2
    CHECK (status IN (
      'pending', 'in_review', 'approved', 'rejected', 'returned',
      'overdue', 'escalated', 'cancelled'
    )),
  CONSTRAINT docutracker_routing_records_step_order_check_prod_v1
    CHECK (step_order >= 1)
);

CREATE TABLE IF NOT EXISTS docutracker_routing_record_assignees (
  routing_record_id UUID NOT NULL REFERENCES docutracker_routing_records(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (routing_record_id, user_id)
);

CREATE TABLE IF NOT EXISTS docutracker_notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL
    CHECK (type IN ('assigned', 'deadline_near', 'overdue', 'escalated', 'returned', 'rejected')),
  title TEXT,
  body TEXT,
  read BOOLEAN DEFAULT false,
  event_key TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS docutracker_permissions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  role_id TEXT REFERENCES docutracker_roles(role_id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  document_type TEXT NOT NULL DEFAULT '*',
  action TEXT NOT NULL,
  granted BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT docutracker_permissions_scope_check_v1
    CHECK ((user_id IS NOT NULL) <> (role_id IS NOT NULL)),
  CONSTRAINT docutracker_permissions_action_check_prod_v1
    CHECK (action IN (
      'view', 'create', 'create_draft', 'submit', 'download', 'edit', 'delete',
      'forward', 'approve', 'reject', 'return'
    ))
);

CREATE TABLE IF NOT EXISTS docutracker_escalation_configs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_type TEXT NOT NULL,
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  escalation_target_role TEXT,
  escalation_delay_minutes INT NOT NULL DEFAULT 60,
  max_escalation_level INT NOT NULL DEFAULT 3,
  notify_original_sender BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT docutracker_escalation_configs_escalation_delay_minutes_check
    CHECK (escalation_delay_minutes > 0),
  CONSTRAINT docutracker_escalation_configs_max_escalation_level_check
    CHECK (max_escalation_level >= 1)
);

CREATE TABLE IF NOT EXISTS docutracker_transition_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  document_id UUID NOT NULL REFERENCES docutracker_documents(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
  response_payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (document_id, action, idempotency_key)
);

CREATE TABLE IF NOT EXISTS docutracker_document_number_seq (
  year INT PRIMARY KEY,
  last_value BIGINT NOT NULL DEFAULT 0
);

-- DocuTracker indexes
CREATE INDEX IF NOT EXISTS idx_docutracker_documents_created_by ON docutracker_documents(created_by);
CREATE INDEX IF NOT EXISTS idx_docutracker_documents_current_holder ON docutracker_documents(current_holder_id);
CREATE INDEX IF NOT EXISTS idx_docutracker_documents_status ON docutracker_documents(status);
CREATE INDEX IF NOT EXISTS idx_docutracker_documents_doc_type ON docutracker_documents(document_type);
CREATE INDEX IF NOT EXISTS idx_docutracker_documents_type_status_created
  ON docutracker_documents(document_type, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_docutracker_documents_holder_status_deadline
  ON docutracker_documents(current_holder_id, status, deadline_time);
CREATE INDEX IF NOT EXISTS idx_docutracker_documents_deadline_active
  ON docutracker_documents(deadline_time)
  WHERE status IN ('pending', 'in_review', 'escalated', 'overdue');

CREATE INDEX IF NOT EXISTS idx_docutracker_routing_config_versions_type_version_desc
  ON docutracker_routing_config_versions(document_type, version DESC);

CREATE INDEX IF NOT EXISTS idx_docutracker_workflow_steps_type_version
  ON docutracker_workflow_steps(document_type, workflow_version);
CREATE INDEX IF NOT EXISTS idx_docutracker_workflow_steps_department
  ON docutracker_workflow_steps(department_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_step_assignees_one_primary_per_step
  ON docutracker_workflow_step_assignees(step_id)
  WHERE is_primary = true;
CREATE INDEX IF NOT EXISTS idx_docutracker_step_assignees_user
  ON docutracker_workflow_step_assignees(user_id);
CREATE INDEX IF NOT EXISTS idx_docutracker_step_assignees_step_enabled
  ON docutracker_workflow_step_assignees(step_id)
  WHERE is_enabled = true;

CREATE INDEX IF NOT EXISTS idx_docutracker_history_document_id ON docutracker_document_history(document_id);
CREATE INDEX IF NOT EXISTS idx_docutracker_history_document_created_desc
  ON docutracker_document_history(document_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_routing_records_unique_step
  ON docutracker_routing_records(document_id, step_order);
CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_routing_records_one_active_per_doc
  ON docutracker_routing_records(document_id)
  WHERE status IN ('pending', 'in_review', 'escalated', 'overdue');
CREATE INDEX IF NOT EXISTS idx_docutracker_routing_records_assignee_status_deadline
  ON docutracker_routing_records(assignee_id, status, deadline_time);
CREATE INDEX IF NOT EXISTS idx_docutracker_routing_records_document_step
  ON docutracker_routing_records(document_id, step_order);

CREATE INDEX IF NOT EXISTS idx_docutracker_routing_record_assignees_user
  ON docutracker_routing_record_assignees(user_id);

CREATE INDEX IF NOT EXISTS idx_docutracker_notifications_user_id ON docutracker_notifications(user_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_notifications_event_key_unique
  ON docutracker_notifications(document_id, user_id, type, event_key)
  WHERE event_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_docutracker_notifications_user_read_created
  ON docutracker_notifications(user_id, read, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_permissions_user_unique
  ON docutracker_permissions(user_id, document_type, action)
  WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_docutracker_permissions_role_unique
  ON docutracker_permissions(role_id, document_type, action)
  WHERE role_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_docutracker_permissions_user_lookup
  ON docutracker_permissions(user_id, document_type, action)
  WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_docutracker_permissions_role_lookup
  ON docutracker_permissions(role_id, document_type, action)
  WHERE role_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_docutracker_transition_requests_lookup
  ON docutracker_transition_requests(document_id, action, idempotency_key);

-- DocuTracker functions
CREATE OR REPLACE FUNCTION docutracker_normalize_role(p_role_id TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(btrim(coalesce(p_role_id, '')))
    WHEN '' THEN ''
    WHEN 'hr_staff' THEN 'hr'
    WHEN 'dept_head' THEN 'supervisor'
    ELSE lower(btrim(coalesce(p_role_id, '')))
  END
$$;

CREATE OR REPLACE FUNCTION docutracker_has_permission(
  p_user_id UUID,
  p_role_id TEXT,
  p_document_type TEXT,
  p_action TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
WITH args AS (
  SELECT
    p_user_id AS user_id,
    docutracker_normalize_role(p_role_id) AS role_id,
    p_document_type AS document_type,
    p_action AS action
),
candidates AS (
  SELECT 1 AS prio, p.granted
  FROM docutracker_permissions p, args a
  WHERE p.user_id = a.user_id
    AND p.role_id IS NULL
    AND p.document_type = a.document_type
    AND p.action = a.action

  UNION ALL
  SELECT 2 AS prio, p.granted
  FROM docutracker_permissions p, args a
  WHERE p.user_id = a.user_id
    AND p.role_id IS NULL
    AND p.document_type = '*'
    AND p.action = a.action

  UNION ALL
  SELECT 3 AS prio, p.granted
  FROM docutracker_permissions p, args a
  WHERE p.user_id IS NULL
    AND p.role_id = a.role_id
    AND p.document_type = a.document_type
    AND p.action = a.action

  UNION ALL
  SELECT 4 AS prio, p.granted
  FROM docutracker_permissions p, args a
  WHERE p.user_id IS NULL
    AND p.role_id = a.role_id
    AND p.document_type = '*'
    AND p.action = a.action
)
SELECT COALESCE(
  (SELECT granted FROM candidates ORDER BY prio LIMIT 1),
  false
);
$$;

CREATE OR REPLACE FUNCTION docutracker_permission_explain(
  p_user_id UUID,
  p_role_id TEXT,
  p_document_type TEXT,
  p_action TEXT
)
RETURNS TABLE (
  granted BOOLEAN,
  source TEXT,
  matched_document_type TEXT
)
LANGUAGE sql
STABLE
AS $$
WITH args AS (
  SELECT
    p_user_id AS user_id,
    docutracker_normalize_role(p_role_id) AS role_id,
    p_document_type AS document_type,
    p_action AS action
),
matches AS (
  SELECT 1 AS prio, p.granted, 'user_override'::text AS source, p.document_type AS matched_document_type
  FROM docutracker_permissions p, args a
  WHERE p.user_id = a.user_id
    AND p.role_id IS NULL
    AND p.document_type = a.document_type
    AND p.action = a.action

  UNION ALL
  SELECT 2 AS prio, p.granted, 'user_override'::text AS source, p.document_type AS matched_document_type
  FROM docutracker_permissions p, args a
  WHERE p.user_id = a.user_id
    AND p.role_id IS NULL
    AND p.document_type = '*'
    AND p.action = a.action

  UNION ALL
  SELECT 3 AS prio, p.granted, 'role_baseline'::text AS source, p.document_type AS matched_document_type
  FROM docutracker_permissions p, args a
  WHERE p.user_id IS NULL
    AND p.role_id = a.role_id
    AND p.document_type = a.document_type
    AND p.action = a.action

  UNION ALL
  SELECT 4 AS prio, p.granted, 'role_baseline'::text AS source, p.document_type AS matched_document_type
  FROM docutracker_permissions p, args a
  WHERE p.user_id IS NULL
    AND p.role_id = a.role_id
    AND p.document_type = '*'
    AND p.action = a.action
)
SELECT
  COALESCE(m.granted, false) AS granted,
  COALESCE(m.source, 'default_deny') AS source,
  m.matched_document_type
FROM (SELECT * FROM matches ORDER BY prio LIMIT 1) m;
$$;

CREATE OR REPLACE FUNCTION docutracker_next_document_number()
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
  y INT := EXTRACT(YEAR FROM now())::INT;
  v BIGINT;
BEGIN
  INSERT INTO docutracker_document_number_seq(year, last_value)
  VALUES (y, 0)
  ON CONFLICT (year) DO NOTHING;

  UPDATE docutracker_document_number_seq
  SET last_value = last_value + 1
  WHERE year = y
  RETURNING last_value INTO v;

  RETURN format('DOC-%s-%s', y, lpad(v::TEXT, 6, '0'));
END $$;

CREATE OR REPLACE FUNCTION docutracker_documents_set_doc_number()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.document_number IS NULL OR btrim(NEW.document_number) = '' THEN
    NEW.document_number := docutracker_next_document_number();
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION docutracker_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION docutracker_enforce_step_assignees_invariants()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  sid uuid;
  enabled_count int;
  enabled_primary_count int;
BEGIN
  sid := COALESCE(NEW.step_id, OLD.step_id);
  IF sid IS NULL THEN
    RETURN NULL;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM docutracker_workflow_steps WHERE id = sid) THEN
    RETURN NULL;
  END IF;

  SELECT
    COUNT(*) FILTER (WHERE a.is_enabled = true),
    COUNT(*) FILTER (WHERE a.is_enabled = true AND a.is_primary = true)
  INTO enabled_count, enabled_primary_count
  FROM docutracker_workflow_step_assignees a
  WHERE a.step_id = sid;

  IF enabled_count < 1 THEN
    RAISE EXCEPTION 'Workflow step % must have at least one enabled assignee', sid
      USING ERRCODE = '23514';
  END IF;

  IF enabled_primary_count <> 1 THEN
    RAISE EXCEPTION 'Workflow step % must have exactly one enabled primary assignee', sid
      USING ERRCODE = '23514';
  END IF;

  RETURN NULL;
END;
$$;

-- DocuTracker triggers
DROP TRIGGER IF EXISTS trg_docutracker_documents_doc_number ON docutracker_documents;
CREATE TRIGGER trg_docutracker_documents_doc_number
BEFORE INSERT ON docutracker_documents
FOR EACH ROW EXECUTE PROCEDURE docutracker_documents_set_doc_number();

DROP TRIGGER IF EXISTS trg_docutracker_documents_updated_at ON docutracker_documents;
CREATE TRIGGER trg_docutracker_documents_updated_at
BEFORE UPDATE ON docutracker_documents
FOR EACH ROW EXECUTE PROCEDURE docutracker_set_updated_at();

DROP TRIGGER IF EXISTS trg_docutracker_routing_configs_updated_at ON docutracker_routing_configs;
CREATE TRIGGER trg_docutracker_routing_configs_updated_at
BEFORE UPDATE ON docutracker_routing_configs
FOR EACH ROW EXECUTE PROCEDURE docutracker_set_updated_at();

DROP TRIGGER IF EXISTS trg_docutracker_routing_records_updated_at ON docutracker_routing_records;
CREATE TRIGGER trg_docutracker_routing_records_updated_at
BEFORE UPDATE ON docutracker_routing_records
FOR EACH ROW EXECUTE PROCEDURE docutracker_set_updated_at();

DROP TRIGGER IF EXISTS trg_docutracker_permissions_updated_at ON docutracker_permissions;
CREATE TRIGGER trg_docutracker_permissions_updated_at
BEFORE UPDATE ON docutracker_permissions
FOR EACH ROW EXECUTE PROCEDURE docutracker_set_updated_at();

DROP TRIGGER IF EXISTS trg_docutracker_escalation_configs_updated_at ON docutracker_escalation_configs;
CREATE TRIGGER trg_docutracker_escalation_configs_updated_at
BEFORE UPDATE ON docutracker_escalation_configs
FOR EACH ROW EXECUTE PROCEDURE docutracker_set_updated_at();

DROP TRIGGER IF EXISTS trg_docutracker_step_assignees_invariants ON docutracker_workflow_step_assignees;
CREATE CONSTRAINT TRIGGER trg_docutracker_step_assignees_invariants
AFTER INSERT OR UPDATE OR DELETE
ON docutracker_workflow_step_assignees
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE PROCEDURE docutracker_enforce_step_assignees_invariants();

-- DocuTracker permission baseline (role defaults)
WITH baseline(role_id, document_type, action, granted) AS (
  VALUES
    ('employee',  '*', 'view',     true),
    ('employee',  '*', 'create',   true),
    ('employee',  '*', 'submit',   true),
    ('employee',  '*', 'download', true),
    ('employee',  '*', 'edit',     false),
    ('employee',  '*', 'delete',   false),
    ('employee',  '*', 'forward',  false),
    ('employee',  '*', 'approve',  false),
    ('employee',  '*', 'reject',   false),
    ('employee',  '*', 'return',   false),
    ('hr',        '*', 'view',     true),
    ('hr',        '*', 'create',   true),
    ('hr',        '*', 'submit',   true),
    ('hr',        '*', 'download', true),
    ('hr',        '*', 'edit',     true),
    ('hr',        '*', 'delete',   false),
    ('hr',        '*', 'forward',  true),
    ('hr',        '*', 'approve',  true),
    ('hr',        '*', 'reject',   true),
    ('hr',        '*', 'return',   true),
    ('supervisor','*', 'view',     true),
    ('supervisor','*', 'create',   true),
    ('supervisor','*', 'submit',   true),
    ('supervisor','*', 'download', true),
    ('supervisor','*', 'edit',     true),
    ('supervisor','*', 'delete',   false),
    ('supervisor','*', 'forward',  true),
    ('supervisor','*', 'approve',  true),
    ('supervisor','*', 'reject',   true),
    ('supervisor','*', 'return',   true),
    ('admin',     '*', 'view',     true),
    ('admin',     '*', 'create',   true),
    ('admin',     '*', 'submit',   true),
    ('admin',     '*', 'download', true),
    ('admin',     '*', 'edit',     true),
    ('admin',     '*', 'delete',   true),
    ('admin',     '*', 'forward',  true),
    ('admin',     '*', 'approve',  true),
    ('admin',     '*', 'reject',   true),
    ('admin',     '*', 'return',   true)
)
INSERT INTO docutracker_permissions(role_id, user_id, document_type, action, granted)
SELECT b.role_id, NULL::uuid, b.document_type, b.action, b.granted
FROM baseline b
ON CONFLICT (role_id, document_type, action)
WHERE role_id IS NOT NULL
DO UPDATE SET
  granted = EXCLUDED.granted,
  updated_at = now();

-- =========================================
-- INDEXES
-- =========================================
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_lower_email ON users(LOWER(email));
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_employee_number ON users(employee_number);
CREATE INDEX IF NOT EXISTS idx_users_biometric_user_id ON users(biometric_user_id);
CREATE INDEX IF NOT EXISTS idx_users_is_active ON users(is_active);
CREATE INDEX IF NOT EXISTS idx_auth_refresh_tokens_user_id ON auth_refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_auth_refresh_tokens_expires_at ON auth_refresh_tokens(expires_at);
CREATE INDEX IF NOT EXISTS idx_auth_refresh_tokens_revoked_at ON auth_refresh_tokens(revoked_at);
CREATE INDEX IF NOT EXISTS idx_auth_password_reset_otps_user_active
  ON auth_password_reset_otps(user_id, expires_at DESC)
  WHERE consumed_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_auth_password_reset_otps_expires_at
  ON auth_password_reset_otps(expires_at);

CREATE INDEX IF NOT EXISTS idx_departments_is_active ON departments(is_active);
CREATE INDEX IF NOT EXISTS idx_departments_department_number ON departments(department_number);

CREATE INDEX IF NOT EXISTS idx_positions_department_id ON positions(department_id);
CREATE INDEX IF NOT EXISTS idx_positions_is_active ON positions(is_active);

CREATE INDEX IF NOT EXISTS idx_shifts_is_active ON shifts(is_active);

CREATE INDEX IF NOT EXISTS idx_assignments_employee_id ON assignments(employee_id);
CREATE INDEX IF NOT EXISTS idx_assignments_department_id ON assignments(department_id);
CREATE INDEX IF NOT EXISTS idx_assignments_position_id ON assignments(position_id);
CREATE INDEX IF NOT EXISTS idx_assignments_shift_id ON assignments(shift_id);
CREATE INDEX IF NOT EXISTS idx_assignments_effective_from ON assignments(effective_from);
CREATE INDEX IF NOT EXISTS idx_assignments_effective_to ON assignments(effective_to);
CREATE INDEX IF NOT EXISTS idx_assignments_employee_active_dates
ON assignments(employee_id, is_active, effective_from DESC, effective_to);
CREATE INDEX IF NOT EXISTS idx_assignments_department_active_dates
ON assignments(department_id, is_active, effective_from, effective_to, employee_id);

CREATE INDEX IF NOT EXISTS idx_policy_assignments_employee_id ON policy_assignments(employee_id);
CREATE INDEX IF NOT EXISTS idx_policy_assignments_department_id ON policy_assignments(department_id);
CREATE INDEX IF NOT EXISTS idx_policy_assignments_shift_id ON policy_assignments(shift_id);
CREATE INDEX IF NOT EXISTS idx_policy_assignments_policy_id ON policy_assignments(attendance_policy_id);

CREATE INDEX IF NOT EXISTS idx_holidays_date_range ON holidays(date_from, date_to);
CREATE INDEX IF NOT EXISTS idx_holidays_type ON holidays(holiday_type);
CREATE INDEX IF NOT EXISTS idx_holiday_default_template_items_template
ON holiday_default_template_items(template_id, sort_order, date_from);

CREATE INDEX IF NOT EXISTS idx_leave_requests_employee_id ON leave_requests(employee_id);
CREATE INDEX IF NOT EXISTS idx_leave_requests_user_id ON leave_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_leave_requests_status ON leave_requests(status);
CREATE INDEX IF NOT EXISTS idx_leave_requests_dates ON leave_requests(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_leave_requests_status_employee_dates
ON leave_requests(status, employee_id, start_date, end_date);

-- Prevent duplicate pending/approved requests on the same date range.
-- PARTIAL so draft/returned/cancelled/rejected records are not affected.
CREATE UNIQUE INDEX IF NOT EXISTS uq_leave_requests_no_overlap
ON leave_requests (user_id, start_date, end_date)
WHERE status IN ('pending', 'pending_department_head', 'pending_hr', 'approved');

CREATE INDEX IF NOT EXISTS idx_biometric_attendance_logs_user_id ON biometric_attendance_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_biometric_attendance_logs_logged_at ON biometric_attendance_logs(logged_at);
CREATE INDEX IF NOT EXISTS idx_biometric_attendance_logs_biometric_user_id ON biometric_attendance_logs(biometric_user_id);
CREATE INDEX IF NOT EXISTS idx_biometric_logs_user_logged
ON biometric_attendance_logs(user_id, logged_at);

CREATE INDEX IF NOT EXISTS idx_dtr_logs_employee_id ON dtr_logs(employee_id);
CREATE INDEX IF NOT EXISTS idx_dtr_logs_log_time ON dtr_logs(log_time);
CREATE INDEX IF NOT EXISTS idx_dtr_logs_biometric_user_id ON dtr_logs(biometric_user_id);
CREATE INDEX IF NOT EXISTS idx_dtr_logs_device_ref_id ON dtr_logs(device_ref_id);
CREATE INDEX IF NOT EXISTS idx_dtr_logs_source ON dtr_logs(source);

CREATE INDEX IF NOT EXISTS idx_dtr_daily_summary_employee_id ON dtr_daily_summary(employee_id);
CREATE INDEX IF NOT EXISTS idx_dtr_daily_summary_date ON dtr_daily_summary(attendance_date);
CREATE INDEX IF NOT EXISTS idx_dtr_daily_summary_status ON dtr_daily_summary(status);
CREATE INDEX IF NOT EXISTS idx_dtr_daily_summary_assignment_id ON dtr_daily_summary(assignment_id);
CREATE INDEX IF NOT EXISTS idx_dtr_leave_request ON dtr_daily_summary(leave_request_id);
CREATE INDEX IF NOT EXISTS idx_dtr_daily_summary_date_time
ON dtr_daily_summary(attendance_date DESC, time_in DESC);
CREATE INDEX IF NOT EXISTS idx_dtr_daily_summary_date_employee
ON dtr_daily_summary(attendance_date, employee_id);

CREATE INDEX IF NOT EXISTS idx_locator_slips_status_employee_date
ON locator_slips(status, employee_id, slip_date);

CREATE INDEX IF NOT EXISTS idx_dtr_corrections_employee_id ON dtr_corrections(employee_id);
CREATE INDEX IF NOT EXISTS idx_dtr_corrections_status ON dtr_corrections(status);
CREATE INDEX IF NOT EXISTS idx_dtr_corrections_attendance_date ON dtr_corrections(attendance_date);

CREATE INDEX IF NOT EXISTS idx_attendance_policies_is_active ON attendance_policies(is_active);

CREATE INDEX IF NOT EXISTS idx_biometric_devices_device_id ON biometric_devices(device_id);
CREATE INDEX IF NOT EXISTS idx_biometric_devices_is_active ON biometric_devices(is_active);

CREATE INDEX IF NOT EXISTS idx_overtime_requests_employee_id ON overtime_requests(employee_id);
CREATE INDEX IF NOT EXISTS idx_overtime_requests_status ON overtime_requests(status);
CREATE INDEX IF NOT EXISTS idx_overtime_requests_ot_date ON overtime_requests(ot_date);

CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity_type ON audit_logs(entity_type);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at);

CREATE INDEX IF NOT EXISTS idx_bi_form_entries_created
  ON bi_form_entries(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_performance_evaluation_entries_created
  ON performance_evaluation_entries(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_training_need_analysis_entries_created
  ON training_need_analysis_entries(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_action_brainstorming_coaching_entries_created
  ON action_brainstorming_coaching_entries(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_turn_around_time_entries_created
  ON turn_around_time_entries(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_idp_entries_created
  ON idp_entries(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_training_daily_reports_employee_submitted
  ON training_daily_reports(employee_id, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_training_daily_reports_status
  ON training_daily_reports(status);
CREATE INDEX IF NOT EXISTS idx_training_report_attachments_report
  ON training_report_attachments(report_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ld_training_requirement_employee
  ON ld_training_requirement_records(employee_id);

CREATE INDEX IF NOT EXISTS idx_recruitment_applications_status
  ON recruitment_applications(status);
CREATE INDEX IF NOT EXISTS idx_recruitment_applications_created
  ON recruitment_applications(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_recruitment_exam_results_application
  ON recruitment_exam_results(application_id);
CREATE INDEX IF NOT EXISTS idx_recruitment_exam_questions_type
  ON recruitment_exam_questions(exam_type);
CREATE INDEX IF NOT EXISTS idx_job_vacancy_announcement_updated
  ON job_vacancy_announcement(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_selection_lineup_entries_created
  ON selection_lineup_entries(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_applicants_profile_entries_created
  ON applicants_profile_entries(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_comparative_assessment_entries_created
  ON comparative_assessment_entries(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_promotion_certification_entries_created
  ON promotion_certification_entries(created_at DESC);

-- =========================================
-- updated_at TRIGGERS
-- =========================================
DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();

DROP TRIGGER IF EXISTS trg_user_push_tokens_updated_at ON user_push_tokens;
CREATE TRIGGER trg_user_push_tokens_updated_at
BEFORE UPDATE ON user_push_tokens
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();

DROP TRIGGER IF EXISTS trg_departments_updated_at ON departments;
CREATE TRIGGER trg_departments_updated_at
BEFORE UPDATE ON departments
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();

DROP TRIGGER IF EXISTS trg_offices_updated_at ON offices;
CREATE TRIGGER trg_offices_updated_at
BEFORE UPDATE ON offices
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();

DROP TRIGGER IF EXISTS trg_positions_updated_at ON positions;
CREATE TRIGGER trg_positions_updated_at
BEFORE UPDATE ON positions
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();

DROP TRIGGER IF EXISTS trg_shifts_updated_at ON shifts;
CREATE TRIGGER trg_shifts_updated_at
BEFORE UPDATE ON shifts
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();

DROP TRIGGER IF EXISTS trg_attendance_policies_updated_at ON attendance_policies;
CREATE TRIGGER trg_attendance_policies_updated_at
BEFORE UPDATE ON attendance_policies
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();

DROP TRIGGER IF EXISTS trg_biometric_devices_updated_at ON biometric_devices;
CREATE TRIGGER trg_biometric_devices_updated_at
BEFORE UPDATE ON biometric_devices
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();

DROP TRIGGER IF EXISTS trg_assignments_updated_at ON assignments;
CREATE TRIGGER trg_assignments_updated_at
BEFORE UPDATE ON assignments
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();

DROP TRIGGER IF EXISTS trg_policy_assignments_updated_at ON policy_assignments;
CREATE TRIGGER trg_policy_assignments_updated_at
BEFORE UPDATE ON policy_assignments
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();

DROP TRIGGER IF EXISTS trg_leave_requests_updated_at ON leave_requests;
CREATE TRIGGER trg_leave_requests_updated_at
BEFORE UPDATE ON leave_requests
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();

DROP TRIGGER IF EXISTS trg_locator_slips_updated_at ON locator_slips;
CREATE TRIGGER trg_locator_slips_updated_at
BEFORE UPDATE ON locator_slips
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();

DROP TRIGGER IF EXISTS trg_dtr_daily_summary_updated_at ON dtr_daily_summary;
CREATE TRIGGER trg_dtr_daily_summary_updated_at
BEFORE UPDATE ON dtr_daily_summary
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();

DROP TRIGGER IF EXISTS trg_dtr_corrections_updated_at ON dtr_corrections;
CREATE TRIGGER trg_dtr_corrections_updated_at
BEFORE UPDATE ON dtr_corrections
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();

DROP TRIGGER IF EXISTS trg_overtime_requests_updated_at ON overtime_requests;
CREATE TRIGGER trg_overtime_requests_updated_at
BEFORE UPDATE ON overtime_requests
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();

DROP TRIGGER IF EXISTS trg_leave_balances_updated_at ON leave_balances;
CREATE TRIGGER trg_leave_balances_updated_at
BEFORE UPDATE ON leave_balances
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();

DROP TRIGGER IF EXISTS trg_training_daily_reports_updated_at ON training_daily_reports;
CREATE TRIGGER trg_training_daily_reports_updated_at
BEFORE UPDATE ON training_daily_reports
FOR EACH ROW
EXECUTE PROCEDURE set_updated_at();
