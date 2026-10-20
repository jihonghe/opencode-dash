import QtQuick
import qs.Commons
import qs.Commons as Commons
import "../Model.js" as Model

Column {
  id: root

  property var samples: []
  property string mode: "7d"
  property real nowMs: Date.now()
  property real cycleStartMs: 0
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family

  readonly property var filtered: Model.trendSamples(samples, mode, nowMs, cycleStartMs)
  readonly property var rolling: seriesFor("rolling")
  readonly property var weekly: seriesFor("weekly")
  readonly property var monthly: seriesFor("monthly")
  readonly property bool hasData: rolling.length >= 2 || weekly.length >= 2 || monthly.length >= 2

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(2)

  function seriesFor(name) {
    var out = []
    for (var i = 0; i < filtered.length; i++) {
      var value = filtered[i][name]
      if (value === undefined || value === null) continue
      var time = new Date(filtered[i].t).getTime()
      if (!isFinite(time)) continue
      out.push({ t: time, v: Math.max(0, Math.min(100, 100 - Number(value))) })
    }
    return out
  }

  function latest(name) {
    var points = seriesFor(name)
    return points.length > 0 ? Math.round(points[points.length - 1].v) + "%" : ""
  }

  readonly property string historyText: {
    if (filtered.length === 0) return "no samples"
    var first = new Date(filtered[0].t).getTime()
    var last = new Date(filtered[filtered.length - 1].t).getTime()
    var span = Math.max(0, Math.round((last - first) / 1000))
    var range = mode === "24h" ? 86400 : (mode === "7d" ? 7 * 86400 : 30 * 86400)
    var suffix = span < range ? " \u00b7 all samples so far" : " \u00b7 " + filtered.length + " samples"
    return Model.fmtDuration(span) + suffix
  }

  function colorFor(name) {
    if (name === "rolling") return accent
    if (name === "weekly") return Qt.rgba(foreground.r, foreground.g, foreground.b, 0.78)
    return Qt.rgba(foreground.r, foreground.g, foreground.b, 0.42)
  }

  function css(color, alpha) {
    return "rgba(" + Math.round(color.r * 255) + ","
      + Math.round(color.g * 255) + ","
      + Math.round(color.b * 255) + ","
      + alpha + ")"
  }

  function pad2(value) {
    return value < 10 ? "0" + value : String(value)
  }

  function stamp(iso) {
    var date = new Date(iso)
    if (isNaN(date.getTime())) return ""
    return pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
      + " " + pad2(date.getHours()) + ":" + pad2(date.getMinutes())
  }

  Row {
    id: legend
    spacing: Style.space(10)

    SeriesLabel {
      visible: root.latest("rolling") !== ""
      label: "5h " + root.latest("rolling")
      swatch: root.colorFor("rolling")
      fontFamily: root.fontFamily
    }
    SeriesLabel {
      visible: root.latest("weekly") !== ""
      label: "7d " + root.latest("weekly")
      swatch: root.colorFor("weekly")
      dashed: true
      fontFamily: root.fontFamily
    }
    SeriesLabel {
      visible: root.latest("monthly") !== ""
      label: "M " + root.latest("monthly")
      swatch: root.colorFor("monthly")
      fontFamily: root.fontFamily
    }
    Text {
      text: "remaining %"
      color: Qt.darker(root.foreground, 1.45)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }
  }

  Canvas {
    id: graph
    width: root.width
    height: Style.space(116)

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (!root.hasData) return

      var seriesList = [
        { name: "rolling", points: root.rolling, color: root.colorFor("rolling"), dash: [], width: 2 },
        { name: "weekly", points: root.weekly, color: root.colorFor("weekly"), dash: [4, 3], width: 1.5 },
        { name: "monthly", points: root.monthly, color: root.colorFor("monthly"), dash: [], width: 2 }
      ]

      var first = Infinity
      var last = -Infinity
      var minimum = Infinity
      var maximum = -Infinity
      for (var s = 0; s < seriesList.length; s++) {
        var points = seriesList[s].points
        for (var p = 0; p < points.length; p++) {
          first = Math.min(first, points[p].t)
          last = Math.max(last, points[p].t)
          minimum = Math.min(minimum, points[p].v)
          maximum = Math.max(maximum, points[p].v)
        }
      }
      if (!isFinite(first) || !isFinite(last) || last <= first) return

      if (maximum - minimum < 8) {
        var middle = (maximum + minimum) / 2
        minimum = Math.max(0, middle - 4)
        maximum = Math.min(100, middle + 4)
      }
      if (maximum <= minimum) maximum = minimum + 1

      var padLeft = Style.space(4)
      var padRight = Style.space(4)
      var padTop = Style.space(12)
      var padBottom = Style.space(16)
      var plotWidth = width - padLeft - padRight
      var plotHeight = height - padTop - padBottom
      if (plotWidth <= 0 || plotHeight <= 0) return

      ctx.lineWidth = 1
      for (var g = 0; g < 3; g++) {
        var gridY = padTop + plotHeight * (g / 2)
        ctx.strokeStyle = root.css(root.foreground, 0.08)
        ctx.beginPath()
        ctx.moveTo(padLeft, gridY)
        ctx.lineTo(padLeft + plotWidth, gridY)
        ctx.stroke()
      }

      ctx.font = Style.font.caption + "px '" + root.fontFamily + "'"
      ctx.textBaseline = "top"
      ctx.fillStyle = root.css(root.foreground, 0.42)
      var maxLabel = Math.round(maximum) + "%"
      var minLabel = Math.round(minimum) + "%"
      ctx.fillText(maxLabel, padLeft + plotWidth - ctx.measureText(maxLabel).width, padTop + Style.space(1))
      ctx.fillText(minLabel, padLeft + plotWidth - ctx.measureText(minLabel).width,
        padTop + plotHeight - Style.font.caption - Style.space(1))

      for (var s2 = 0; s2 < seriesList.length; s2++) {
        var series = seriesList[s2]
        if (series.points.length < 2) continue
        ctx.setLineDash(series.dash)
        ctx.lineWidth = series.width
        ctx.lineCap = "round"
        ctx.strokeStyle = root.css(series.color, 1)
        ctx.beginPath()
        for (var q = 0; q < series.points.length; q++) {
          var x = padLeft + ((series.points[q].t - first) / (last - first)) * plotWidth
          var y = padTop + (1 - (series.points[q].v - minimum) / (maximum - minimum)) * plotHeight
          if (q === 0) ctx.moveTo(x, y)
          else ctx.lineTo(x, y)
        }
        ctx.stroke()
        ctx.setLineDash([])
        var lastPoint = series.points[series.points.length - 1]
        var dotX = padLeft + ((lastPoint.t - first) / (last - first)) * plotWidth
        var dotY = padTop + (1 - (lastPoint.v - minimum) / (maximum - minimum)) * plotHeight
        ctx.fillStyle = root.css(series.color, 1)
        ctx.beginPath()
        ctx.arc(dotX, dotY, 1.5, 0, Math.PI * 2)
        ctx.fill()
      }

      ctx.fillStyle = root.css(root.foreground, 0.45)
      if (root.filtered.length > 0) {
        var firstLabel = root.stamp(root.filtered[0].t)
        var lastLabel = root.stamp(root.filtered[root.filtered.length - 1].t)
        ctx.fillText(firstLabel, padLeft, height - padBottom + Style.space(2))
        ctx.fillText(lastLabel, padLeft + plotWidth - ctx.measureText(lastLabel).width,
          height - padBottom + Style.space(2))
      }
    }
  }

  Text {
    width: root.width
    text: "Official API samples \u00b7 " + root.historyText
    color: Qt.darker(root.foreground, 1.45)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
  }

  Text {
    visible: root.historyText.indexOf("all samples so far") !== -1
    width: root.width
    text: "24h / 7d / Cycle differ once more samples accumulate."
    color: Qt.darker(root.foreground, 1.55)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
  }

  Connections {
    target: root
    function onSamplesChanged() { graph.requestPaint() }
    function onModeChanged() { graph.requestPaint() }
    function onNowMsChanged() { graph.requestPaint() }
    function onForegroundChanged() { graph.requestPaint() }
    function onAccentChanged() { graph.requestPaint() }
  }
}
