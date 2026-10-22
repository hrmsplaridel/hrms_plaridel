# Shared Leave and Locator approval inbox

The Flutter client shares `/api/approval-workflows/inbox?include_history=true&paginated=true&limit=50`
between Leave and Locator. Previously, approval-tab checks and both modules
independently downloaded the same full response.

`WorkflowInboxCache` keeps one in-memory response for 15 seconds and combines
concurrent reads, including concurrent explicit refreshes, into one HTTP request.
Each consumer receives an independent copy filtered to its module. It does not
cache reviewer-eligibility endpoints or grant authority to approve a request.
The backend continues to authorize and validate every action.

Manual queue refreshes, action-triggered refreshes and the Leave review dialog's
live checks bypass the cached response. A forced read joins an existing fetch;
a mutation or realtime invalidation supersedes an older in-flight response so it
cannot repopulate the cache with obsolete assignments. Failed reads propagate
their error, and subsequent reads can retry.

Successful Leave, Locator, workflow and related reviewer-configuration mutations
invalidate the inbox through `ApiClient`. Decision conflicts invalidate it too.
The shared review dialog also invalidates after a successful decision. The
realtime bridge invalidates on Leave/Locator changes, and a WebSocket connection
invalidates data that may have changed while disconnected.

Login, logout, credential removal and account/role changes clear the cache and
terminate old-session readers. Data is never persisted to disk or shared between
devices. This optimization does not change the server's Nginx limits.

## Pagination and query work

The first response contains at most 50 visible records per module. Independent
`has_more` and `next_cursor` maps prevent one module's records from hiding the
other module's approval tab. Each queue offers **Load more workflow requests**.
Requests awaiting a decision come before history. Counts identify loaded Leave
requests while additional assigned pages remain.

Continuations include `kind` and `cursor`. The backend validates module, history
scope and page size (1–200 per module). Cursors retain PostgreSQL's timestamp
precision and the request ID, including when records share a timestamp. Rows
are scanned in batches of 100, and authorization filtering happens before a
visible page fills. A `request_id` lookup verifies one selected request without
downloading all pages again; a later-page request remains reviewable.

Identical SELECT queries from the existing reviewer resolver are reused only
within one inbox HTTP request. This reduces repeated primary/backup, user and
access lookups without caching authority between requests or changing action
authorization. Distinct applicants/assignments can still require distinct
queries. Older clients retain the original array response when `paginated`
is omitted, and the new client accepts that legacy array during rollout.

## Local load test — October 23, 2026

From `backend/`, run `node scripts/load-test-workflow-inbox.js`. It requires the
local `localhost:5433/hrms_plaridel` connection, creates a uniquely named empty
test database, seeds synthetic accounts and records, starts an isolated HTTP
server on an ephemeral loopback port, and removes the database afterward. It
does not seed or migrate the application database, send emails, or alter the
running backend's configuration. Database credentials/JWTs are not printed.

The fixture contains 50 synthetic reviewers, 2,007 Leave requests and 2,007
Locator requests, with explicit primary/backup steps and approved history. Each
phase sends ten waves of simultaneous reads from `127.0.0.1`, using the real
authentication, application rate limiters, inbox service and PostgreSQL pool
(20 connections). PostgreSQL checks also exercise dynamic department, final HR,
Mayor/manual routes, visibility, history, tied timestamps and targeted reads.

| Concurrent users | Requests | HTTP 200 | Median | 95th percentile |
| --- | --- | --- | --- | --- |
| 10 | 100 | 100 | 167.4 ms | 555.2 ms |
| 25 | 250 | 250 | 413.7 ms | 636.5 ms |
| 50 | 500 | 500 | 750.4 ms | 1,067.0 ms |

The 50-user phase delivered 55.4 requests/second, averaging 9.8 SQL queries per
request and 152,987 response bytes. The comparison unpaged response for the
first reviewer contained 446 records and 693,830 bytes. Request-scoped query
reuse kept that unpaged read to 10 queries as well; the optimization tests assert
that repeated reviewer lookups are shared, while later HTTP requests recheck.

These are local synthetic measurements, not an Ubuntu production capacity
guarantee. They exclude Nginx/Cloudflare, network latency, Flutter rendering and
other endpoints; the test client and API also run in the same Node process.
The Nginx rate of 10 requests/second still applies to the entire office IP;
`burst=60` only accommodates temporary excess. Validate realistic combined
traffic through staging before deciding on a higher sustained network limit.

## Deployment and verification

Deploy the backend changes, run `npm run preflight`, restart Ubuntu's `hrms-api`
service and check `/health` and `/health/db`. Rebuild/distribute the Windows app
to use paged loading. Updating the landing website alone does not update an
installed Windows app. No schema migration or initializer change is required.

Validation includes the full Leave (404) and Locator (358) backend suites,
pagination/route tests, real PostgreSQL workflow checks, and Flutter cache,
load-more, session, approval, backup, revocation, notification and loading-state
regressions. Edited Dart files pass analysis. The local PM2 backend was restarted
and both legacy and paged inbox responses passed authenticated read-only smoke
checks. No production deployment or production load test was performed.
