#!/usr/bin/env python3
"""
Multi-vendor biometric sync service — pushes device attendance to HRMS.

Supported vendors: zkteco (pyzk/TCP 4370), hikvision (ISAPI/HTTP), anviz (TCP 5010).
Device list and vendor come from GET /api/biometric-attendance-logs/devices.

Install:
  pip install pyzk requests          (ZKTeco + Hikvision + Anviz)
  # or
  pip install -r scripts/requirements-zkteco.txt

Run: python scripts/zkteco-sync-py.py

Environment: HRMS_API_URL, BIO_SYNC_API_KEY, ZK_REALTIME, ZK_POLL_INTERVAL,
ZK_FALLBACK_INTERVAL, ZK_TIMEZONE_OFFSET, etc.
"""
import json
import os
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

# ---------------------------------------------------------------------------
# Load .env
# ---------------------------------------------------------------------------
env_path = Path(__file__).resolve().parent.parent / ".env"
if env_path.exists():
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            os.environ.setdefault(k.strip(), v.strip())

POLL_INTERVAL        = int(os.environ.get("ZK_POLL_INTERVAL", "10"))
API_URL              = os.environ.get("HRMS_API_URL", "http://localhost:3000").rstrip("/")
API_KEY              = os.environ.get("BIO_SYNC_API_KEY")
STATE_FILE           = Path(__file__).resolve().parent.parent / ".zkteco-sync-state.json"
TIMEOUT              = 60
TZ_OFFSET            = os.environ.get("ZK_TIMEZONE_OFFSET", "+08:00")
REALTIME_ENABLED     = os.environ.get("ZK_REALTIME", "1").strip().lower() not in ("0", "false", "no", "off")
DISCOVERY_INTERVAL   = int(os.environ.get("ZK_DISCOVERY_INTERVAL", "30"))
FALLBACK_INTERVAL    = int(os.environ.get("ZK_FALLBACK_INTERVAL", "300"))
LIVE_CAPTURE_TIMEOUT = int(os.environ.get("ZK_LIVE_CAPTURE_TIMEOUT", "10"))
LIVE_RECONNECT_DELAY = int(os.environ.get("ZK_LIVE_RECONNECT_DELAY", "5"))
STATE_LOCK           = threading.Lock()
STOP_EVENT           = threading.Event()


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def device_port(dev, fallback=4370):
    try:
        return int(dev.get("port") or dev.get("device_port") or fallback)
    except Exception:
        return fallback


def device_key(dev):
    ip = str(dev.get("ip_address") or "").strip()
    return f"{ip}:{device_port(dev)}"


def device_source(dev, prefix):
    ip        = str(dev.get("ip_address") or "").strip()
    device_id = str(dev.get("device_id") or "").strip()
    label     = device_id or ip
    return f"{prefix}-{label}"


def ts_to_iso(ts):
    """Convert a naive datetime (device local time) to ISO string with configured offset."""
    if hasattr(ts, "strftime"):
        return ts.strftime(f"%Y-%m-%dT%H:%M:%S.000{TZ_OFFSET}")
    return str(ts)


def result_has_activity(result):
    if not result:
        return False
    keys = (
        "inserted", "duplicates_skipped", "skipped_unmatched",
        "skipped_no_schedule", "skipped_holiday", "skipped_leave",
        "skipped_after_shift_first_punch", "skipped_invalid_timestamp",
    )
    return any(result.get(k, 0) for k in keys)


def log_push_result(prefix, result):
    if not result_has_activity(result):
        return
    print(
        f"[bio-sync] {prefix} -> Pushed: {result.get('inserted', 0)}, "
        f"duplicates: {result.get('duplicates_skipped', 0)}, "
        f"unmatched: {result.get('skipped_unmatched', 0)}, "
        f"no_schedule: {result.get('skipped_no_schedule', 0)}, "
        f"holiday: {result.get('skipped_holiday', 0)}, "
        f"leave: {result.get('skipped_leave', 0)}, "
        f"after_shift_first_punch: {result.get('skipped_after_shift_first_punch', 0)}, "
        f"invalid_ts: {result.get('skipped_invalid_timestamp', 0)}"
    )


def load_last_sync(key):
    with STATE_LOCK:
        if STATE_FILE.exists():
            try:
                d = json.loads(STATE_FILE.read_text())
                return d.get(key, {}).get("lastRecordTime")
            except Exception:
                pass
    return None


def save_last_sync(key, iso_str):
    with STATE_LOCK:
        try:
            d = {}
            if STATE_FILE.exists():
                try:
                    d = json.loads(STATE_FILE.read_text())
                except Exception:
                    pass
            if key not in d:
                d[key] = {}
            d[key]["lastRecordTime"] = iso_str
            d[key]["updatedAt"]      = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
            STATE_FILE.write_text(json.dumps(d, indent=2))
        except Exception as e:
            print(f"[bio-sync] Could not save state for {key}: {e}")


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
        print(f"[bio-sync] Failed to fetch devices: {e}")
        return []


def push_punches(state_key, punches, latest_ts=None, source_name=None):
    import requests
    if not punches:
        return {"pushed": 0}
    payload = {"punches": punches, "source_name": source_name or f"bio-sync-{state_key}"}
    try:
        r = requests.post(
            f"{API_URL}/api/biometric-attendance-logs/push",
            json=payload,
            headers={"Content-Type": "application/json", "X-Api-Key": API_KEY},
            timeout=30,
        )
        r.raise_for_status()
        body = r.json()
        if latest_ts:
            save_last_sync(state_key, ts_to_iso(latest_ts) if hasattr(latest_ts, "strftime") else str(latest_ts))
        return body
    except Exception as e:
        print(f"[bio-sync] Push error ({state_key}): {e}")
        return None


# ---------------------------------------------------------------------------
# ZKTeco driver  (pyzk / TCP 4370)
# ---------------------------------------------------------------------------

class ZKTecoDriver:
    """Syncs attendance from ZKTeco devices via pyzk (TCP binary protocol)."""

    PREFIX = "zkteco"

    def __init__(self, dev):
        self.dev  = dev
        self.ip   = str(dev.get("ip_address") or "").strip()
        self.port = device_port(dev, fallback=4370)

    # ------------------------------------------------------------------
    def sync_once(self, source_name=None):
        from zk import ZK

        state_key = f"{self.ip}:{self.port}"
        last      = load_last_sync(state_key)
        last_dt   = None
        if last:
            try:
                last_dt = datetime.fromisoformat(last.replace("Z", "+00:00"))
            except Exception:
                pass

        conn = None
        zk   = ZK(self.ip, port=self.port, timeout=TIMEOUT)
        try:
            conn = zk.connect()
            conn.disable_device()
            attendances = conn.get_attendance()
            conn.enable_device()
            conn.disconnect()
            conn = None
        except Exception as e:
            print(f"[bio-sync] ZKTeco device error ({self.ip}): {e}")
            if conn:
                try:
                    conn.enable_device()
                    conn.disconnect()
                except Exception:
                    pass
            return None

        punches   = []
        latest_ts = None
        for a in attendances:
            uid = str(getattr(a, "user_id", None) or getattr(a, "uid", "") or "").strip()
            ts  = getattr(a, "timestamp", None) or getattr(a, "punch_time", None)
            if not uid or not ts:
                continue
            try:
                ts_naive   = ts.replace(tzinfo=None) if hasattr(ts, "replace") else ts
                last_naive = last_dt.replace(tzinfo=None) if last_dt and hasattr(last_dt, "replace") else last_dt
                if last_naive and ts_naive <= last_naive:
                    continue
            except Exception:
                pass
            punches.append({"biometric_user_id": uid, "logged_at": ts_to_iso(ts)})
            if latest_ts is None or (hasattr(ts, "__gt__") and ts > latest_ts):
                latest_ts = ts

        return push_punches(state_key, punches, latest_ts=latest_ts, source_name=source_name)

    # ------------------------------------------------------------------
    def poll_until_stopped(self, stop_event, label_prefix="Poll"):
        while not stop_event.is_set():
            result = self.sync_once(source_name=device_source(self.dev, f"{self.PREFIX}-poll"))
            log_push_result(f"{label_prefix} {self.ip}", result)
            stop_event.wait(POLL_INTERVAL)

    # ------------------------------------------------------------------
    def live_worker(self, stop_event):
        from zk import ZK

        source_name     = device_source(self.dev, f"{self.PREFIX}-live")
        backfill_source = device_source(self.dev, f"{self.PREFIX}-backfill")
        state_key       = f"{self.ip}:{self.port}"

        print(f"[bio-sync] ZKTeco live listener starting for {self.ip}:{self.port}")

        while not stop_event.is_set():
            result = self.sync_once(source_name=backfill_source)
            log_push_result(f"Backfill {self.ip}", result)
            if stop_event.wait(0.2):
                break

            conn = None
            try:
                zk   = ZK(self.ip, port=self.port, timeout=TIMEOUT)
                conn = zk.connect()
                if not hasattr(conn, "live_capture"):
                    print(f"[bio-sync] ZKTeco live_capture unavailable for {self.ip}; falling back to polling.")
                    try:
                        conn.disconnect()
                    except Exception:
                        pass
                    self.poll_until_stopped(stop_event, label_prefix="Fallback poll")
                    return

                next_backfill = time.monotonic() + FALLBACK_INTERVAL
                print(f"[bio-sync] ZKTeco live listener connected for {self.ip}:{self.port}")

                for attendance in conn.live_capture(new_timeout=LIVE_CAPTURE_TIMEOUT):
                    if stop_event.is_set():
                        break
                    if attendance is None:
                        if time.monotonic() >= next_backfill:
                            print(f"[bio-sync] ZKTeco live backfill due for {self.ip}")
                            break
                        continue
                    uid = str(getattr(attendance, "user_id", None) or getattr(attendance, "uid", "") or "").strip()
                    ts  = getattr(attendance, "timestamp", None) or getattr(attendance, "punch_time", None)
                    if not uid or not ts:
                        continue
                    punch  = {"biometric_user_id": uid, "logged_at": ts_to_iso(ts)}
                    result = push_punches(state_key, [punch], latest_ts=ts, source_name=source_name)
                    log_push_result(f"Live {self.ip}", result)

            except Exception as e:
                print(f"[bio-sync] ZKTeco live listener error ({self.ip}): {e}")
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

        print(f"[bio-sync] ZKTeco live listener stopped for {self.ip}:{self.port}")


# ---------------------------------------------------------------------------
# Hikvision driver  (ISAPI / HTTP)
# ---------------------------------------------------------------------------

class HikvisionDriver:
    """
    Syncs attendance from Hikvision devices via ISAPI HTTP REST.

    Requires environment variables (or device-level credentials stored in HRMS):
      HIK_USERNAME   default admin
      HIK_PASSWORD   required – device admin password

    The driver polls GET /ISAPI/AccessControl/AcsEvent with searchID paging.
    Set HIK_USE_HTTPS=1 to connect via HTTPS (self-signed cert ignored).
    """

    PREFIX = "hikvision"

    def __init__(self, dev):
        self.dev      = dev
        self.ip       = str(dev.get("ip_address") or "").strip()
        self.port     = device_port(dev, fallback=80)
        self.username = os.environ.get("HIK_USERNAME", "admin")
        self.password = os.environ.get("HIK_PASSWORD", "")
        scheme        = "https" if os.environ.get("HIK_USE_HTTPS", "0").strip() == "1" else "http"
        self.base_url = f"{scheme}://{self.ip}:{self.port}"

    # ------------------------------------------------------------------
    def _fetch_events(self, start_time_iso=None):
        """
        Fetch AcsEvent attendance records via Hikvision ISAPI.
        Returns list of (biometric_user_id, datetime) tuples.
        """
        import requests
        from requests.auth import HTTPDigestAuth

        # Default to last 24h if no prior sync time
        if start_time_iso:
            begin_time = start_time_iso.replace("+08:00", "+08:00")
        else:
            begin_time = datetime.now(timezone.utc).strftime("%Y-%m-%dT00:00:00+08:00")

        end_time     = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+08:00")
        search_id    = f"hrms-{int(time.time())}"
        search_result_position = 0
        max_results  = 50
        punches      = []

        while True:
            payload = {
                "AcsEventCond": {
                    "searchID":             search_id,
                    "searchResultPosition": search_result_position,
                    "maxResults":           max_results,
                    "major":                0,
                    "minor":                0,
                    "startTime":            begin_time,
                    "endTime":              end_time,
                },
            }
            try:
                r = requests.post(
                    f"{self.base_url}/ISAPI/AccessControl/AcsEvent?format=json",
                    json=payload,
                    auth=HTTPDigestAuth(self.username, self.password),
                    timeout=30,
                    verify=False,
                )
                r.raise_for_status()
                data = r.json()
            except Exception as e:
                print(f"[bio-sync] Hikvision fetch error ({self.ip}): {e}")
                break

            acs = data.get("AcsEvent", {})
            info_list = acs.get("InfoList", []) or []

            for item in info_list:
                employee_no = str(item.get("employeeNoString") or item.get("employeeNo") or "").strip()
                event_time  = item.get("time", "")
                if employee_no and event_time:
                    punches.append((employee_no, event_time))

            total     = acs.get("totalMatches", 0)
            responded = acs.get("responseStatusStrg", "")
            search_result_position += len(info_list)

            if responded == "NO MORE" or search_result_position >= total or not info_list:
                break

        return punches

    # ------------------------------------------------------------------
    def sync_once(self, source_name=None):
        state_key = f"{self.ip}:{self.port}"
        last      = load_last_sync(state_key)

        raw_punches = self._fetch_events(start_time_iso=last)
        if raw_punches is None:
            return None

        punches   = []
        latest_ts = None

        for employee_no, event_time in raw_punches:
            punches.append({"biometric_user_id": employee_no, "logged_at": event_time})
            try:
                # Keep the latest timestamp for state file
                dt = datetime.fromisoformat(event_time.replace("Z", "+00:00"))
                if latest_ts is None or dt > latest_ts:
                    latest_ts = dt
            except Exception:
                pass

        if not punches:
            return {"pushed": 0}

        return push_punches(
            state_key,
            punches,
            latest_ts=latest_ts,
            source_name=source_name or device_source(self.dev, self.PREFIX),
        )

    # ------------------------------------------------------------------
    def poll_until_stopped(self, stop_event, label_prefix="Poll"):
        while not stop_event.is_set():
            result = self.sync_once(source_name=device_source(self.dev, f"{self.PREFIX}-poll"))
            log_push_result(f"{label_prefix} {self.ip}", result)
            stop_event.wait(POLL_INTERVAL)

    # ------------------------------------------------------------------
    def live_worker(self, stop_event):
        """Hikvision does not support live push to an external service; polling is used."""
        print(f"[bio-sync] Hikvision device {self.ip}: using polling (no live capture).")
        self.poll_until_stopped(stop_event, label_prefix="Hikvision poll")


# ---------------------------------------------------------------------------
# Anviz driver  (binary TCP / port 5010)
# ---------------------------------------------------------------------------

class AnvizDriver:
    """
    Syncs attendance from Anviz devices.

    Anviz uses a proprietary binary protocol on TCP port 5010.
    This driver uses polling (no live capture).

    Note: Anviz SDK details vary by firmware. This implementation uses
    the documented Anviz A300 / C2 series protocol (GetRecord command 0x30).
    Test with your specific device and adjust if needed.
    """

    PREFIX = "anviz"

    def __init__(self, dev):
        self.dev  = dev
        self.ip   = str(dev.get("ip_address") or "").strip()
        self.port = device_port(dev, fallback=5010)

    # ------------------------------------------------------------------
    @staticmethod
    def _build_packet(stx, device_id, cmd, data=b""):
        """Build an Anviz TCP command packet."""
        length = 8 + len(data)
        packet = bytearray()
        packet += stx.to_bytes(1, "little")
        packet += device_id.to_bytes(4, "little")
        packet += length.to_bytes(2, "little")
        packet += cmd.to_bytes(1, "little")
        packet += data
        checksum = sum(packet) & 0xFF
        packet += checksum.to_bytes(1, "little")
        return bytes(packet)

    @staticmethod
    def _parse_timestamp(raw):
        """Parse Anviz 4-byte packed BCD timestamp to datetime."""
        try:
            b = raw if isinstance(raw, (bytes, bytearray)) else bytes([raw])
            second = (b[0] & 0x0F) + ((b[0] >> 4) & 0x0F) * 10
            minute = (b[1] & 0x0F) + ((b[1] >> 4) & 0x0F) * 10
            hour   = (b[2] & 0x0F) + ((b[2] >> 4) & 0x0F) * 10
            day    = (b[3] & 0x0F) + ((b[3] >> 4) & 0x0F) * 10
            # Byte 4 and 5 for month/year may vary; fall back gracefully
            return datetime(datetime.now().year, datetime.now().month, day, hour, minute, second)
        except Exception:
            return None

    # ------------------------------------------------------------------
    def _fetch_records(self):
        """
        Connect to Anviz device and fetch attendance records.
        Returns list of (user_id_str, datetime) or empty list on error.
        """
        import socket

        results = []
        try:
            with socket.create_connection((self.ip, self.port), timeout=TIMEOUT) as sock:
                # GetRecord command: 0x30
                pkt = self._build_packet(0xAA, 0x00000001, 0x30)
                sock.sendall(pkt)

                # Read response (variable length; read until no more data)
                response = b""
                sock.settimeout(5)
                try:
                    while True:
                        chunk = sock.recv(4096)
                        if not chunk:
                            break
                        response += chunk
                except socket.timeout:
                    pass

            # Parse records from response (each record is typically 14 bytes)
            # Format: user_id (5 bytes BCD) + timestamp (4 bytes BCD) + punch_type (1 byte) + ...
            if len(response) < 9:
                return results

            # Skip packet header (8 bytes)
            i = 8
            while i + 10 <= len(response) - 1:
                try:
                    user_id_bytes = response[i:i+5]
                    ts_bytes      = response[i+5:i+9]

                    user_id = ""
                    for b in user_id_bytes:
                        user_id += str((b >> 4) & 0x0F)
                        user_id += str(b & 0x0F)
                    user_id = user_id.lstrip("0") or "0"

                    ts = self._parse_timestamp(ts_bytes)
                    if ts and user_id:
                        results.append((user_id, ts))
                    i += 14
                except Exception:
                    break

        except Exception as e:
            print(f"[bio-sync] Anviz device error ({self.ip}): {e}")

        return results

    # ------------------------------------------------------------------
    def sync_once(self, source_name=None):
        state_key = f"{self.ip}:{self.port}"
        last      = load_last_sync(state_key)
        last_dt   = None
        if last:
            try:
                last_dt = datetime.fromisoformat(last.replace("Z", "+00:00"))
            except Exception:
                pass

        raw = self._fetch_records()
        punches   = []
        latest_ts = None

        for user_id, ts in raw:
            try:
                ts_naive   = ts.replace(tzinfo=None) if hasattr(ts, "replace") else ts
                last_naive = last_dt.replace(tzinfo=None) if last_dt and hasattr(last_dt, "replace") else last_dt
                if last_naive and ts_naive <= last_naive:
                    continue
            except Exception:
                pass
            punches.append({"biometric_user_id": user_id, "logged_at": ts_to_iso(ts)})
            if latest_ts is None or ts > latest_ts:
                latest_ts = ts

        return push_punches(
            state_key,
            punches,
            latest_ts=latest_ts,
            source_name=source_name or device_source(self.dev, self.PREFIX),
        )

    # ------------------------------------------------------------------
    def poll_until_stopped(self, stop_event, label_prefix="Poll"):
        while not stop_event.is_set():
            result = self.sync_once(source_name=device_source(self.dev, f"{self.PREFIX}-poll"))
            log_push_result(f"{label_prefix} {self.ip}", result)
            stop_event.wait(POLL_INTERVAL)

    # ------------------------------------------------------------------
    def live_worker(self, stop_event):
        """Anviz does not support live capture; use polling."""
        print(f"[bio-sync] Anviz device {self.ip}: using polling (no live capture).")
        self.poll_until_stopped(stop_event, label_prefix="Anviz poll")


# ---------------------------------------------------------------------------
# Driver factory
# ---------------------------------------------------------------------------

def get_driver(dev):
    """Return the correct driver instance based on the device vendor field."""
    vendor = (dev.get("vendor") or "zkteco").lower().strip()
    if vendor == "hikvision":
        return HikvisionDriver(dev)
    if vendor == "anviz":
        return AnvizDriver(dev)
    # Default: ZKTeco (covers 'zkteco' and 'other' — 'other' falls back gracefully)
    return ZKTecoDriver(dev)


# ---------------------------------------------------------------------------
# Service orchestration  (same structure as before, now vendor-agnostic)
# ---------------------------------------------------------------------------

def run_polling_service():
    while not STOP_EVENT.is_set():
        devices = get_devices()
        if not devices:
            print("[bio-sync] No active devices found. Waiting...")

        for dev in devices:
            if not dev.get("ip_address"):
                continue
            driver = get_driver(dev)
            result = driver.sync_once(source_name=device_source(dev, "bio-sync-poll"))
            log_push_result(f"Sync {dev.get('ip_address')}", result)

        STOP_EVENT.wait(POLL_INTERVAL)


def _live_worker_wrapper(dev, stop_event):
    driver = get_driver(dev)
    driver.live_worker(stop_event)


def run_realtime_service():
    workers = {}

    try:
        while not STOP_EVENT.is_set():
            devices    = get_devices()
            active_keys = set()

            if not devices:
                print("[bio-sync] No active devices found. Waiting...")

            for dev in devices:
                ip = str(dev.get("ip_address") or "").strip()
                if not ip:
                    continue
                key = device_key(dev)
                active_keys.add(key)
                worker = workers.get(key)
                if not worker or not worker["thread"].is_alive():
                    stop_event = threading.Event()
                    thread     = threading.Thread(
                        target=_live_worker_wrapper,
                        args=(dev, stop_event),
                        name=f"bio-live-{key}",
                        daemon=True,
                    )
                    workers[key] = {"thread": thread, "stop": stop_event}
                    thread.start()

            for key in list(workers.keys()):
                if key in active_keys:
                    continue
                print(f"[bio-sync] Stopping listener for inactive device {key}")
                workers[key]["stop"].set()
                workers[key]["thread"].join(timeout=LIVE_CAPTURE_TIMEOUT + 2)
                del workers[key]

            STOP_EVENT.wait(DISCOVERY_INTERVAL)
    finally:
        for worker in workers.values():
            worker["stop"].set()
        for worker in workers.values():
            worker["thread"].join(timeout=LIVE_CAPTURE_TIMEOUT + 2)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    if not API_KEY:
        print("[bio-sync] ERROR: BIO_SYNC_API_KEY required")
        sys.exit(1)

    try:
        import requests  # noqa: F401
    except ImportError:
        print("[bio-sync] Install deps: pip install requests")
        sys.exit(1)

    print("[bio-sync] Starting multi-vendor biometric sync service")
    print(f"[bio-sync] API: {API_URL}")
    print(f"[bio-sync] Mode: {'real-time live capture' if REALTIME_ENABLED else 'polling'}")
    print(f"[bio-sync] Poll interval: {POLL_INTERVAL}s")
    if REALTIME_ENABLED:
        print(f"[bio-sync] Device discovery interval: {DISCOVERY_INTERVAL}s")
        print(f"[bio-sync] Live capture timeout: {LIVE_CAPTURE_TIMEOUT}s")
        print(f"[bio-sync] Fallback backfill interval: {FALLBACK_INTERVAL}s")
    print("---")

    try:
        if REALTIME_ENABLED:
            run_realtime_service()
        else:
            run_polling_service()
    except KeyboardInterrupt:
        STOP_EVENT.set()
        print("\n[bio-sync] Stopped")


if __name__ == "__main__":
    main()
