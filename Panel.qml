import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  manageIpc: false

  Text {
    anchors.centerIn: parent
    text: "OpenCode Quota"
    color: root.barForeground
  }
}
