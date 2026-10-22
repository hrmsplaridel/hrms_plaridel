# DTR daily-summary module

`src/routes/dtrDailySummary.js` remains the server's compatibility entry.
`dtr.router.js` registers the same 14 endpoints, in the same order, under
`/api/dtr-daily-summary`. Existing consumers can keep their import paths.

## Responsibilities

- `controllers/`: HTTP validation and responses for reports, dashboard counts,
  current shifts, today's record, manual attendance, recalculation, deletion,
  restoration, and holiday synchronization.
- `repositories/`: shared assignment, attendance-policy, leave/locator coverage,
  and holiday queries. Endpoint-specific SQL remains with its controller in this
  extraction; transaction bodies stay together.
- `policies/`: calendar/time conversion, report query limits, and locator labels.
- `services/`: shift calculations, late/undertime rules, attendance remarks,
  report cutoffs, saved-row mapping, and individual report overlays.
- `serializers/`: assignment export and audit snapshot mappings.
- `use-cases/completeReport.js`: resolves the report's employee scope and schedules,
  then runs the existing overlay stages in order: holidays, approved leave,
  absences, approved locators, locator annotations, and attendance-policy deductions.
  The shared `rows`, date keys, and saved shift snapshots remain request-local.

`dependencies.js` resolves the existing shared services when a router is created.
`dtr.runtime.js` composes focused functions in dependency order. Factories receive
their dependencies explicitly; cached modules must not retain an earlier database
pool or mock. Holiday-column capability caching remains per router instance.

## Compatibility requirements

1. Preserve endpoint paths, registration order, middleware, response fields, and
   status codes. Keep the bulk-report heavy-work wrapper on the router.
2. Keep the flat Express router stack: existing tests and integrations inspect it.
3. Preserve date-effective assignments, saved shift snapshots, overnight rules,
   working-day overrides, and holiday/leave/locator precedence.
4. Physical punches remain authoritative when locator coverage is present.
5. Pagination happens after overlays; total-count headers refer to all scoped rows.
6. Keep audit writes, row locks, commit/rollback, reconciliation calls, and realtime
   broadcasts at their existing transaction boundaries.
7. Existing shared services stay at `src/services/`. Biometric import routes, the
   DTR assistant, Leave, Locator, and other teams' modules are outside this extraction.

## Verification

Run `npm run test:dtr-management`, `npm run test:leave-management`, and
`npm run preflight` from `backend/`.

The DTR suite checks the captured route/authorization contract, authentication
through real Express requests, repeated dependency loading, relative import casing,
reports and pagination, overlays, historical scope, shifts, attendance policies,
manual corrections, audit deletion/restoration, and the heavy-work wrapper.
This refactor requires no database migration and changes no schema or records.
