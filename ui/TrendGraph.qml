import QtQuick
import qs.Commons
import qs.Commons as Commons
import "../Model.js" as Model

Item {
  id: root

  property var daily: []
  property var samples: []
  property string mode: "7d"
  property real nowMs: Date.now()
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family

  readonly property var rows: Model.trendDaily(daily, mode, nowMs)
  readonly property var series: {
    var filtered = Model.trendSamples(samples, mode, nowMs)
    var values = []
    for (var i = 0; i < filtered.length; i++) {
      var value = filtered[i].monthly
      if (value !== undefined && value !== null) values.push(filtered[i])
    }
    return values
  }
  readonly property bool hasBars: rows.length > 0
  readonly property bool hasLine: series.length >= 2

  implicitHeight: Style.space(132)
  width: parent ? parent.width : implicitWidth

  function css(color, alpha) {
    return "rgba(" + Math.round(color.r * 255) + ","
      + Math.round(color.g * 255) + ","
      + Math.round(color.b * 255) + ","
      + alpha + ")"
  }

  Canvas {
    id: graph
    anchors.fill: parent

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      var padLeft = Style.space(4)
      var padRight = Style.space(4)
      var padTop = Style.space(18)
      var padBottom = Style.space(18)
      var plotWidth = width - padLeft - padRight
      var plotHeight = height - padTop - padBottom
      if (plotWidth <= 0 || plotHeight <= 0) return

      ctx.lineWidth = 1
      ctx.strokeStyle = root.css(root.foreground, 0.10)
      ctx.beginPath()
      ctx.moveTo(padLeft, padTop + plotHeight / 2)
      ctx.lineTo(padLeft + plotWidth, padTop + plotHeight / 2)
      ctx.stroke()

      var maximum = 0
      for (var i = 0; i < root.rows.length; i++) maximum = Math.max(maximum, Number(root.rows[i].cost) || 0)
      if (maximum <= 0) maximum = 1

      if (root.rows.length > 0) {
        var slot = plotWidth / Math.max(root.rows.length, 1)
        var barWidth = Math.max(2, Math.min(Style.space(18), slot * 0.55))
        for (var b = 0; b < root.rows.length; b++) {
          var cost = Number(root.rows[b].cost) || 0
          var barHeight = Math.max(cost > 0 ? 2 : 0, (cost / maximum) * plotHeight)
          var x = padLeft + b * slot + (slot - barWidth) / 2
          ctx.fillStyle = root.css(root.accent, 0.55)
          ctx.fillRect(x, padTop + plotHeight - barHeight, barWidth, barHeight)
        }
      }

      if (root.series.length >= 2) {
        var values = []
        for (var s = 0; s < root.series.length; s++) values.push(Number(root.series[s].monthly))
        var minimum = Math.min.apply(null, values)
        var highest = Math.max.apply(null, values)
        if (highest - minimum < 8) {
          var middle = (highest + minimum) / 2
          minimum = Math.max(0, middle - 4)
          highest = Math.min(100, middle + 4)
        }
        if (highest <= minimum) highest = minimum + 1

        var firstTime = new Date(root.series[0].t).getTime()
        var lastTime = new Date(root.series[root.series.length - 1].t).getTime()
        var span = lastTime - firstTime
        if (span > 0) {
          ctx.lineWidth = Math.max(1.5, Style.space(2))
          ctx.lineCap = "round"
          ctx.strokeStyle = root.css(root.foreground, 0.9)
          ctx.beginPath()
          for (var p = 0; p < root.series.length; p++) {
            var time = new Date(root.series[p].t).getTime()
            var px = padLeft + ((time - firstTime) / span) * plotWidth
            var value = Number(root.series[p].monthly)
            var py = padTop + (1 - (value - minimum) / (highest - minimum)) * plotHeight
            if (p === 0) ctx.moveTo(px, py)
            else ctx.lineTo(px, py)
          }
          ctx.stroke()
        }
      }

      ctx.textBaseline = "top"
      ctx.font = Style.font.caption + "px '" + root.fontFamily + "'"
      ctx.fillStyle = root.css(root.foreground, 0.55)
      ctx.fillText("local cost", padLeft, Style.space(3))
      var costLabel = "$" + maximum.toFixed(2)
      ctx.fillText(costLabel, padLeft + plotWidth - ctx.measureText(costLabel).width, Style.space(3))

      if (root.rows.length > 0) {
        var firstDate = String(root.rows[0].date || "")
        var lastDate = String(root.rows[root.rows.length - 1].date || "")
        ctx.fillStyle = root.css(root.foreground, 0.45)
        ctx.fillText(firstDate, padLeft, height - padBottom + Style.space(3))
        ctx.fillText(lastDate, padLeft + plotWidth - ctx.measureText(lastDate).width,
          height - padBottom + Style.space(3))
      }

      if (root.series.length >= 1) {
        var lastPercent = Number(root.series[root.series.length - 1].monthly)
        var percentLabel = "monthly " + Math.round(lastPercent) + "%"
        ctx.fillStyle = root.css(root.foreground, 0.75)
        ctx.fillText(percentLabel, padLeft + plotWidth - ctx.measureText(percentLabel).width,
          Style.space(3) + Style.font.caption + Style.space(2))
      }
    }
  }

  Text {
    visible: !root.hasBars && !root.hasLine
    anchors.centerIn: parent
    text: "No local usage or samples yet"
    color: Qt.darker(root.foreground, 1.5)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    textFormat: Text.PlainText
  }

  Text {
    visible: root.hasBars && !root.hasLine
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: Style.space(4)
    anchors.topMargin: Style.space(3) + Style.font.caption * 2
    text: "Collecting samples\u2026"
    color: Qt.darker(root.foreground, 1.5)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    textFormat: Text.PlainText
  }

  Connections {
    target: root
    function onRowsChanged() { graph.requestPaint() }
    function onSeriesChanged() { graph.requestPaint() }
    function onModeChanged() { graph.requestPaint() }
    function onForegroundChanged() { graph.requestPaint() }
    function onAccentChanged() { graph.requestPaint() }
  }
}
