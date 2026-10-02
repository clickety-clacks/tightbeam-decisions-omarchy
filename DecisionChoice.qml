import QtQuick
import qs.Commons

Item {
  id: root

  required property string label
  required property string effect
  required property string rawOption
  required property int number
  property string density: "full"
  property bool armed: false
  property bool focused: false
  property bool focusActive: false
  property bool proposed: false
  property bool recording: false
  property bool interactive: true
  property bool tooltipsEnabled: true
  property real fontScale: 1
  property string sansFamily: ""
  property string sansMediumFamily: ""
  property string monoFamily: ""
  property color ground: Color.background
  property color ink: Color.foreground
  property color secondary: Color.foreground
  property color faint: Color.foreground
  property color hairline: Color.foreground
  property color keyBorder: Color.foreground

  signal activated()
  signal focusedByUser()
  signal consequenceHovered(bool hovered)

  readonly property bool outlined: armed || focused
  readonly property real horizontalPadding: Math.round(12 * fontScale)
  readonly property real verticalPadding: Math.round(10 * fontScale)
  readonly property real compactHeight: Math.round(38 * fontScale)
  readonly property real compactKeySize: Math.round(24 * fontScale)
  readonly property real textWidth: Math.max(0, width - horizontalPadding * 2 - keySize - keyGap)
  readonly property real keySize: density === "compact"
    ? compactKeySize : Math.round(24 * fontScale)
  readonly property real keyGap: Math.round(12 * fontScale)
  readonly property real fullHeight: verticalPadding + labelText.implicitHeight
    + (effectText.visible ? Math.round(2 * fontScale) + effectText.implicitHeight : 0)
    + (rawText.visible ? Math.round(3 * fontScale) + rawText.implicitHeight : 0)
    + (proposalText.visible ? Math.round(4 * fontScale) + proposalText.implicitHeight : 0)
    + verticalPadding
  readonly property real clampedHeight: verticalPadding * 2 + Math.round((19 * 1.35 + 2 + 17 * 1.45) * fontScale)
  readonly property real implicitRowHeight: density === "full"
    ? fullHeight : density === "clamped" ? clampedHeight : compactHeight

  implicitHeight: implicitRowHeight
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    color: root.outlined ? root.ground : "transparent"
    border.color: root.outlined ? root.ink : "transparent"
    border.width: root.outlined ? 1 : 0
    radius: Style.cornerRadius
  }

  Rectangle {
    visible: root.density !== "compact" && !root.outlined
    x: 0
    y: 0
    width: root.width
    height: 1
    color: root.hairline
  }

  Text {
    id: keycap
    x: root.density === "compact" ? Math.round(4 * root.fontScale) : root.width - width - Math.round(12 * root.fontScale)
    y: root.density === "compact" ? (root.height - height) / 2 : Math.round(12 * root.fontScale)
    width: root.keySize
    height: root.keySize
    text: String(root.number)
    color: root.secondary
    font.family: root.monoFamily
    font.pixelSize: Math.round(14 * root.fontScale)
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    Rectangle {
      anchors.fill: parent
      color: "transparent"
      border.color: root.keyBorder
      border.width: 1
      radius: Math.round(4 * root.fontScale)
    }
  }

  Text {
    id: labelText
    x: root.density === "compact"
      ? Math.round(4 * root.fontScale) + root.compactKeySize + Math.round(8 * root.fontScale)
      : root.horizontalPadding
    y: root.density === "compact"
      ? (root.height - height) / 2
      : root.verticalPadding
    width: root.density === "compact"
      ? Math.max(0, root.width - x - Math.round(8 * root.fontScale))
      : root.textWidth
    height: root.density === "full" ? implicitHeight : Math.round(20 * root.fontScale)
    text: root.recording ? "Recording…"
      : (root.proposed && root.density !== "full" ? "proposed · " + root.label : root.label)
    color: root.ink
    font.family: root.sansMediumFamily !== "" ? root.sansMediumFamily : root.sansFamily
    font.pixelSize: Math.round((root.density === "compact" ? 16 : 19) * root.fontScale)
    font.weight: Font.DemiBold
    font.variableAxes: ({ "wght": 600 })
    lineHeight: font.pixelSize * (root.density === "compact" ? 1.3 : 1.35)
    lineHeightMode: Text.FixedHeight
    wrapMode: root.density === "full" ? Text.Wrap : Text.NoWrap
    maximumLineCount: root.density === "full" ? 0 : 1
    elide: root.density === "full" ? Text.ElideNone : Text.ElideRight
  }

  Text {
    id: effectText
    visible: root.density !== "compact" && (root.recording || root.effect.trim() !== "")
    x: root.horizontalPadding
    y: labelText.y + labelText.implicitHeight + Math.round(2 * root.fontScale)
    width: root.textWidth
    text: root.recording ? "Recording…" : root.effect
    color: root.secondary
    font.family: root.sansFamily
    font.pixelSize: Math.round(17 * root.fontScale)
    lineHeight: font.pixelSize * 1.45
    lineHeightMode: Text.FixedHeight
    wrapMode: root.density === "full" ? Text.Wrap : Text.NoWrap
    maximumLineCount: root.density === "full" ? 0 : 1
    elide: root.density === "full" ? Text.ElideNone : Text.ElideRight
  }

  Text {
    id: rawText
    visible: root.density === "full" && !root.recording
    x: root.horizontalPadding
    y: (effectText.visible
      ? effectText.y + effectText.implicitHeight
      : labelText.y + labelText.implicitHeight) + Math.round(3 * root.fontScale)
    width: root.textWidth
    text: root.rawOption
    color: root.faint
    font.family: root.monoFamily
    font.pixelSize: Math.round(13 * root.fontScale)
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  Text {
    id: proposalText
    visible: root.density === "full" && root.proposed && !root.recording
    x: root.horizontalPadding
    y: rawText.visible
      ? rawText.y + rawText.implicitHeight + Math.round(4 * root.fontScale)
      : (effectText.visible
        ? effectText.y + effectText.implicitHeight
        : labelText.y + labelText.implicitHeight) + Math.round(4 * root.fontScale)
    width: root.textWidth
    text: "proposed in conversation"
    color: root.secondary
    font.family: root.monoFamily
    font.pixelSize: Math.round(12 * root.fontScale)
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  MouseArea {
    id: choiceMouse
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onPressed: root.focusedByUser()
    onClicked: root.activated()
  }

  HoverHandler {
    id: choiceHover
    enabled: root.tooltipsEnabled && root.interactive && root.density !== "full"
    cursorShape: Qt.PointingHandCursor
    onHoveredChanged: root.consequenceHovered(hovered)
  }
}
