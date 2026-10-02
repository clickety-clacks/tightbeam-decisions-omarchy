import QtQuick
import qs.Commons

Item {
  id: root

  required property var choices
  property int columns: 2
  property bool showLabel: true
  property bool showExplain: false
  property string hint: ""
  property real fontScale: 1
  property int armedIndex: -1
  property int focusedIndex: -1
  property int proposedIndex: -1
  property bool focusActive: false
  property bool interactive: true
  property string recordingChoice: ""
  property string sansFamily: ""
  property string sansMediumFamily: ""
  property string monoFamily: ""
  property color ground: Color.background
  property color panel: Color.background
  property color ink: Color.foreground
  property color secondary: Color.foreground
  property color faint: Color.foreground
  property color hairline: Color.foreground
  property color keyBorder: Color.foreground

  signal choiceActivated(int index)
  signal choiceFocused(int index)
  signal explainRequested()

  readonly property real horizontalPadding: Math.round(16 * fontScale)
  readonly property real verticalPadding: Math.round(10 * fontScale)
  readonly property real headerHeight: Math.round(20 * fontScale)
  readonly property real gap: Math.round(6 * fontScale)
  readonly property real rowHeight: Math.round(34 * fontScale)
  readonly property int safeColumns: Math.max(1, columns)
  readonly property int rowCount: Math.ceil((choices || []).length / safeColumns)
  readonly property real gridHeight: rowCount * rowHeight
    + Math.max(0, rowCount - 1) * Math.round(2 * fontScale)

  implicitHeight: verticalPadding + (showLabel ? headerHeight + gap : 0)
    + gridHeight + verticalPadding
  height: implicitHeight
  clip: true

  Rectangle {
    anchors.fill: parent
    color: root.panel
  }

  Text {
    visible: root.showLabel
    x: root.horizontalPadding
    y: root.verticalPadding
    width: Math.max(0, root.width - root.horizontalPadding * 2 - explainButton.width - root.gap)
    height: root.headerHeight
    text: "DECIDE"
    color: root.ink
    font.family: root.monoFamily
    font.pixelSize: Math.round(11 * root.fontScale)
    font.weight: Font.Medium
    font.letterSpacing: Math.round(1.3 * root.fontScale)
    verticalAlignment: Text.AlignVCenter
  }

  Text {
    id: explainButton
    visible: root.showExplain || root.hint !== ""
    x: Math.max(0, root.width - width - root.horizontalPadding)
    y: root.verticalPadding
    width: Math.max(0, Math.min(root.width - root.horizontalPadding * 2, implicitWidth))
    height: root.headerHeight
    text: root.hint !== "" ? root.hint : (root.showExplain ? "explain choices ↑" : "")
    color: root.secondary
    font.family: root.monoFamily
    font.pixelSize: Math.round(11 * root.fontScale)
    elide: Text.ElideLeft
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignRight

    MouseArea {
      anchors.fill: parent
      enabled: root.showExplain
      cursorShape: Qt.PointingHandCursor
      onClicked: root.explainRequested()
    }
  }

  Item {
    id: grid
    x: root.horizontalPadding
    y: root.verticalPadding + (root.showLabel ? root.headerHeight + root.gap : 0)
    width: Math.max(0, root.width - root.horizontalPadding * 2)
    height: root.gridHeight
    readonly property real rowGap: Math.round(2 * root.fontScale)
    readonly property real columnGap: Math.round(8 * root.fontScale)
    readonly property real cellWidth: Math.max(0,
      (width - (root.safeColumns - 1) * columnGap) / root.safeColumns)

    Repeater {
      model: root.choices || []
      delegate: DecisionChoice {
        required property var modelData
        required property int index
        x: (index % root.safeColumns) * (grid.cellWidth + grid.columnGap)
        y: Math.floor(index / root.safeColumns) * (root.rowHeight + grid.rowGap)
        width: grid.cellWidth
        height: root.rowHeight
        density: "compact"
        label: String(modelData.label || "")
        effect: String(modelData.effect || "")
        rawOption: String(modelData.rawOption || "")
        number: Number(modelData.number || index + 1)
        armed: root.armedIndex === index
        focused: root.focusedIndex === index
        focusActive: root.focusActive
        proposed: root.proposedIndex === index
        recording: root.recordingChoice !== ""
          && String(modelData.rawOption || "") === root.recordingChoice
        interactive: root.interactive && !modelData.disabled
        fontScale: root.fontScale
        sansFamily: root.sansFamily
        sansMediumFamily: root.sansMediumFamily
        monoFamily: root.monoFamily
        ground: root.ground
        ink: root.ink
        secondary: root.secondary
        faint: root.faint
        hairline: root.hairline
        keyBorder: root.keyBorder
        onFocusedByUser: root.choiceFocused(index)
        onActivated: root.choiceActivated(index)
      }
    }
  }
}
