# ZKTeco K20 Sync Diagnostic Report

## A. Exact Failing Step

**Failing step:** `getAttendances()` → `readWithBuffer(REQUEST_DATA.GET_ATTENDANCE_LOGS)` → `requestData(buf)`

**Location:** `node_modules/node-zklib/zklibtcp.js` — `requestData()` line 131

**Flow:**
1. `createSocket()` → TCP connect + CMD_CONNECT — **succeeds** ("ok tcp")
2. `getAttendances()` calls `freeData()` then `readWithBuffer(GET_ATTENDANCE_LOGS)`
3. `readWithBuffer` sends `CMD_DATA_WRRQ` with attendance log request
4. `requestData` waits for device response
5. Device either doesn't respond in time, or responds with a command ID that triggers the timeout path
6. **`TIMEOUT_ON_RECEIVING_REQUEST_DATA`** is thrown

The timeout occurs specifically during **attendance log retrieval**. The device may:
- Respond with `CMD_PREPARE_DATA` (chunked transfer) but the chunk receive logic times out
- Use a slightly different protocol for K20/ZMM200_TFT that node-zklib doesn't handle
- Require `disable_device` before data fetch (pyzk does this; node-zklib did not originally)

---

## B. Is node-zklib the Issue?

**Likely yes**, for this device. Evidence:

| Factor | node-zklib | Observation |
|--------|------------|-------------|
| **Age/maintenance** | Last update ~2020, low activity | May not support newer K20/ZMM200_TFT protocol |
| **disable_device** | Not called before getAttendances | pyzk explicitly disables device; some ZKTeco models require it |
| **Protocol variation** | Single implementation | ZKTeco has many device families; protocol differs |
| **Timeout handling** | Fixed timeouts, no retry | Chunked receive can fail on slow/large datasets |

**Mitigation attempted:** Added `disableDevice()` before `getAttendances()` in the sync script. If that doesn't fix it, **replace with pyzk**.

---

## C. Recommended Local Sync Stack

| Priority | Stack | When to use |
|----------|-------|-------------|
| **1** | **Python + pyzk** | When node-zklib times out on K20/ZMM200_TFT |
| 2 | Node + node-zklib (with disableDevice) | If diagnostic shows success after adding disable |

**Recommendation:** Run the diagnostic script first. If step 5 (getAttendances) still fails, **switch to the Python sync** (`zkteco-sync-py.py`).

---

## D. Python Proof-of-Connection Script

**File:** `backend/scripts/zkteco_python_proof.py`

**Install:**
```bash
pip install pyzk
# or
pip install -r scripts/requirements-zkteco.txt
```

**Run:**
```bash
cd backend
python scripts/zkteco_python_proof.py
```

**Expected output (success):**
```
--- ZKTeco K20 Python proof-of-connection ---
Device: 192.168.254.201:4370

[1] Connecting...
[OK] Connected
[2] Disabling device...
[OK] Device disabled
[3] Getting device info...
    Firmware: ...
[4] Getting users...
[OK] N users
[5] Getting attendance logs...
[OK] M attendance records
[6] Enabling device...
[OK] Device enabled

--- All steps completed successfully ---
```

**If successful:** Use `zkteco-sync-py.py` as the sync service instead of `zkteco-sync.js`.

---

## Diagnostic Script (Node)

**Run to isolate the failing step:**
```bash
node scripts/zkteco-diagnose.js
```

This tries, in order: connect → getInfo → getUsers → disableDevice → getAttendances → enableDevice → disconnect. The last [OK] before [FAIL] identifies the failing step.

---

## Summary

| Question | Answer |
|----------|--------|
| **Exact failing step** | `getAttendances()` → `requestData()` in node-zklib |
| **node-zklib the issue?** | Likely yes for K20/ZMM200_TFT |
| **Recommended stack** | Python + pyzk if Node continues to fail |
| **Proof script** | `zkteco_python_proof.py` |
