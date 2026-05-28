/* Builds DocuTracker SQL rollups from individual scripts under backend/scripts/. */
const fs = require("fs");
const path = require("path");

const base = __dirname;

const APPLY_ONCE_FILE = "migrate-docutracker-production-hardening-apply-once.sql";

const coreSections = [
  ["01 — BASE SCHEMA (tables, indexes)", "init-schema-docutracker.sql"],
  ["02 — MVP CONSTRAINTS (status checks, permissions, routing indexes)", "migrate-docutracker-mvp-constraints.sql"],
  ["03 — SUPABASE / STANDALONE PARITY (columns, nullable assignee)", "migrate-docutracker-supabase-parity.sql"],
  ["04 — WORKFLOW VERSIONING (routing_config_versions, workflow_version on documents)", "migrate-docutracker-workflow-versioning.sql"],
  ["05 — WORKFLOW STEPS + STEP ASSIGNEES (normalized selected-person)", "migrate-docutracker-workflow-step-assignees-v1.sql"],
  ["06 — STEP ASSIGNEE CONSTRAINT TRIGGER (primary + enabled rules)", "migrate-docutracker-workflow-step-assignees-constraints-v1.sql"],
  ["07 — ROUTING RECORD ASSIGNEES (junction + backfill)", "migrate-docutracker-routing-record-assignees-v1.sql"],
  ["08 — HARDENING V2 (numeric guards, notifications event_key, permissions uniqueness, transition_requests)", "migrate-docutracker-hardening-v2.sql"],
];

const postSections = [
  ["10 — STATUS SEMANTICS V2 (drop forwarded as document status)", "migrate-docutracker-status-semantics-v2.sql"],
  ["11 — ACTIVE ROUTING STEP INDEX (one active row per document)", "migrate-docutracker-active-step-index-v1.sql"],
  ["12 — SEED PERMISSION BASELINE (role rows)", "seed-docutracker-permission-baseline.sql"],
  ["13 — OPTIONAL VERIFY (checks source tables exist)", "verify-docutracker-source-parity.sql"],
  ["14 — AI SUMMARIES (saved metadata-only summaries)", "migrate-docutracker-ai-summaries-v1.sql"],
];

function readBody(file) {
  const p = path.join(base, file);
  if (!fs.existsSync(p)) {
    throw new Error(`Missing: ${p}`);
  }
  return fs.readFileSync(p, "utf8").trimEnd();
}

function buildRollup({ title, descriptionLines, tocLines, sections }) {
  const toc = tocLines.map((line) => `--   ${line}`).join("\n");
  let out = `-- =============================================================================
-- ${title}
-- =============================================================================
${descriptionLines.map((l) => `-- ${l}`).join("\n")}
--
-- TABLE OF CONTENTS
${toc}
--
-- =============================================================================

`;
  for (const [secTitle, file] of sections) {
    const body = readBody(file);
    out += "\n\n-- #############################################################################\n";
    out += `-- ${secTitle}\n`;
    out += `-- Source file: ${file}\n`;
    out += "-- #############################################################################\n\n";
    out += `${body}\n`;
  }
  return out;
}

// --- Phase 1: core (01–08)
const coreToc = coreSections.map(([t]) => t);
const coreOut = buildRollup({
  title: "HRMS Plaridel — DocuTracker: INSTALL PHASE 1 (core, 01–08)",
  descriptionLines: [
    "PREREQUISITE: psql -d YOUR_DB -f scripts/init-schema.sql",
    "Requires: uuid-ossp, users, departments (and related core HR tables).",
    "NEXT (required before post-hardening phases): run docutracker-install-production-hardening-apply-once.sql",
  ],
  tocLines: coreToc,
  sections: coreSections,
});

// --- Phase 2: production hardening apply-once (09) — standalone by design
const applyOnceBody = readBody(APPLY_ONCE_FILE);
const applyOnceOut = `-- =============================================================================
-- HRMS Plaridel — DocuTracker: PRODUCTION HARDENING (apply once)
-- =============================================================================
-- Source: ${APPLY_ONCE_FILE}
-- Run AFTER phase 1 (docutracker-install-core.sql) completes successfully.
-- Run BEFORE phase 3 (docutracker-install-post-production-hardening.sql).
--
-- This script is large and may require data fixes if constraints fail; fix rows,
-- then re-run with ON_ERROR_STOP.
--
-- USAGE:
--   psql -d hrms_plaridel -v ON_ERROR_STOP=1 -f scripts/docutracker-install-production-hardening-apply-once.sql
-- =============================================================================

${applyOnceBody}
`;

// --- Phase 3: post production hardening (10–13)
const postToc = postSections.map(([t]) => t);
const postOut = buildRollup({
  title: "HRMS Plaridel — DocuTracker: INSTALL PHASE 3 (post production hardening, 10–13)",
  descriptionLines: [
    "PREREQUISITE: phase 1 complete AND docutracker-install-production-hardening-apply-once.sql applied.",
    "Section 10 drops/replaces *_prod_v1 status constraints created in production hardening.",
    "Section 11 fails if multiple active routing rows exist per document; fix data then re-run.",
    "Section 13 raises if optional source-module tables are missing; comment it out for DocuTracker-only DBs.",
  ],
  tocLines: postToc,
  sections: postSections,
});

// --- Orchestrator: one psql command, same order (\ir is relative to this file's directory)
const orchestratorOut = `-- =============================================================================
-- HRMS Plaridel — DocuTracker: FULL INSTALL (orchestrator — runs phases in order)
-- =============================================================================
-- PREREQUISITE:
--   psql -d YOUR_DB -f scripts/init-schema.sql
--
-- This file uses psql \\ir (include relative to this file) to run, in order:
--   1) docutracker-install-core.sql                    (sections 01–08)
--   2) docutracker-install-production-hardening-apply-once.sql
--   3) docutracker-install-post-production-hardening.sql (sections 10–13)
--
-- USAGE (from repo root; path must point at this file — \\ir resolves next to it):
--   psql -d hrms_plaridel -v ON_ERROR_STOP=1 -f backend/scripts/docutracker-install-all-in-order.sql
--
-- To run phases separately, execute those three -f files in order (see each file's header).
--
-- Regenerate rollups: node backend/scripts/build-docutracker-all.js
-- =============================================================================

\\echo 'DocuTracker phase 1/3: core (01–08)...'
\\ir docutracker-install-core.sql
\\echo 'DocuTracker phase 2/3: production hardening (apply once)...'
\\ir docutracker-install-production-hardening-apply-once.sql
\\echo 'DocuTracker phase 3/3: post production hardening (10–13)...'
\\ir docutracker-install-post-production-hardening.sql
\\echo 'DocuTracker install finished.'
`;

const writes = [
  ["docutracker-install-core.sql", coreOut],
  ["docutracker-install-production-hardening-apply-once.sql", applyOnceOut],
  ["docutracker-install-post-production-hardening.sql", postOut],
  ["docutracker-install-all-in-order.sql", orchestratorOut],
];

for (const [name, content] of writes) {
  const dest = path.join(base, name);
  fs.writeFileSync(dest, content, "utf8");
  console.log(`Wrote ${dest} (${content.length} bytes)`);
}
