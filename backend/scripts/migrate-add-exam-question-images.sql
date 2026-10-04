-- Optional images / diagrams for RSP exam questions and answer choices.
-- Backward compatible: existing text-only rows keep working (all new columns are NULL).
-- options_json and correct_index are unchanged; option_images_json is a JSON array
-- parallel to options_json (same length, null where a choice has no image).
ALTER TABLE public.recruitment_exam_questions
  ADD COLUMN IF NOT EXISTS question_image_path TEXT;
ALTER TABLE public.recruitment_exam_questions
  ADD COLUMN IF NOT EXISTS question_image_caption TEXT;
ALTER TABLE public.recruitment_exam_questions
  ADD COLUMN IF NOT EXISTS option_images_json JSONB;
