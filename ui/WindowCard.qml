import QtQuick
import qs.Commons
import qs.Commons as Commons
import "../Model.js" as Model

Item {
  id: root

  property string name: "rolling"
  property var window: ({})
  property var settings: ({})
  property var runwaySeconds: null
  property real nowMs: Date.now()

  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color warnColor: "#e8a33d"
  property color critColor: Commons.Color.urgent
  property color okColor: "#9ece6a"
  property string fontFamily: Style.font.family

  readonly property bool available: !!(window && window.available !== false
    && window.percent !== undefined && window.percent !== null)
  readonly property real remaining: available ? Number(window.remaining) : 0
  readonly property int warn: Number(settings && settings.warnRemaining !== undefined
    ? settings.warnRemaining : 20)
  readonly property int crit: Number(settings && settings.critRemaining !== undefined
    ? settings.critRemaining : 10)
  readonly property string level: !available ? "none"
    : (remaining <= crit ? "crit" : (remaining <= warn ? "warn" : "normal"))
  readonly property color ringColor: level === "crit" ? critColor
    : (level === "warn" ? warnColor : okColor)
  readonly property color trackColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.10)
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string percent: available
    ? Model.percentText(window, settings ? settings.percentMode : "remaining") + "%" : "\u2014"
  readonly property int resetInSec: {
    if (!window || !window.resetsAt) return 0
    var reset = new Date(window.resetsAt).getTime()
    if (isNaN(reset)) return 0
    return Math.max(0, Math.round((reset - nowMs) / 1000))
  }

  implicitHeight: Style.space(72)
  width: parent ? parent.width : implicitWidth

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.045)
    border.width: 1
    border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
  }

  Row {
    anchors.fill: parent
    anchors.margins: Style.space(10)
    spacing: Style.space(12)

    Item {
      width: Style.space(52)
      height: width
      anchors.verticalCenter: parent.verticalCenter

      Canvas {
        id: ring
        anchors.fill: parent

        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          var center = width / 2
          var radius = Math.min(width, height) / 2 - Style.space(2)
          ctx.lineWidth = Math.max(2, Style.space(3))
          ctx.lineCap = "round"
          ctx.strokeStyle = root.trackColor
          ctx.beginPath()
          ctx.arc(center, center, radius, 0, Math.PI * 2)
          ctx.stroke()
          if (!root.available) return
          var fraction = Math.max(0, Math.min(1, root.remaining / 100))
          if (fraction <= 0) return
          ctx.strokeStyle = root.ringColor
          ctx.beginPath()
          ctx.arc(center, center, radius, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * fraction)
          ctx.stroke()
        }
      }

      Text {
        anchors.centerIn: parent
        text: root.percent
        color: root.level === "crit" ? root.critColor
          : (root.level === "warn" ? root.warnColor
            : (root.level === "normal" ? root.okColor : root.foreground))
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        textFormat: Text.PlainText
      }

      Connections {
        target: root
        function onAvailableChanged() { ring.requestPaint() }
        function onRemainingChanged() { ring.requestPaint() }
        function onRingColorChanged() { ring.requestPaint() }
        function onTrackColorChanged() { ring.requestPaint() }
      }
    }

    Column {
      width: parent.width - Style.space(52) - Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(6)

        Text {
          text: Model.windowLabel(root.name) + " window"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          textFormat: Text.PlainText
        }

        Text {
          visible: !root.available
          text: "unavailable"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }
      }

      Text {
        width: parent.width
        text: root.available
          ? "Resets " + Model.fmtReset(root.name, root.window.resetsAt)
            + "  (in ~" + Model.fmtDuration(root.resetInSec) + ")"
          : "No usage data for this window"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }

      Text {
        width: parent.width
        text: "Runway  " + (root.runwaySeconds !== null && root.runwaySeconds !== undefined
          ? "~" + Model.fmtDuration(root.runwaySeconds) : "\u2014")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
    }
  }
}
