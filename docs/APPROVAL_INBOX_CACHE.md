# Shared Leave and Locator approval inbox

The Flutter client shares `/api/approval-workflows/inbox?include_history=true`
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
devices. This optimization does not change the server's Nginx limits or establish
a supported user capacity; those still require monitoring and load testing.

This is a frontend-only change. Restart the Flutter development app or rebuild
and distribute the Windows application to use it. No database migration or
backend restart is required.

Verification: 179 selected Flutter tests passed, including inbox concurrency,
expiry, session isolation, mutation/realtime invalidation, approval-tab access,
backup completion, revocation, notifications and loading-state regressions.
Dart analysis of all changed Dart files reported no issues. The original two
request-count regressions were demonstrated failing before implementation.
No live-server load test or production deployment was performed.
