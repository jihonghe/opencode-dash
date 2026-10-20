import QtQuick
import "../Model.js" as Model

Item {
  id: root

  property var failures: []

  function check(name, condition) {
    if (!condition) root.failures.push(name)
  }

  function sampleReport() {
    return {
      state: "ok",
      stale: false,
      updatedAt: "2026-10-20T20:35:00+00:00",
      windows: {
        rolling: { available: true, percent: 2, remaining: 98, resetsAt: "2026-10-20T16:08:43Z", resetInSec: 14923 },
        weekly: { available: true, percent: 20, remaining: 80, resetsAt: "2026-10-26T00:00:00Z", resetInSec: 463280 },
        monthly: { available: true, percent: 14, remaining: 86, resetsAt: "2026-11-17T14:35:30Z", resetInSec: 2416610 }
      },
      models: [
        { id: "deepseek-v4.1-flash", messages: 1196, cost: 3.99, free: false },
        { id: "nemotron-3.5-super-vl-free", messages: 24, cost: 0, free: true }
      ],
      daily: [
        { date: "2026-10-13", messages: 1, cost: 0.1 },
        { date: "2026-10-14", messages: 2, cost: 0.2 },
        { date: "2026-10-20", messages: 3, cost: 0.3 }
      ],
      samples: [
        { t: "2026-10-13T00:00:00Z", monthly: 5 },
        { t: "2026-10-20T00:00:00Z", monthly: 14 }
      ]
    }
  }

  Component.onCompleted: {
    var report = sampleReport()

    check("worst", Model.barText(report, {}) === "7d 80%")
    check("all", Model.barText(report, { barWindows: "all" }) === "5h 98% \u00b7 7d 80% \u00b7 M 86%")
    check("month", Model.barText(report, { barWindows: "month" }) === "M 86%")
    check("used", Model.barText(report, { barWindows: "month", percentMode: "used" }) === "M 14%")
    check("worst switches", Model.worstWindow({
      rolling: { available: true, percent: 10, remaining: 90 },
      weekly: { available: true, percent: 95, remaining: 5 },
      monthly: { available: true, percent: 50, remaining: 50 }
    }) === "weekly")

    var critical = sampleReport()
    critical.windows.monthly.percent = 91
    critical.windows.monthly.remaining = 9
    check("critical mark", Model.barText(critical, {}) === "M 9%!")
    check("critical all mark", Model.barText(critical, { barWindows: "all" }).indexOf("M 9%!") !== -1)

    var unavailable = sampleReport()
    unavailable.windows.weekly.available = false
    check("unavailable skipped", Model.barText(unavailable, {}) === "M 86%")
    check("month unavailable", Model.barText(unavailable, { barWindows: "month" }) === "M 86%")

    check("no data", Model.barText(null, {}) === "\u2014")
    check("no key", Model.barText({ state: "no-key", windows: {} }, {}) === "\u2014")
    check("auth expired", Model.barText({ state: "auth-expired", windows: {} }, {}) === "\u2014")
    check("stale shows cached", Model.barText({
      state: "stale", stale: true, windows: report.windows
    }, {}) === "7d 80%")

    var vertical = Model.verticalParts(report, {})
    check("vertical label", vertical.label === "7d")
    check("vertical value", vertical.value === "80%")

    check("duration hours", Model.fmtDuration(14923) === "4h 8m")
    check("duration minutes", Model.fmtDuration(90) === "1m")
    check("duration hours long", Model.fmtDuration(90000) === "25h")
    check("duration days", Model.fmtDuration(187200) === "2d 4h")
    check("duration null", Model.fmtDuration(null) === "\u2014")
    check("reset rolling", Model.fmtReset("rolling", "2026-10-20T16:08:43Z") === "16:08")
    check("reset weekly", Model.fmtReset("weekly", "2026-10-26T00:00:00Z") === "Mon 00:00")
    check("reset monthly", Model.fmtReset("monthly", "2026-11-17T14:35:30Z") === "11-17 14:35")
    check("compact", Model.fmtCompact(10710000) === "10.7M")
    check("cost", Model.fmtCost(3.993) === "$3.99")
    check("free cost", Model.fmtCost(0) === "$0")

    var defaults = Model.settingsWithDefaults({ refreshIntervalSec: 10, warnRemaining: 0, critRemaining: 200 })
    check("clamp refresh", defaults.refreshIntervalSec === 60)
    check("clamp warn", defaults.warnRemaining === 1)
    check("clamp crit", defaults.critRemaining === 1)
    check("default plan", defaults.planLabel === "OpenCode Go")
    check("bool string", Model.settingsWithDefaults({ notifyEnabled: "false" }).notifyEnabled === false)

    var tip = Model.tooltip(report, {})
    check("tooltip windows", tip.indexOf("5h") !== -1 && tip.indexOf("7d") !== -1 && tip.indexOf("M ") !== -1)
    check("tooltip local usage", tip.indexOf("local usage this cycle") !== -1)
    check("tooltip updated", tip.indexOf("updated 20:35") !== -1)
    var staleTip = Model.tooltip({ state: "stale", stale: true, updatedAt: "2026-10-20T20:35:00+00:00", windows: report.windows }, {})
    check("tooltip stale", staleTip.indexOf("cached at 20:35") !== -1)
    check("tooltip no key", Model.tooltip({ state: "no-key" }, {}).indexOf("not signed in") !== -1)

    var now = new Date("2026-10-20T12:00:00Z").getTime()
    check("trend 7d", Model.trendDaily(report.daily, "7d", now).length === 2)
    check("trend cycle", Model.trendDaily(report.daily, "cycle", now).length === 3)
    check("trend samples 7d", Model.trendSamples(report.samples, "7d", now).length === 1)

    var config = { layout: { right: [{ id: "jihonghe.opencode-quota", barWindows: "all" }, { id: "omarchy.clock" }] } }
    var saved = Model.savedBarSettings(config, "jihonghe.opencode-quota", { section: "right", index: 0 })
    check("saved settings", saved && saved.barWindows === "all")
    check("saved by id", Model.savedBarSettings(config, "jihonghe.opencode-quota", null).barWindows === "all")

    var pending = { barWindows: { value: "month", at: 1000 } }
    check("with pending", Model.withPending({ barWindows: "all" }, pending).barWindows === "month")
    check("prune applied", Object.keys(Model.prunePending({ barWindows: "month" }, pending, 2000)).length === 0)
    check("prune expired", Object.keys(Model.prunePending({ barWindows: "all" }, pending, 20000)).length === 0)

    if (root.failures.length > 0) {
      console.error("MODEL TEST FAILURES: " + root.failures.join(", "))
    } else {
      console.log("MODEL TESTS OK")
    }
    // qml6 drops buffered logs when exiting non-zero, so the shell wrapper
    // reads this marker instead of relying on the process status.
    Qt.exit(0)
  }
}
