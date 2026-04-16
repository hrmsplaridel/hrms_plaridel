# 30-Second Polling Implementation Audit

**Date:** March 22, 2025  
**Files audited:** `dtr_dashboard.dart`, `employee_dashboard.dart`

---

## A. Is the polling implementation safe?

**Partially** — core correctness (timer lifecycle, context safety) is good; overlapping requests and incomplete data refresh are minor issues.

---

## B. Risks and inefficiencies

| Issue                       | Severity | Location           | Description                                                                                                                                                                                                             |
| --------------------------- | -------- | ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Overlapping requests        | Low      | DTR Dashboard      | If `_load()` is still running when the timer fires, a second `_load()` starts. Two concurrent API calls can race; the last response may be overwritten by an older one.                                                 |
| Redundant concurrent calls  | Low      | Employee Dashboard | Multiple `loadTodayRecord()` calls can run at once. No corruption, but duplicate API traffic.                                                                                                                           |
| Incomplete employee refresh | Medium   | Employee Dashboard | Polling only calls `loadTodayRecord()`. `_AttendanceCard` uses `dtr.timeRecords` (monthly present count). New biometric punches update `todayRecord` but not `timeRecords`, so the "Present Days" count can stay stale. |
| loadMyShiftToday not polled | Low      | Employee Dashboard | Shift end time rarely changes. Polling it adds little value and extra API calls.                                                                                                                                        |

---

## C. Code improvements (implemented)

### C1. DTR Dashboard — request guard

Skip a poll if a load is already in progress:

```dart
_pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
  if (!mounted) return;
  final dtr = context.read<DtrProvider>();
  if (dtr.loading) return;  // Avoid overlapping requests
  _load();
});
```

### C2. Employee Dashboard — refresh both today and month data

Include `loadTimeRecordsForUser` so `_AttendanceCard` stays up to date:

```dart
_pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
  if (!mounted) return;
  final dtr = context.read<DtrProvider>();
  if (dtr.loading) return;  // Optional: loadTodayRecord doesn't set loading
  dtr.loadTodayRecord();
  final now = DateTime.now();
  dtr.loadTimeRecordsForUser(
    startDate: DateTime(now.year, now.month, 1),
    endDate: DateTime(now.year, now.month + 1, 0),
  );
});
```

Note: `loadTodayRecord` does not set `_loading`; `loadTimeRecordsForUser` does. A `dtr.loading` check would guard against overlapping month refresh only.

### C3. DTR Dashboard \_load — mounted check for async

`_load()` is async and uses `context.read`. Add a post-await `mounted` check:

```dart
Future<void> _load() async {
  if (!mounted) return;
  final dtr = context.read<DtrProvider>();
  await dtr.loadSummary();
  if (!mounted) return;
  await dtr.loadTimeRecordsForAdmin(limit: 20);
}
```

---

## D. Request-locking assessment

| Screen             | Needed?            | Rationale                                                                                                                                                        |
| ------------------ | ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| DTR Dashboard      | Yes (simple guard) | `loadTimeRecordsForAdmin` sets `_loading`. Concurrent calls can race and overwrite state. A simple `if (dtr.loading) return` before calling `_load()` is enough. |
| Employee Dashboard | Optional           | `loadTodayRecord` does not set `_loading`. `loadTimeRecordsForUser` does. If we add `loadTimeRecordsForUser` to the poll, a `dtr.loading` guard helps.           |

**Recommendation:** Add the `dtr.loading` guard to both screens. No mutex or extra locking is required.

---

## Verification summary

| Check                               | DTR Dashboard                                  | Employee Dashboard  |
| ----------------------------------- | ---------------------------------------------- | ------------------- |
| Timer starts only once in initState | Yes                                            | Yes                 |
| Timer cancelled in dispose          | Yes                                            | Yes                 |
| No memory leaks                     | Yes                                            | Yes                 |
| No context access after unmount     | Yes (`if (!mounted) return`)                   | Yes                 |
| Duplicate initial + poll            | No (initial is post-frame; poll is 30s later)  | No                  |
| Overlapping requests                | Possible; add guard                            | Possible; add guard |
| Rebuild loops                       | No (provider `notifyListeners` is intentional) | No                  |
| Provider updates work               | Yes                                            | Yes                 |

---

## What should polling refresh?

**Employee Dashboard:**

| Data                              | Used by          | Poll? | Reason                       |
| --------------------------------- | ---------------- | ----- | ---------------------------- |
| `loadTodayRecord()`               | \_ClockInCard    | Yes   | Today’s punch status         |
| `loadTimeRecordsForUser()`        | \_AttendanceCard | Yes   | Monthly "Present Days" count |
| `loadMyShiftToday()`              | PM In validation | No    | Rarely changes               |
| `LeaveProvider.loadMyLeaveData()` | Leave cards      | No    | Out of scope for attendance  |

**Recommendation:** Poll both `loadTodayRecord()` and `loadTimeRecordsForUser()` so both Clock In and Attendance cards reflect biometric updates.
