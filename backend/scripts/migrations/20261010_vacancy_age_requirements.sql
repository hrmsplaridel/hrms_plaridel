-- Per-vacancy age rules live on each object in job_vacancy_announcement.vacancies.
-- Existing rows keep their current eligibility: minimum 18, no maximum.

UPDATE public.job_vacancy_announcement
SET vacancies = (
  SELECT COALESCE(
    jsonb_agg(
      CASE
        WHEN jsonb_typeof(elem->'minimum_age') = 'number'
          THEN elem
        ELSE elem || '{"minimum_age":18}'::jsonb
      END
      ORDER BY ord
    ),
    '[]'::jsonb
  )
  FROM jsonb_array_elements(COALESCE(vacancies, '[]'::jsonb))
    WITH ORDINALITY AS listed(elem, ord)
)
WHERE jsonb_typeof(vacancies) = 'array'
  AND EXISTS (
    SELECT 1
    FROM jsonb_array_elements(vacancies) elem
    WHERE jsonb_typeof(elem->'minimum_age') IS DISTINCT FROM 'number'
  );
