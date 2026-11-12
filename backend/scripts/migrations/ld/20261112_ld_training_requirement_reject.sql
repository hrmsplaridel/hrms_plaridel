-- Allow HR to reject individual training requirement PDFs and request resubmit.

ALTER TABLE public.ld_training_requirement_records
  ADD COLUMN IF NOT EXISTS doc_invitation_letter_reject_reason TEXT,
  ADD COLUMN IF NOT EXISTS doc_travel_order_reject_reason TEXT,
  ADD COLUMN IF NOT EXISTS doc_lap_reject_reason TEXT,
  ADD COLUMN IF NOT EXISTS doc_training_certificate_reject_reason TEXT;
