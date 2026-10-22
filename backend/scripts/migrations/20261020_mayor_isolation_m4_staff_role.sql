-- M4 — Add Mayor's Office Staff role key
-- DO NOT RUN until hard isolation M1–M3 are applied (or explicitly approved earlier).
-- Display name in UI: "Mayor's Office Staff"
-- DB role key: mayor_office_staff
-- Keeps users_single_active_mayor_idx unchanged (mayor only).

BEGIN;

ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_check;

ALTER TABLE public.users
  ADD CONSTRAINT users_role_check
  CHECK (
    role = ANY (
      ARRAY[
        'admin'::text,
        'hr'::text,
        'employee'::text,
        'supervisor'::text,
        'mayor'::text,
        'mayor_office_staff'::text,
        'super_admin'::text
      ]
    )
  );

COMMIT;
