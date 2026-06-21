#!/usr/bin/env python3
"""
ZKTeco sync service — pushes device attendance to HRMS via pyzk.

Device IPs come from GET /api/biometric-attendance-logs/devices (see get_devices()).

Install: pip install pyzk requests  (or pip install -r scripts/requirements-zkteco.txt)
Run: python scripts/zkteco-sync-py.py

Environment: HRMS_API_URL, BIO_SYNC_API_KEY, ZK_REALTIME, ZK_POLL_INTERVAL,
ZK_FALLBACK_INTERVAL, ZK_TIMEZONE_OFFSET, etc.
"""
import json
import os
import sys
import threading
import time
from datetime import datetime
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
REALTIME_ENABLED = os.environ.get("ZK_REALTIME", "1").strip().lower() not in ("0", "false", "no", "off")
DISCOVERY_INTERVAL = int(os.environ.get("ZK_DISCOVERY_INTERVAL", "30"))
FALLBACK_INTERVAL = int(os.environ.get("ZK_FALLBACK_INTERVAL", "300"))
LIVE_CAPTURE_TIMEOUT = int(os.environ.get("ZK_LIVE_CAPTURE_TIMEOUT", "10"))
LIVE_RECONNECT_DELAY = int(os.environ.get("ZK_LIVE_RECONNECT_DELAY", "5"))
STATE_LOCK = threading.Lock()
STOP_EVENT = threading.Event()


def device_port(dev):
    try:
        return int(dev.get("port") or dev.get("device_port") or 4370)
    except Exception:
        return 4370


def device_key(dev):
    ip = str(dev.get("ip_address") or "").strip()
    return f"{ip}:{device_port(dev)}"


def device_source(dev, prefix):
    ip = str(dev.get("ip_address") or "").strip()
    device_id = str(dev.get("device_id") or "").strip()
    label = device_id or ip
    return f"{prefix}-{label}"


def attendance_to_punch(attendance):
    uid = str(
        getattr(attendance, "user_id", None)
        or getattr(attendance, "uid", "")
        or ""
    ).strip()
    ts = (
        getattr(attendance, "timestamp", None)
        or getattr(attendance, "punch_time", None)
    )
    if not uid or not ts:
        return None, None
    iso = ts.strftime(f"%Y-%m-%dT%H:%M:%S.000{TZ_OFFSET}") if hasattr(ts, "strftime") else str(ts)
    return {"biometric_user_id": uid, "logged_at": iso}, ts


def result_has_activity(result):
    if not result:
        return False
    keys = (
        "inserted",
        "duplicates_skipped",
        "skipped_unmatched",
        "skipped_no_schedule",
        "skipped_holiday",
        "skipped_leave",
        "skipped_invalid_timestamp",
    )
    return any(result.get(k, 0) for k in keys)


def log_push_result(prefix, result):
    if not result_has_activity(result):
        return
    print(
        f"[zkteco-sync-py] {prefix} -> Pushed: {result.get('inserted', 0)}, "
        f"duplicates: {result.get('duplicates_skipped', 0)}, "
        f"unmatched: {result.get('skipped_unmatched', 0)}, "
        f"no_schedule: {result.get('skipped_no_schedule', 0)}, "
        f"holiday: {result.get('skipped_holiday', 0)}, "
        f"leave: {result.get('skipped_leave', 0)}, "
        f"invalid_ts: {result.get('skipped_invalid_timestamp', 0)}"
    )

def load_last_sync(ip):
    with STATE_LOCK:
        if STATE_FILE.exists():
            try:
                d = json.loads(STATE_FILE.read_text())
                ip_data = d.get(ip, {})
                return ip_data.get("lastRecordTime")
            except Exception:
                pass
    return None

def save_last_sync(ip, iso_str):
    with STATE_LOCK:
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


def push_punches(ip, punches, latest_ts=None, source_name=None):
    import requests

    if not punches:
        return {"pushed": 0}

    payload = {"punches": punches, "source_name": source_name or f"zkteco-sync-py-{ip}"}
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


def sync_once(ip, port=4370, source_name=None):
    from zk import ZK

    last = load_last_sync(ip)
    last_dt = None
    if last:
        try:
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
        punch, _ = attendance_to_punch(a)
        if punch:
            punches.append(punch)
        if latest_ts is None or (hasattr(ts, "__gt__") and ts > latest_ts):
            latest_ts = ts

    return push_punches(ip, punches, latest_ts=latest_ts, source_name=source_name)


def poll_device_until_stopped(dev, stop_event, label_prefix="Poll"):
    ip = str(dev.get("ip_address") or "").strip()
    if not ip:
        return
    port = device_port(dev)
    while not stop_event.is_set():
        result = sync_once(ip, port=port, source_name=device_source(dev, "zkteco-poll"))
        log_push_result(f"{label_prefix} {ip}", result)
        stop_event.wait(POLL_INTERVAL)


def live_device_worker(dev, stop_event):
    from zk import ZK

    ip = str(dev.get("ip_address") or "").strip()
    if not ip:
        return
    port = device_port(dev)
    source_name = device_source(dev, "zkteco-live")
    backfill_source = device_source(dev, "zkteco-backfill")

    print(f"[zkteco-sync-py] Live listener starting for {ip}:{port}")

    while not stop_event.is_set():
        result = sync_once(ip, port=port, source_name=backfill_source)
        log_push_result(f"Backfill {ip}", result)
        if stop_event.wait(0.2):
            break

        conn = None
        try:
            zk = ZK(ip, port=port, timeout=TIMEOUT)
            conn = zk.connect()
            if not hasattr(conn, "live_capture"):
                print(
                    f"[zkteco-sync-py] pyzk live_capture is unavailable for {ip}; "
                    f"falling back to {POLL_INTERVAL}s polling."
                )
                try:
                    conn.disconnect()
                except Exception:
                    pass
                poll_device_until_stopped(dev, stop_event, label_prefix="Fallback poll")
                return

            next_backfill = time.monotonic() + FALLBACK_INTERVAL
            print(f"[zkteco-sync-py] Live listener connected for {ip}:{port}")

            for attendance in conn.live_capture(new_timeout=LIVE_CAPTURE_TIMEOUT):
                if stop_event.is_set():
                    break

                if attendance is None:
                    if time.monotonic() >= next_backfill:
                        print(f"[zkteco-sync-py] Live backfill due for {ip}")
                        break
                    continue

                punch, ts = attendance_to_punch(attendance)
                if not punch:
                    continue

                result = push_punches(
                    ip,
                    [punch],
                    latest_ts=ts,
                    source_name=source_name,
                )
                log_push_result(f"Live {ip}", result)

        except Exception as e:
            print(f"[zkteco-sync-py] Live listener error ({ip}): {e}")
            stop_event.wait(LIVE_RECONNECT_DELAY)
        finally:
            if conn:
                try:
                    if hasattr(conn, "end_live_capture"):
                        conn.end_live_capture = True
                except Exception:
                    pass
                try:
                    conn.enable_device()
                except Exception:
                    pass
                try:
                    conn.disconnect()
                except Exception:
                    pass

    print(f"[zkteco-sync-py] Live listener stopped for {ip}:{port}")


def run_polling_service():
    while not STOP_EVENT.is_set():
        devices = get_devices()
        if not devices:
            print("[zkteco-sync-py] No active devices found in database. Waiting...")

        for dev in devices:
            ip = dev.get("ip_address")
            if not ip:
                continue
            result = sync_once(
                ip,
                port=device_port(dev),
                source_name=device_source(dev, "zkteco-sync-py"),
            )
            log_push_result(f"Sync {ip}", result)
        STOP_EVENT.wait(POLL_INTERVAL)


def run_realtime_service():
    workers = {}

    try:
        while not STOP_EVENT.is_set():
            devices = get_devices()
            active_keys = set()
            if not devices:
                print("[zkteco-sync-py] No active devices found in database. Waiting...")

            for dev in devices:
                ip = str(dev.get("ip_address") or "").strip()
                if not ip:
                    continue
                key = device_key(dev)
                active_keys.add(key)
                worker = workers.get(key)
                if not worker or not worker["thread"].is_alive():
                    stop_event = threading.Event()
                    thread = threading.Thread(
                        target=live_device_worker,
                        args=(dev, stop_event),
                        name=f"zk-live-{key}",
                        daemon=True,
                    )
                    workers[key] = {"thread": thread, "stop": stop_event}
                    thread.start()

            for key in list(workers.keys()):
                if key in active_keys:
                    continue
                print(f"[zkteco-sync-py] Stopping listener for inactive device {key}")
                workers[key]["stop"].set()
                workers[key]["thread"].join(timeout=LIVE_CAPTURE_TIMEOUT + 2)
                del workers[key]

            STOP_EVENT.wait(DISCOVERY_INTERVAL)
    finally:
        for worker in workers.values():
            worker["stop"].set()
        for worker in workers.values():
            worker["thread"].join(timeout=LIVE_CAPTURE_TIMEOUT + 2)

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
    print(f"[zkteco-sync-py] Mode: {'real-time live capture' if REALTIME_ENABLED else 'polling'}")
    print(f"[zkteco-sync-py] Poll interval: {POLL_INTERVAL}s")
    if REALTIME_ENABLED:
        print(f"[zkteco-sync-py] Device discovery interval: {DISCOVERY_INTERVAL}s")
        print(f"[zkteco-sync-py] Live capture timeout: {LIVE_CAPTURE_TIMEOUT}s")
        print(f"[zkteco-sync-py] Fallback backfill interval: {FALLBACK_INTERVAL}s")
    print("---")

    try:
        if REALTIME_ENABLED:
            run_realtime_service()
        else:
            run_polling_service()
    except KeyboardInterrupt:
        STOP_EVENT.set()
        print("\n[zkteco-sync-py] Stopped")

if __name__ == "__main__":
    main()
