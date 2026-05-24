-- =============================================================================
-- HRMS Plaridel — DocuTracker: FULL INSTALL (orchestrator — runs phases in order)
-- =============================================================================
-- PREREQUISITE:
--   psql -d YOUR_DB -f scripts/init-schema.sql
--
-- This file uses psql \ir (include relative to this file) to run, in order:
--   1) docutracker-install-core.sql                    (sections 01–08)
--   2) docutracker-install-production-hardening-apply-once.sql
--   3) docutracker-install-post-production-hardening.sql (sections 10–13)
--
-- USAGE (from repo root; path must point at this file — \ir resolves next to it):
--   psql -d hrms_plaridel -v ON_ERROR_STOP=1 -f backend/scripts/docutracker-install-all-in-order.sql
--
-- To run phases separately, execute those three -f files in order (see each file's header).
--
-- Regenerate rollups: node backend/scripts/build-docutracker-all.js
-- =============================================================================

\echo 'DocuTracker phase 1/3: core (01–08)...'
\ir docutracker-install-core.sql
\echo 'DocuTracker phase 2/3: production hardening (apply once)...'
\ir docutracker-install-production-hardening-apply-once.sql
\echo 'DocuTracker phase 3/3: post production hardening (10–13)...'
\ir docutracker-install-post-production-hardening.sql
\echo 'DocuTracker install finished.'
