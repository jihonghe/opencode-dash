#!/usr/bin/env python3
"""Data layer for OpenCode Quota.

Collects subscription usage from the official OpenCode Go endpoint and local
per-model usage from opencode.db. The output is a single JSON document for the
QML widget.

Security rules:
  * The API key is read only here and only used as an Authorization header.
  * It is never written to stdout/stderr, cache files, or exception text.
  * The OpenCode database is always opened read-only.
"""

from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import json
import math
import os
import sqlite3
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

API_URL = "https://opencode.ai/zen/go/v1/usage"
USER_AGENT = "opencode-quota/1.0"
WINDOWS = ("rolling", "weekly", "monthly")
WINDOW_LABELS = {"rolling": "5h", "weekly": "7d", "monthly": "M"}

CACHE_TTL_SEC = 60
SAMPLE_RETENTION_SEC = 30 * 24 * 3600
RUNWAY_HORIZON_SEC = {
    "rolling": 6 * 3600,
    "weekly": 7 * 24 * 3600,
    "monthly": 31 * 24 * 3600,
}
RUNWAY_MIN_SPAN_SEC = 3600
RUNWAY_MIN_POINTS = 3
# Hard upper bounds for display countdowns. A rolling reset cannot be more
# than 5h away; clamping protects against stale caches or clock anomalies.
RESET_HORIZON_SEC = {
    "rolling": 5 * 3600 + 60,
    "weekly": 7 * 86400 + 60,
    "monthly": 31 * 86400 + 60,
}


class ApiError(Exception):
    """A handled API failure. `kind` is auth, network, or malformed."""

    def __init__(self, kind: str):
        super().__init__(kind)
        self.kind = kind


# --------------------------------------------------------------------- paths


def _home() -> Path:
    return Path(os.path.expanduser("~"))


def default_data_dir() -> Path:
    return Path(os.environ.get("XDG_DATA_HOME") or (_home() / ".local" / "share"))


def default_cache_dir() -> Path:
    return Path(os.environ.get("XDG_CACHE_HOME") or (_home() / ".cache")) / "opencode-quota"


def default_db_path() -> Path:
    return default_data_dir() / "opencode" / "opencode.db"


def default_auth_path() -> Path:
    return default_data_dir() / "opencode" / "auth.json"


def _resolve(path: Optional[str], fallback: Path) -> Path:
    if path:
        return Path(os.path.expanduser(str(path)))
    return fallback


# --------------------------------------------------------------------- time


def _as_utc(value: Optional[dt.datetime]) -> dt.datetime:
    if value is None:
        return dt.datetime.now(dt.timezone.utc)
    if value.tzinfo is None:
        return value.replace(tzinfo=dt.timezone.utc)
    return value.astimezone(dt.timezone.utc)


def parse_iso(value: Any) -> dt.datetime:
    text = str(value).strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    parsed = dt.datetime.fromisoformat(text)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def iso_z(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def local_iso(timestamp: float) -> str:
    return dt.datetime.fromtimestamp(timestamp).astimezone().isoformat(timespec="seconds")


# --------------------------------------------------------------------- key


def read_key(db_path: Optional[str] = None, auth_path: Optional[str] = None) -> Tuple[Optional[str], str]:
    """Return (key, source) where source is db, auth.json, or none.

    Never log or otherwise expose the returned key.
    """
    db = _resolve(db_path, default_db_path())
    if db.exists():
        try:
            con = sqlite3.connect(db.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
            try:
                row = con.execute(
                    "select value from credential where integration_id = 'opencode-go' limit 1"
                ).fetchone()
            finally:
                con.close()
            if row and row[0]:
                parsed = json.loads(row[0])
                if isinstance(parsed, dict):
                    key = parsed.get("key")
                    if isinstance(key, str) and key:
                        return key, "db"
        except Exception:
            # A missing table, a locked database, or malformed JSON all fall
            # through to the v1 fallback without leaking the value.
            pass

    auth = _resolve(auth_path, default_auth_path())
    if auth.exists():
        try:
            parsed = json.loads(auth.read_text(encoding="utf-8"))
            entry = parsed.get("opencode-go") if isinstance(parsed, dict) else None
            if isinstance(entry, dict):
                key = entry.get("key")
                if isinstance(key, str) and key:
                    return key, "auth.json"
        except Exception:
            pass

    return None, "none"


# --------------------------------------------------------------------- api


def fetch_usage(key: str, timeout: float = 15.0) -> Dict[str, Dict[str, Any]]:
    """Call the unofficial-but-official usage endpoint.

    Returns a normalized per-window dict. Raises ApiError on handled failures.
    urllib honors the standard https_proxy/HTTPS_PROXY environment variables.
    """
    request = urllib.request.Request(
        API_URL,
        headers={
            "Authorization": "Bearer " + key,
            "User-Agent": USER_AGENT,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
    except urllib.error.HTTPError as exc:
        raise ApiError("auth" if exc.code in (401, 403) else "network")
    except Exception:
        raise ApiError("network")

    try:
        payload = json.loads(raw.decode("utf-8", "replace"))
    except Exception:
        raise ApiError("malformed")

    usage = payload.get("usage") if isinstance(payload, dict) else None
    if not isinstance(usage, dict):
        raise ApiError("malformed")

    normalized: Dict[str, Dict[str, Any]] = {}
    for name in WINDOWS:
        window = usage.get(name)
        if not isinstance(window, dict):
            raise ApiError("malformed")
        status = str(window.get("status", "ok"))
        percent = window.get("percent")
        resets_at = window.get("resetsAt")
        if status != "ok":
            normalized[name] = {"available": False, "status": status, "percent": None, "resetsAt": None}
            continue
        if isinstance(percent, bool) or not isinstance(percent, (int, float)):
            raise ApiError("malformed")
        if not isinstance(resets_at, str):
            raise ApiError("malformed")
        try:
            reset_dt = parse_iso(resets_at)
        except Exception:
            raise ApiError("malformed")
        percent_int = max(0, min(100, int(round(float(percent)))))
        normalized[name] = {
            "available": True,
            "status": "ok",
            "percent": percent_int,
            "resetsAt": iso_z(reset_dt),
        }
    return normalized


def build_windows(raw: Dict[str, Dict[str, Any]], now: dt.datetime) -> Dict[str, Dict[str, Any]]:
    windows: Dict[str, Dict[str, Any]] = {}
    for name in WINDOWS:
        window = raw.get(name) or {}
        if not window.get("available"):
            windows[name] = {
                "available": False,
                "status": window.get("status", "unavailable"),
                "percent": None,
                "remaining": None,
                "resetsAt": None,
                "resetInSec": None,
            }
            continue
        percent = int(window["percent"])
        remaining = max(0, min(100, 100 - percent))
        try:
            reset_dt = parse_iso(window["resetsAt"])
        except Exception:
            windows[name] = {
                "available": False,
                "status": "malformed",
                "percent": None,
                "remaining": None,
                "resetsAt": None,
                "resetInSec": None,
            }
            continue
        windows[name] = {
            "available": True,
            "status": "ok",
            "percent": percent,
            "remaining": remaining,
            "resetsAt": iso_z(reset_dt),
            "resetInSec": min(RESET_HORIZON_SEC[name],
                               max(0, int((reset_dt - now).total_seconds()))),
        }
    return windows


def rehydrate_windows(cached: Dict[str, Any], now: dt.datetime) -> Dict[str, Dict[str, Any]]:
    """Rebuild the cached windows with a fresh resetInSec."""
    windows: Dict[str, Dict[str, Any]] = {}
    for name in WINDOWS:
        window = cached.get(name) if isinstance(cached, dict) else None
        if not isinstance(window, dict):
            continue
        if not window.get("available") or window.get("percent") is None:
            windows[name] = {
                "available": False,
                "status": window.get("status", "unavailable"),
                "percent": None,
                "remaining": None,
                "resetsAt": None,
                "resetInSec": None,
            }
            continue
        try:
            reset_dt = parse_iso(window["resetsAt"])
        except Exception:
            continue
        percent = max(0, min(100, int(window["percent"])))
        cached_remaining = window.get("remaining")
        remaining = max(0, min(100, int(
            cached_remaining if cached_remaining is not None else 100 - percent
        )))
        windows[name] = {
            "available": True,
            "status": "ok",
            "percent": percent,
            "remaining": remaining,
            "resetsAt": iso_z(reset_dt),
            "resetInSec": min(RESET_HORIZON_SEC[name],
                               max(0, int((reset_dt - now).total_seconds()))),
        }
    return windows


# --------------------------------------------------------------------- cache


def _read_json(path: Path) -> Optional[Dict[str, Any]]:
    try:
        parsed = json.loads(path.read_text(encoding="utf-8"))
        return parsed if isinstance(parsed, dict) else None
    except Exception:
        return None


def load_state(cache_dir: Path) -> Dict[str, Any]:
    return _read_json(cache_dir / "state.json") or {}


def save_state(cache_dir: Path, state: Dict[str, Any]) -> None:
    try:
        cache_dir.mkdir(parents=True, exist_ok=True)
        target = cache_dir / "state.json"
        temp = cache_dir / "state.json.tmp"
        temp.write_text(json.dumps(state, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        os.replace(temp, target)
    except OSError:
        # A read-only cache must not break the widget.
        pass


class CacheLock:
    def __init__(self, cache_dir: Path):
        self.cache_dir = cache_dir
        self.fd: Optional[int] = None

    def __enter__(self) -> "CacheLock":
        try:
            self.cache_dir.mkdir(parents=True, exist_ok=True)
            self.fd = os.open(str(self.cache_dir / ".lock"), os.O_CREAT | os.O_RDWR, 0o600)
            fcntl.flock(self.fd, fcntl.LOCK_EX)
        except OSError:
            self.fd = None
        return self

    def __exit__(self, *_args: Any) -> None:
        if self.fd is not None:
            try:
                fcntl.flock(self.fd, fcntl.LOCK_UN)
            finally:
                os.close(self.fd)
                self.fd = None


def cache_is_fresh(state: Dict[str, Any], now: dt.datetime, ttl: float) -> bool:
    fetched = state.get("fetchedAt")
    if not isinstance(fetched, (int, float)):
        return False
    return (now.timestamp() - float(fetched)) < ttl and bool(state.get("windows"))


# --------------------------------------------------------------------- samples


def _sample_file(cache_dir: Path) -> Path:
    return cache_dir / "samples.jsonl"


def read_samples(cache_dir: Path) -> List[Dict[str, Any]]:
    path = _sample_file(cache_dir)
    samples: List[Dict[str, Any]] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return samples
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            raw = json.loads(line)
            timestamp = parse_iso(raw["t"])
        except Exception:
            continue
        sample: Dict[str, Any] = {"t": iso_z(timestamp), "_dt": timestamp}
        found = False
        for name in WINDOWS:
            value = raw.get(name)
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                sample[name] = int(round(value))
                found = True
            else:
                sample[name] = None
        if found:
            samples.append(sample)
    samples.sort(key=lambda item: item["_dt"])
    return samples


def write_samples(cache_dir: Path, samples: Sequence[Dict[str, Any]], now: dt.datetime) -> List[Dict[str, Any]]:
    kept = [
        sample
        for sample in samples
        if (now - sample["_dt"]).total_seconds() <= SAMPLE_RETENTION_SEC
    ]
    try:
        cache_dir.mkdir(parents=True, exist_ok=True)
        target = _sample_file(cache_dir)
        temp = cache_dir / "samples.jsonl.tmp"
        with temp.open("w", encoding="utf-8") as handle:
            for sample in kept:
                record = {"t": sample["t"]}
                for name in WINDOWS:
                    if sample.get(name) is not None:
                        record[name] = sample[name]
                handle.write(json.dumps(record, separators=(",", ":")) + "\n")
        os.replace(temp, target)
    except OSError:
        pass
    return kept


def append_sample(
    cache_dir: Path,
    samples: List[Dict[str, Any]],
    now: dt.datetime,
    windows: Dict[str, Dict[str, Any]],
) -> List[Dict[str, Any]]:
    values = {
        name: (windows.get(name, {}).get("percent") if windows.get(name, {}).get("available") else None)
        for name in WINDOWS
    }
    if all(value is None for value in values.values()):
        return write_samples(cache_dir, samples, now)
    if samples and (now - samples[-1]["_dt"]).total_seconds() < 60:
        return write_samples(cache_dir, samples, now)
    sample: Dict[str, Any] = {"t": iso_z(now), "_dt": now}
    sample.update(values)
    samples = list(samples) + [sample]
    return write_samples(cache_dir, samples, now)


def downsample(samples: Sequence[Dict[str, Any]], max_points: int = 360) -> List[Dict[str, Any]]:
    if len(samples) <= max_points:
        return list(samples)
    step = max(1, math.ceil(len(samples) / max_points))
    result = list(samples[::step])
    if result[-1] is not samples[-1]:
        result.append(samples[-1])
    return result


def compute_runway(
    samples: Sequence[Dict[str, Any]],
    windows: Dict[str, Dict[str, Any]],
    now: dt.datetime,
) -> Dict[str, Dict[str, Any]]:
    """Estimate how long the current burn rate can continue.

    Uses a least-squares slope over the current increasing segment of samples.
    Returns seconds capped by the window reset, or None when there is not
    enough history.
    """
    result: Dict[str, Dict[str, Any]] = {}
    for name in WINDOWS:
        window = windows.get(name) or {}
        if not window.get("available") or window.get("remaining") is None:
            result[name] = {"seconds": None, "reason": "unavailable"}
            continue
        percent = window.get("percent")
        if percent is not None and int(percent) == 0:
            result[name] = {"seconds": None, "ratePerHour": 0.0, "reason": "flat"}
            continue
        horizon = RUNWAY_HORIZON_SEC[name]
        points: List[Tuple[dt.datetime, int]] = []
        for sample in samples:
            value = sample.get(name)
            if value is None:
                continue
            age = (now - sample["_dt"]).total_seconds()
            if age < -60 or age > horizon:
                continue
            # The rolling window slides: a decrease can be old usage ageing out,
            # not a reset. Weekly/monthly only decrease when the window resets.
            if name != "rolling" and points and value < points[-1][1]:
                points = []
            points.append((sample["_dt"], int(value)))

        if len(points) < RUNWAY_MIN_POINTS:
            result[name] = {"seconds": None, "reason": "insufficient"}
            continue
        span = (points[-1][0] - points[0][0]).total_seconds()
        if span < RUNWAY_MIN_SPAN_SEC:
            result[name] = {"seconds": None, "reason": "insufficient"}
            continue

        origin = points[0][0]
        xs = [(point[0] - origin).total_seconds() for point in points]
        ys = [point[1] for point in points]
        mean_x = sum(xs) / len(xs)
        mean_y = sum(ys) / len(ys)
        denominator = sum((value - mean_x) ** 2 for value in xs)
        if denominator <= 0:
            result[name] = {"seconds": None, "reason": "insufficient"}
            continue
        slope = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys)) / denominator
        if slope <= 0:
            result[name] = {"seconds": None, "ratePerHour": 0.0, "reason": "flat"}
            continue
        remaining = float(window["remaining"])
        seconds = 0.0 if remaining <= 0 else remaining / slope
        reset_in = window.get("resetInSec")
        if reset_in is not None:
            seconds = min(seconds, float(reset_in))
        result[name] = {
            "seconds": int(max(0, round(seconds))),
            "ratePerHour": round(slope * 3600, 2),
            "reason": "ok",
        }
    return result


# --------------------------------------------------------------------- alerts


def _prune_alerts(state: Dict[str, Any], now: dt.datetime) -> None:
    sent = state.get("alertsSent")
    if not isinstance(sent, dict):
        state["alertsSent"] = {}
        return
    cutoff = now.timestamp() - 40 * 24 * 3600
    state["alertsSent"] = {
        key: value
        for key, value in sent.items()
        if isinstance(value, (int, float)) and value >= cutoff
    }


def compute_alerts(
    windows: Dict[str, Dict[str, Any]],
    state: Dict[str, Any],
    now: dt.datetime,
    warn: int,
    crit: int,
    notify_reset: bool,
    enabled: bool,
) -> List[Dict[str, Any]]:
    """Return new alerts and update dedup state in place."""
    alerts: List[Dict[str, Any]] = []
    sent = state.setdefault("alertsSent", {})
    last_resets = state.setdefault("lastResetsAt", {})
    crit = min(crit, warn)

    for name in WINDOWS:
        window = windows.get(name) or {}
        if not window.get("available") or window.get("remaining") is None:
            continue
        remaining = int(window["remaining"])
        resets_at = window.get("resetsAt")
        if not resets_at:
            continue
        try:
            reset_in = min(RESET_HORIZON_SEC[name],
                           max(0, int((parse_iso(resets_at) - now).total_seconds())))
        except Exception:
            reset_in = None

        previous = last_resets.get(name)
        if enabled and previous and previous != resets_at:
            try:
                old_dt = parse_iso(previous)
                new_dt = parse_iso(resets_at)
                if old_dt <= now < new_dt and notify_reset:
                    key = "%s:reset:%s" % (name, resets_at)
                    if key not in sent:
                        alerts.append({
                            "window": name,
                            "level": "reset",
                            "remaining": remaining,
                            "percent": window.get("percent"),
                            "resetsAt": resets_at,
                            "resetInSec": reset_in,
                        })
                        sent[key] = int(now.timestamp())
            except Exception:
                pass
        last_resets[name] = resets_at

        if not enabled:
            continue
        level = "crit" if remaining <= crit else ("warn" if remaining <= warn else None)
        if level is None:
            continue
        key = "%s:%s:%s" % (name, level, resets_at)
        if key in sent:
            continue
        alerts.append({
            "window": name,
            "level": level,
            "remaining": remaining,
            "percent": window.get("percent"),
            "resetsAt": resets_at,
            "resetInSec": reset_in,
        })
        sent[key] = int(now.timestamp())

    _prune_alerts(state, now)
    return alerts


# --------------------------------------------------------------------- report


def _cache_windows(windows: Dict[str, Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    cached: Dict[str, Dict[str, Any]] = {}
    for name, window in windows.items():
        cached[name] = {
            "available": bool(window.get("available")),
            "status": window.get("status", "unavailable"),
            "percent": window.get("percent"),
            "remaining": window.get("remaining"),
            "resetsAt": window.get("resetsAt"),
        }
    return cached


def _report_samples(samples: Sequence[Dict[str, Any]]) -> List[Dict[str, Any]]:
    output = []
    for sample in downsample(samples):
        record = {"t": sample["t"]}
        for name in WINDOWS:
            if sample.get(name) is not None:
                record[name] = sample[name]
        output.append(record)
    return output


def collect_report(
    *,
    now: Optional[dt.datetime] = None,
    db_path: Optional[str] = None,
    auth_path: Optional[str] = None,
    cache_dir: Optional[str] = None,
    warn: int = 20,
    crit: int = 10,
    notify_reset: bool = False,
    no_alerts: bool = False,
    plan_label: str = "OpenCode Go",
    force: bool = False,
    fetch: Optional[Callable[[str], Dict[str, Dict[str, Any]]]] = None,
) -> Dict[str, Any]:
    now = _as_utc(now)
    cache_root = Path(cache_dir) if cache_dir else default_cache_dir()
    fetch = fetch or (lambda key: fetch_usage(key))
    warn = max(1, min(99, int(warn)))
    crit = max(1, min(99, int(crit)))

    report: Dict[str, Any] = {
        "ok": False,
        "state": "no-data",
        "stale": False,
        "updatedAt": local_iso(now.timestamp()),
        "planLabel": plan_label,
        "windows": {},
        "runway": {name: {"seconds": None} for name in WINDOWS},
        "samples": [],
        "alerts": [],
    }

    key, _source = read_key(db_path, auth_path)
    state = load_state(cache_root)
    samples = read_samples(cache_root)

    if not key:
        report["state"] = "no-key"
        report["samples"] = _report_samples(samples)
        report["runway"] = compute_runway(samples, {}, now)
        return report

    def use_cached(updated_ts: float, stale: bool) -> Dict[str, Any]:
        windows = rehydrate_windows(state.get("windows") or {}, now)
        report["windows"] = windows
        report["state"] = "stale" if stale else "ok"
        report["stale"] = stale
        report["ok"] = not stale
        report["updatedAt"] = local_iso(updated_ts)
        report["runway"] = compute_runway(samples, windows, now)
        report["samples"] = _report_samples(samples)
        return report

    if cache_is_fresh(state, now, CACHE_TTL_SEC) and not force:
        return use_cached(float(state["fetchedAt"]), False)

    with CacheLock(cache_root):
        # Another bar instance may have refreshed while we waited for the lock.
        state = load_state(cache_root)
        samples = read_samples(cache_root)
        if cache_is_fresh(state, now, CACHE_TTL_SEC) and not force:
            return use_cached(float(state["fetchedAt"]), False)

        try:
            raw = fetch(key)
        except ApiError as exc:
            if exc.kind == "auth":
                report["state"] = "auth-expired"
                report["stale"] = False
                report["samples"] = _report_samples(samples)
                return report

            if state.get("windows"):
                return use_cached(float(state.get("fetchedAt") or 0) or now.timestamp(), True)

            report["state"] = "no-data"
            report["stale"] = True
            report["samples"] = _report_samples(samples)
            return report

        windows = build_windows(raw, now)

        samples = append_sample(cache_root, samples, now, windows)
        runway = compute_runway(samples, windows, now)
        alerts = compute_alerts(
            windows,
            state,
            now,
            warn,
            crit,
            notify_reset,
            not no_alerts,
        )

        state.update({
            "version": 1,
            "state": "ok",
            "fetchedAt": int(now.timestamp()),
            "windows": _cache_windows(windows),
        })
        save_state(cache_root, state)

        report["state"] = "ok"
        report["stale"] = False
        report["ok"] = True
        report["windows"] = windows
        report["runway"] = runway
        report["samples"] = _report_samples(samples)
        report["alerts"] = alerts
        return report


def fixture_report(path: str) -> Dict[str, Any]:
    """Load a static report for UI development. Never used in production."""
    try:
        parsed = json.loads(Path(os.path.expanduser(path)).read_text(encoding="utf-8"))
    except Exception as exc:
        return {"ok": False, "state": "error", "error": type(exc).__name__}
    if not isinstance(parsed, dict):
        return {"ok": False, "state": "error", "error": "invalid-fixture"}
    report = {
        "ok": parsed.get("ok", parsed.get("state") == "ok"),
        "state": parsed.get("state", "ok"),
        "stale": bool(parsed.get("stale", False)),
        "updatedAt": parsed.get("updatedAt") or local_iso(dt.datetime.now().timestamp()),
        "planLabel": parsed.get("planLabel", "OpenCode Go"),
        "windows": parsed.get("windows", {}),
        "runway": parsed.get("runway", {name: {"seconds": None} for name in WINDOWS}),
        "samples": parsed.get("samples", []),
        "alerts": [],
    }
    return report


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="OpenCode Quota data collector")
    parser.add_argument("--json", action="store_true", help="emit JSON (always on)")
    parser.add_argument("--pretty", action="store_true", help="pretty-print JSON")
    parser.add_argument("--force", action="store_true", help="ignore the 60s cache")
    parser.add_argument("--warn", type=int, default=20, help="warn below this remaining percentage")
    parser.add_argument("--crit", type=int, default=10, help="critical below this remaining percentage")
    parser.add_argument("--notify-reset", action="store_true", help="emit reset alerts")
    parser.add_argument("--no-alerts", action="store_true", help="do not emit alerts")
    parser.add_argument("--plan-label", default="OpenCode Go", help="label echoed in the output")
    parser.add_argument("--db", default="", help="override opencode.db path")
    parser.add_argument("--auth", default="", help="override auth.json path")
    parser.add_argument("--cache-dir", default="", help="override cache directory")
    parser.add_argument("--fixture", default="", help="serve a static JSON report (development only)")
    parser.add_argument("--debug", action="store_true", help="print sanitized diagnostics to stderr")
    args = parser.parse_args(argv)

    try:
        if args.fixture:
            report = fixture_report(args.fixture)
        else:
            report = collect_report(
                db_path=args.db or None,
                auth_path=args.auth or None,
                cache_dir=args.cache_dir or None,
                warn=args.warn,
                crit=args.crit,
                notify_reset=args.notify_reset,
                no_alerts=args.no_alerts,
                plan_label=args.plan_label,
                force=args.force,
            )
        if args.debug:
            sys.stderr.write(
                "opencode-quota: state=%s windows=%d samples=%d\n"
                % (report.get("state"), len(report.get("windows") or {}), len(report.get("samples") or []))
            )
        print(json.dumps(
            report,
            ensure_ascii=False,
            indent=2 if args.pretty else None,
            separators=None if args.pretty else (",", ":"),
        ))
        return 0
    except Exception as exc:  # never include request data or the key
        if args.debug:
            sys.stderr.write("opencode-quota: internal error %s\n" % type(exc).__name__)
        print(json.dumps({"ok": False, "state": "error", "error": type(exc).__name__}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
