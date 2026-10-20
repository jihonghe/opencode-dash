import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root

  property var report: null
  property var localSettings: Model.settingsWithDefaults({})
  property var pendingSettings: ({})
  property bool fetching: false
  property bool pendingForce: false
  property bool ready: false
  property bool hovered: false
  property string lastError: ""

  readonly property string scriptPath: {
    var url = Qt.resolvedUrl("scripts/quota.py").toString()
    if (url.indexOf("file://") === 0) url = url.slice(7)
    return decodeURIComponent(url)
  }

  readonly property var savedEntry: {
    var shell = bar && bar.shell ? bar.shell : null
    var config = shell && shell.barConfig ? shell.barConfig : null
    return Model.savedBarSettings(config, moduleName, locateSelf())
  }

  readonly property string horizontalText: Model.barText(report, localSettings)
  readonly property var verticalParts: Model.verticalParts(report, localSettings)
  readonly property string level: Model.statusLevel(report, localSettings)
  readonly property bool tooltipHovered: visible && opacity > 0 && mouseArea.containsMouse

  readonly property color displayColor: {
    if (!bar) return Commons.Color.foreground
    if (level === "crit") return bar.urgent || Commons.Color.urgent
    if (level === "warn") {
      var background = bar.background || Commons.Color.background
      var luminance = 0.2126 * background.r + 0.7152 * background.g + 0.0722 * background.b
      return luminance > 0.5 ? "#a35f00" : "#e8a33d"
    }
    return bar.barForeground || bar.foreground || Commons.Color.foreground
  }

  readonly property real displayOpacity: report && report.stale ? 0.55 : 1.0

  // ------------------------------------------------------------- lifecycle

  Component.onCompleted: {
    syncSettings()
    ready = true
    refresh(false)
  }

  IpcHandler {
    target: "jihonghe.opencode-quota"
    function toggle(): void { panel.toggle() }
    function open(): void { panel.open() }
    function close(): void { panel.close() }
    function settings(): void { panel.openSettings() }
    function refresh(): string { root.refresh(true); return "ok" }
  }

  onSettingsChanged: syncSettings()
  onSavedEntryChanged: {
    pendingSettings = Model.prunePending(savedEntry, pendingSettings, Date.now())
    syncSettings()
  }

  function syncSettings() {
    var saved = Model.withPending(savedEntry || {}, pendingSettings)
    localSettings = Model.settingsWithDefaults(Model.mergeSettings(settings, saved))
  }

  onReportChanged: {
    if (hovered && bar) bar.showTooltip(root, Model.tooltip(report, localSettings))
  }
  onLocalSettingsChanged: {
    if (hovered && bar) bar.showTooltip(root, Model.tooltip(report, localSettings))
  }

  // ------------------------------------------------------------- settings

  function updateSetting(key, value) {
    var next = Model.settingsWithDefaults(localSettings)
    var changes = {}

    if (key === "warnRemaining" || key === "critRemaining" || key === "refreshIntervalSec") {
      var number = Number(value)
      if (!isFinite(number)) return false
      if (key === "refreshIntervalSec") value = Math.max(60, Math.min(3600, Math.round(number)))
      else value = Math.max(1, Math.min(99, Math.round(number)))
    } else if (key === "barWindows") {
      if (["worst", "all", "month"].indexOf(value) === -1) return false
    } else if (key === "percentMode") {
      if (["remaining", "used"].indexOf(value) === -1) return false
    } else if (key === "notifyEnabled" || key === "notifyReset" || key === "showModelDetail") {
      value = !!value
    } else if (key === "renewOverride") {
      value = String(value || "").trim()
      if (value && isNaN(new Date(value).getTime())) return false
    } else if (key === "planLabel") {
      value = String(value || "").trim().slice(0, 40) || "OpenCode Go"
    } else {
      return false
    }

    next[key] = value
    changes[key] = value

    if (key === "warnRemaining" && next.critRemaining > next.warnRemaining) {
      next.critRemaining = next.warnRemaining
      changes.critRemaining = next.critRemaining
    }

    localSettings = next
    var pending = {}
    for (var p in pendingSettings) pending[p] = pendingSettings[p]
    for (var c in changes) pending[c] = { value: changes[c], at: Date.now() }
    pendingSettings = pending
    for (var changed in changes) persistSetting(changed, changes[changed])

    if (key === "warnRemaining" || key === "critRemaining" || key === "notifyEnabled"
        || key === "notifyReset" || key === "renewOverride") {
      refresh(false)
    }
    return true
  }

  function persistSetting(key, value) {
    if (!bar || !bar.shell) return
    var where = locateSelf()
    var registry = bar.shell.pluginRegistry
    if (registry && where && typeof registry.setBarWidget === "function") {
      try {
        var error = registry.setBarWidget(moduleName, key, value, { section: where.section, index: where.index })
        if (!error) return
        console.warn("opencode-quota: setBarWidget failed (" + error + "), falling back")
      } catch (e) {
        console.warn("opencode-quota: setBarWidget unavailable, falling back")
      }
    }

    if (typeof bar.shell.updateEntryInline === "function") {
      var entry = { id: moduleName }
      for (var settingKey in localSettings) {
        if (settingKey !== "id" && settingKey !== "debugFixture") entry[settingKey] = localSettings[settingKey]
      }
      bar.shell.updateEntryInline(moduleName, entry)
      return
    }

    if (typeof bar.run === "function") {
      var isJson = typeof value === "boolean" || typeof value === "number"
      var command = "omarchy bar set " + quote(moduleName) + " " + quote(key) + " "
        + quote(isJson ? JSON.stringify(value) : String(value))
        + (isJson ? " --json" : "")
      bar.run(command)
    }
  }

  function quote(value) {
    if (bar && typeof bar.shellQuote === "function") return bar.shellQuote(String(value))
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  // Where this widget lives in shell.json. Adapted from crmne/omastats (MIT).
  function locateSelf() {
    if (!bar || typeof bar.layoutEntries !== "function" || !Array.isArray(bar.moduleSlots)) return null
    var mine = null
    for (var i = 0; i < bar.moduleSlots.length; i++) {
      var slot = bar.moduleSlots[i]
      if (slot && slot.activeItem === root) { mine = slot; break }
    }
    if (!mine) return null
    var region = String(mine.region || "")
    var entries = bar.layoutEntries(region)
    var direct = entries.indexOf(mine.entry)
    if (direct !== -1) return { section: region, index: direct }
    var candidates = []
    for (var j = 0; j < entries.length; j++) {
      if (typeof bar.entryId === "function" && bar.entryId(entries[j]) === moduleName) candidates.push(j)
    }
    if (candidates.length === 1) return { section: region, index: candidates[0] }
    if (candidates.length === 0) return null
    var siblings = []
    for (var k = 0; k < bar.moduleSlots.length; k++) {
      var other = bar.moduleSlots[k]
      if (!other || other.region !== region || other.moduleName !== moduleName) continue
      if (typeof bar.sameWindow === "function" && typeof bar.slotWindow === "function"
          && !bar.sameWindow(bar.slotWindow(other), bar.slotWindow(mine))) continue
      siblings.push(other)
    }
    siblings.sort(function (a, b) { return root.vertical ? a.y - b.y : a.x - b.x })
    var ordinal = siblings.indexOf(mine)
    if (ordinal < 0 || ordinal >= candidates.length) return null
    return { section: region, index: candidates[ordinal] }
  }

  // ------------------------------------------------------------- refresh

  function refresh(force) {
    if (fetching) {
      if (force) pendingForce = true
      return
    }
    var args = [
      scriptPath,
      "--json",
      "--warn", String(localSettings.warnRemaining),
      "--crit", String(localSettings.critRemaining),
      "--plan-label", String(localSettings.planLabel)
    ]
    if (!localSettings.notifyEnabled) args.push("--no-alerts")
    if (localSettings.notifyReset) args.push("--notify-reset")
    if (localSettings.renewOverride) args.push("--renew-override", String(localSettings.renewOverride))
    if (force) args.push("--force")

    var fixture = setting("debugFixture", "")
    if (fixture) args.push("--fixture", String(fixture))

    fetching = true
    fetchProcess.command = ["/usr/bin/env", "python3"].concat(args)
    fetchProcess.running = true
  }

  function handleOutput(text) {
    if (!text || !String(text).trim()) {
      lastError = "empty output"
      markStale()
      return
    }
    try {
      var parsed = JSON.parse(text)
      if (!parsed || typeof parsed !== "object") throw new Error("invalid report")
      report = parsed
      lastError = ""
      fireAlerts(parsed.alerts || [])
    } catch (e) {
      lastError = "invalid JSON"
      markStale()
    }
  }

  function markStale() {
    if (!report) {
      report = {
        state: "no-data",
        stale: true,
        updatedAt: "",
        windows: {},
        runway: {},
        models: [],
        daily: [],
        samples: [],
        alerts: []
      }
      return
    }
    var copy = JSON.parse(JSON.stringify(report))
    copy.stale = true
    if (copy.state === "ok") copy.state = "stale"
    report = copy
  }

  function fireAlerts(alerts) {
    if (!alerts || !alerts.length) return
    for (var i = 0; i < alerts.length; i++) {
      var alert = alerts[i]
      var label = Model.windowLabel(alert.window)
      var title = ""
      var body = ""
      var urgency = alert.level === "crit" ? "critical" : "normal"

      if (alert.level === "reset") {
        title = localSettings.planLabel + " \u00b7 " + label + " quota reset"
        body = "A new " + label + " window has started."
      } else {
        title = localSettings.planLabel + " \u00b7 " + label + " " + Math.round(alert.remaining) + "% remaining"
        body = "Resets " + Model.fmtReset(alert.window, alert.resetsAt)
          + " (in ~" + Model.fmtDuration(alert.resetInSec) + ")"
      }

      Quickshell.execDetached([
        "notify-send",
        "-a", "OpenCode Quota",
        "-u", urgency,
        "-t", "15000",
        title,
        body
      ])
    }
  }

  Process {
    id: fetchProcess
    running: false
    command: []

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleOutput(text)
    }

    stderr: StdioCollector {
      waitForEnd: true
    }

    onExited: function (exitCode) {
      root.fetching = false
      if (exitCode !== 0) {
        root.lastError = "exit " + exitCode
        root.markStale()
      }
      if (root.pendingForce) {
        root.pendingForce = false
        root.refresh(true)
      }
    }
  }

  Timer {
    interval: Math.max(60, Number(root.localSettings.refreshIntervalSec)) * 1000
    running: root.ready
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  // ------------------------------------------------------------- display

  Text {
    id: horizontal
    visible: !root.vertical
    anchors.centerIn: parent
    text: root.horizontalText
    color: root.displayColor
    opacity: root.displayOpacity
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    textFormat: Text.PlainText
  }

  Column {
    visible: root.vertical
    anchors.centerIn: parent
    spacing: 0

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.verticalParts.label
      color: root.displayColor
      opacity: root.displayOpacity
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.verticalParts.value
      color: root.displayColor
      opacity: root.displayOpacity
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor

    onClicked: function (mouse) {
      if (mouse.button === Qt.LeftButton) panel.toggle()
      else if (mouse.button === Qt.RightButton) panel.openSettings()
      else if (mouse.button === Qt.MiddleButton) root.refresh(true)
    }

    onEntered: {
      root.hovered = true
      if (root.bar) root.bar.showTooltip(root, Model.tooltip(root.report, root.localSettings))
    }
    onExited: {
      root.hovered = false
      if (root.bar) root.bar.hideTooltip(root)
    }
  }

  implicitWidth: root.vertical ? barSize : horizontal.implicitWidth + Style.space(16)
  implicitHeight: root.vertical
    ? Math.max(barSize, verticalParts.value === "" ? barSize : Style.font.caption + Style.font.bodySmall + Style.space(2))
    : barSize

  QuotaPanel {
    id: panel
    bar: root.bar
    settings: root.localSettings
    anchorItem: root
    report: root.report
    onUpdateSetting: function (key, value) { root.updateSetting(key, value) }
    onRefreshRequested: root.refresh(true)
  }
}
