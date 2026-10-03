-- Permit a dedicated system identity that is not an employee.
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check
  CHECK (role IN ('admin', 'hr', 'employee', 'supervisor', 'mayor', 'super_admin'));

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_super_admin_not_employee_check;
ALTER TABLE users ADD CONSTRAINT users_super_admin_not_employee_check
  CHECK (role <> 'super_admin' OR (employee_number IS NULL AND leave_credit_eligible = false));

CREATE UNIQUE INDEX IF NOT EXISTS users_single_super_admin_idx
  ON users (role) WHERE role = 'super_admin';
