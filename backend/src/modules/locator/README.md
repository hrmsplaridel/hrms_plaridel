# Locator backend module

`src/routes/locatorSlips.js` remains the compatibility entry used by the server
and workflow integrations. `locator.router.js` registers the same 30 endpoints
and authenticated `/print` mount under `/api/locator-slips`, in their original order.

## Responsibilities

- `controllers/`: availability, request types, personal requests, staff filing,
  submission, documented corrections, cancellation/resubmission, attachments,
  history, department/final queues and decisions, and revocation.
- `policies/`: type defaults and validation, field parsing, and request statuses.
- `repositories/`: shared type and request-detail queries. Endpoint-specific SQL
  stays with its controller so existing transaction bodies remain together.
- `serializers/`: type/request response fields, date-only values, and conflicts.
- `services/`: notifications/realtime events and composition of the existing
  shared submission service.
- `infrastructure/`: upload storage and the retained startup compatibility
  initializer. This extraction neither adds nor removes initialization queries.

`dependencies.js` resolves shared services for each new router instance.
`locator.runtime.js` composes the module's functions in dependency order. Each
factory receives explicit dependencies and creates fresh closures; cached module
files must not retain an earlier database pool, submission service, or test mock.

## Compatibility requirements

1. Preserve endpoint paths, middleware order, status codes, and response fields.
   Keep the flat Express router stack used by workflow integrations.
2. Preserve approval routing, reviewer/signature checks, type snapshots, correction
   rules, and history. Keep each transaction's locks, writes, audit records, and
   commit/rollback on the same PostgreSQL client.
3. Keep notifications and broadcasts at their existing points relative to commit.
4. The default upload root remains `backend/uploads`. `UPLOAD_DIR` overrides it
   as before; stored attachment paths remain `locator-attachments/<filename>`.
   Preserve file restrictions, access auditing, and failed-submission cleanup.
5. The print router and shared Locator services retain their existing paths.
   Existing Leave, DTR, shared workflow, and DocuTracker integrations are unchanged.
6. Retain the legacy startup initializer's behavior. Replacing it with explicit
   migrations is a separate change and is outside this refactor.

## Verification

Run `npm run test:locator-management`, `npm run test:leave-management`,
`npm run test:dtr-management`, and `npm run preflight` from `backend/`.

The Locator suite covers the captured endpoint/middleware contract, authentication
through real Express requests, fresh dependencies, relative import casing, upload
roots and multipart handling, failure cleanup, transaction/audit/broadcast ordering,
filing, workflow transitions, reviewer access, corrections, attachments, signatures,
snapshots, printable layouts, and leave/locator queue separation.

Tests use mock database clients and temporary upload directories. The opt-in
`locator*Postgres.integration.test.js` suites are separate and require their
documented disposable test database variables; the management command does not
connect to the application database or apply migrations.
