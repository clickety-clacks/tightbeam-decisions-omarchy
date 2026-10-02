import QtQuick
import qs.Commons

Item {
  id: root

  required property string status
  required property string actor
  required property string determination
  property real fontScale: 1
  property string sansFamily: ""
  property string monoFamily: ""
  property color foreground: Color.foreground
  property color secondary: Color.foreground
  property color hairline: Color.foreground
  property color background: Color.background

  readonly property real padding: Math.round(16 * fontScale)
  readonly property real labelHeight: Math.round(20 * fontScale)
  clip: true
  implicitHeight: padding * 2 + labelHeight + Math.round(8 * fontScale)
    + outcomeText.implicitHeight

  Rectangle {
    anchors.fill: parent
    color: root.background
    border.color: root.hairline
    border.width: 1
  }

  Text {
    x: root.padding
    y: root.padding
    width: Math.max(0, root.width - root.padding * 2)
    height: root.labelHeight
    text: (root.actor === "" ? "" : root.actor + " · ") + root.status
    color: root.foreground
    font.family: root.monoFamily
    font.pixelSize: Math.round(11 * root.fontScale)
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
  }

  Text {
    id: outcomeText
    x: root.padding
    y: root.padding + root.labelHeight + Math.round(8 * root.fontScale)
    width: Math.max(0, root.width - root.padding * 2)
    height: implicitHeight
    text: root.determination
    color: root.secondary
    font.family: root.sansFamily
    font.pixelSize: Math.round(15 * root.fontScale)
    lineHeight: font.pixelSize * 1.45
    lineHeightMode: Text.FixedHeight
    wrapMode: Text.Wrap
  }
}
