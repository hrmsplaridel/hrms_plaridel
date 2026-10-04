# System health

System Administrator → System Health shows CPU, memory, disk, API process uptime,
and PostgreSQL connectivity. Only active `super_admin` accounts can read
`GET /api/system-health?hours=1|24|168`; the endpoint uses the existing account
verification and role checks and disables response caching.

The API collects readings at startup and every minute, even with no dashboard open.
The first CPU reading is unavailable until two CPU counter samples exist. Charts
show averages in at most 337 time buckets; missing buckets appear as gaps.
Warnings flag CPU ≥85%, memory ≥90%, disk ≥85%, available disk below 10%, database
failure, database latency ≥1 second, and unavailable readings. These are dashboard
warnings, not email/SMS alerts. No backup tracking or request-performance monitoring
is included in this first version.

History is capped at seven days / 10,081 readings, stored in a private local JSON
file with atomic replacement. A failed disk write leaves readings available in
memory and shows a persistence warning. Restarting the API reloads saved history.
No schema change or database migration is required.

Optional backend environment settings:

| Setting | Default | Purpose |
| --- | --- | --- |
| `SYSTEM_HEALTH_DATA_DIR` | `backend/.system-health` | Persistent writable directory for history; keep outside public/static uploads. |
| `SYSTEM_HEALTH_DISK_PATH` | `backend/uploads` | Existing directory on the filesystem to monitor. |

Use a persistent volume for history when deploying in containers. The collector is
intended for this application's single API instance; multiple processes must use
separate history directories. It measures resources visible to the API host, not
the browser's computer or a remote database server. Memory usage is total minus
free memory and can include OS caches; container quotas are not separately measured.
Disk used space excludes free blocks; available space excludes reserved blocks.
The dedicated database probe pool is limited to one connection with five-second
connection, query, and statement timeouts.

Collection stops when the API is stopped. Gaps therefore do not establish a precise
outage duration. The dashboard marks readings older than two minutes stale and
preserves the last displayed readings when refresh fails. Existing authentication
requires PostgreSQL, so during a database outage readings continue to be recorded
locally but the dashboard may not be accessible until authentication recovers.
Use external monitoring if alerts during complete API/database outages are needed.

Validation:

```text
cd backend
node --test test/systemHealth.test.js test/authMiddlewareAccountState.test.js test/accountCreationAccess.test.js
cd ../frontend
flutter test --no-pub test/system_health_page_test.dart
flutter analyze --no-pub lib/features/dashboard/presentation/super_admin test/system_health_page_test.dart
```

Implementation uses Node's [OS counters](https://nodejs.org/api/os.html) and
[filesystem statistics](https://nodejs.org/api/fs.html#class-fsstatfs).
