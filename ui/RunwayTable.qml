import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Model.js" as Model

Column {
  id: root

  property var report: null
  property var settings: ({})
  property real nowMs: Date.now()
  property color foreground: Commons.Color.foreground
  property color warnColor: "#e8a33d"
  property color critColor: Commons.Color.urgent
  property color okColor: "#9ece6a"
  property string fontFamily: Style.font.family

  readonly property var cfg: Model.settingsWithDefaults(settings)
  readonly property var windows: report && report.windows ? report.windows : ({})
  readonly property var runway: report && report.runway ? report.runway : ({})
  readonly property var samples: report && report.samples ? report.samples : []
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property real columnGap: Style.space(10)
  readonly property real periodWidth: Style.space(64)
  readonly property real rateWidth: Style.space(110)
  readonly property real lastsWidth: Math.max(Style.space(110),
    width - periodWidth - rateWidth - columnGap * 2)
  readonly property real latestSampleAge: {
    if (samples.length === 0) return -1
    var time = new Date(samples[samples.length - 1].t).getTime()
    if (!isFinite(time)) return -1
    return Math.max(0, (nowMs - time) / 1000)
  }
  readonly property bool fresh: latestSampleAge >= 0
    && latestSampleAge <= Math.max(900, 2 * cfg.refreshIntervalSec)
  readonly property bool hasRows: hasEstimate() && fresh
  readonly property bool cached: report && report.stale
  readonly property string spanText: {
    if (samples.length === 0) return ""
    var first = new Date(samples[0].t).getTime()
    var last = new Date(samples[samples.length - 1].t).getTime()
    if (!isFinite(first) || !isFinite(last)) return ""
    return Model.fmtDuration(Math.max(0, (last - first) / 1000))
  }
  readonly property string footerText: "Based on official API samples \u00b7 " + spanText
    + " \u00b7 " + samples.length + " points" + (cached ? " \u00b7 cached" : "")

  visible: hasRows
  width: parent ? parent.width : implicitWidth
  spacing: Style.space(4)

  function windowFor(name) {
    return windows[name] || ({})
  }

  function entryFor(name) {
    return runway[name] || ({})
  }

  function resetSeconds(name) {
    var window = windowFor(name)
    if (!window.resetsAt) return 0
    var reset = new Date(window.resetsAt).getTime()
    if (isNaN(reset)) return 0
    return Math.min(Model.resetHorizon(name),
      Math.max(0, Math.round((reset - nowMs) / 1000)))
  }

  function avgLabel(name) {
    var entry = entryFor(name)
    return Model.runwayLabel(entry.seconds, resetSeconds(name),
      windowFor(name).remaining, entry.reason)
  }

  function avgRateText(name) {
    return Model.burnText(entryFor(name).ratePerHour, name)
  }

  function colorForLevel(level) {
    if (level === "crit") return critColor
    if (level === "warn") return warnColor
    if (level === "normal") return okColor
    return dim
  }

  function avgColor(name) {
    var entry = entryFor(name)
    return colorForLevel(Model.runwayLevel(
      windowFor(name).remaining, entry.seconds, resetSeconds(name),
      cfg.warnRemaining, cfg.critRemaining, entry.reason))
  }

  function hasEstimate() {
    var names = ["rolling", "weekly", "monthly"]
    for (var i = 0; i < names.length; i++) {
      if (avgLabel(names[i]) !== "") return true
    }
    return false
  }

  PanelSectionHeader {
    text: "Runway"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Row {
    width: parent.width
    spacing: root.columnGap

    Text {
      width: root.periodWidth
      text: "Period"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      textFormat: Text.PlainText
    }
    Text {
      width: root.rateWidth
      text: "Avg pace"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
    }
    Text {
      width: root.lastsWidth
      text: "Lasts"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
    }
  }

  Repeater {
    model: ["rolling", "weekly", "monthly"]

    delegate: Row {
      required property string modelData
      width: root.width
      spacing: root.columnGap

      Text {
        width: root.periodWidth
        text: Model.periodLabel(modelData)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
      }

      Text {
        width: root.rateWidth
        text: root.avgRateText(modelData)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
      }

      Text {
        width: root.lastsWidth
        text: root.avgLabel(modelData)
        color: root.avgColor(modelData)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
      }
    }
  }

  Text {
    width: parent.width
    text: "Avg includes idle  \u00b7  \u2265 lasts until reset  \u00b7  ~ runs out earlier"
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
  }

  Text {
    width: parent.width
    text: root.footerText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
  }
}
