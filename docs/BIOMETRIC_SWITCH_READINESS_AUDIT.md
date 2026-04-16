# Biometric Switch Readiness Audit — HRMS DTR Module

**Date:** March 22, 2025  
**Scope:** Switch from manual Time In/Time Out button attendance to biometric-device-based attendance with real-time admin dashboard updates.

---

## A. Executive Summary

| Question | Answer |
|----------|--------|
| **Is the system biometric-switch ready?** | **Partially** |
| **Can admin dashboard reflect biometric punches in real time with the current implementation?** | **Partially** (polling every 30s on Time Logs only; dashboard does not poll) |

**Summary:**  
The codebase has substantial biometric infrastructure already in place: `biometric_attendance_logs` table, `biometricProcessing.js` to interpret punches and write to `dtr_daily_summary`, and an admin UI for importing `.dat` files. Attendance creation is **partially abstract** — the backend POST and biometric processing both write to the same `dtr_daily_summary` table, but the frontend clock-in flow is tightly coupled to employee button clicks. Real-time updates are **polling-based** (30s) only on the DTR Time Logs screen; the admin dashboard and employee dashboard do not auto-refresh, so new biometric punches will not appear until manual refresh or navigation.

---

## B. Current Attendance Flow

### Step-by-step flow (manual button punch)

1. **UI** — Employee taps Clock In / AM Out / PM In / PM Out on `_ClockInCard` in `employee_dashboard.dart` (lines 906–975).
2. **State management** — `DtrProvider` methods: `clockIn()`, `clockAmOut()`, `clockPmIn()`, `clockPmInAsFirst()`, `clockOut()`.
3. **Repository** — `TimeRecordRepo.instance.insert()` or `update()`.
4. **API** — `POST /api/dtr-daily-summary` (create) or `PUT /api/dtr-daily-summary/:id` (update).
5. **Backend** — `dtrDailySummary.js`: inserts/updates `dtr_daily_summary` with `source = 'manual'`, computes late/undertime from shift rules.
6. **Database** — `dtr_daily_summary` table.
7. **Admin update** — After punch, `DtrProvider` calls `loadTodayRecord()` and optionally `loadTimeRecordsForAdmin()`. Admin DTR Time Logs screen polls every 30s via `Timer.periodic`.

### Files/modules involved

| Layer | File | Role |
|-------|------|------|
| UI | `lib/employee/screens/employee_dashboard.dart` | `_ClockInCard` — Time In/Out buttons |
| Provider | `lib/dtr/dtr_provider.dart` | `clockIn`, `clockAmOut`, `clockPmIn`, `clockPmInAsFirst`, `clockOut` |
| Data | `lib/data/time_record.dart` | `TimeRecord` model, `TimeRecordRepo` |
| API | `lib/api/client.dart` | Dio HTTP client |
| Backend | `backend/src/routes/dtrDailySummary.js` | POST, PUT, GET |
| DB | `dtr_daily_summary` | Attendance records |

---

## C. Readiness Assessment

| Area | Status | Notes |
|------|--------|-------|
| **Backend** | Partially ready | Biometric import + processing exist; manual POST is separate flow; no real-time push API |
| **Frontend** | Not ready for switch | Employee clock-in tightly coupled to buttons; no abstraction for “attendance from any source” |
| **Database** | Ready | `dtr_daily_summary`, `biometric_attendance_logs`, `users.biometric_user_id`, `source` column |
| **Dashboard realtime** | Partially ready | DTR Time Logs polls 30s; DTR Dashboard and Employee Dashboard do not auto-refresh |
| **DTR processing** | Ready | Late/undertime computed on read; punch interpretation works for 1–4+ punches |

---

## D. Gaps / Missing Pieces

### 1. Source of attendance truth

- **Current:** Employee UI action → `DateTime.now()` on client → sent to backend → stored.
- **Timestamp:** Client-side; backend trusts it (no server timestamp override).
- **Coupling:** `DtrProvider` clock methods are the **only** path that creates/updates records from the employee UI. Biometric import bypasses this and writes directly to DB.

### 2. Biometric-switch readiness

| Capability | Status | Notes |
|------------|--------|-------|
| Imported biometric logs | ✅ Ready | `POST /api/biometric-attendance-logs/import` + `processBiometricLogsToSummary()` |
| API-pushed biometric logs | ⚠️ Needs work | Import expects `user_id`; device would need to push with `biometric_user_id` and backend would resolve to `user_id` |
| Local sync service/device listener | ❌ Missing | No service that listens to device or syncs from local device export |
| Multiple input sources | ✅ Supported | `source` column: `manual`, `system`, `adjusted`; biometric uses `system` |

### 3. Real-time admin dashboard readiness

| Component | Refresh mechanism | Real-time? |
|-----------|-------------------|------------|
| DTR Time Logs | `Timer.periodic(30s)` → `_applyFilters()` | Polling (30s) |
| DTR Dashboard | `_load()` on init only | No |
| Employee Dashboard | `loadTodayRecord()` on init only | No |
| DTR Recent Activity | Passed `dtr.timeRecords` from provider | Depends on parent refresh |

**Result:** A biometric-generated record inserted into `dtr_daily_summary` will:
- **Appear on DTR Time Logs** within 30 seconds (if that screen is open).
- **Not appear on DTR Dashboard** until manual refresh or re-navigation.
- **Not appear on Employee Dashboard** until manual refresh or re-navigation.

**Missing:** WebSocket/Socket.io or similar for push-based updates; no server-side real-time mechanism.

### 4. Database readiness

| Item | Status | Notes |
|------|--------|-------|
| `dtr_daily_summary` | ✅ | time_in, break_out, break_in, time_out, source |
| `biometric_attendance_logs` | ✅ | user_id, biometric_user_id, logged_at, raw_line |
| `users.biometric_user_id` | ✅ | Maps device user ID → HRMS user |
| `biometric_devices` | ✅ | device_id, name, location, last_sync_at |
| `dtr_logs` | ⚠️ | Has device_ref_id; **biometric_attendance_logs** does NOT have device_id/terminal_id |
| device_id / terminal_id in raw logs | ❌ | `biometric_attendance_logs` has `source_file_name` only, no device FK |
| sync_status / device sync | ❌ | No sync_status on biometric_attendance_logs |

### 5. Business logic readiness

| Logic | Status | Notes |
|-------|--------|-------|
| Late minutes | ✅ | Computed on GET from `dtrDailySummary.js` (shift-based) |
| Undertime | ✅ | Same |
| Work hours / total_hours | ✅ | Computed in `biometricProcessing.interpretPunchesForDay` |
| Daily summary | ✅ | Same table, same structure |
| Punch pairing | ✅ | `interpretPunchesForDay`: 1→time_in; 2→time_in+time_out; 3→incomplete; 4+→time_in, break_out, break_in, time_out |

**Note:** `biometricProcessing.js` inserts with `late_minutes=0`, `undertime_minutes=0`. The GET handler recomputes these when they are 0, so late/undertime are correct when data is read.

### 6. UI dependency removal

**If the employee Time In/Time Out button is removed:**

| Component | Impact |
|-----------|--------|
| `_ClockInCard` | Would show no next action; employee cannot punch |
| `DtrProvider.clockIn/Out` | Would become unused for employees; admin `addManualEntry` still uses `TimeRecordRepo.upsert` |
| Employee “today” status | Depends on `loadTodayRecord()` — would still work if data comes from biometric |
| Admin counters (Present/Late) | `loadSummary()` reads from DB; would reflect biometric data |
| Reports, summaries | Read from `dtr_daily_summary`; source-agnostic |

**Conclusion:** Counters, reports, and summaries do **not** depend on the button. Only the employee punch **action** does. If biometric is the source, employee dashboard can show “Today’s status” as read-only.

---

## E. Recommended Refactor Plan

### Phase 1: Minimal changes (enable biometric as primary)

1. **Add polling to DTR Dashboard**  
   Use same 30s timer as DTR Time Logs so `loadSummary()` and `loadTimeRecordsForAdmin()` run periodically.

2. **Add polling to Employee Dashboard**  
   Poll `loadTodayRecord()` every 30–60s so biometric punches show without refresh.

3. **Keep manual punching as fallback**  
   Do not remove buttons yet; allow both manual and biometric. Use `source` to distinguish.

4. **Optional: device_id in biometric_attendance_logs**  
   Add `device_id` FK (or `device_ref_id`) if multiple devices need to be tracked.

### Phase 2: Proper biometric integration

1. **Device push / sync API**  
   - `POST /api/biometric-attendance-logs/push` for devices that push single punches.  
   - Accept `biometric_user_id`, `logged_at`, `device_id`; resolve `user_id` from `users.biometric_user_id`; insert raw log; optionally trigger processing for that user/date.

2. **Real-time updates**  
   - Add Socket.io (or similar) for `dtr_daily_summary` changes.  
   - Emit events on INSERT/UPDATE; admin and employee UIs subscribe and refresh.

3. **Employee dashboard: read-only mode**  
   - When biometric is primary, hide or disable punch buttons.  
   - Show “Last punch: X” from `todayRecord`; no edit actions.

### Phase 3: Optional cleanup

1. Remove employee punch buttons if manual punching is fully deprecated.
2. Add `device_id` to `biometric_attendance_logs` for multi-device tracking.
3. Add `sync_status` if device sync needs retry/error handling.

---

## F. Concrete File-Level Action Items

| File | What to change | Why |
|------|----------------|-----|
| `lib/dtr/screens/dtr_dashboard.dart` | Add `Timer.periodic(30s)` calling `_load()` | Admin dashboard shows new biometric punches without manual refresh |
| `lib/employee/screens/employee_dashboard.dart` | Add `Timer.periodic(30s)` calling `dtr.loadTodayRecord()` | Employee sees biometric punches without refresh |
| `backend/src/routes/biometricAttendanceLogs.js` | Add `POST /push` for single-punch from device | Enables real-time device push without file import |
| `backend/scripts/init-schema.sql` (migration) | Add `device_ref_id UUID REFERENCES biometric_devices(id)` to `biometric_attendance_logs` | Track which device produced each punch |
| `backend/src/index.js` | Add Socket.io server; emit on dtr_daily_summary change | True real-time updates |
| `lib/dtr/dtr_provider.dart` | Optional: add WebSocket listener to refresh on server push | Consume real-time events |
| `lib/employee/screens/employee_dashboard.dart` | When config says “biometric only”, hide/disable `_ClockInCard` buttons, show read-only status | Remove UI dependency on manual punch |

---

## G. Integration Gap Summary

| Category | Items |
|----------|-------|
| **Already ready** | `dtr_daily_summary` schema, `biometric_attendance_logs`, `biometric_user_id` mapping, punch interpretation, late/undertime on read, import API, DTR Time Logs 30s poll |
| **Needs refactor** | DTR Dashboard and Employee Dashboard (add polling or real-time), optional device push API |
| **Missing entirely** | WebSocket/real-time push, device-level push endpoint, `device_id` in raw logs, sync service for device export |
| **Risky/unclear** | Client `DateTime.now()` for manual punch (could be spoofed); no server timestamp override |

---

## H. Answer to Key Questions

1. **Can attendance come from a non-UI source?**  
   **Yes.** Biometric import already writes to `dtr_daily_summary` with `source = 'system'`. The backend and DB support multiple sources.

2. **Would an inserted attendance log from an external source automatically update the admin dashboard?**  
   **No.** Only the DTR Time Logs screen polls every 30s. The DTR Dashboard and Employee Dashboard do not auto-refresh. Manual refresh or navigation is required for them to show new data.

3. **Is attendance creation reusable from a biometric source?**  
   **Yes.** `processBiometricLogsToSummary()` writes to the same table. It does not go through `DtrProvider` or the employee UI.
