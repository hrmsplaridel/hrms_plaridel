-- Built-in exams (bei, general, math, general_info) removed from the Exams picker.
CREATE TABLE IF NOT EXISTS public.recruitment_hidden_exams (
  exam_type TEXT PRIMARY KEY,
  hidden_at TIMESTAMPTZ DEFAULT now()
);
