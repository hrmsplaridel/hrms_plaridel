# ZKTeco Biometric Sync Service

Local service that connects to ZKTeco devices via TCP (pyzk) and pushes attendance logs to the HRMS backend.

## Quick Start

```bash
cd backend
pip install -r scripts/requirements-zkteco.txt
# Set environment (see below)
python scripts/zkteco-sync-py.py
```

## Environment Variables

| Variable             | Default               | Description                                                        |
| -------------------- | --------------------- | ------------------------------------------------------------------ |
| `HRMS_API_URL`       | http://localhost:3000 | Backend base URL                                                   |
| `BIO_SYNC_API_KEY`   | (required)            | API key for push and `/devices` endpoints                          |
| `ZK_POLL_INTERVAL`   | 10                    | Poll interval in seconds                                           |
| `ZK_TIMEZONE_OFFSET` | +08:00                | Device local time offset (Philippines: +08:00)                     |
| `ZK_SYNC_STATE_FILE` | (internal)            | State is stored in `backend/.zkteco-sync-state.json` per device IP |

Active device IPs are loaded from **`GET /api/biometric-attendance-logs/devices`** (rows in `biometric_devices`). You do not set a single `ZK_DEVICE_IP` in the Python sync unless you change the script.

## Setup

1. **Backend**: Add `BIO_SYNC_API_KEY` to `.env` (or environment):

   ```
   BIO_SYNC_API_KEY=your-secure-random-key
   ```

   Generate a key: `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`

2. **Devices**: Register devices in HRMS (`biometric_devices`) with correct `ip_address` on the same network as the machine running the sync script.

3. **User mapping**: Each employee must have `biometric_user_id` set in the HRMS `users` table to match the device user ID. Unmatched punches are skipped (and counted in the push response).

### Push HRMS users onto the device (enrollment stub)

The backend can **create/update** a user record on the ZKTeco (`pyzk` `set_user`) so the ID and name exist on the clock. **Fingerprint/face templates** are still enrolled **on the physical device** (or vendor software) after the user exists.

- **API**: `POST /api/biometric-devices/:deviceId/push-user` (admin JWT), body `{ "employee_id": "<uuid>" }`. Requires the employee to have **`biometric_user_id`** set; uses **`full_name`** as the display name on the device (truncated in `zk_actions.py`).
- **Flutter**: Edit Employee → **Push to clock** (device dropdown + button).
- **Requirements**: Same as **GET /users** — the **API server host** must reach the device **IP** on TCP **4370**, with **Python + pyzk** installed where `zk_actions.py` runs (the Node backend process).

## How to Run

```bash
cd backend
python scripts/zkteco-sync-py.py
```

Run in the background (e.g. via `pm2`, `systemd`, or `nohup`):

```bash
nohup python scripts/zkteco-sync-py.py > zkteco-sync.log 2>&1 &
```

## Dependencies

- **Python 3** with **pyzk** and **requests** — see `scripts/requirements-zkteco.txt`.

## Poll Interval

**Recommended: 10 seconds.** This balances real-time updates, device load, and network use. Use 30–60 seconds if the device has very large log counts or a slow link.

## Duplicate Prevention

1. **Client**: Persists `lastRecordTime` per device IP in `.zkteco-sync-state.json`. Only records _after_ that time are sent.
2. **Server**: Uses `ON CONFLICT (biometric_user_id, logged_at) DO NOTHING` to ignore duplicates.

## Error Handling

- **Device connection failed**: Retries on the next poll. Check IP, port, and network.
- **Push failed**: Logged; next poll will resend the same records (server dedup handles it).
- **Unmatched biometric_user_id**: Punch is skipped. Ensure `users.biometric_user_id` matches the device.
- **Policy skips**: Server may skip insert when there is no shift, a **whole-day holiday**, or **blocking approved leave**; see push response `skipped_no_schedule`, `skipped_holiday`, `skipped_leave`.

## Diagnostics

- **`python scripts/zkteco_python_proof.py`** — quick connect / users / attendance test.
- **`node scripts/zkteco-diagnose.js`** — step-by-step Node/pyzk-style isolation (optional; requires Node + node-zklib if used).

See `scripts/ZK_DIAGNOSTIC_REPORT.md` for more.

---

## Limitations

| Limitation         | Notes                                                                                     |
| ------------------ | ----------------------------------------------------------------------------------------- |
| **Full log fetch** | Fetches attendance from the device; first run can be slow if the device has many records. |
| **Multi-device**   | One process polls every IP returned by `/devices`.                                        |
| **TCP**            | Typical ZKTeco port 4370.                                                                 |
| **Polling**        | Not a persistent real-time stream from the device.                                        |
