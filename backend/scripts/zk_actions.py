#!/usr/bin/env python3
"""
Utility script for HRMS biometric integration.
Usage:
  python scripts/zk_actions.py --action get_users --ip 192.168.1.201 --port 4370
  python scripts/zk_actions.py --action set_user --ip 192.168.1.201 --user-id "1001" --name "Dela Cruz, Juan"
"""
import argparse
import json
import sys


def main():
    parser = argparse.ArgumentParser(description="ZKTeco Device Actions")
    parser.add_argument(
        "--action",
        required=True,
        choices=["get_users", "set_user"],
        help="Action to perform",
    )
    parser.add_argument("--ip", required=True, help="IP address of the device")
    parser.add_argument("--port", type=int, default=4370, help="Port of the device")
    parser.add_argument("--timeout", type=int, default=60, help="Connection timeout in seconds")
    # set_user
    parser.add_argument(
        "--user-id",
        dest="user_id_str",
        default="",
        help="Biometric user ID (PIN / user number on device)",
    )
    parser.add_argument("--name", default="", help="Display name on device (short)")
    parser.add_argument(
        "--privilege",
        type=int,
        default=0,
        help="0=user, 14=admin on many ZKTeco models",
    )
    parser.add_argument(
        "--pin",
        default="0",
        help="Numeric keypad password on device (default 0)",
    )
    args = parser.parse_args()

    try:
        from zk import ZK
    except ImportError:
        print(json.dumps({"error": "Dependency missing. Run: pip install pyzk"}))
        sys.exit(1)

    conn = None
    zk = ZK(args.ip, port=args.port, timeout=args.timeout)

    try:
        conn = zk.connect()
        conn.disable_device()

        if args.action == "get_users":
            users = conn.get_users()
            user_list = []
            for u in users:
                raw_id = str(getattr(u, "user_id", "?")).replace("\x00", "").strip()
                raw_name = str(getattr(u, "name", "?")).replace("\x00", "").strip()
                user_list.append(
                    {
                        "uid": u.uid,
                        "biometric_user_id": raw_id,
                        "full_name": raw_name,
                        "privilege": getattr(u, "privilege", 0),
                    }
                )

            print(json.dumps({"users": user_list, "success": True}))
            sys.stdout.flush()

        elif args.action == "set_user":
            user_id_str = str(args.user_id_str or "").strip()
            if not user_id_str:
                print(json.dumps({"success": False, "error": "user_id is required for set_user"}))
                sys.exit(1)
            # Many devices limit name length (~24–32 chars)
            name = str(args.name or "User").replace("\x00", "").strip()[:32] or "User"

            users = conn.get_users()
            target_uid = None
            for u in users:
                rid = str(getattr(u, "user_id", "") or "").replace("\x00", "").strip()
                if rid == user_id_str:
                    target_uid = u.uid
                    break

            if target_uid is None:
                max_uid = max((u.uid for u in users), default=0)
                target_uid = max_uid + 1

            pin_str = str(args.pin or "0").strip()
            if not pin_str.isdigit():
                pin_str = "0"
            # pyzk calls password.encode() internally; must be str (ints raise 'int' has no attribute 'encode').
            password_for_device = pin_str

            # pyzk's set_user has no `return True` on success — it returns None. Failures raise ZKErrorResponse.
            conn.set_user(
                uid=target_uid,
                name=name,
                privilege=int(args.privilege),
                password=password_for_device,
                group_id="",
                user_id=user_id_str,
                card=0,
            )

            print(
                json.dumps(
                    {
                        "success": True,
                        "uid": target_uid,
                        "biometric_user_id": user_id_str,
                        "name": name,
                    }
                )
            )
            sys.stdout.flush()

    except Exception as e:
        print(json.dumps({"error": str(e), "success": False}))
        sys.exit(1)
    finally:
        if conn:
            try:
                conn.enable_device()
            except Exception:
                pass
            try:
                conn.disconnect()
            except Exception:
                pass


if __name__ == "__main__":
    main()
