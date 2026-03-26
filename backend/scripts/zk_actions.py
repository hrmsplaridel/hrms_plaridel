#!/usr/bin/env python3
"""
Utility script for HRMS biometric integration.
Usage: python scripts/zk_actions.py --action get_users --ip 192.168.1.201 --port 4370
"""
import argparse
import json
import sys

def main():
    parser = argparse.ArgumentParser(description="ZKTeco Device Actions")
    parser.add_argument("--action", required=True, choices=["get_users"], help="Action to perform")
    parser.add_argument("--ip", required=True, help="IP address of the device")
    parser.add_argument("--port", type=int, default=4370, help="Port of the device")
    parser.add_argument("--timeout", type=int, default=30, help="Connection timeout in seconds")
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
                raw_id = str(getattr(u, 'user_id', '?')).replace('\x00', '').strip()
                raw_name = str(getattr(u, 'name', '?')).replace('\x00', '').strip()
                user_list.append({
                    "uid": u.uid,
                    "biometric_user_id": raw_id,
                    "full_name": raw_name,
                    "privilege": getattr(u, 'privilege', 0)
                })
            
            # Print JSON to stdout so Node.js can parse it easily
            print(json.dumps({"users": user_list, "success": True}))
            sys.stdout.flush()

        conn.enable_device()
        sys.exit(0)

    except Exception as e:
        print(json.dumps({"error": str(e), "success": False}))
        sys.exit(1)
    finally:
        if conn:
            try:
                conn.disconnect()
            except:
                pass

if __name__ == "__main__":
    main()
