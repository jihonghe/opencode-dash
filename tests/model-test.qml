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
      samples: [
        { t: "2026-10-13T00:00:00Z", monthly: 5 },
        { t: "2026-10-20T00:00:00Z", monthly: 14 }
      ]
    }
  }

  Component.onCompleted: {
    var report = sampleReport()
    var now = new Date("2026-10-20T12:00:00Z").getTime()

    check("worst", Model.barText(report, {}, now) === "Weekly\n80% (5d 12h)")
    check("all", Model.barText(report, { barWindows: "all" }, now) === "Rolling 98% \u00b7 Weekly 80% \u00b7 Monthly 86%")
    check("month", Model.barText(report, { barWindows: "month" }, now) === "Monthly\n86% (28d 2h)")
    check("used", Model.barText(report, { barWindows: "month", percentMode: "used" }, now) === "Monthly\n14% (28d 2h)")
    check("worst switches", Model.worstWindow({
      rolling: { available: true, percent: 10, remaining: 90 },
      weekly: { available: true, percent: 95, remaining: 5 },
      monthly: { available: true, percent: 50, remaining: 50 }
    }) === "weekly")

    var segments = Model.barSegments(report, { barWindows: "all" })
    var segmentText = ""
    for (var si = 0; si < segments.length; si++) segmentText += segments[si].text
    check("bar segments all", segmentText === "Rolling 98% \u00b7 Weekly 80% \u00b7 Monthly 86%")
    check("bar segment label uncolored", segments[0].tone === "none")
    check("bar segment percentage colored", segments[1].tone === "normal" && segments[1].text === "98%")

    var warnSingle = Model.barSingle({
      state: "ok", windows: {
        rolling: { available: true, percent: 85, remaining: 15, resetsAt: "2026-10-20T16:00:00Z" },
        weekly: { available: true, percent: 20, remaining: 80, resetsAt: "2026-10-26T00:00:00Z" },
        monthly: { available: true, percent: 14, remaining: 86, resetsAt: "2026-11-17T14:35:30Z" }
      }
    }, { barWindows: "worst" }, now)
    check("single warn", warnSingle.value === "15%" && warnSingle.tone === "warn")
    check("single label", warnSingle.label === "Rolling")
    check("single reset", warnSingle.reset === "(4h)")

    var monthSingle = Model.barSingle(report, { barWindows: "month" }, now)
    check("single month", monthSingle.label === "Monthly" && monthSingle.value === "86%"
      && monthSingle.reset === "(28d 2h)")

    var noReset = Model.barSingle({
      state: "ok", windows: {
        rolling: { available: true, percent: 10, remaining: 90 },
        weekly: { available: false },
        monthly: { available: false }
      }
    }, {}, now)
    check("single no reset", noReset.value === "90%" && noReset.reset === "")

    var noDataSingle = Model.barSingle(null, {}, now)
    check("single no data", noDataSingle.label === "\u2014" && noDataSingle.value === "")

    var critical = sampleReport()
    critical.windows.monthly.percent = 91
    critical.windows.monthly.remaining = 9
    check("critical mark", Model.barText(critical, {}, now) === "Monthly\n9%! (28d 2h)")
    check("critical all mark", Model.barText(critical, { barWindows: "all" }, now).indexOf("Monthly 9%!") !== -1)
    var critSingle = Model.barSingle(critical, {}, now)
    check("single crit", critSingle.value === "9%!" && critSingle.tone === "crit")

    var unavailable = sampleReport()
    unavailable.windows.weekly.available = false
    check("unavailable skipped", Model.barText(unavailable, {}, now) === "Monthly\n86% (28d 2h)")
    check("month unavailable", Model.barText(unavailable, { barWindows: "month" }, now) === "Monthly\n86% (28d 2h)")

    check("no data", Model.barText(null, {}, now) === "\u2014")
    check("no key", Model.barText({ state: "no-key", windows: {} }, {}, now) === "\u2014")
    check("auth expired", Model.barText({ state: "auth-expired", windows: {} }, {}, now) === "\u2014")
    check("stale shows cached", Model.barText({
      state: "stale", stale: true, windows: report.windows
    }, {}, now) === "Weekly\n80% (5d 12h)")

    var vertical = Model.verticalParts(report, {})
    check("vertical label", vertical.label === "7d")
    check("vertical value", vertical.value === "80%")
    check("vertical tone", vertical.tone === "normal")

    check("duration hours", Model.fmtDuration(14923) === "4h 8m")
    check("duration minutes", Model.fmtDuration(90) === "1m")
    check("duration hours long", Model.fmtDuration(90000) === "25h")
    check("duration days", Model.fmtDuration(187200) === "2d 4h")
    check("duration null", Model.fmtDuration(null) === "\u2014")
    check("reset seconds", Model.resetSeconds("rolling", report.windows.rolling, now) === 14923)
    check("reset text", Model.resetText("weekly", report.windows.weekly, now) === "(5d 12h)")
    check("reset missing", Model.resetText("weekly", { available: true }, now) === "")
    check("reset malformed", Model.resetSeconds("weekly", { resetsAt: "nope" }, now) === null)
    check("reset past", Model.resetText("rolling", { resetsAt: "2026-10-20T11:00:00Z" }, now) === "(<1m)")
    check("reset clamp", Model.resetSeconds("rolling", { resetsAt: "2026-10-30T12:00:00Z" }, now)
      === Model.resetHorizon("rolling"))
    check("reset rolling", Model.fmtReset("rolling", "2026-10-20T16:08:43Z") === "16:08")
    check("reset weekly", Model.fmtReset("weekly", "2026-10-26T00:00:00Z") === "Mon 00:00")
    check("reset monthly", Model.fmtReset("monthly", "2026-11-17T14:35:30Z") === "11-17 14:35")
    var defaults = Model.settingsWithDefaults({ refreshIntervalSec: 10, warnRemaining: 0, critRemaining: 200 })
    check("clamp refresh", defaults.refreshIntervalSec === 60)
    check("clamp warn", defaults.warnRemaining === 1)
    check("clamp crit", defaults.critRemaining === 1)
    check("default plan", defaults.planLabel === "OpenCode Go")
    check("valid plan", Model.settingsWithDefaults({ planLabel: "OpenCode Go Plus" }).planLabel === "OpenCode Go Plus")
    check("invalid plan", Model.settingsWithDefaults({ planLabel: "Custom" }).planLabel === "OpenCode Go")
    check("bool string", Model.settingsWithDefaults({ notifyEnabled: "false" }).notifyEnabled === false)
    check("plan valid", Model.settingsWithDefaults({ planLabel: "OpenCode Go Plus" }).planLabel === "OpenCode Go Plus")
    check("plan fallback", Model.settingsWithDefaults({ planLabel: "Custom" }).planLabel === "OpenCode Go")
    check("plan options", Model.planOptions().join(",") === "OpenCode Go,OpenCode Go Plus")
    check("reset horizon", Model.resetHorizon("rolling") === 5 * 3600 + 60
      && Model.resetHorizon("weekly") === 7 * 86400 + 60
      && Model.resetHorizon("monthly") === 31 * 86400 + 60)

    check("burn rolling", Model.burnText(2.7, "rolling") === "2.7%/h")
    check("burn weekly", Model.burnText(0.97, "weekly") === "23.3%/day")
    check("runway short", Model.runwayLabel(3600, 7200, 50) === "~1h")
    check("runway capped", Model.runwayLabel(7200, 7200, 50) === "\u2265 2h")
    check("runway near cap", Model.runwayLabel(7190, 7200, 50) === "\u2265 2h")
    check("runway empty", Model.runwayLabel(0, 7200, 0) === "0m")
    check("runway null", Model.runwayLabel(null, 7200, 50) === "")
    check("cycle unused", Model.cycleUnusedText({ available: true, unusedPercent: 38 }) === "~38% unused")
    check("cycle unused rounds", Model.cycleUnusedText({ available: true, unusedPercent: 37.6 }) === "~38% unused")
    check("cycle unused unavailable", Model.cycleUnusedText({ available: false, unusedPercent: 38 }) === "")
    check("cycle unused null", Model.cycleUnusedText(null) === "")
    check("cycle unused missing percent", Model.cycleUnusedText({ available: true }) === "")
    check("eta", Model.etaLabel(50, 20, 1, 200000) === "~30h")
    check("eta now", Model.etaLabel(15, 20, 1, 86400) === "now")
    check("eta after reset", Model.etaLabel(50, 20, 1, 3600) === "> 1h")
    check("eta zero rate", Model.etaLabel(50, 20, 0, 3600) === "> 1h")
    check("runway level normal", Model.runwayLevel(74, 7200, 3600, 20, 10) === "normal")
    check("runway level short", Model.runwayLevel(74, 1800, 3600, 20, 10) === "warn")
    check("runway level warn", Model.runwayLevel(15, 7200, 3600, 20, 10) === "warn")
    check("runway level crit", Model.runwayLevel(5, 1800, 3600, 20, 10) === "crit")
    check("runway level empty", Model.runwayLevel(0, 0, 3600, 20, 10) === "crit")
    check("runway level none", Model.runwayLevel(74, null, 3600, 20, 10) === "none")
    check("runway level flat", Model.runwayLevel(74, null, 3600, 20, 10, "flat") === "normal")
    check("burn idle", Model.burnText(0, "rolling") === "0.0%/h")
    check("runway idle label", Model.runwayLabel(null, 3600, 74, "flat") === "\u2265 1h")
    check("runway idle empty", Model.runwayLabel(null, 3600, 0, "flat") === "0m")
    check("eta idle", Model.etaLabel(74, 20, 0, 3600, "flat") === "> 1h")
    check("eta idle now", Model.etaLabel(15, 20, 0, 3600, "flat") === "now")

    var config = { layout: { right: [{ id: "jihonghe.opencode-dash", barWindows: "all" }, { id: "omarchy.clock" }] } }
    var saved = Model.savedBarSettings(config, "jihonghe.opencode-dash", { section: "right", index: 0 })
    check("saved settings", saved && saved.barWindows === "all")
    check("saved by id", Model.savedBarSettings(config, "jihonghe.opencode-dash", null).barWindows === "all")

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
