// Pure display and settings helpers for OpenCode Quota.
//
// Kept free of QML imports so the same file can be exercised by the QML
// runtime (tests/model-test.qml) and by ordinary JavaScript tooling.

var WINDOW_ORDER = ["rolling", "weekly", "monthly"]
var WINDOW_LABELS = { rolling: "5h", weekly: "7d", monthly: "M" }
var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

var DEFAULTS = {
  refreshIntervalSec: 300,
  barWindows: "worst",
  percentMode: "remaining",
  warnRemaining: 20,
  critRemaining: 10,
  notifyEnabled: true,
  notifyReset: false,
  showModelDetail: true,
  renewOverride: "",
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
  out.showModelDetail = boolValue(out.showModelDetail, true)
  out.planLabel = String(out.planLabel || "OpenCode Go")
  out.renewOverride = String(out.renewOverride || "")
  return out
}

function windowLabel(name) {
  return WINDOW_LABELS[name] || name
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
      parts.push(windowLabel(name) + " " + percentText(report.windows[name], cfg.percentMode)
        + "%" + criticalMark(report.windows[name], cfg))
    }
    return parts.join(" \u00b7 ")
  }

  if (cfg.barWindows === "month" && !isAvailable(report.windows.monthly)) return "\u2014"
  var target = cfg.barWindows === "month" ? "monthly" : worstWindow(report.windows)
  if (!target) return "\u2014"
  var window = report.windows[target]
  return windowLabel(target) + " " + percentText(window, cfg.percentMode) + "%"
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
      { text: windowLabel(name) + " ", tone: "none" },
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

function fmtCompact(value) {
  var number = Number(value) || 0
  var absolute = Math.abs(number)
  if (absolute >= 1e9) return (number / 1e9).toFixed(1) + "B"
  if (absolute >= 1e6) return (number / 1e6).toFixed(1) + "M"
  if (absolute >= 1e3) return (number / 1e3).toFixed(1) + "K"
  return String(Math.round(number))
}

function fmtCost(value) {
  var cost = Number(value) || 0
  if (cost === 0) return "$0"
  return "$" + cost.toFixed(2)
}

var PAD = "\u00a0"
var TOOLTIP_WIDTH = 47

function padEnd(value, width) {
  var text = String(value)
  while (text.length < width) text += PAD
  return text
}

function padStart(value, width) {
  var text = String(value)
  while (text.length < width) text = PAD + text
  return text
}

function truncate(value, width) {
  var text = String(value)
  if (text.length <= width) return text
  return text.slice(0, Math.max(1, width - 1)) + "\u2026"
}

function repeatChar(character, count) {
  var out = ""
  for (var i = 0; i < count; i++) out += character
  return out
}

function tooltipBlock(lines) {
  var width = 0
  for (var i = 0; i < lines.length; i++) width = Math.max(width, lines[i].length)
  var out = []
  for (var j = 0; j < lines.length; j++) out.push(padEnd(lines[j], width))
  return out.join("\n")
}

function statusDot(window, settings) {
  if (!window || window.remaining === undefined || window.remaining === null) return "\u2014"
  var remaining = Number(window.remaining)
  if (remaining <= settings.critRemaining) return "\u{1F534}"
  if (remaining <= settings.warnRemaining) return "\u{1F7E1}"
  return "\u{1F7E2}"
}

function tooltip(report, settings, nowMs) {
  var cfg = settingsWithDefaults(settings)
  if (!report) return "OpenCode Quota"
  var state = report.state || "no-data"
  var label = String(cfg.planLabel || "OpenCode Go")
  var title = truncate(label, TOOLTIP_WIDTH)
  var separator = repeatChar("-", TOOLTIP_WIDTH)

  if (state === "no-key") {
    return tooltipBlock([
      title,
      separator,
      "Not signed in to OpenCode Go.",
      "Run OpenCode and sign in."
    ])
  }
  if (state === "auth-expired") {
    return tooltipBlock([
      title,
      separator,
      "Sign-in expired.",
      "Run OpenCode to refresh credentials."
    ])
  }
  if (state === "no-data" || state === "error") {
    var message = state === "error"
      ? "Could not read quota data."
      : (report.stale ? "API unavailable and no cached reading." : "Waiting for the first reading.")
    return tooltipBlock([title, separator, message])
  }

  var modeLabel = cfg.percentMode === "used" ? "used" : "remaining"
  title = truncate(label + " - " + modeLabel + (report.stale ? " (cached)" : ""), TOOLTIP_WIDTH)

  var leftHeader = cfg.percentMode === "used" ? "Used" : "Left"
  var header = padEnd("Win", 3) + "  " + padEnd("St", 2) + "  "
    + padStart(leftHeader, 5) + "  " + padStart("Resets in", 9) + "  "
    + padStart("At", 11) + "  " + padStart("Runway", 7)
  var lines = [title, separator, padEnd(header, TOOLTIP_WIDTH)]

  var names = availableNames(report.windows)
  for (var i = 0; i < names.length; i++) {
    var name = names[i]
    var window = report.windows[name]
    var resetSeconds = window.resetInSec
    if (window.resetsAt) {
      var resetTime = new Date(window.resetsAt).getTime()
      if (isFinite(resetTime)) {
        resetSeconds = Math.max(0, Math.round((resetTime - (nowMs || Date.now())) / 1000))
      }
    }
    var runway = report.runway && report.runway[name] ? report.runway[name].seconds : null
    var runwayText = runway !== null && runway !== undefined ? fmtDuration(runway) : "\u2014"
    var row = padEnd(windowLabel(name), 3) + "  " + padEnd(statusDot(window, cfg), 2)
      + "  " + padStart(percentText(window, cfg.percentMode) + "%", 5)
      + "  " + padStart(fmtDuration(resetSeconds), 9)
      + "  " + padStart(fmtReset(name, window.resetsAt), 11)
      + "  " + padStart(runwayText, 7)
    lines.push(padEnd(row, TOOLTIP_WIDTH))
  }

  if (cfg.showModelDetail && report.models && report.models.length) {
    lines.push(separator)
    lines.push(padEnd("Local usage - this cycle", TOOLTIP_WIDTH))
    lines.push(padEnd(
      padEnd("Model", 26) + "  " + padStart("Cost", 5) + "  "
        + padStart("Msgs", 6) + "  " + padEnd("Free", 4),
      TOOLTIP_WIDTH
    ))
    var limit = Math.min(report.models.length, 3)
    for (var m = 0; m < limit; m++) {
      var model = report.models[m]
      var modelName = truncate(String(model.id || "unknown"), 26)
      lines.push(padEnd(
        padEnd(modelName, 26) + "  " + padStart(fmtCost(model.cost), 5) + "  "
          + padStart(String(model.messages), 6) + "  " + padEnd(model.free ? "yes" : "-", 4),
        TOOLTIP_WIDTH
      ))
    }
    if (report.models.length > limit) {
      lines.push(padEnd("+" + (report.models.length - limit) + " more models", TOOLTIP_WIDTH))
    }
  }

  lines.push(separator)
  lines.push(padEnd(
    report.stale
      ? "cached at " + fmtUpdated(report.updatedAt) + " (API unavailable)"
      : "updated " + fmtUpdated(report.updatedAt),
    TOOLTIP_WIDTH
  ))
  return tooltipBlock(lines)
}

function stateMessage(report) {
  if (!report) return "Waiting for the first reading."
  var state = report.state || "no-data"
  if (state === "no-key") return "OpenCode Go credentials not found. Run OpenCode and sign in."
  if (state === "auth-expired") return "OpenCode Go credentials expired. Run OpenCode to refresh them."
  if (state === "no-data") return report.stale ? "API unavailable and no cached reading." : "Waiting for the first reading."
  if (state === "error") return "Could not read quota data."
  if (report.stale) return "Showing the last successful reading. API is currently unavailable."
  return ""
}

function trendDaily(daily, mode, nowMs) {
  var rows = (daily || []).slice().sort(function (a, b) {
    return a.date < b.date ? -1 : (a.date > b.date ? 1 : 0)
  })
  if (mode !== "7d") return rows
  var now = new Date(nowMs || Date.now())
  var cutoff = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6)
  return rows.filter(function (row) {
    var parts = String(row.date || "").split("-")
    if (parts.length !== 3) return false
    var date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
    return date >= cutoff
  })
}

function trendSamples(samples, mode, nowMs) {
  var rows = (samples || []).slice()
  if (mode !== "7d") return rows
  var cutoff = (nowMs || Date.now()) - 7 * 24 * 3600 * 1000
  return rows.filter(function (sample) {
    var time = new Date(sample.t).getTime()
    return isFinite(time) && time >= cutoff
  })
}

// ---------------------------------------------------------------- settings
// Adapted from crmne/omastats (MIT) so panel edits and Setup > Plugins edit
// the same inline shell.json entry without the shell re-injecting stale values.

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
    DEFAULTS: DEFAULTS,
    settingsWithDefaults: settingsWithDefaults,
    windowLabel: windowLabel,
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
    fmtReset: fmtReset,
    fmtUpdated: fmtUpdated,
    fmtCompact: fmtCompact,
    fmtCost: fmtCost,
    tooltip: tooltip,
    statusDot: statusDot,
    stateMessage: stateMessage,
    trendDaily: trendDaily,
    trendSamples: trendSamples,
    withPending: withPending,
    mergeSettings: mergeSettings,
    prunePending: prunePending,
    savedBarSettings: savedBarSettings
  }
}
