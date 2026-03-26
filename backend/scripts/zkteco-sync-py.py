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

# Removed fallback single IP from .env so we query the db instead.
POLL_INTERVAL = int(os.environ.get("ZK_POLL_INTERVAL", "10"))
API_URL = os.environ.get("HRMS_API_URL", "http://localhost:3000").rstrip("/")
API_KEY = os.environ.get("BIO_SYNC_API_KEY")
STATE_FILE = Path(__file__).resolve().parent.parent / ".zkteco-sync-state.json"
TIMEOUT = 60
# Device stores local time. Use same as HRMS (Asia/Manila = UTC+8). Do NOT use Z (UTC).
TZ_OFFSET = os.environ.get("ZK_TIMEZONE_OFFSET", "+08:00")

def load_last_sync(ip):
    if STATE_FILE.exists():
        try:
            d = json.loads(STATE_FILE.read_text())
            ip_data = d.get(ip, {})
            return ip_data.get("lastRecordTime")
        except Exception:
            pass
    return None

def save_last_sync(ip, iso_str):
    try:
        d = {}
        if STATE_FILE.exists():
            try:
                d = json.loads(STATE_FILE.read_text())
            except Exception:
                pass
        
        if ip not in d:
            d[ip] = {}
        
        d[ip]["lastRecordTime"] = iso_str
        d[ip]["updatedAt"] = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
        STATE_FILE.write_text(json.dumps(d, indent=2))
    except Exception as e:
        print(f"[zkteco-sync-py] Could not save state for {ip}: {e}")

def get_devices():
    import requests
    try:
        r = requests.get(
            f"{API_URL}/api/biometric-attendance-logs/devices",
            headers={"X-Api-Key": API_KEY},
            timeout=10,
        )
        r.raise_for_status()
        return r.json()
    except Exception as e:
        print(f"[zkteco-sync-py] Failed to fetch devices: {e}")
        return []

def sync_once(ip, port=4370):
    import requests
    from zk import ZK

    last = load_last_sync(ip)
    last_dt = None
    if last:
        try:
            from datetime import datetime
            last_dt = datetime.fromisoformat(last.replace("Z", "+00:00"))
        except Exception:
            pass

    conn = None
    zk = ZK(ip, port=port, timeout=TIMEOUT)

    try:
        conn = zk.connect()
        conn.disable_device()

        attendances = conn.get_attendance()

        conn.enable_device()
        conn.disconnect()
        conn = None
    except Exception as e:
        print(f"[zkteco-sync-py] Device error ({ip}): {e}")
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

    payload = {"punches": punches, "source_name": f"zkteco-sync-py-{ip}"}
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
            save_last_sync(ip, latest_ts.strftime(f"%Y-%m-%dT%H:%M:%S.000{TZ_OFFSET}"))
        return body
    except Exception as e:
        print(f"[zkteco-sync-py] Push error ({ip}): {e}")
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

    print("[zkteco-sync-py] Starting multi-device sync service")
    print(f"[zkteco-sync-py] API: {API_URL}")
    print(f"[zkteco-sync-py] Poll interval: {POLL_INTERVAL}s")
    print("---")

    try:
        while True:
            devices = get_devices()
            if not devices:
                print("[zkteco-sync-py] No active devices found in database. Waiting...")
            
            for dev in devices:
                ip = dev.get("ip_address")
                if not ip: continue
                # You can safely extract port if you prefer storing it in DB, default 4370
                result = sync_once(ip)
                if result and (result.get("inserted", 0) or result.get("duplicates_skipped", 0) or result.get("skipped_unmatched", 0)):
                    print(f"[zkteco-sync-py] Sync {ip} -> Pushed: {result.get('inserted', 0)}, duplicates: {result.get('duplicates_skipped', 0)}, unmatched: {result.get('skipped_unmatched', 0)}")
            time.sleep(POLL_INTERVAL)
    except KeyboardInterrupt:
        print("\n[zkteco-sync-py] Stopped")

if __name__ == "__main__":
    main()
