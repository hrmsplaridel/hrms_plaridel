# DocuTracker Release Readiness Checklist

Use this document for P0/P1/P2 closure before go-live.

## P0 - Blockers

### 1) Schema parity (mandatory)

- [ ] Run: `backend/scripts/verify-docutracker-source-parity.sql`
- [ ] Required source tables exist:
  - [ ] `training_daily_reports`
  - [ ] `leave_requests`
  - [ ] `dtr_corrections`
  - [ ] `overtime_requests`
  - [ ] `recruitment_applications`
- [ ] Required DocuTracker tables exist:
  - [ ] `docutracker_documents`
  - [ ] `docutracker_permissions`
  - [ ] `docutracker_routing_configs`
  - [ ] `docutracker_routing_records`
  - [ ] `docutracker_document_history`
  - [ ] `docutracker_notifications`

### 2) Permission baseline (mandatory)

- [ ] Apply baseline seed: `backend/scripts/seed-docutracker-permission-baseline.sql`
- [ ] Confirm role matrix loaded (employee/hr/supervisor/admin + aliases)
- [ ] Validate selected-employee override behavior in setup screen

## P1 - Security and Behavior

### 3) Restriction matrix

- [ ] Execute all 7 cases from `docs/docutracker-restriction-test-matrix.md`
- [ ] Archive screenshot/API evidence for each case
- [ ] Resolve any failed case before proceeding

### 4) Workflow integrity

- [ ] Non-holder transition protection verified
- [ ] Invalid status transitions blocked
- [ ] Next-step assignee validation passes
- [ ] Last-step approve ends workflow correctly
- [ ] Return action routes to valid previous assignee

## P2 - UX and Handoff

### 5) UX consistency

- [ ] User-facing Leave terminology is consistent
- [ ] No duplicated controls (create/refresh/filter)
- [ ] Ownership distinction visible (`Mine`, `Assigned to me`)
- [ ] Mobile and desktop layouts free from overflow issues

### 6) Known limitations

- [ ] Missing source-table warning behavior documented
- [ ] Source-backed rows open in source module (not DocuTracker detail) documented

### 7) Go-live and rollback

#### Go-live

1. Deploy backend with latest `docutrackerWorkflowService` and routes.
2. Apply schema parity + permission baseline scripts.
3. Deploy Flutter web/app build.
4. Run smoke tests (admin + employee accounts).

#### Rollback

1. Re-deploy previous backend artifact.
2. Revert to previous frontend build.
3. Keep DB data intact (no destructive rollback by default).
4. Disable DocuTracker source-sync usage operationally until fix is applied.

## Sign-off

- QA Lead: __________________ Date: __________
- Product Owner: ____________ Date: __________
- Tech Lead: _________________ Date: __________
