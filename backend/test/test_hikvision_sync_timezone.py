import importlib.util
import unittest
from datetime import datetime, timezone
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "zkteco-sync-py.py"
SPEC = importlib.util.spec_from_file_location("biometric_sync", SCRIPT_PATH)
SYNC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SYNC)


class HikvisionQueryWindowTest(unittest.TestCase):
    def test_converts_utc_instant_to_manila_clock_time(self):
        begin, end = SYNC.hikvision_query_window(
            now_utc=datetime(2026, 9, 12, 9, 0, 0, tzinfo=timezone.utc)
        )

        self.assertEqual(begin, "2026-09-12T00:00:00+08:00")
        self.assertEqual(end, "2026-09-12T17:00:00+08:00")

    def test_uses_the_manila_date_after_utc_day_boundary(self):
        begin, end = SYNC.hikvision_query_window(
            now_utc=datetime(2026, 9, 12, 16, 30, 0, tzinfo=timezone.utc)
        )

        self.assertEqual(begin, "2026-09-13T00:00:00+08:00")
        self.assertEqual(end, "2026-09-13T00:30:00+08:00")

    def test_normalizes_a_utc_cursor_to_the_device_timezone(self):
        begin, end = SYNC.hikvision_query_window(
            start_time_iso="2026-09-12T08:00:00Z",
            now_utc=datetime(2026, 9, 12, 9, 0, 0, tzinfo=timezone.utc),
        )

        self.assertEqual(begin, "2026-09-12T16:00:00+08:00")
        self.assertEqual(end, "2026-09-12T17:00:00+08:00")


if __name__ == "__main__":
    unittest.main()
