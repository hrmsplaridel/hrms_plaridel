-- Granular RSP Recruitment Management + Forms, and L&D Forms permissions.
-- Additive only — does not alter dtr_admin_access.

ALTER TABLE rsp_admin_access
  ADD COLUMN IF NOT EXISTS applications_allowed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS exam_results_allowed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS scheduling_allowed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS final_requirements_allowed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS form_bi_allowed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS form_applicants_profile_allowed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS form_selection_lineup_allowed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS form_computation_of_points_allowed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS form_work_experience_allowed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS form_turn_around_time_allowed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS form_ojt_allowed BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE ld_admin_access
  ADD COLUMN IF NOT EXISTS form_tna_allowed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS form_action_brainstorming_allowed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS form_idp_allowed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS form_lap_allowed BOOLEAN NOT NULL DEFAULT false;

-- One-time backfill from previous module-level toggles (only when all children are still false).
UPDATE rsp_admin_access
   SET applications_allowed = true,
       exam_results_allowed = true,
       scheduling_allowed = true,
       final_requirements_allowed = true
 WHERE recruitment_allowed = true
   AND applications_allowed = false
   AND exam_results_allowed = false
   AND scheduling_allowed = false
   AND final_requirements_allowed = false;

UPDATE rsp_admin_access
   SET form_bi_allowed = true,
       form_applicants_profile_allowed = true,
       form_selection_lineup_allowed = true,
       form_computation_of_points_allowed = true,
       form_work_experience_allowed = true,
       form_turn_around_time_allowed = true,
       form_ojt_allowed = true
 WHERE forms_allowed = true
   AND form_bi_allowed = false
   AND form_applicants_profile_allowed = false
   AND form_selection_lineup_allowed = false
   AND form_computation_of_points_allowed = false
   AND form_work_experience_allowed = false
   AND form_turn_around_time_allowed = false
   AND form_ojt_allowed = false;

UPDATE ld_admin_access
   SET form_tna_allowed = true,
       form_action_brainstorming_allowed = true,
       form_idp_allowed = true,
       form_lap_allowed = true
 WHERE forms_allowed = true
   AND form_tna_allowed = false
   AND form_action_brainstorming_allowed = false
   AND form_idp_allowed = false
   AND form_lap_allowed = false;
