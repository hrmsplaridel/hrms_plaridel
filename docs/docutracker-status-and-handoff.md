# DocuTracker — implementation status and handoff

**Date recorded:** 21 October 2026.

This note is a handoff. It does not authorize new features, schema changes, or workarounds.

## 1. Current status

DocuTracker is feature-complete for the currently confirmed requirements.

Pending: client validation, and Purchase Request requirements from HR / Procurement.

## 2. Completed major features

- **Native document workflow.** Documents move through the saved workflow. The backend decides who may act and records the result.
- **Department reviewer routing.** A step can assign the submitter’s department reviewer, or a fixed department’s reviewer, instead of a named person.
- **Primary/backup reviewer handling.** The designated primary reviewer acts. The backup acts when the primary is unavailable under the current rules.
- **No-self-review.** The submitter is not given their own review step.
- **Single active reviewer.** One reviewer holds the active review at a time.
- **Admin Recovery.** An administrator can recover a stuck document without approving it in place of the reviewer.
- **Escalation safety.** Escalation follows the configured limit and target. It does not skip the workflow rules.
- **System Access permissions.** Type-specific grants and denies are edited in System Access. A more specific row outranks a wildcard.
- **Required Actions.** The queue separates “Needs your review” from “Needs your signature,” then setup and waiting items.
- **Governance audit.** Permission and workflow changes that the product records stay available for review.
- **Release / Distribution.** When a type requires release, an authorized user releases the approved document to the chosen departments.
- **Released-department view-only visibility.** A department recipient with no active review, signature, or release duty sees the document as view only.
- **RSP/L&D signature integration.** RSP and L&D forms keep their own records. DocuTracker carries the signature request and the signed PDF.
- **RSP recruitment removed from normal DocuTracker browsing.** Recruitment is not part of ordinary DocuTracker document browsing.
- **Official Memo template.** Memorandum uses the locked Memo layout, not a free-form page.
- **Memo structured Prepared by / Approved by signing.** Those two blocks are fixed signatory slots.
- **Signer identity snapshots.** A signature keeps the name and position captured at signing.
- **Unicode-capable PDF fonts.** Official Memo PDFs and RSP/L&D form PDFs use bundled Noto Sans Regular and Bold. No italic file is bundled, so italic runs use the upright face.
- **Dark mode, CTA, and usability.** Release uses the same brand primary button as Create Draft. Approved documents that still need release say they are awaiting release. Compact System Access save stays reachable on a narrow screen.

## 3. Confirmed architectural rules

- The backend is authoritative.
- Workflow mutations stay transactional.
- There is no admin bypass for workflow approval.
- A user-specific view deny overrides visibility.
- A role-level view deny does not block relationship or released-department visibility where the current rules allow that visibility.
- Release is separate from workflow approval.
- Release does not change the stored workflow status from `approved`.
- RSP, L&D, and DTR keep ownership of their own records. DocuTracker does not become the system of record for those rows.

## 4. Memo pending items

These wait on HR or on official artwork. Do not hard-code stand-ins.

- Official Asenso Plaridel artwork is still needed.
- Bagong Pilipinas artwork is still needed.
- The official footer strip is still needed.
- If a preparer’s title should print, HR should correct that person’s directory position. This includes Kristoffer / the current preparer.
- If the printed Mayor line should be the actual mayor, HR should replace the generic Mayor’s Office account with the mayor’s employee account.
- Signature replacement policy still needs an HR decision.
- Physical A4 print acceptance is still pending.

## 5. Purchase Request

See [docutracker-purchase-request-requirements.md](docutracker-purchase-request-requirements.md).

Implementation is on hold until HR / Procurement provides the official blank form and the exact workflow and signature requirements.

The current Purchase Request route and form are a placeholder. Do not treat them as the official process.

## 6. Real-user usability testing

Heuristic review is complete. Moderated real-user testing is still pending.

Prepared dev records for those sessions:

- `DOC-2026-000042` — reviewer scenario
- `DOC-2026-000043` — awaiting-release scenario
- `DOC-2026-000044` — released-department scenario

`DOC-2026-000041` is a protected Memo signing acceptance sample. Do not modify it.

Do not invent usability findings before the sessions occur. Run the usability cleanup scripts only after those sessions are finished.

## 7. Known technical follow-up

`primary_reviewer_designations` was missing on the app database (port 5432) because the DTR migration `backend/scripts/migrations/dtr/20261009_employee_primary_reviewers.sql` had not been applied. Fresh databases get the table from `backend/scripts/init-schema.sql`. DocuTracker does not create it.

The usability setup created the table so testing could continue. Before DocuTracker deployment or testing, run `node backend/scripts/check-docutracker-schema.js`. The check is read-only and does not run the migration.

## 8. Current validation baseline

Latest confirmed Flutter baseline:

- DocuTracker + shared tests: 334 passed
- No DocuTracker PDF font warnings in that run
- No DocuTracker analyzer issues introduced by the recent PDF font cleanup
- Remaining analyzer infos are outside DocuTracker

Backend tests were not rerun for this baseline.

## 9. Do not change without new requirements

- Purchase Request workflow and template
- Memo visual structure
- Department reviewer semantics
- Release visibility semantics
- Recruitment separation from normal DocuTracker browsing
- Signature snapshot behavior
- The rule that admin cannot bypass workflow approval
