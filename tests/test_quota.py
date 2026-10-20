import contextlib
import datetime as dt
import importlib.util
import io
import json
import os
import sqlite3
import tempfile
import time
import unittest
from unittest import mock
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("quota", ROOT / "scripts" / "quota.py")
quota = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(quota)

KEY = "SUPERSECRET-TEST-KEY"
NOW = dt.datetime(2026, 10, 20, 12, 0, 0, tzinfo=dt.timezone.utc)
ROLLING_RESET = "2026-10-20T16:08:43Z"
WEEKLY_RESET = "2026-10-26T00:00:00Z"
MONTHLY_RESET = "2026-11-17T14:35:30Z"


def ok_raw():
    return {
        "rolling": {"available": True, "status": "ok", "percent": 2, "resetsAt": ROLLING_RESET},
        "weekly": {"available": True, "status": "ok", "percent": 20, "resetsAt": WEEKLY_RESET},
        "monthly": {"available": True, "status": "ok", "percent": 13, "resetsAt": MONTHLY_RESET},
    }


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.db = self.root / "opencode.db"
        self.auth = self.root / "auth.json"
        self.cache = self.root / "cache"
        os.environ["TZ"] = "UTC"
        time.tzset()

    def tearDown(self):
        self.tmp.cleanup()

    def collect(self, **kwargs):
        options = {
            "now": NOW,
            "db_path": str(self.db),
            "auth_path": str(self.auth),
            "cache_dir": str(self.cache),
        }
        options.update(kwargs)
        return quota.collect_report(**options)

    def write_auth(self, key=KEY):
        self.auth.write_text(json.dumps({"opencode-go": {"type": "api", "key": key}}), encoding="utf-8")

    def write_v2_db(self, key=KEY):
        con = sqlite3.connect(self.db)
        con.execute("create table credential(integration_id text, value text)")
        con.execute(
            "insert into credential values(?, ?)",
            ("opencode-go", json.dumps({"type": "api", "key": key})),
        )
        con.commit()
        con.close()

class KeyTests(Base):
    def test_v2_key_from_credential_table(self):
        self.write_v2_db()
        key, source = quota.read_key(str(self.db), str(self.auth))
        self.assertEqual(key, KEY)
        self.assertEqual(source, "db")

    def test_v1_key_from_auth_json(self):
        self.write_auth()
        key, source = quota.read_key(str(self.db), str(self.auth))
        self.assertEqual(key, KEY)
        self.assertEqual(source, "auth.json")

    def test_no_key(self):
        report = self.collect(fetch=lambda _key: ok_raw())
        self.assertEqual(report["state"], "no-key")
        self.assertFalse(report["ok"])
        self.assertEqual(report["windows"], {})


class ApiStateTests(Base):
    def test_ok_windows_and_remaining(self):
        self.write_auth()
        report = self.collect(fetch=lambda _key: ok_raw())
        self.assertEqual(report["state"], "ok")
        self.assertTrue(report["ok"])
        self.assertFalse(report["stale"])
        self.assertEqual(report["windows"]["rolling"]["percent"], 2)
        self.assertEqual(report["windows"]["rolling"]["remaining"], 98)
        self.assertEqual(report["windows"]["rolling"]["resetInSec"], 14923)

    def test_official_only_fields(self):
        self.write_auth()
        report = self.collect(fetch=lambda _key: ok_raw())
        for field in ("models", "daily", "cycleStart", "localUpdatedAt"):
            self.assertNotIn(field, report)

    def test_auth_expired(self):
        self.write_auth()

        def fail(_key):
            raise quota.ApiError("auth")

        report = self.collect(fetch=fail)
        self.assertEqual(report["state"], "auth-expired")
        self.assertFalse(report["ok"])
        self.assertEqual(report["windows"], {})

    def test_network_failure_uses_cache(self):
        self.write_auth()
        self.collect(fetch=lambda _key: ok_raw())
        state = quota.load_state(self.cache)
        self.assertTrue(state["windows"])

        def fail(_key):
            raise quota.ApiError("network")

        report = self.collect(now=NOW + dt.timedelta(seconds=120), fetch=fail)
        self.assertEqual(report["state"], "stale")
        self.assertTrue(report["stale"])
        self.assertEqual(report["windows"]["weekly"]["percent"], 20)
        self.assertEqual(report["updatedAt"], quota.local_iso(float(state["fetchedAt"])))

    def test_malformed_response_uses_cache(self):
        self.write_auth()
        self.collect(fetch=lambda _key: ok_raw())

        def fail(_key):
            raise quota.ApiError("malformed")

        report = self.collect(now=NOW + dt.timedelta(seconds=120), fetch=fail)
        self.assertEqual(report["state"], "stale")
        self.assertEqual(report["windows"]["monthly"]["percent"], 13)

    def test_network_failure_without_cache(self):
        self.write_auth()

        def fail(_key):
            raise quota.ApiError("network")

        report = self.collect(fetch=fail)
        self.assertEqual(report["state"], "no-data")
        self.assertTrue(report["stale"])
        self.assertEqual(report["windows"], {})

    def test_cache_ttl_and_force(self):
        self.write_auth()
        calls = {"n": 0}

        def fetch(_key):
            calls["n"] += 1
            return ok_raw()

        first = self.collect(fetch=fetch)
        second = self.collect(now=NOW + dt.timedelta(seconds=30), fetch=fetch)
        self.assertEqual(calls["n"], 1)
        self.assertEqual(first["updatedAt"], second["updatedAt"])

        self.collect(now=NOW + dt.timedelta(seconds=61), fetch=fetch)
        self.assertEqual(calls["n"], 2)

        self.collect(now=NOW + dt.timedelta(seconds=62), force=True, fetch=fetch)
        self.assertEqual(calls["n"], 3)



class RunwayTests(unittest.TestCase):
    def test_runway_linear_and_cap(self):
        windows = {
            "rolling": {"available": True, "remaining": 50, "resetInSec": 86400},
            "weekly": {"available": True, "remaining": 80, "resetInSec": 86400},
            "monthly": {"available": True, "remaining": 90, "resetInSec": 86400},
        }
        samples = []
        for hours, value in ((2, 10), (1, 15), (0, 20)):
            samples.append({"t": quota.iso_z(NOW - dt.timedelta(hours=hours)), "_dt": NOW - dt.timedelta(hours=hours), "rolling": value, "weekly": None, "monthly": None})
        runway = quota.compute_runway(samples, windows, NOW)
        self.assertEqual(runway["rolling"]["seconds"], 36000)
        self.assertIsNone(runway["weekly"]["seconds"])

    def test_runway_needs_enough_samples(self):
        windows = {"rolling": {"available": True, "remaining": 50, "resetInSec": 86400}}
        samples = [
            {"t": quota.iso_z(NOW - dt.timedelta(hours=2)), "_dt": NOW - dt.timedelta(hours=2), "rolling": 10},
            {"t": quota.iso_z(NOW), "_dt": NOW, "rolling": 20},
        ]
        self.assertIsNone(quota.compute_runway(samples, windows, NOW)["rolling"]["seconds"])

    def test_runway_restarts_after_reset(self):
        windows = {"rolling": {"available": True, "remaining": 50, "resetInSec": 86400}}
        samples = []
        for hours, value in ((4, 10), (3, 20), (2, 2), (1, 7), (0, 12)):
            samples.append({"t": quota.iso_z(NOW - dt.timedelta(hours=hours)), "_dt": NOW - dt.timedelta(hours=hours), "rolling": value})
        runway = quota.compute_runway(samples, windows, NOW)
        self.assertEqual(runway["rolling"]["seconds"], 36000)

    def test_sample_trim(self):
        samples = [
            {"t": quota.iso_z(NOW - dt.timedelta(days=40)), "_dt": NOW - dt.timedelta(days=40), "rolling": 1},
            {"t": quota.iso_z(NOW - dt.timedelta(days=1)), "_dt": NOW - dt.timedelta(days=1), "rolling": 2},
        ]
        cache = self.cache_dir()
        kept = quota.write_samples(cache, samples, NOW)
        self.assertEqual(len(kept), 1)
        self.assertEqual(len(quota.read_samples(cache)), 1)

    def cache_dir(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        return Path(tmp.name)


class AlertTests(unittest.TestCase):
    def windows(self, rolling=18, weekly=5, monthly=50):
        return {
            "rolling": {"available": True, "percent": 100 - rolling, "remaining": rolling, "resetsAt": ROLLING_RESET},
            "weekly": {"available": True, "percent": 100 - weekly, "remaining": weekly, "resetsAt": WEEKLY_RESET},
            "monthly": {"available": True, "percent": 100 - monthly, "remaining": monthly, "resetsAt": MONTHLY_RESET},
        }

    def test_warn_and_crit_once_per_reset(self):
        state = {}
        first = quota.compute_alerts(self.windows(), state, NOW, 20, 10, False, True)
        levels = {(alert["window"], alert["level"]) for alert in first}
        self.assertIn(("rolling", "warn"), levels)
        self.assertIn(("weekly", "crit"), levels)
        self.assertNotIn(("monthly", "warn"), levels)

        second = quota.compute_alerts(self.windows(), state, NOW, 20, 10, False, True)
        self.assertEqual(second, [])

        changed = self.windows()
        changed["rolling"]["resetsAt"] = "2026-10-20T22:00:00Z"
        third = quota.compute_alerts(changed, state, NOW, 20, 10, False, True)
        self.assertIn(("rolling", "warn"), {(a["window"], a["level"]) for a in third})

    def test_reset_alert_only_when_old_reset_passed(self):
        state = {"lastResetsAt": {"rolling": quota.iso_z(NOW - dt.timedelta(hours=1))}}
        alerts = quota.compute_alerts(self.windows(), state, NOW, 20, 10, True, True)
        self.assertIn(("rolling", "reset"), {(a["window"], a["level"]) for a in alerts})

        state = {"lastResetsAt": {"rolling": quota.iso_z(NOW + dt.timedelta(hours=1))}}
        alerts = quota.compute_alerts(self.windows(), state, NOW, 20, 10, True, True)
        self.assertNotIn(("rolling", "reset"), {(a["window"], a["level"]) for a in alerts})

    def test_disabled_notifications(self):
        state = {}
        alerts = quota.compute_alerts(self.windows(), state, NOW, 20, 10, True, False)
        self.assertEqual(alerts, [])
        self.assertIn("rolling", state["lastResetsAt"])


class SecurityTests(Base):
    def test_key_never_appears_in_output_or_cache(self):
        self.write_auth()
        report = self.collect(fetch=lambda _key: ok_raw())
        payload = json.dumps(report)
        self.assertNotIn(KEY, payload)
        for path in self.cache.glob("*"):
            if path.is_file():
                self.assertNotIn(KEY, path.read_text(encoding="utf-8", errors="ignore"), path.name)

    def test_main_stdout_is_clean(self):
        self.write_auth()
        output = io.StringIO()
        with mock.patch.object(quota, "fetch_usage", return_value=ok_raw()):
            with contextlib.redirect_stdout(output):
                code = quota.main([
                    "--json", "--force",
                    "--db", str(self.db),
                    "--auth", str(self.auth),
                    "--cache-dir", str(self.cache),
                ])
        self.assertEqual(code, 0)
        self.assertNotIn(KEY, output.getvalue())
        parsed = json.loads(output.getvalue())
        self.assertEqual(parsed["state"], "ok")


if __name__ == "__main__":
    unittest.main()
