-- Who requested the endorsement + Mayor meeting schedule / no-show.
ALTER TABLE public.mayor_endorsement_requests
  ADD COLUMN IF NOT EXISTS submitted_by UUID REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.mayor_endorsement_requests
  ADD COLUMN IF NOT EXISTS submitted_by_name TEXT;
ALTER TABLE public.mayor_endorsement_requests
  ADD COLUMN IF NOT EXISTS appointment_at TIMESTAMPTZ;
ALTER TABLE public.mayor_endorsement_requests
  ADD COLUMN IF NOT EXISTS appointment_status TEXT NOT NULL DEFAULT 'none';
ALTER TABLE public.mayor_endorsement_requests
  ADD COLUMN IF NOT EXISTS appointment_notes TEXT;
ALTER TABLE public.mayor_endorsement_requests
  ADD COLUMN IF NOT EXISTS no_show_count INT NOT NULL DEFAULT 0;

UPDATE public.mayor_endorsement_requests mer
   SET submitted_by = mal.actor_id,
       submitted_by_name = COALESCE(mer.submitted_by_name, u.full_name)
  FROM (
    SELECT DISTINCT ON (request_id) request_id, actor_id
    FROM public.mayor_endorsement_activity_logs
    WHERE action = 'request_submitted'
    ORDER BY request_id, created_at ASC
  ) mal
  LEFT JOIN public.users u ON u.id = mal.actor_id
 WHERE mer.submitted_by IS NULL
   AND mal.request_id = mer.id;
