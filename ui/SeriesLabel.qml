import QtQuick
import qs.Commons

Row {
  id: root

  property string label: ""
  property color swatch: Commons.Color.foreground
  property bool dashed: false
  property string fontFamily: Style.font.family

  spacing: Style.space(4)

  Item {
    width: Style.space(14)
    height: Math.max(Style.font.caption, Style.space(8))

    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Rectangle {
        width: root.dashed ? Style.space(5) : Style.space(12)
        height: Math.max(1, Style.space(1))
        color: root.swatch
      }
      Rectangle {
        visible: root.dashed
        width: Style.space(5)
        height: Math.max(1, Style.space(1))
        color: root.swatch
      }
    }
  }

  Text {
    text: root.label
    color: root.swatch
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    textFormat: Text.PlainText
  }
}
