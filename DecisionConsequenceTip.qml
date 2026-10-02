import QtQuick
import QtQuick.Controls as QQC
import qs.Commons

// A single consequence popup is shared by each choice surface. Keeping one
// popup prevents hidden measurement delegates and keyboard focus from opening
// copies of the same explanation in the window overlay.
QQC.Popup {
  id: root

  property Item anchorItem: null
  property Item boundsItem: null
  property string consequence: ""
  property string sansFamily: ""
  property real fontScale: 1
  property string text: root.consequence
  property string fontFamily: root.sansFamily
  property real fontSize: Math.round(15 * root.fontScale)
  property bool active: true
  property real edgeMargin: Math.round(8 * fontScale)
  property real anchorGap: Math.round(4 * fontScale)

  visible: root.active && anchorItem !== null && boundsItem !== null && consequence.trim() !== ""
  parent: root.boundsItem
  padding: 0
  clip: true
  width: Math.max(0, Math.min(root.tipAvailableWidth,
    Math.max(Math.round(160 * root.fontScale), implicitWidth)))
  height: Math.max(0, Math.min(implicitHeight,
    root.boundsItem ? root.boundsItem.height - root.edgeMargin * 2 : 0))

  contentItem: Text {
    textFormat: Text.PlainText
    text: root.text
    color: Color.tooltip.text
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    wrapMode: Text.Wrap
    width: Math.max(0, root.width - root.leftPadding - root.rightPadding)
    leftPadding: Style.spacing.controlPaddingX
    rightPadding: Style.spacing.controlPaddingX
    topPadding: Style.spacing.controlPaddingY
    bottomPadding: Style.spacing.controlPaddingY
  }

  background: Rectangle {
    color: Color.tooltip.background
    border.color: Color.tooltip.border
    border.width: 1
    radius: Style.cornerRadius
  }

  readonly property real tipAvailableWidth: Math.max(0,
    root.boundsItem ? root.boundsItem.width - root.edgeMargin * 2 : 0)

  function pointAt(offsetY) {
    if (!root.anchorItem || !root.boundsItem) return Qt.point(0, 0)
    return root.anchorItem.mapToItem(root.boundsItem, 0, offsetY)
  }

  x: {
    var point = root.pointAt(0)
    var maxX = Math.max(0, root.boundsItem ? root.boundsItem.width - width : 0)
    return Math.max(0, Math.min(maxX, point.x))
  }

  y: {
    var below = root.pointAt(root.anchorItem ? root.anchorItem.height + root.anchorGap : 0).y
    var above = root.pointAt(root.anchorItem ? -height - root.anchorGap : 0).y
    var bottom = root.boundsItem ? root.boundsItem.height - root.edgeMargin : 0
    var preferred = below + height <= bottom ? below : above
    return Math.max(root.edgeMargin, Math.min(Math.max(root.edgeMargin, bottom - height), preferred))
  }
}
