import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Model.js" as Model

// Hover card for the OpenCode Quota bar widget. The bar's shared tooltip is
// plain monochrome text, so this popup renders its own rows and can color the
// percentage itself.
PopupWindow {
  id: root

  property Item anchorItem: null
  property QtObject bar: null
  property var report: null
  property var settings: ({})
  property bool shown: false
  property color foreground: Commons.Color.tooltip.text
  property color okColor: "#9ece6a"
  property color warnColor: "#e8a33d"
  property color critColor: Commons.Color.urgent
  property string fontFamily: Style.font.family
  property real nowMs: Date.now()

  readonly property var cfg: Model.settingsWithDefaults(settings)
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property var windows: report && report.windows ? report.windows : ({})
  readonly property var available: Model.availableNames(windows)
  readonly property bool hasWindows: available.length > 0
  readonly property string stateText: Model.stateMessage(report)
  readonly property var samples: report && report.samples ? report.samples : []
  readonly property bool fresh: {
    if (samples.length === 0) return false
    var time = new Date(samples[samples.length - 1].t).getTime()
    if (!isFinite(time)) return false
    var age = Math.max(0, (nowMs - time) / 1000)
    return age <= Math.max(900, 2 * cfg.refreshIntervalSec)
  }
  readonly property bool showRunway: {
    if (!fresh || !report || !report.runway) return false
    var names = ["rolling", "weekly", "monthly"]
    for (var i = 0; i < names.length; i++) {
      if (hasEstimate(names[i])) return true
    }
    return false
  }

  color: "transparent"
  implicitWidth: Style.space(428)
  implicitHeight: bubble.implicitHeight

  property bool revealed: false
  visible: revealed && anchorItem !== null

  onShownChanged: {
    if (shown) {
      // The popup lives for the whole shell session; refresh now before the
      // first reveal so countdowns do not use the creation-time clock.
      nowMs = Date.now()
      revealTimer.restart()
    } else {
      revealTimer.stop()
      revealed = false
    }
  }

  Timer {
    id: revealTimer
    interval: 350
    repeat: false
    onTriggered: root.revealed = root.shown
  }

  Timer {
    interval: 30000
    running: root.revealed
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  function toneColor(level) {
    if (level === "crit") return critColor
    if (level === "warn") return warnColor
    if (level === "normal") return okColor
    return foreground
  }

  function resetSeconds(name, window) {
    if (!window || !window.resetsAt) return 0
    var reset = new Date(window.resetsAt).getTime()
    if (isNaN(reset)) return 0
    return Math.min(Model.resetHorizon(name),
      Math.max(0, Math.round((reset - nowMs) / 1000)))
  }

  function windowFor(name) {
    return root.windows[name] || ({})
  }

  function entryFor(name) {
    return report && report.runway ? (report.runway[name] || ({})) : ({})
  }

  function avgLabel(name) {
    var entry = entryFor(name)
    var window = windowFor(name)
    return Model.runwayLabel(entry.seconds, resetSeconds(name, window),
      window.remaining, entry.reason)
  }

  function activeLabel(name) {
    var entry = entryFor(name)
    var window = windowFor(name)
    return Model.runwayLabel(entry.activeSeconds, resetSeconds(name, window),
      window.remaining, entry.activeReason)
  }

  function avgRateText(name) {
    return Model.burnText(entryFor(name).ratePerHour, name)
  }

  function activeRateText(name) {
    return Model.burnText(entryFor(name).activeRatePerHour, name)
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
      windowFor(name).remaining, entry.seconds, resetSeconds(name, windowFor(name)),
      root.cfg.warnRemaining, root.cfg.critRemaining, entry.reason))
  }

  function activeColor(name) {
    var entry = entryFor(name)
    return colorForLevel(Model.runwayLevel(
      windowFor(name).remaining, entry.activeSeconds, resetSeconds(name, windowFor(name)),
      root.cfg.warnRemaining, root.cfg.critRemaining, entry.activeReason))
  }

  function hasEstimate(name) {
    return avgLabel(name) !== "" || activeLabel(name) !== ""
  }

  readonly property string sampleSpan: {
    if (!report || !report.samples || report.samples.length === 0) return ""
    var first = new Date(report.samples[0].t).getTime()
    var last = new Date(report.samples[report.samples.length - 1].t).getTime()
    if (!isFinite(first) || !isFinite(last)) return ""
    return Model.fmtDuration(Math.max(0, (last - first) / 1000))
  }

  readonly property string footerText: {
    var span = root.sampleSpan
    if (span !== "") {
      return "Official API \u00b7 estimates from " + span + " of samples"
        + (root.report && root.report.stale ? " \u00b7 cached" : "")
    }
    return "Official API \u00b7 all clients"
  }

  anchor {
    id: tipAnchor
    window: root.anchorItem && root.anchorItem.QsWindow ? root.anchorItem.QsWindow.window : null
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1
    onAnchoring: root.reposition()
  }

  function reposition() {
    if (!anchorItem || !tipAnchor.window) return
    var position = bar ? String(bar.position) : "top"
    var popupWidth = implicitWidth
    var popupHeight = implicitHeight
    var localX = anchorItem.width / 2 - popupWidth / 2
    var localY = anchorItem.height + 6

    if (position === "bottom") {
      localY = -popupHeight - 6
    } else if (position === "left") {
      localX = anchorItem.width + 6
      localY = anchorItem.height / 2 - popupHeight / 2
    } else if (position === "right") {
      localX = -popupWidth - 6
      localY = anchorItem.height / 2 - popupHeight / 2
    }

    var point = tipAnchor.window.contentItem.mapFromItem(anchorItem, localX, localY)
    tipAnchor.rect.x = Math.round(point.x)
    tipAnchor.rect.y = Math.round(point.y)
  }

  onImplicitHeightChanged: if (revealed) Qt.callLater(reposition)
  onRevealedChanged: {
    if (revealed) {
      nowMs = Date.now()
      Qt.callLater(reposition)
    }
  }

  Connections {
    target: root.bar
    function onPositionChanged() { if (root.revealed) Qt.callLater(root.reposition) }
  }

  BorderSurface {
    id: bubble
    width: root.implicitWidth
    implicitHeight: content.implicitHeight + Style.spacing.popupPadding * 2
    color: Commons.Color.tooltip.background
    borderSpec: Border.surfaceSpec("tooltip", "border", Commons.Color.tooltip.border, 1)
    radius: Style.cornerRadius

    Column {
      id: content
      x: Style.spacing.popupPadding
      y: Style.spacing.popupPadding
      width: bubble.width - Style.spacing.popupPadding * 2
      spacing: Style.space(5)

      Item {
        width: parent.width
        height: Math.max(title.implicitHeight, updated.implicitHeight)

        Text {
          id: title
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - (updated.visible ? updated.implicitWidth + Style.space(8) : 0)
          text: root.cfg.planLabel + " \u00b7 "
            + (root.cfg.percentMode === "used" ? "used" : "remaining")
          elide: Text.ElideRight
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          textFormat: Text.PlainText
        }

        Text {
          id: updated
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.report ? "updated " + Model.fmtUpdated(root.report.updatedAt) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }
      }

      Text {
        visible: root.stateText !== ""
        width: parent.width
        text: root.stateText
        color: root.report && root.report.stale ? root.warnColor : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
      }

      Rectangle {
        visible: root.hasWindows
        width: parent.width
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
      }

      Column {
        visible: root.hasWindows
        width: parent.width
        spacing: Style.space(3)

        Row {
          width: parent.width
          spacing: Style.space(10)

          Text {
            width: Style.space(56)
            text: "Period"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            textFormat: Text.PlainText
          }
          Text {
            width: Style.space(48)
            text: root.cfg.percentMode === "used" ? "Used" : "Left"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
          }
          Text {
            width: parent.width - Style.space(56) - Style.space(48)
              - (root.showRunway ? Style.space(210) + 3 * Style.space(10) : 2 * Style.space(10))
            text: "Resets in"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
          }
          Text {
            visible: root.showRunway
            width: Style.space(210)
            text: "Runway"
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
            width: parent.width
            spacing: Style.space(10)

            readonly property var win: root.windows[modelData] ? root.windows[modelData] : ({})
            readonly property bool avail: Model.isAvailable(win)
            readonly property string level: Model.windowLevel(win, root.cfg)

            Text {
              width: Style.space(56)
              text: Model.periodLabel(modelData)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
            Text {
              width: Style.space(48)
              text: parent.avail
                ? Model.percentText(parent.win, root.cfg.percentMode) + "%"
                  + (Number(parent.win.remaining) <= root.cfg.critRemaining ? "!" : "")
                : "\u2014"
              color: root.toneColor(parent.level)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
            }
            Text {
              width: parent.width - Style.space(56) - Style.space(48)
                - (root.showRunway ? Style.space(210) + 3 * Style.space(10) : 2 * Style.space(10))
              text: parent.avail
                ? Model.fmtDuration(root.resetSeconds(modelData, parent.win))
                : "no data"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }
            Column {
              visible: root.showRunway
              width: Style.space(210)

              Row {
                width: parent.width
                spacing: Style.space(3)
                visible: root.avgLabel(modelData) !== ""

                Text {
                  width: Style.space(42)
                  text: "Avg"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  textFormat: Text.PlainText
                }
                Text {
                  width: Style.space(74)
                  text: root.avgRateText(modelData)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignRight
                  textFormat: Text.PlainText
                }
                Text {
                  width: parent.width - Style.space(42) - Style.space(74) - 2 * Style.space(3)
                  text: "\u2192 " + root.avgLabel(modelData)
                  color: root.avgColor(modelData)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  horizontalAlignment: Text.AlignRight
                  textFormat: Text.PlainText
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(3)
                visible: root.activeLabel(modelData) !== ""

                Text {
                  width: Style.space(42)
                  text: "Active"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  textFormat: Text.PlainText
                }
                Text {
                  width: Style.space(74)
                  text: root.activeRateText(modelData)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignRight
                  textFormat: Text.PlainText
                }
                Text {
                  width: parent.width - Style.space(42) - Style.space(74) - 2 * Style.space(3)
                  text: "\u2192 " + root.activeLabel(modelData)
                  color: root.activeColor(modelData)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  horizontalAlignment: Text.AlignRight
                  textFormat: Text.PlainText
                }
              }
            }
          }
        }
      }

      Text {
        visible: root.report && root.report.stale
        text: "cached at " + Model.fmtUpdated(root.report ? root.report.updatedAt : "")
          + " (API unavailable)"
        color: root.warnColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }

      Text {
        text: root.footerText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
    }
  }
}
