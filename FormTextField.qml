import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  property string label: ""
  property alias text: field.text
  property alias placeholderText: field.placeholderText
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal accepted()

  spacing: Style.space(4)

  Text {
    width: parent.width
    text: root.label
    color: Qt.darker(root.foreground, 1.35)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  TextField {
    id: field
    width: parent.width
    foreground: root.foreground
    accent: root.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    onAccepted: root.accepted()
  }
}
