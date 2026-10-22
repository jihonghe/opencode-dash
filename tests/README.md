# Tests

## Data layer

The unit tests use temporary directories and injected API responses. They do
not read the real key and do not use the network.

```bash
python3 -m unittest discover -s tests -v
```

Coverage includes v2/v1 credential lookup, `no-key` / `auth-expired` / `stale`
states, cache TTL and forced refresh, ISO reset parsing, official-only report
fields, runway, sample trimming, alert deduplication, and key redaction.

## Display helpers

`Model.js` is exercised by the QML engine the widget itself uses:

```bash
tests/run-model-test.sh
```

The wrapper sets `QML_RUNTIME` if your `qml6` binary is not at
`/usr/sbin/qml6`.

## UI fixtures

These reports can be injected with the hidden `debugFixture` setting on the
widget's `shell.json` entry:

```json
{ "id": "jihonghe.opencode-dash", "debugFixture": "/path/to/tests/fixtures/report-stale.json" }
```

Available fixtures:

- `report-stale.json` — cached readings with `stale=true`; the Runway table is
  hidden until the API succeeds again.
- `report-no-key.json` — signed-out state.
- `report-auth-expired.json` — expired credentials.
- `report-not-ready.json` — fewer than 3 samples; `Avg pace` shows `Collecting`
  and `Lasts` shows `—`.
- `report-idle.json` — one period is flat; both derived columns show `—` for
  that period, while the other periods show numeric estimates.
- `report-preview.json` — deterministic 100/64/78 values with weekly/monthly
  runway estimates; used for README screenshots.

Non-stale fixtures are shifted to the current time when loaded, so their
samples and reset countdowns stay usable. Reload the shell config or restart
the shell after changing the fixture.
