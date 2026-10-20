import QtQuick
import qs.Commons
import qs.Commons as Commons
import "../Model.js" as Model

Column {
  id: root

  property var models: []
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property real msgsWidth: Style.space(46)
  readonly property real tokensWidth: Style.space(150)
  readonly property real costWidth: Style.space(56)
  readonly property real gap: Style.space(6)
  readonly property real modelWidth: Math.max(Style.space(100),
    width - msgsWidth - tokensWidth - costWidth - gap * 3)

  width: parent ? parent.width : implicitWidth
  spacing: 0

  function tokensText(model) {
    var tokens = model.tokens || {}
    return Model.fmtCompact(tokens.input) + "/" + Model.fmtCompact(tokens.output)
      + "/" + Model.fmtCompact(tokens.reasoning) + "/" + Model.fmtCompact(tokens.cacheRead)
  }

  Row {
    width: root.width
    height: Style.space(20)
    spacing: root.gap

    Text {
      width: root.modelWidth
      text: "Model"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      textFormat: Text.PlainText
    }
    Text {
      width: root.msgsWidth
      text: "Msgs"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
    }
    Text {
      width: root.tokensWidth
      text: "Tokens in/out/think/cache"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
      textFormat: Text.PlainText
    }
    Text {
      width: root.costWidth
      text: "Cost"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
    }
  }

  Repeater {
    model: root.models

    delegate: Column {
      required property var modelData
      width: root.width

      Row {
        width: root.width
        height: Style.space(25)
        spacing: root.gap

        Text {
          width: root.modelWidth
          text: modelData.id + (modelData.free ? "  (free)" : "")
          color: modelData.free ? root.dim : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
        }
        Text {
          width: root.msgsWidth
          text: String(modelData.messages)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
        }
        Text {
          width: root.tokensWidth
          text: root.tokensText(modelData)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }
        Text {
          width: root.costWidth
          text: Model.fmtCost(modelData.cost)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
        }
      }

      Rectangle {
        width: root.width
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
      }
    }
  }

  Text {
    visible: root.models.length === 0
    text: "No local usage this cycle"
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    textFormat: Text.PlainText
  }
}
