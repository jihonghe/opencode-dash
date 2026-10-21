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
  readonly property real periodWidth: Style.space(68)
  readonly property real burnWidth: Style.space(60)
  readonly property real etaWidth: Style.space(60)
  readonly property real runwayWidth: Math.max(Style.space(140),
    width - periodWidth - burnWidth - etaWidth * 2 - columnGap * 4)
  readonly property real latestSampleAge: {
    if (samples.length === 0) return -1
    var time = new Date(samples[samples.length - 1].t).getTime()
    if (!isFinite(time)) return -1
    return Math.max(0, (nowMs - time) / 1000)
  }
  readonly property bool fresh: latestSampleAge >= 0
    && latestSampleAge <= Math.max(900, 2 * cfg.refreshIntervalSec)
  readonly property bool hasAnyRunway: {
    var names = ["rolling", "weekly", "monthly"]
    for (var i = 0; i < names.length; i++) {
      var entry = runway[names[i]]
      if (entry && ((entry.seconds !== null && entry.seconds !== undefined)
          || entry.reason === "flat")) return true
    }
    return false
  }
  readonly property bool hasRows: hasAnyRunway && fresh
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

  function resetSeconds(name, window) {
    if (!window || !window.resetsAt) return 0
    var reset = new Date(window.resetsAt).getTime()
    if (isNaN(reset)) return 0
    return Math.min(Model.resetHorizon(name),
      Math.max(0, Math.round((reset - nowMs) / 1000)))
  }

  function rate(name) {
    var entry = runway[name]
    if (!entry || entry.ratePerHour === undefined || entry.ratePerHour === null) return null
    return Number(entry.ratePerHour)
  }

  function runwaySeconds(name) {
    var entry = runway[name]
    if (!entry || entry.seconds === undefined || entry.seconds === null) return null
    return Number(entry.seconds)
  }

  function burnFor(name) {
    return Model.burnText(rate(name), name)
  }

  function runwayFor(name) {
    var window = windows[name] || ({})
    var entry = runway[name] || ({})
    return Model.runwayLabel(runwaySeconds(name), resetSeconds(name, window), window.remaining, entry.reason)
  }

  function etaFor(name, threshold) {
    var window = windows[name] || ({})
    var entry = runway[name] || ({})
    return Model.etaLabel(window.remaining, threshold, rate(name), resetSeconds(name, window), entry.reason)
  }

  function runwayColor(name) {
    var window = windows[name] || ({})
    var entry = runway[name] || ({})
    var level = Model.runwayLevel(window.remaining, runwaySeconds(name),
      resetSeconds(name, window), cfg.warnRemaining, cfg.critRemaining, entry.reason)
    if (level === "crit") return critColor
    if (level === "warn") return warnColor
    if (level === "normal") return okColor
    return dim
  }

  function etaColor(name, threshold, level) {
    if (etaFor(name, threshold) !== "now") return dim
    return level === "crit" ? critColor : warnColor
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
      width: root.burnWidth
      text: "Burn"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
    }
    Text {
      width: root.runwayWidth
      text: "Runway"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
    }
    Text {
      width: root.etaWidth
      text: "Warn " + root.cfg.warnRemaining + "%"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
    }
    Text {
      width: root.etaWidth
      text: "Crit " + root.cfg.critRemaining + "%"
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

    delegate: Column {
      required property string modelData
      required property int index
      width: root.width
      spacing: Style.space(2)

      Row {
        width: parent.width
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
          width: root.burnWidth
          text: root.burnFor(modelData)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
        }
        Text {
          width: root.runwayWidth
          text: root.runwayFor(modelData)
          color: root.runwayColor(modelData)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }
        Text {
          width: root.etaWidth
          text: root.etaFor(modelData, root.cfg.warnRemaining)
          color: root.etaColor(modelData, root.cfg.warnRemaining, "warn")
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
        }
        Text {
          width: root.etaWidth
          text: root.etaFor(modelData, root.cfg.critRemaining)
          color: root.etaColor(modelData, root.cfg.critRemaining, "crit")
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
        }
      }

      Rectangle {
        visible: index < 2
        width: parent.width
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
      }
    }
  }

  Text {
    width: parent.width
    text: "\u2265 lasts until reset  \u00b7  > after reset"
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
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
