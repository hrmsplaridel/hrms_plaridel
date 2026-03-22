#!/usr/bin/env python3
"""
ZKTeco sync service - Python version using pyzk.

Alternative to zkteco-sync.js when node-zklib fails on K20/ZMM200_TFT.

Install: pip install pyzk requests
Run: python scripts/zkteco-sync-py.py

Environment: Same as Node version (ZK_DEVICE_IP, ZK_DEVICE_PORT, HRMS_API_URL, BIO_SYNC_API_KEY, etc.)
"""
import json
import os
import sys
import time
from pathlib import Path

# Load .env
env_path = Path(__file__).resolve().parent.parent / ".env"
if env_path.exists():
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            os.environ.setdefault(k.strip(), v.strip())

DEVICE_IP = os.environ.get("ZK_DEVICE_IP", "192.168.254.201")
DEVICE_PORT = int(os.environ.get("ZK_DEVICE_PORT", "4370"))
POLL_INTERVAL = int(os.environ.get("ZK_POLL_INTERVAL", "10"))
API_URL = os.environ.get("HRMS_API_URL", "http://localhost:3000").rstrip("/")
API_KEY = os.environ.get("BIO_SYNC_API_KEY")
STATE_FILE = Path(__file__).resolve().parent.parent / ".zkteco-sync-state.json"
TIMEOUT = 60
# Device stores local time. Use same as HRMS (Asia/Manila = UTC+8). Do NOT use Z (UTC).
TZ_OFFSET = os.environ.get("ZK_TIMEZONE_OFFSET", "+08:00")

def load_last_sync():
    if STATE_FILE.exists():
        try:
            d = json.loads(STATE_FILE.read_text())
            return d.get("lastRecordTime")
        except Exception:
            pass
    return None

def save_last_sync(iso_str):
    try:
        STATE_FILE.write_text(json.dumps({
            "lastRecordTime": iso_str,
            "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
        }))
    except Exception as e:
        print(f"[zkteco-sync-py] Could not save state: {e}")

def sync_once():
    import requests
    from zk import ZK

    last = load_last_sync()
    last_dt = None
    if last:
        try:
            from datetime import datetime
            last_dt = datetime.fromisoformat(last.replace("Z", "+00:00"))
        except Exception:
            pass

    conn = None
    zk = ZK(DEVICE_IP, port=DEVICE_PORT, timeout=TIMEOUT)

    try:
        conn = zk.connect()
        conn.disable_device()

        attendances = conn.get_attendance()

        conn.enable_device()
        conn.disconnect()
        conn = None
    except Exception as e:
        print(f"[zkteco-sync-py] Device error: {e}")
        if conn:
            try:
                conn.enable_device()
                conn.disconnect()
            except Exception:
                pass
        return None

    punches = []
    latest_ts = None
    for a in attendances:
        uid = str(getattr(a, "user_id", None) or getattr(a, "uid", "") or "").strip()
        ts = getattr(a, "timestamp", None) or getattr(a, "punch_time", None)
        if not uid or not ts:
            continue
        try:
            ts_naive = ts.replace(tzinfo=None) if hasattr(ts, "replace") else ts
            last_naive = last_dt.replace(tzinfo=None) if last_dt and hasattr(last_dt, "replace") else last_dt
            if last_naive and ts_naive <= last_naive:
                continue
        except Exception:
            pass
        # Device time is local (no TZ). Send with offset so backend stores correctly (not as UTC).
        iso = ts.strftime(f"%Y-%m-%dT%H:%M:%S.000{TZ_OFFSET}") if hasattr(ts, "strftime") else str(ts)
        punches.append({"biometric_user_id": uid, "logged_at": iso})
        if latest_ts is None or (hasattr(ts, "__gt__") and ts > latest_ts):
            latest_ts = ts

    if not punches:
        return {"pushed": 0}

    payload = {"punches": punches, "source_name": f"zkteco-sync-py-{DEVICE_IP}"}
    try:
        r = requests.post(
            f"{API_URL}/api/biometric-attendance-logs/push",
            json=payload,
            headers={"Content-Type": "application/json", "X-Api-Key": API_KEY},
            timeout=30,
        )
        r.raise_for_status()
        body = r.json()
        if latest_ts and hasattr(latest_ts, "strftime"):
            save_last_sync(latest_ts.strftime(f"%Y-%m-%dT%H:%M:%S.000{TZ_OFFSET}"))
        return body
    except Exception as e:
        print(f"[zkteco-sync-py] Push error: {e}")
        return None

def main():
    if not API_KEY:
        print("[zkteco-sync-py] ERROR: BIO_SYNC_API_KEY required")
        sys.exit(1)

    try:
        import requests
        from zk import ZK
    except ImportError as e:
        print(f"[zkteco-sync-py] Install deps: pip install pyzk requests")
        sys.exit(1)

    print("[zkteco-sync-py] Starting sync service")
    print(f"[zkteco-sync-py] Device: {DEVICE_IP}:{DEVICE_PORT}")
    print(f"[zkteco-sync-py] API: {API_URL}")
    print(f"[zkteco-sync-py] Poll interval: {POLL_INTERVAL}s")
    print("---")

    try:
        while True:
            result = sync_once()
            if result and (result.get("inserted", 0) or result.get("duplicates_skipped", 0) or result.get("skipped_unmatched", 0)):
                print(f"[zkteco-sync-py] Pushed: {result.get('inserted', 0)}, duplicates: {result.get('duplicates_skipped', 0)}, unmatched: {result.get('skipped_unmatched', 0)}")
            time.sleep(POLL_INTERVAL)
    except KeyboardInterrupt:
        print("\n[zkteco-sync-py] Stopped")

if __name__ == "__main__":
    main()
