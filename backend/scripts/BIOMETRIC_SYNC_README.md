# ZKTeco Biometric Sync Service

Local service that connects to a ZKTeco K20 (or compatible) device via TCP and pushes attendance logs to the HRMS backend.

## Quick Start

```bash
cd backend
npm install
# Set environment (see below)
node scripts/zkteco-sync.js
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ZK_DEVICE_IP` | 192.168.1.201 | Device IP address |
| `ZK_DEVICE_PORT` | 4370 | Device TCP port |
| `ZK_POLL_INTERVAL` | 10 | Poll interval in seconds |
| `HRMS_API_URL` | http://localhost:3000 | Backend base URL |
| `BIO_SYNC_API_KEY` | (required) | API key for push endpoint |
| `ZK_SYNC_STATE_FILE` | .zkteco-sync-state.json | Path to persist last sync time |
| `ZK_TIMEZONE_OFFSET` | +08:00 | Device stores local time; use +08:00 for Philippines so dates/times display correctly |

## Setup

1. **Backend**: Add `BIO_SYNC_API_KEY` to `.env` (or environment):
   ```
   BIO_SYNC_API_KEY=your-secure-random-key
   ```
   Generate a key: `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`

2. **Device**: Ensure the ZKTeco device is on the same network, and `ZK_DEVICE_IP` is correct.

3. **User mapping**: Each employee must have `biometric_user_id` set in the HRMS `users` table to match the device user ID. Unmatched punches are skipped (and counted in the response).

## How to Run

```bash
cd backend
node scripts/zkteco-sync.js
```

Run in the background (e.g. via `pm2`, `systemd`, or `nohup`):

```bash
nohup node scripts/zkteco-sync.js > zkteco-sync.log 2>&1 &
```

## Dependencies

- **node-zklib** (^1.3.0) – ZKTeco device protocol. Installed with `npm install`.
- Node.js 18+ (for native `fetch`). For older Node, add `node-fetch` and adjust the script.

## Poll Interval

**Recommended: 10 seconds.** This balances:

- **Real-time**: New punches appear in HRMS within ~10–30 seconds.
- **Device load**: Avoids hammering the device; K20 can be slow with large log counts.
- **Network**: Minimal API traffic.

Use 30–60 seconds if the device has thousands of logs or is on a slow link.

## Duplicate Prevention

1. **Client**: Persists `lastRecordTime` to `.zkteco-sync-state.json`. Only records *after* that time are sent.
2. **Server**: Uses `ON CONFLICT (biometric_user_id, logged_at) DO NOTHING` to ignore duplicates.

## Error Handling

- **Device connection failed**: Retries on the next poll. Check IP, port, and network.
- **Push failed**: Logged; next poll will resend the same records (server dedup handles it).
- **Unmatched biometric_user_id**: Punch is skipped. Ensure `users.biometric_user_id` matches the device.

## Python Alternative (if Node times out on K20)

If `zkteco-sync.js` fails with `TIMEOUT_ON_RECEIVING_REQUEST_DATA` on ZKTeco K20/ZMM200_TFT:

1. **Proof script:** `python scripts/zkteco_python_proof.py` — tests connect, users, attendance
2. **Python sync:** `python scripts/zkteco-sync-py.py` — same behavior as Node, uses pyzk
3. **Install:** `pip install -r scripts/requirements-zkteco.txt`

See `scripts/ZK_DIAGNOSTIC_REPORT.md` for details.

---

## Limitations

| Limitation | Notes |
|------------|-------|
| **Full log fetch** | `getAttendances()` returns *all* logs. No server-side filter. First run can be slow if the device has many records. |
| **Single device** | Script connects to one device. For multiple devices, run one process per device with different `ZK_DEVICE_IP`. |
| **TCP only** | ZKTeco K20 uses TCP. UDP fallback exists in node-zklib but K20 typically uses TCP. |
| **No real-time mode** | Uses polling, not `getRealTimeLogs()`. Real-time would require a persistent connection and more complex handling. |
| **Comm code** | Some devices need `comm_code` for auth. node-zklib constructor supports it; extend the script if required. |
