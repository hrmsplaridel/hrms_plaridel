BEGIN;

-- New RSP/L&D forms record their authenticated creator so the official
-- Prepared by field can be assigned without trusting a typed client value.
ALTER TABLE IF EXISTS public.applicants_profile_entries
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE IF EXISTS public.selection_lineup_entries
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE IF EXISTS public.computation_of_points_entries
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE IF EXISTS public.turn_around_time_entries
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE IF EXISTS public.idp_entries
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.users(id) ON DELETE SET NULL;

COMMIT;
