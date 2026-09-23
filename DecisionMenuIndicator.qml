import QtQuick
import qs.Commons
import qs.Ui

WidgetButton {
  id: root
  property bool hasNew: false
  property string countText: "…"
  // Keep the invisible native label for the bar's sizing and click geometry.
  text: "\uf059 " + countText
  labelVisible: false

  Row {
    anchors.centerIn: parent
    spacing: 0
    rotation: root.textRotation
    FlagIcon {
      objectName: "decisionMenuIcon"
      anchors.verticalCenter: parent.verticalCenter
      size: root.fontSize
      color: root.hasNew ? Color.accent : root.foreground
    }
    Text {
      objectName: "decisionMenuCount"
      anchors.verticalCenter: parent.verticalCenter
      text: " " + root.countText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      renderType: Text.NativeRendering
    }
  }
}
