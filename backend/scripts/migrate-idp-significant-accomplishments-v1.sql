-- IDP: significant accomplishments field (matches paper form section).
ALTER TABLE public.idp_entries ADD COLUMN IF NOT EXISTS significant_accomplishments TEXT;
