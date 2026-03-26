#!/usr/bin/env python3
"""
ZKTeco K20 proof-of-connection script using pyzk.

Install: pip install pyzk
Run: python scripts/zkteco_python_proof.py

Environment: ZK_DEVICE_IP, ZK_DEVICE_PORT (optional, defaults below)
"""
import os
from pathlib import Path

# Load .env if present
env_path = Path(__file__).resolve().parent.parent / ".env"
if env_path.exists():
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            os.environ.setdefault(k.strip(), v.strip())

DEVICE_IP = os.environ.get("ZK_DEVICE_IP", "192.168.1.201")
DEVICE_PORT = int(os.environ.get("ZK_DEVICE_PORT", "4370"))
TIMEOUT = 30

def main():
    try:
        from zk import ZK
    except ImportError:
        print("ERROR: pyzk not installed. Run: pip install pyzk")
        return 1

    conn = None
    zk = ZK(DEVICE_IP, port=DEVICE_PORT, timeout=TIMEOUT)

    print("--- ZKTeco K20 Python proof-of-connection ---")
    print(f"Device: {DEVICE_IP}:{DEVICE_PORT}")
    print()

    try:
        print("[1] Connecting...")
        conn = zk.connect()
        print("[OK] Connected")

        print("[2] Disabling device (required before data fetch on many models)...")
        conn.disable_device()
        print("[OK] Device disabled")

        print("[3] Getting device info...")
        fw = conn.get_firmware_version()
        print(f"    Firmware: {fw}")

        print("[4] Getting users...")
        users = conn.get_users()
        print(f"[OK] {len(users)} users")
        for u in users[:3]:
            print(f"    - uid={u.uid} user_id={getattr(u, 'user_id', '?')} name={getattr(u, 'name', '?')}")
        if len(users) > 3:
            print(f"    ... and {len(users) - 3} more")

        print("[5] Getting attendance logs...")
        attendances = conn.get_attendance()
        print(f"[OK] {len(attendances)} attendance records")
        for a in attendances[:5]:
            # Attendance: user_id, timestamp, punch (0=in, 1=out, etc.)
            uid = getattr(a, "user_id", getattr(a, "uid", "?"))
            ts = getattr(a, "timestamp", getattr(a, "punch_time", "?"))
            punch = getattr(a, "punch", "?")
            print(f"    - user_id={uid} timestamp={ts} punch={punch}")
        if len(attendances) > 5:
            print(f"    ... and {len(attendances) - 5} more")

        print("[6] Enabling device...")
        conn.enable_device()
        print("[OK] Device enabled")

        print()
        print("--- All steps completed successfully ---")
        return 0

    except Exception as e:
        print(f"[FAIL] {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        try:
            if conn:
                conn.enable_device()
                conn.disconnect()
        except Exception:
            pass
        return 1
    finally:
        if conn:
            try:
                conn.disconnect()
            except Exception:
                pass

if __name__ == "__main__":
    exit(main())
