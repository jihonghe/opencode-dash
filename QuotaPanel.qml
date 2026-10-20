import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "ui"

Panel {
  id: root
  manageIpc: false

  property Item anchorItem: null
  property var report: null
  property bool settingsMode: false
  property real nowMs: Date.now()

  signal updateSetting(string key, var value)
  signal refreshRequested()

  readonly property var cfg: Model.settingsWithDefaults(settings)
  readonly property color foreground: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color warnColor: {
    var background = Commons.Color.popups.background
    var luminance = 0.2126 * background.r + 0.7152 * background.g + 0.0722 * background.b
    return luminance > 0.5 ? "#a35f00" : "#e8a33d"
  }
  readonly property color critColor: bar && bar.urgent ? bar.urgent : Commons.Color.urgent
  readonly property color okColor: {
    var background = Commons.Color.popups.background
    var luminance = 0.2126 * background.r + 0.7152 * background.g + 0.0722 * background.b
    return luminance > 0.5 ? "#2e7d32" : "#9ece6a"
  }
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var windows: report && report.windows ? report.windows : ({})
  readonly property string stateText: Model.stateMessage(report)
  function openSettings() {
    settingsMode = true
    open()
  }

  function toggleSettings() {
    settingsMode = !settingsMode
  }

  onOpenedChanged: {
    if (opened) {
      nowMs = Date.now()
      flick.contentY = 0
      refreshRequested()
      Qt.callLater(function () { keyCatcher.forceActiveFocus() })
    } else {
      settingsMode = false
    }
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(480))
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onActivateRequested: if (root.settingsMode) root.settingsMode = false
      onMoveRequested: function (dx, dy) {
        if (dy === 0) return
        var limit = Math.max(0, flick.contentHeight - flick.height)
        flick.contentY = Math.max(0, Math.min(limit, flick.contentY + dy * Style.space(48)))
      }
      onTextKey: function (text) {
        if (text === "r" || text === "R") root.refreshRequested()
        else if (text === "s" || text === "S") root.toggleSettings()
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: flick.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            height: Style.space(28)

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.settingsMode ? "Settings" : "OpenCode Quota"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              textFormat: Text.PlainText
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              PanelActionButton {
                visible: !root.settingsMode
                iconText: "\u21bb"
                tooltipText: "Refresh now"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.refreshRequested()
              }

              PanelActionButton {
                iconText: root.settingsMode ? "\u2190" : "\u2699"
                tooltipText: root.settingsMode ? "Back" : "Settings"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.settingsMode = !root.settingsMode
              }

              PanelActionButton {
                iconText: "\u2715"
                tooltipText: "Close"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.close()
              }
            }
          }

          Item {
            visible: !root.settingsMode
            width: parent.width
            height: stateLabel.visible
              ? Math.max(Style.space(20), planLabel.implicitHeight + stateLabel.implicitHeight + Style.space(2))
              : Style.space(20)

            Text {
              id: planLabel
              anchors.left: parent.left
              anchors.top: parent.top
              text: root.cfg.planLabel
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
              width: Math.min(implicitWidth, parent.width - updatedText.implicitWidth - Style.space(8))
              textFormat: Text.PlainText
            }

            Text {
              id: updatedText
              anchors.right: parent.right
              anchors.top: parent.top
              text: root.report ? "updated " + Model.fmtUpdated(root.report.updatedAt) : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
            }

            Text {
              id: stateLabel
              visible: root.stateText !== ""
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: planLabel.bottom
              anchors.topMargin: Style.space(2)
              text: root.stateText
              color: root.report && root.report.stale ? root.warnColor : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
            }
          }

          Column {
            visible: !root.settingsMode
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: ["rolling", "weekly", "monthly"]

              delegate: WindowCard {
                required property string modelData
                width: parent.width
                name: modelData
                window: root.windows[modelData] ? root.windows[modelData] : ({})
                settings: root.cfg
                nowMs: root.nowMs
                foreground: root.foreground
                accent: root.accent
                warnColor: root.warnColor
                critColor: root.critColor
                okColor: root.okColor
                fontFamily: root.fontFamily
              }
            }
          }

          Item {
            visible: !root.settingsMode && runwayTable.hasRows
            width: parent.width
            height: visible ? runwayTable.implicitHeight : 0

            RunwayTable {
              id: runwayTable
              width: parent.width
              report: root.report
              settings: root.cfg
              nowMs: root.nowMs
              foreground: root.foreground
              warnColor: root.warnColor
              critColor: root.critColor
              okColor: root.okColor
              fontFamily: root.fontFamily
            }
          }

          PanelSeparator {
            visible: !root.settingsMode
            foreground: root.foreground
          }

          Text {
            visible: !root.settingsMode
            width: parent.width
            text: "Official usage API \u00b7 account-wide, all clients"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
          }

          SettingsPage {
            id: settingsView
            visible: root.settingsMode
            width: parent.width
            settings: root.cfg
            report: root.report
            nowMs: root.nowMs
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onUpdateSetting: function (key, value) { root.updateSetting(key, value) }
            onDone: root.settingsMode = false
          }
        }
      }
    }
  }
}
