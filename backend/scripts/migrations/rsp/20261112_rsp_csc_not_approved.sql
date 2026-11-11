-- Allow HR to record CSC as not approved (final requirements stay locked).

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'recruitment_applications_csc_approval_status_check'
  ) THEN
    ALTER TABLE public.recruitment_applications
      DROP CONSTRAINT recruitment_applications_csc_approval_status_check;
  END IF;

  ALTER TABLE public.recruitment_applications
    ADD CONSTRAINT recruitment_applications_csc_approval_status_check
    CHECK (
      csc_approval_status IS NULL
      OR csc_approval_status IN ('waiting', 'approved', 'not_approved')
    );
END $$;
