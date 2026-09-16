import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "zkteco-sync-py.py"
SPEC = importlib.util.spec_from_file_location("biometric_sync_state", SCRIPT_PATH)
SYNC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SYNC)


class BiometricSyncStateTest(unittest.TestCase):
    def setUp(self):
        self.original_state_file = SYNC.STATE_FILE
        self.temp_dir = tempfile.TemporaryDirectory()
        SYNC.STATE_FILE = Path(self.temp_dir.name) / "sync-state.json"

    def tearDown(self):
        SYNC.STATE_FILE = self.original_state_file
        self.temp_dir.cleanup()

    @staticmethod
    def device(**overrides):
        value = {
            "id": "11111111-1111-4111-8111-111111111111",
            "device_id": "ZK-SERIAL-01",
            "vendor": "zkteco",
            "ip_address": "192.168.1.20",
        }
        value.update(overrides)
        return value

    def test_same_registered_device_keeps_cursor_when_ip_changes(self):
        first = self.device(ip_address="192.168.1.20")
        moved = self.device(ip_address="192.168.254.20")

        self.assertEqual(
            SYNC.device_state_identity(first),
            SYNC.device_state_identity(moved),
        )
        self.assertEqual(SYNC.device_key(first), SYNC.device_key(moved))
        self.assertNotEqual(
            SYNC.device_worker_signature(first),
            SYNC.device_worker_signature(moved),
        )

    def test_replacement_at_same_endpoint_cannot_inherit_another_uuid_cursor(self):
        old_device = self.device()
        replacement = self.device(
            id="22222222-2222-4222-8222-222222222222",
            device_id="ZK-SERIAL-02",
        )
        old_key, old_fingerprint = SYNC.device_state_identity(old_device)
        replacement_key, replacement_fingerprint = SYNC.device_state_identity(
            replacement
        )
        SYNC.save_last_sync(
            old_key,
            "2026-09-10T17:00:00+08:00",
            old_fingerprint,
        )

        self.assertNotEqual(old_key, replacement_key)
        self.assertIsNone(
            SYNC.load_last_sync(replacement_key, replacement_fingerprint)
        )

    def test_changed_hardware_identity_resets_cursor_for_same_registration(self):
        old_device = self.device(device_id="ZK-SERIAL-01")
        replacement = self.device(device_id="ZK-SERIAL-02")
        state_key, old_fingerprint = SYNC.device_state_identity(old_device)
        replacement_key, replacement_fingerprint = SYNC.device_state_identity(
            replacement
        )
        SYNC.save_last_sync(
            state_key,
            "2026-09-10T17:00:00+08:00",
            old_fingerprint,
        )

        self.assertEqual(state_key, replacement_key)
        self.assertNotEqual(old_fingerprint, replacement_fingerprint)
        self.assertIsNone(
            SYNC.load_last_sync(replacement_key, replacement_fingerprint)
        )

    def test_state_persists_under_uuid_with_identity_fingerprint(self):
        state_key, fingerprint = SYNC.device_state_identity(self.device())
        timestamp = "2026-09-10T17:00:00+08:00"
        SYNC.save_last_sync(state_key, timestamp, fingerprint)

        self.assertEqual(SYNC.load_last_sync(state_key, fingerprint), timestamp)
        state = json.loads(SYNC.STATE_FILE.read_text())
        self.assertEqual(state[state_key]["identityFingerprint"], fingerprint)
        self.assertEqual(state[state_key]["lastRecordTime"], timestamp)

    def test_legacy_ip_cursor_is_not_assigned_to_a_registered_device(self):
        SYNC.STATE_FILE.write_text(
            json.dumps(
                {
                    "192.168.1.20:4370": {
                        "lastRecordTime": "2026-09-10T17:00:00+08:00"
                    }
                }
            )
        )
        state_key, fingerprint = SYNC.device_state_identity(self.device())

        self.assertIsNone(SYNC.load_last_sync(state_key, fingerprint))

    def test_worker_signature_changes_for_runtime_device_settings(self):
        original = self.device()

        self.assertNotEqual(
            SYNC.device_worker_signature(original),
            SYNC.device_worker_signature(self.device(vendor="hikvision")),
        )
        self.assertNotEqual(
            SYNC.device_worker_signature(original),
            SYNC.device_worker_signature(self.device(device_id="ZK-SERIAL-02")),
        )
        self.assertNotEqual(
            SYNC.device_worker_signature(original),
            SYNC.device_worker_signature(self.device(ip_address="192.168.1.21")),
        )

    def test_reconciler_restarts_worker_when_configuration_changes(self):
        threads = []

        class FakeThread:
            def __init__(self, **kwargs):
                self.kwargs = kwargs
                self.started = False
                self.alive = False
                threads.append(self)

            def start(self):
                self.started = True
                self.alive = True

            def is_alive(self):
                return self.alive

            def join(self, timeout=None):
                del timeout
                self.alive = False

        workers = {}
        original = self.device()
        SYNC.reconcile_realtime_workers(workers, [original], thread_factory=FakeThread)
        key = SYNC.device_key(original)
        old_worker = workers[key]

        updated = self.device(device_id="ZK-SERIAL-02")
        SYNC.reconcile_realtime_workers(workers, [updated], thread_factory=FakeThread)

        self.assertEqual(len(threads), 2)
        self.assertTrue(old_worker["stop"].is_set())
        self.assertIsNot(workers[key]["thread"], old_worker["thread"])
        self.assertEqual(
            workers[key]["signature"],
            SYNC.device_worker_signature(updated),
        )

    def test_reconciler_retains_unchanged_worker_and_stops_inactive_worker(self):
        threads = []

        class FakeThread:
            def __init__(self, **kwargs):
                self.alive = False
                threads.append(self)

            def start(self):
                self.alive = True

            def is_alive(self):
                return self.alive

            def join(self, timeout=None):
                del timeout
                self.alive = False

        workers = {}
        device = self.device()
        key = SYNC.device_key(device)
        SYNC.reconcile_realtime_workers(workers, [device], thread_factory=FakeThread)
        worker = workers[key]
        SYNC.reconcile_realtime_workers(workers, [device], thread_factory=FakeThread)

        self.assertEqual(len(threads), 1)
        self.assertIs(workers[key], worker)

        SYNC.reconcile_realtime_workers(workers, [], thread_factory=FakeThread)
        self.assertTrue(worker["stop"].is_set())
        self.assertEqual(workers, {})


if __name__ == "__main__":
    unittest.main()
