import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  readonly property string text: "OCQ"

  implicitWidth: label.implicitWidth + Style.space(16)
  implicitHeight: barSize

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    color: root.bar ? root.bar.barForeground : Commons.Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }
}
