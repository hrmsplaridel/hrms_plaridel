-- Seed leave_types with names matching Flutter LeaveType enum (.value = enum name).
-- Run once on existing DBs: psql -h localhost -p 5433 -U postgres -d hrms_plaridel -f backend/scripts/seed-leave-types.sql
-- New installs: leave_types table is created by init-schema.sql; this script populates it.

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
