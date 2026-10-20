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
{ "id": "jihonghe.opencode-quota", "debugFixture": "/path/to/tests/fixtures/report-stale.json" }
```

Available fixtures:

- `report-stale.json` — cached readings, runway values, trend data.
- `report-no-key.json` — signed-out state with local model usage.
- `report-auth-expired.json` — expired credentials.
- `report-not-ready.json` — fewer than 3 samples / no runway; the Runway table
  must be hidden and the remaining layout must fill the panel/tooltip.
- `report-idle.json` — one window has zero burn; it must show `0.0%/h`,
  `Lasts until reset`, and `after reset` instead of blank cells.

Reload the shell config or restart the shell after changing the fixture.
