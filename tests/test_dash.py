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
SPEC = importlib.util.spec_from_file_location("dash", ROOT / "scripts" / "dash.py")
dash = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(dash)

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
        return dash.collect_report(**options)

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
        key, source = dash.read_key(str(self.db), str(self.auth))
        self.assertEqual(key, KEY)
        self.assertEqual(source, "db")

    def test_v1_key_from_auth_json(self):
        self.write_auth()
        key, source = dash.read_key(str(self.db), str(self.auth))
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

    def test_cached_reset_horizon_is_clamped(self):
        cached = {
            "rolling": {
                "available": True,
                "percent": 0,
                "remaining": 100,
                "resetsAt": dash.iso_z(NOW + dt.timedelta(hours=10)),
            }
        }
        windows = dash.rehydrate_windows(cached, NOW)
        self.assertEqual(windows["rolling"]["resetInSec"], 5 * 3600 + 60)

    def test_reset_horizon_is_clamped(self):
        raw = ok_raw()
        raw["rolling"]["resetsAt"] = dash.iso_z(NOW + dt.timedelta(hours=10))
        windows = dash.build_windows(raw, NOW)
        self.assertEqual(windows["rolling"]["resetInSec"], 5 * 3600 + 60)

    def test_auth_expired(self):
        self.write_auth()

        def fail(_key):
            raise dash.ApiError("auth")

        report = self.collect(fetch=fail)
        self.assertEqual(report["state"], "auth-expired")
        self.assertFalse(report["ok"])
        self.assertEqual(report["windows"], {})

    def test_network_failure_uses_cache(self):
        self.write_auth()
        self.collect(fetch=lambda _key: ok_raw())
        state = dash.load_state(self.cache)
        self.assertTrue(state["windows"])

        def fail(_key):
            raise dash.ApiError("network")

        report = self.collect(now=NOW + dt.timedelta(seconds=120), fetch=fail)
        self.assertEqual(report["state"], "stale")
        self.assertTrue(report["stale"])
        self.assertEqual(report["windows"]["weekly"]["percent"], 20)
        self.assertEqual(report["updatedAt"], dash.local_iso(float(state["fetchedAt"])))

    def test_malformed_response_uses_cache(self):
        self.write_auth()
        self.collect(fetch=lambda _key: ok_raw())

        def fail(_key):
            raise dash.ApiError("malformed")

        report = self.collect(now=NOW + dt.timedelta(seconds=120), fetch=fail)
        self.assertEqual(report["state"], "stale")
        self.assertEqual(report["windows"]["monthly"]["percent"], 13)

    def test_network_failure_without_cache(self):
        self.write_auth()

        def fail(_key):
            raise dash.ApiError("network")

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
            samples.append({"t": dash.iso_z(NOW - dt.timedelta(hours=hours)), "_dt": NOW - dt.timedelta(hours=hours), "rolling": value, "weekly": None, "monthly": None})
        runway = dash.compute_runway(samples, windows, NOW)
        self.assertEqual(runway["rolling"]["seconds"], 36000)
        self.assertEqual(runway["rolling"]["reason"], "ok")
        self.assertIsNone(runway["weekly"]["seconds"])

    def test_runway_needs_enough_samples(self):
        windows = {"rolling": {"available": True, "remaining": 50, "resetInSec": 86400}}
        samples = [
            {"t": dash.iso_z(NOW - dt.timedelta(hours=2)), "_dt": NOW - dt.timedelta(hours=2), "rolling": 10},
            {"t": dash.iso_z(NOW), "_dt": NOW, "rolling": 20},
        ]
        result = dash.compute_runway(samples, windows, NOW)["rolling"]
        self.assertIsNone(result["seconds"])
        self.assertEqual(result["reason"], "insufficient")

    def test_runway_restarts_after_reset(self):
        windows = {"weekly": {"available": True, "remaining": 50, "resetInSec": 86400}}
        samples = []
        for hours, value in ((4, 10), (3, 20), (2, 2), (1, 7), (0, 12)):
            samples.append({"t": dash.iso_z(NOW - dt.timedelta(hours=hours)), "_dt": NOW - dt.timedelta(hours=hours), "weekly": value})
        runway = dash.compute_runway(samples, windows, NOW)
        self.assertEqual(runway["weekly"]["seconds"], 36000)

    def test_runway_rolling_ignores_slide(self):
        windows = {"rolling": {"available": True, "remaining": 50, "resetInSec": 86400}}
        samples = []
        for hours, value in ((4, 10), (3, 20), (2, 2), (1, 7), (0, 12)):
            samples.append({"t": dash.iso_z(NOW - dt.timedelta(hours=hours)), "_dt": NOW - dt.timedelta(hours=hours), "rolling": value})
        result = dash.compute_runway(samples, windows, NOW)["rolling"]
        self.assertIsNone(result["seconds"])
        self.assertEqual(result["reason"], "flat")

    def test_runway_zero_percent_is_idle(self):
        windows = {"rolling": {"available": True, "percent": 0, "remaining": 100, "resetInSec": 86400}}
        result = dash.compute_runway([], windows, NOW)["rolling"]
        self.assertIsNone(result["seconds"])
        self.assertEqual(result["ratePerHour"], 0.0)
        self.assertEqual(result["reason"], "flat")

    def test_runway_flat_is_idle(self):
        windows = {"rolling": {"available": True, "percent": 50, "remaining": 50, "resetInSec": 86400}}
        samples = []
        for hours in (2, 1, 0):
            samples.append({
                "t": dash.iso_z(NOW - dt.timedelta(hours=hours)),
                "_dt": NOW - dt.timedelta(hours=hours),
                "rolling": 0,
            })
        result = dash.compute_runway(samples, windows, NOW)["rolling"]
        self.assertIsNone(result["seconds"])
        self.assertEqual(result["ratePerHour"], 0.0)
        self.assertEqual(result["reason"], "flat")

    def test_sample_trim(self):
        samples = [
            {"t": dash.iso_z(NOW - dt.timedelta(days=40)), "_dt": NOW - dt.timedelta(days=40), "rolling": 1},
            {"t": dash.iso_z(NOW - dt.timedelta(days=1)), "_dt": NOW - dt.timedelta(days=1), "rolling": 2},
        ]
        cache = self.cache_dir()
        kept = dash.write_samples(cache, samples, NOW)
        self.assertEqual(len(kept), 1)
        self.assertEqual(len(dash.read_samples(cache)), 1)

    def cache_dir(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        return Path(tmp.name)


class CycleOutlookTests(unittest.TestCase):
    def outlook(self, *, remaining=62, reset_in=12 * 86400, rate=2.0 / 24,
                span=19 * 86400, reason="ok", available=True):
        windows = {
            "monthly": {
                "available": available,
                "remaining": remaining,
                "resetInSec": reset_in,
            }
        }
        runway = {
            "monthly": {
                "seconds": reset_in,
                "ratePerHour": rate,
                "reason": reason,
                "spanSec": span,
            }
        }
        return dash.compute_cycle_outlook(windows, runway)

    def test_projects_unused_monthly_budget(self):
        result = self.outlook()
        self.assertTrue(result["available"])
        self.assertEqual(result["unusedPercent"], 38)
        self.assertEqual(result["resetInSec"], 12 * 86400)
        self.assertEqual(result["spanSec"], 19 * 86400)

    def test_waits_for_second_half(self):
        result = self.outlook(reset_in=20 * 86400)
        self.assertFalse(result["available"])
        self.assertEqual(result["reason"], "early")

    def test_needs_enough_observed_span(self):
        result = self.outlook(span=5 * 86400)
        self.assertFalse(result["available"])
        self.assertEqual(result["reason"], "insufficient")

    def test_hides_when_budget_will_be_used(self):
        result = self.outlook(remaining=10)
        self.assertFalse(result["available"])
        self.assertEqual(result["reason"], "full")
        self.assertLess(result["unusedPercent"], dash.CYCLE_OUTLOOK_MIN_UNUSED_PERCENT)

    def test_monthly_unavailable(self):
        result = self.outlook(available=False)
        self.assertFalse(result["available"])
        self.assertEqual(result["reason"], "unavailable")

    def test_flat_rate_is_not_projected(self):
        result = self.outlook(reason="flat", rate=0.0)
        self.assertFalse(result["available"])
        self.assertEqual(result["reason"], "flat")

    def test_missing_reset_is_not_projected(self):
        result = self.outlook(reset_in=0)
        self.assertFalse(result["available"])
        self.assertEqual(result["reason"], "no-reset")

    def test_weekly_is_never_used(self):
        windows = {"weekly": {"available": True, "remaining": 64, "resetInSec": 2 * 86400}}
        runway = {"weekly": {"seconds": 2 * 86400, "ratePerHour": 0.3, "reason": "ok", "spanSec": 5 * 86400}}
        result = dash.compute_cycle_outlook(windows, runway)
        self.assertFalse(result["available"])
        self.assertEqual(result["reason"], "unavailable")


class CycleOutlookIntegrationTests(Base):
    def test_report_includes_monthly_outlook(self):
        self.write_auth()
        samples = []
        for days, value in ((19, 0), (10, 19), (0, 38)):
            when = NOW - dt.timedelta(days=days)
            samples.append({
                "t": dash.iso_z(when),
                "_dt": when,
                "rolling": None,
                "weekly": None,
                "monthly": value,
            })
        dash.write_samples(self.cache, samples, NOW)

        def fetch(_key):
            raw = ok_raw()
            raw["monthly"]["percent"] = 38
            raw["monthly"]["resetsAt"] = dash.iso_z(NOW + dt.timedelta(days=12))
            return raw

        report = self.collect(fetch=fetch)
        outlook = report["cycleOutlook"]
        self.assertTrue(outlook["available"])
        self.assertEqual(outlook["unusedPercent"], 38)
        self.assertEqual(outlook["resetInSec"], 12 * 86400)


class AlertTests(unittest.TestCase):
    def windows(self, rolling=18, weekly=5, monthly=50):
        return {
            "rolling": {"available": True, "percent": 100 - rolling, "remaining": rolling, "resetsAt": ROLLING_RESET},
            "weekly": {"available": True, "percent": 100 - weekly, "remaining": weekly, "resetsAt": WEEKLY_RESET},
            "monthly": {"available": True, "percent": 100 - monthly, "remaining": monthly, "resetsAt": MONTHLY_RESET},
        }

    def test_warn_and_crit_once_per_reset(self):
        state = {}
        first = dash.compute_alerts(self.windows(), state, NOW, 20, 10, False, True)
        levels = {(alert["window"], alert["level"]) for alert in first}
        self.assertIn(("rolling", "warn"), levels)
        self.assertIn(("weekly", "crit"), levels)
        self.assertNotIn(("monthly", "warn"), levels)

        second = dash.compute_alerts(self.windows(), state, NOW, 20, 10, False, True)
        self.assertEqual(second, [])

        changed = self.windows()
        changed["rolling"]["resetsAt"] = "2026-10-20T22:00:00Z"
        third = dash.compute_alerts(changed, state, NOW, 20, 10, False, True)
        self.assertIn(("rolling", "warn"), {(a["window"], a["level"]) for a in third})

    def test_reset_alert_only_when_old_reset_passed(self):
        state = {"lastResetsAt": {"rolling": dash.iso_z(NOW - dt.timedelta(hours=1))}}
        alerts = dash.compute_alerts(self.windows(), state, NOW, 20, 10, True, True)
        self.assertIn(("rolling", "reset"), {(a["window"], a["level"]) for a in alerts})

        state = {"lastResetsAt": {"rolling": dash.iso_z(NOW + dt.timedelta(hours=1))}}
        alerts = dash.compute_alerts(self.windows(), state, NOW, 20, 10, True, True)
        self.assertNotIn(("rolling", "reset"), {(a["window"], a["level"]) for a in alerts})

    def test_disabled_notifications(self):
        state = {}
        alerts = dash.compute_alerts(self.windows(), state, NOW, 20, 10, True, False)
        self.assertEqual(alerts, [])
        self.assertIn("rolling", state["lastResetsAt"])


class FakeResponse:
    def __init__(self, body=b"", headers=None):
        self.body = body
        self.headers = headers or {}

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self, amount=None):
        if amount is None:
            return self.body
        return self.body[:amount]


class FakeOpener:
    def __init__(self, response):
        self.response = response
        self.requests = []

    def open(self, request, timeout=None):
        self.requests.append((request, timeout))
        return self.response


class NetworkHardeningTests(unittest.TestCase):
    def test_redirect_handler_refuses(self):
        handler = dash.NoRedirectHandler()
        with self.assertRaises(dash.RedirectRefused):
            handler.redirect_request(None, None, 302, "Found", {}, "https://evil.example/")

    def test_redirect_is_reported_as_network_error(self):
        class RefusingOpener:
            def open(self, request, timeout=None):
                raise dash.RedirectRefused("redirect refused")

        with mock.patch.object(dash, "OPENER", RefusingOpener()):
            with self.assertRaises(dash.ApiError) as raised:
                dash.fetch_usage(KEY)
        self.assertEqual(raised.exception.kind, "network")

    def test_declared_oversized_response_is_rejected(self):
        response = FakeResponse(b"{}", {"Content-Length": str(dash.MAX_RESPONSE_BYTES + 1)})
        with mock.patch.object(dash, "OPENER", FakeOpener(response)):
            with self.assertRaises(dash.ApiError) as raised:
                dash.fetch_usage(KEY)
        self.assertEqual(raised.exception.kind, "malformed")

    def test_oversized_body_is_rejected(self):
        response = FakeResponse(b"x" * (dash.MAX_RESPONSE_BYTES + 1))
        with mock.patch.object(dash, "OPENER", FakeOpener(response)):
            with self.assertRaises(dash.ApiError) as raised:
                dash.fetch_usage(KEY)
        self.assertEqual(raised.exception.kind, "malformed")

    def test_normal_response_still_parses(self):
        body = json.dumps({
            "usage": {
                "rolling": {"status": "ok", "percent": 2, "resetsAt": ROLLING_RESET},
                "weekly": {"status": "ok", "percent": 20, "resetsAt": WEEKLY_RESET},
                "monthly": {"status": "ok", "percent": 13, "resetsAt": MONTHLY_RESET},
            }
        }).encode("utf-8")
        response = FakeResponse(body, {"Content-Length": str(len(body))})
        with mock.patch.object(dash, "OPENER", FakeOpener(response)):
            raw = dash.fetch_usage(KEY)
        self.assertEqual(raw["rolling"]["percent"], 2)
        self.assertEqual(raw["monthly"]["resetsAt"], MONTHLY_RESET)


class CachePermissionTests(unittest.TestCase):
    def test_state_and_samples_are_owner_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp) / "cache"
            dash.save_state(cache, {"windows": {}})
            dash.write_samples(
                cache,
                [{"t": dash.iso_z(NOW), "_dt": NOW, "rolling": 1}],
                NOW,
            )
            self.assertEqual(cache.stat().st_mode & 0o777, 0o700)
            self.assertEqual((cache / "state.json").stat().st_mode & 0o777, 0o600)
            self.assertEqual((cache / "samples.jsonl").stat().st_mode & 0o777, 0o600)

    def test_existing_wider_permissions_are_tightened(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp) / "cache"
            cache.mkdir(mode=0o755)
            target = cache / "state.json"
            target.write_text("{}", encoding="utf-8")
            os.chmod(cache, 0o755)
            os.chmod(target, 0o644)
            dash.save_state(cache, {"windows": {}})
            self.assertEqual(cache.stat().st_mode & 0o777, 0o700)
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)

    def test_symlinked_cache_dir_is_not_used(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            real = root / "real"
            real.mkdir()
            link = root / "cache"
            link.symlink_to(real, target_is_directory=True)
            dash.save_state(link, {"windows": {}})
            self.assertEqual(list(real.iterdir()), [])


class CredentialBoundsTests(Base):
    def test_oversized_auth_json_is_ignored(self):
        self.auth.write_text("x" * (dash.MAX_AUTH_BYTES + 1), encoding="utf-8")
        key, source = dash.read_key(str(self.db), str(self.auth))
        self.assertIsNone(key)
        self.assertEqual(source, "none")

    def test_oversized_key_is_ignored(self):
        self.write_auth("x" * (dash.MAX_KEY_CHARS + 1))
        key, source = dash.read_key(str(self.db), str(self.auth))
        self.assertIsNone(key)
        self.assertEqual(source, "none")


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
        with mock.patch.object(dash, "fetch_usage", return_value=ok_raw()):
            with contextlib.redirect_stdout(output):
                code = dash.main([
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
