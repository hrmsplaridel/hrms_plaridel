import importlib.util
import unittest
from datetime import datetime
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "zkteco-sync-py.py"
SPEC = importlib.util.spec_from_file_location("biometric_sync_anviz", SCRIPT_PATH)
SYNC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SYNC)


class AnvizParserTest(unittest.TestCase):
    def test_rejects_the_old_incomplete_four_byte_timestamp(self):
        parsed = SYNC.AnvizDriver._parse_timestamp(
            bytes([0x30, 0x15, 0x08, 0x31]),
            SYNC.AnvizDriver.BCD6_RECORD_FORMAT,
        )
        self.assertIsNone(parsed)

    def test_parses_an_explicit_complete_six_byte_bcd_format(self):
        parsed = SYNC.AnvizDriver._parse_timestamp(
            bytes([0x30, 0x15, 0x08, 0x31, 0x08, 0x26]),
            SYNC.AnvizDriver.BCD6_RECORD_FORMAT,
        )
        self.assertEqual(parsed, datetime(2026, 8, 31, 8, 15, 30))

    def test_rejects_invalid_bcd_and_impossible_dates(self):
        invalid_bcd = bytes([0x6A, 0x15, 0x08, 0x31, 0x08, 0x26])
        impossible_date = bytes([0x30, 0x15, 0x08, 0x31, 0x09, 0x26])
        self.assertIsNone(
            SYNC.AnvizDriver._parse_timestamp(
                invalid_bcd, SYNC.AnvizDriver.BCD6_RECORD_FORMAT
            )
        )
        self.assertIsNone(
            SYNC.AnvizDriver._parse_timestamp(
                impossible_date, SYNC.AnvizDriver.BCD6_RECORD_FORMAT
            )
        )

    def test_validates_packet_length_and_checksum(self):
        packet = SYNC.AnvizDriver._build_packet(
            0xAA, 0x00000001, 0x30, bytes(14)
        )
        self.assertTrue(SYNC.AnvizDriver._valid_response_packet(packet))

        corrupted = bytearray(packet)
        corrupted[-1] ^= 0x01
        self.assertFalse(SYNC.AnvizDriver._valid_response_packet(corrupted))
        self.assertFalse(SYNC.AnvizDriver._valid_response_packet(packet[:-1]))

    def test_unconfigured_format_fails_without_reporting_a_successful_sync(self):
        driver = SYNC.AnvizDriver(
            {"id": "device-id", "ip_address": "192.0.2.10", "vendor": "anviz"}
        )
        driver.record_format = ""
        push_calls = []
        original_push = SYNC.push_punches
        SYNC.push_punches = lambda *args, **kwargs: push_calls.append((args, kwargs))
        try:
            self.assertIsNone(driver.sync_once())
            self.assertEqual(push_calls, [])
        finally:
            SYNC.push_punches = original_push


if __name__ == "__main__":
    unittest.main()
