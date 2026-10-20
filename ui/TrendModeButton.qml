import QtQuick
import qs.Commons
import qs.Commons as Commons

Rectangle {
  id: root

  property string label: ""
  property bool selected: false
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family

  signal clicked()

  width: Style.space(46)
  height: Style.space(20)
  radius: Style.cornerRadius
  color: selected ? Qt.rgba(accent.r, accent.g, accent.b, 0.18) : "transparent"
  border.width: selected ? 0 : 1
  border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)

  Text {
    anchors.centerIn: parent
    text: root.label
    color: root.selected ? root.accent : Qt.darker(root.foreground, 1.45)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    textFormat: Text.PlainText
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
