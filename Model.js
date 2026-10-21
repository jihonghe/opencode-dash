// Pure display and settings helpers for OpenCode Quota.
//
// Kept free of QML imports so the same file can be exercised by the QML
// runtime (tests/model-test.qml) and by ordinary JavaScript tooling.

var WINDOW_ORDER = ["rolling", "weekly", "monthly"]
var WINDOW_LABELS = { rolling: "5h", weekly: "7d", monthly: "M" }
var PLAN_OPTIONS = ["OpenCode Go", "OpenCode Go Plus"]
var PERIOD_LABELS = { rolling: "Rolling", weekly: "Weekly", monthly: "Monthly" }
var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

var DEFAULTS = {
  refreshIntervalSec: 300,
  barWindows: "worst",
  percentMode: "remaining",
  warnRemaining: 20,
  critRemaining: 10,
  notifyEnabled: true,
  notifyReset: false,
  planLabel: "OpenCode Go"
}

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, value))
}

function numberOrDefault(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function boolValue(value, fallback) {
  if (value === undefined || value === null) return fallback
  if (typeof value === "string") return value.toLowerCase() === "true"
  return !!value
}

function settingsWithDefaults(settings) {
  var out = {}
  for (var key in DEFAULTS) out[key] = DEFAULTS[key]
  if (settings) {
    for (var saved in settings) {
      if (settings[saved] !== undefined && settings[saved] !== null) out[saved] = settings[saved]
    }
  }
  out.refreshIntervalSec = clamp(numberOrDefault(out.refreshIntervalSec, 300), 60, 3600)
  out.warnRemaining = clamp(numberOrDefault(out.warnRemaining, 20), 1, 99)
  out.critRemaining = clamp(numberOrDefault(out.critRemaining, 10), 1, 99)
  if (out.critRemaining > out.warnRemaining) out.critRemaining = out.warnRemaining
  if (["worst", "all", "month"].indexOf(out.barWindows) === -1) out.barWindows = "worst"
  if (["remaining", "used"].indexOf(out.percentMode) === -1) out.percentMode = "remaining"
  out.notifyEnabled = boolValue(out.notifyEnabled, true)
  out.notifyReset = boolValue(out.notifyReset, false)
  out.planLabel = PLAN_OPTIONS.indexOf(String(out.planLabel)) !== -1
    ? String(out.planLabel) : "OpenCode Go"
  return out
}

function resetHorizon(name) {
  if (name === "rolling") return 5 * 3600 + 60
  if (name === "weekly") return 7 * 86400 + 60
  if (name === "monthly") return 31 * 86400 + 60
  return 31 * 86400 + 60
}

function planOptions() {
  return PLAN_OPTIONS.slice()
}

function windowLabel(name) {
  return WINDOW_LABELS[name] || name
}

function periodLabel(name) {
  return PERIOD_LABELS[name] || name
}

function isAvailable(window) {
  return !!window && window.available !== false
    && window.percent !== undefined && window.percent !== null
}

function availableNames(windows) {
  var names = []
  if (!windows) return names
  for (var i = 0; i < WINDOW_ORDER.length; i++) {
    if (isAvailable(windows[WINDOW_ORDER[i]])) names.push(WINDOW_ORDER[i])
  }
  return names
}

function worstWindow(windows) {
  var best = null
  var bestRemaining = Infinity
  var names = availableNames(windows)
  for (var i = 0; i < names.length; i++) {
    var name = names[i]
    var remaining = Number(windows[name].remaining)
    if (!isFinite(remaining)) remaining = 100 - Number(windows[name].percent)
    if (remaining < bestRemaining) {
      bestRemaining = remaining
      best = name
    }
  }
  return best
}

function worstRemaining(windows) {
  var name = worstWindow(windows)
  if (!name) return null
  var remaining = Number(windows[name].remaining)
  return isFinite(remaining) ? remaining : 100 - Number(windows[name].percent)
}

function isNoData(report) {
  if (!report) return true
  var state = report.state || "no-data"
  if (state === "no-key" || state === "auth-expired" || state === "no-data" || state === "error") return true
  return availableNames(report.windows).length === 0
}

function percentText(window, mode) {
  var value = mode === "used" ? window.percent : window.remaining
  return String(Math.round(Number(value)))
}

function criticalMark(window, settings) {
  if (!window || window.remaining === undefined || window.remaining === null) return ""
  return Number(window.remaining) <= settings.critRemaining ? "!" : ""
}

function barText(report, settings) {
  var cfg = settingsWithDefaults(settings)
  if (isNoData(report)) return "\u2014"
  var names = availableNames(report.windows)
  if (!names.length) return "\u2014"

  if (cfg.barWindows === "all") {
    var parts = []
    for (var i = 0; i < names.length; i++) {
      var name = names[i]
      parts.push(periodLabel(name) + " " + percentText(report.windows[name], cfg.percentMode)
        + "%" + criticalMark(report.windows[name], cfg))
    }
    return parts.join(" \u00b7 ")
  }

  if (cfg.barWindows === "month" && !isAvailable(report.windows.monthly)) return "\u2014"
  var target = cfg.barWindows === "month" ? "monthly" : worstWindow(report.windows)
  if (!target) return "\u2014"
  var window = report.windows[target]
  return periodLabel(target) + " " + percentText(window, cfg.percentMode) + "%"
    + criticalMark(window, cfg)
}

function barSegments(report, settings) {
  var cfg = settingsWithDefaults(settings)
  function noData() { return [{ text: "\u2014", tone: "none" }] }
  if (isNoData(report)) return noData()
  var names = availableNames(report.windows)
  if (!names.length) return noData()

  function windowSegments(name) {
    var window = report.windows[name]
    var suffix = "%" + (Number(window.remaining) <= cfg.critRemaining ? "!" : "")
    return [
      { text: periodLabel(name) + " ", tone: "none" },
      { text: percentText(window, cfg.percentMode) + suffix, tone: windowLevel(window, cfg) }
    ]
  }

  if (cfg.barWindows === "all") {
    var out = []
    for (var i = 0; i < names.length; i++) {
      if (i > 0) out.push({ text: " \u00b7 ", tone: "none" })
      var parts = windowSegments(names[i])
      for (var j = 0; j < parts.length; j++) out.push(parts[j])
    }
    return out
  }

  if (cfg.barWindows === "month" && !isAvailable(report.windows.monthly)) return noData()
  var target = cfg.barWindows === "month" ? "monthly" : worstWindow(report.windows)
  if (!target) return noData()
  return windowSegments(target)
}

function verticalParts(report, settings) {
  var cfg = settingsWithDefaults(settings)
  if (isNoData(report)) return { label: "\u2014", value: "", tone: "none" }
  var target = worstWindow(report.windows)
  if (!target) return { label: "\u2014", value: "", tone: "none" }
  var window = report.windows[target]
  return {
    label: windowLabel(target),
    value: percentText(window, cfg.percentMode) + "%" + criticalMark(window, cfg),
    tone: windowLevel(window, cfg)
  }
}

function windowLevel(window, settings) {
  if (!isAvailable(window)) return "none"
  var cfg = settingsWithDefaults(settings)
  var remaining = Number(window.remaining)
  if (remaining <= cfg.critRemaining) return "crit"
  if (remaining <= cfg.warnRemaining) return "warn"
  return "normal"
}

function statusLevel(report, settings) {
  var name = worstWindow(report ? report.windows : null)
  return name ? windowLevel(report.windows[name], settings) : "none"
}

function pad2(value) {
  return value < 10 ? "0" + value : String(value)
}

function fmtDuration(seconds) {
  if (seconds === undefined || seconds === null || !isFinite(Number(seconds))) return "\u2014"
  var total = Math.max(0, Math.round(Number(seconds)))
  if (total < 60) return "<1m"
  var minutes = Math.floor(total / 60)
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  var restMinutes = minutes % 60
  if (hours < 48) return restMinutes ? hours + "h " + restMinutes + "m" : hours + "h"
  var days = Math.floor(hours / 24)
  var restHours = hours % 24
  return restHours ? days + "d " + restHours + "h" : days + "d"
}

function fmtReset(name, iso) {
  if (!iso) return "\u2014"
  var date = new Date(iso)
  if (isNaN(date.getTime())) return "\u2014"
  var clock = pad2(date.getHours()) + ":" + pad2(date.getMinutes())
  if (name === "rolling") return clock
  if (name === "weekly") return WEEKDAYS[date.getDay()] + " " + clock
  return pad2(date.getMonth() + 1) + "-" + pad2(date.getDate()) + " " + clock
}

function fmtUpdated(iso) {
  if (!iso) return "\u2014"
  var date = new Date(iso)
  if (isNaN(date.getTime())) return "\u2014"
  return pad2(date.getHours()) + ":" + pad2(date.getMinutes())
}

function stateMessage(report) {
  if (!report) return "Waiting for the first reading."
  var state = report.state || "no-data"
  if (state === "no-key") return "OpenCode Go credentials not found. Run \"opencode auth login\" and choose OpenCode Go."
  if (state === "auth-expired") return "OpenCode Go credentials expired. Run \"opencode auth login\" again."
  if (state === "no-data") return report.stale ? "API unavailable and no cached reading." : "Waiting for the first reading."
  if (state === "error") return "Could not read quota data."
  if (report.stale) return "Showing the last successful reading. API is currently unavailable."
  return ""
}

function burnText(ratePerHour, windowName) {
  if (ratePerHour === null || ratePerHour === undefined) return ""
  var rate = Number(ratePerHour)
  if (!isFinite(rate) || rate < 0) return ""
  if (windowName === "rolling") return rate.toFixed(1) + "%/h"
  return (rate * 24).toFixed(1) + "%/day"
}

function runwayLabel(seconds, resetInSec, remaining, reason) {
  var rem = remaining === null || remaining === undefined ? null : Number(remaining)
  if (rem !== null && isFinite(rem) && rem <= 0) return "0m"
  var reset = resetInSec === null || resetInSec === undefined ? null : Number(resetInSec)
  if (reason === "flat") {
    if (reset !== null && isFinite(reset) && reset > 0) return "\u2265 " + fmtDuration(reset)
    return "Idle"
  }
  if (seconds === null || seconds === undefined) return ""
  var value = Number(seconds)
  if (!isFinite(value)) return ""
  if (reset !== null && isFinite(reset) && value >= reset - 60) {
    return "\u2265 " + fmtDuration(reset)
  }
  return "~" + fmtDuration(value)
}

function etaLabel(remaining, threshold, ratePerHour, resetInSec, reason) {
  if (remaining === null || remaining === undefined) return ""
  var rem = Number(remaining)
  if (!isFinite(rem)) return ""
  if (rem <= Number(threshold)) return "now"
  var reset = resetInSec === null || resetInSec === undefined ? null : Number(resetInSec)
  var beyondReset = reset !== null && isFinite(reset) && reset > 0
    ? "> " + fmtDuration(reset) : ""
  if (reason === "flat") return beyondReset
  if (ratePerHour === null || ratePerHour === undefined) return ""
  var rate = Number(ratePerHour)
  if (!isFinite(rate) || rate <= 0) return beyondReset
  var seconds = (rem - Number(threshold)) * 3600 / rate
  if (beyondReset !== "" && seconds >= reset - 60) return beyondReset
  return "~" + fmtDuration(seconds)
}

function runwayLevel(remaining, seconds, resetInSec, warn, crit, reason) {
  var rem = remaining === null || remaining === undefined ? null : Number(remaining)
  var sec = seconds === null || seconds === undefined ? null : Number(seconds)
  if (rem !== null && isFinite(rem)) {
    if (rem <= Number(crit)) return "crit"
    if (rem <= Number(warn)) return "warn"
  }
  if (reason === "flat") return rem === null ? "none" : "normal"
  if (sec === null || !isFinite(sec)) return "none"
  if (sec <= 0) return "crit"
  var reset = resetInSec === null || resetInSec === undefined ? null : Number(resetInSec)
  if (reset !== null && isFinite(reset) && sec < reset - 60) return "warn"
  return "normal"
}

function withPending(saved, pending) {
  if (!saved) return null
  var out = {}
  for (var key in saved) out[key] = saved[key]
  for (var name in pending) out[name] = pending[name].value
  return out
}

function mergeSettings(injected, saved) {
  var out = {}
  if (injected) {
    for (var key in injected) out[key] = injected[key]
  }
  if (saved) {
    for (var savedKey in saved) out[savedKey] = saved[savedKey]
  }
  return out
}

function prunePending(saved, pending, now) {
  var out = {}
  for (var key in pending) {
    var entry = pending[key]
    if (saved && JSON.stringify(saved[key]) === JSON.stringify(entry.value)) continue
    if (now - entry.at > 10000) continue
    out[key] = entry
  }
  return out
}

function savedBarSettings(barConfig, id, location) {
  var layout = barConfig && barConfig.layout
  if (!layout) return null
  var entry = null
  if (location) {
    var entries = layout[location.section]
    entry = Array.isArray(entries) ? entries[location.index] : null
    if (!entry || entry.id !== id) return null
  } else {
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var list = layout[sections[s]]
      if (!Array.isArray(list)) continue
      for (var i = 0; i < list.length; i++) {
        if (!list[i] || list[i].id !== id) continue
        if (entry) return null
        entry = list[i]
      }
    }
  }
  if (!entry) return null
  var out = {}
  for (var key in entry) if (key !== "id") out[key] = entry[key]
  return out
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    WINDOW_ORDER: WINDOW_ORDER,
    PLAN_OPTIONS: PLAN_OPTIONS,
    DEFAULTS: DEFAULTS,
    settingsWithDefaults: settingsWithDefaults,
    windowLabel: windowLabel,
    periodLabel: periodLabel,
    planOptions: planOptions,
    resetHorizon: resetHorizon,
    isAvailable: isAvailable,
    availableNames: availableNames,
    worstWindow: worstWindow,
    windowLevel: windowLevel,
    worstRemaining: worstRemaining,
    isNoData: isNoData,
    percentText: percentText,
    barText: barText,
    barSegments: barSegments,
    verticalParts: verticalParts,
    statusLevel: statusLevel,
    fmtDuration: fmtDuration,
    burnText: burnText,
    runwayLabel: runwayLabel,
    etaLabel: etaLabel,
    runwayLevel: runwayLevel,
    fmtReset: fmtReset,
    fmtUpdated: fmtUpdated,
    stateMessage: stateMessage,
    withPending: withPending,
    mergeSettings: mergeSettings,
    prunePending: prunePending,
    savedBarSettings: savedBarSettings
  }
}
