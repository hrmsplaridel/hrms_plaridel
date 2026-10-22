# Leave backend module

`src/routes/leaveRoutes.js` is the compatibility entry used by the server and the
shared workflow bridge. Keep that import path working. `leave.router.js` creates
the Express router and registers all existing endpoints in their original order.

## Responsibilities

- `controllers/`: HTTP handlers for filing, reviews, balances, attachments, types,
  signatories, and administration. Filing and review transaction bodies remain
  together so their locks, credit movements, signatures, DTR coverage, and audit
  writes still commit or roll back as one operation.
- `use-cases/`: approval finalization and credit reservation/release workflows.
  Functions receive the caller's PostgreSQL client; they do not open a second
  transaction or substitute the connection pool for that client.
- `repositories/`: shared queries and query fragments for requests, types, and
  review queues. Some endpoint-specific SQL remains with its controller to keep
  this extraction behavior-preserving.
- `policies/`: calendar-date validation, leave-type configuration, and request
  detail parsing. Existing shared policy services remain at their original paths.
- `services/`: working-day and annual-entitlement calculations, signatory lookup,
  and notification/realtime helpers.
- `serializers/`: the existing request/type API response mappings.
- `infrastructure/`: upload storage and the retained legacy startup initializer.

`dependencies.js` loads existing shared services when a router is created.
`leave.runtime.js` composes the module's functions in dependency order. Factories
declare their dependencies explicitly and create fresh closures for each router;
loading a cached component must not retain a previous database pool or test mock.
No runtime dependency on a code generator or developer-installed tool is needed.

## Compatibility requirements

1. Keep existing API paths, status codes, response fields, and middleware order.
2. Keep the router's endpoint handlers available directly on `router.stack`:
   shared approval requests delegate to these handlers for approval and downloads.
3. Preserve fixed-path ordering ahead of `GET /:id`.
4. The default upload root remains `backend/uploads`; `UPLOAD_DIR` still overrides
   it exactly as before. Moving a file must not change where attachments are read.
5. Send notifications after the same commit points as before. Do not move credit,
   signature, coverage, or history writes outside their existing transactions.
6. The legacy initializer still runs once when the compatibility entry is loaded,
   just as it did before extraction. Replacing it with explicit migrations is a
   separate behavior change, not part of this refactor.

## Verification

Run `npm run test:leave-management` and `npm run preflight` from `backend/`.
The management command includes `test/leaveModuleStructure.test.js`, which checks
the ordered route/middleware contract captured before extraction, authentication
through real Express requests, fresh dependency injection, relative imports, and
upload-root compatibility. Existing tests cover filing concurrency, workflow
delegation, signature checks, annual quotas, credit accounting, and DTR coverage.

For disposable PostgreSQL installation coverage, run `test/dtrFreshSchema.test.js`
with `DTR_FRESH_SCHEMA_TEST_DATABASE_URL` pointing to the intended local server.
That test creates and drops its own database; it does not install the fresh schema
over an existing application database.
