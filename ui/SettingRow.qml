import QtQuick
import qs.Commons
import qs.Commons as Commons

Item {
  id: root

  property string label: ""
  property string hint: ""
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  default property alias control: slot.data

  readonly property color dim: Qt.darker(foreground, 1.45)
  implicitHeight: Math.max(Style.spacing.controlHeight, labelColumn.implicitHeight)
  width: parent ? parent.width : implicitWidth

  Column {
    id: labelColumn
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width * 0.44
    spacing: Style.space(1)

    Text {
      width: parent.width
      text: root.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
    }

    Text {
      visible: root.hint !== ""
      width: parent.width
      text: root.hint
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
    }
  }

  Item {
    id: slot
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width * 0.52
    height: childrenRect.height
  }
}
