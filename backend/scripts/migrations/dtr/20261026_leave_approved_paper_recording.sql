-- Enable recording already-approved paper leave with original approval details.
-- Paper recording is a separate explicit permission and starts disabled.
-- Existing requests, approvals and signature history are unchanged.
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE public.leave_types
 ADD COLUMN IF NOT EXISTS allow_approved_paper_filing BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.leave_requests
 ADD COLUMN IF NOT EXISTS paper_approval_record JSONB;
COMMIT;
