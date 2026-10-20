import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Column {
  id: root

  property var settings: ({})
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property bool invalidRenew: false

  readonly property bool editing: planField.activeFocus || renewField.activeFocus
  readonly property color dim: Qt.darker(foreground, 1.45)

  signal updateSetting(string key, var value)
  signal done()

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(6)

  function value(key, fallback) {
    return settings && settings[key] !== undefined && settings[key] !== null ? settings[key] : fallback
  }

  PanelSectionHeader {
    text: "Display"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  SettingRow {
    label: "Bar display"
    hint: "worst follows the window closest to its limit"
    foreground: root.foreground
    fontFamily: root.fontFamily

    Dropdown {
      width: parent.width
      value: String(root.value("barWindows", "worst"))
      options: ["worst", "all", "month"]
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      showLabel: false
      onChanged: function (newValue) { root.updateSetting("barWindows", newValue) }
    }
  }

  SettingRow {
    label: "Percent meaning"
    hint: "Show the remaining quota or the used share"
    foreground: root.foreground
    fontFamily: root.fontFamily

    Dropdown {
      width: parent.width
      value: String(root.value("percentMode", "remaining"))
      options: ["remaining", "used"]
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      showLabel: false
      onChanged: function (newValue) { root.updateSetting("percentMode", newValue) }
    }
  }

  SettingRow {
    label: "Plan label"
    hint: "Shown in the panel header and notifications"
    foreground: root.foreground
    fontFamily: root.fontFamily

    TextField {
      id: planField
      width: parent.width
      text: String(root.value("planLabel", "OpenCode Go"))
      placeholderText: "OpenCode Go"
      foreground: root.foreground
      accent: root.accent
      onEditingFinished: root.updateSetting("planLabel", text)
    }
  }

  PanelSeparator { foreground: root.foreground }
  PanelSectionHeader {
    text: "Thresholds"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  SettingRow {
    label: "Warn below remaining %"
    foreground: root.foreground
    fontFamily: root.fontFamily

    NumberField {
      anchors.right: parent.right
      from: 1
      to: 99
      stepSize: 1
      value: Number(root.value("warnRemaining", 20))
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      onModified: function (newValue) { root.updateSetting("warnRemaining", newValue) }
    }
  }

  SettingRow {
    label: "Critical below remaining %"
    foreground: root.foreground
    fontFamily: root.fontFamily

    NumberField {
      anchors.right: parent.right
      from: 1
      to: 99
      stepSize: 1
      value: Number(root.value("critRemaining", 10))
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      onModified: function (newValue) { root.updateSetting("critRemaining", newValue) }
    }
  }

  PanelSeparator { foreground: root.foreground }
  PanelSectionHeader {
    text: "Refresh"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  SettingRow {
    label: "Refresh interval (seconds)"
    hint: "Minimum 60 seconds; manual refresh always bypasses the cache"
    foreground: root.foreground
    fontFamily: root.fontFamily

    NumberField {
      anchors.right: parent.right
      from: 60
      to: 3600
      stepSize: 60
      value: Number(root.value("refreshIntervalSec", 300))
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      onModified: function (newValue) { root.updateSetting("refreshIntervalSec", newValue) }
    }
  }

  PanelSeparator { foreground: root.foreground }
  PanelSectionHeader {
    text: "Notifications"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  SettingRow {
    label: "Notify on thresholds"
    foreground: root.foreground
    fontFamily: root.fontFamily

    ToggleSwitch {
      anchors.right: parent.right
      checked: root.value("notifyEnabled", true) === true
      foreground: root.foreground
      accent: root.accent
      onToggled: root.updateSetting("notifyEnabled", !checked)
    }
  }

  SettingRow {
    label: "Notify on reset"
    hint: "One notification when a window starts over"
    foreground: root.foreground
    fontFamily: root.fontFamily

    ToggleSwitch {
      anchors.right: parent.right
      checked: root.value("notifyReset", false) === true
      foreground: root.foreground
      accent: root.accent
      onToggled: root.updateSetting("notifyReset", !checked)
    }
  }

  SettingRow {
    label: "Show per-model usage"
    foreground: root.foreground
    fontFamily: root.fontFamily

    ToggleSwitch {
      anchors.right: parent.right
      checked: root.value("showModelDetail", true) === true
      foreground: root.foreground
      accent: root.accent
      onToggled: root.updateSetting("showModelDetail", !checked)
    }
  }

  PanelSeparator { foreground: root.foreground }
  PanelSectionHeader {
    text: "Renew override"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  SettingRow {
    label: "Manual renew time"
    hint: "ISO 8601. Used only when the API is unavailable"
    foreground: root.foreground
    fontFamily: root.fontFamily

    TextField {
      id: renewField
      width: parent.width
      text: String(root.value("renewOverride", ""))
      placeholderText: "2026-11-17T22:35:00+08:00"
      foreground: root.foreground
      accent: root.accent
      onEditingFinished: {
        var newValue = text.trim()
        if (newValue && isNaN(new Date(newValue).getTime())) {
          root.invalidRenew = true
          return
        }
        root.invalidRenew = false
        root.updateSetting("renewOverride", newValue)
      }
    }
  }

  Text {
    visible: root.invalidRenew
    text: "Invalid ISO 8601 time; value not saved."
    color: Commons.Color.urgent
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    textFormat: Text.PlainText
  }

  Text {
    text: "Settings are stored in ~/.config/omarchy/shell.json and shared with Setup \u2192 Plugins."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
    width: parent.width
    textFormat: Text.PlainText
  }

  Item {
    width: parent.width
    height: Style.spacing.controlHeight

    Rectangle {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(88)
      height: Style.spacing.controlHeight
      radius: Style.cornerRadius
      color: Style.controlFill(false, doneMouse.containsMouse, root.foreground, root.accent)
      border.width: 1
      border.color: Style.normalBorderFor(root.foreground, root.accent, Commons.Color.urgent)

      Text {
        anchors.centerIn: parent
        text: "Done"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
      }

      MouseArea {
        id: doneMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.done()
      }
    }
  }
}
