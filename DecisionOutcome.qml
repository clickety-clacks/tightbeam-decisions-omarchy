import QtQuick
import qs.Commons

FocusScope {
  id: root

  required property string status
  required property string determination
  required property string question
  property real fontScale: 1
  property string newsreaderFamily: ""
  property string sansFamily: ""
  property string monoFamily: ""
  property color ground: Color.background
  property color panel: Color.menu.background
  property color foreground: Color.foreground
  property color secondary: Color.foreground
  property color hairline: Color.foreground

  signal closeRequested()

  readonly property real outerMargin: Math.round(12 * fontScale)
  readonly property real innerMargin: Math.round((width < 440 ? 20 : 32) * fontScale)

  function focusModal() { forceActiveFocus() }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.closeRequested()
      event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    color: root.ground
    opacity: 0.96
  }

  MouseArea { anchors.fill: parent }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.max(0, Math.min(root.width - root.outerMargin * 2,
      Math.max(560 * root.fontScale, Math.min(900 * root.fontScale, root.width * 0.82))))
    height: Math.max(0, Math.min(root.height - root.outerMargin * 2,
      Math.max(380 * root.fontScale, Math.min(820 * root.fontScale, root.height * 0.78))))
    radius: Style.cornerRadius
    color: root.panel
    border.color: root.hairline
    border.width: 1

    Column {
      id: heading
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: root.innerMargin
      spacing: Math.round(8 * root.fontScale)

      Text {
        visible: card.height >= 420 * root.fontScale
        width: parent.width
        text: "DECISION REQUEST"
        color: root.secondary
        font.family: root.monoFamily
        font.pixelSize: Math.round(13 * root.fontScale)
        font.letterSpacing: Math.round(1.2 * root.fontScale)
      }

      Text {
        width: parent.width
        text: root.status === "ruled" ? "Ruled" : "Request handled"
        color: root.foreground
        font.family: root.newsreaderFamily
        font.pixelSize: Math.round((card.height < 420 ? 34 : 46) * root.fontScale)
        wrapMode: Text.Wrap
      }

      Text {
        visible: card.height >= 420 * root.fontScale
        width: parent.width
        text: root.question
        color: root.secondary
        font.family: root.sansFamily
        font.pixelSize: Math.round(18 * root.fontScale)
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
      }
    }

    Rectangle {
      id: divider
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: root.innerMargin
      anchors.rightMargin: root.innerMargin
      anchors.top: heading.bottom
      anchors.topMargin: Math.round((card.height < 420 * root.fontScale ? 10 : 16) * root.fontScale)
      height: 1
      color: root.hairline
    }

    Text {
      id: rulingLabel
      visible: card.height >= 420 * root.fontScale
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: root.innerMargin
      anchors.rightMargin: root.innerMargin
      anchors.top: divider.bottom
      anchors.topMargin: visible ? Math.round(18 * root.fontScale) : 0
      text: root.status === "ruled" ? "THE RULING" : root.status.toUpperCase()
      color: root.secondary
      font.family: root.monoFamily
      font.pixelSize: Math.round(13 * root.fontScale)
      font.letterSpacing: Math.round(1.2 * root.fontScale)
    }

    Flickable {
      id: rulingScroll
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: root.innerMargin
      anchors.rightMargin: root.innerMargin
      anchors.top: rulingLabel.visible ? rulingLabel.bottom : divider.bottom
      anchors.topMargin: rulingLabel.visible ? Math.round(10 * root.fontScale) : 0
      anchors.bottom: closeButton.top
      anchors.bottomMargin: Math.round(22 * root.fontScale)
      clip: true
      contentHeight: Math.max(height, rulingText.implicitHeight)
      interactive: contentHeight > height

      Text {
        id: rulingText
        y: Math.max(0, (rulingScroll.height - implicitHeight) / 2)
        width: rulingScroll.width
        text: root.determination
        color: root.foreground
        font.family: root.newsreaderFamily
        font.pixelSize: Math.round((card.height < 420 ? 25 : 32) * root.fontScale)
        wrapMode: Text.Wrap
        lineHeight: 1.2
      }
    }

    Rectangle {
      id: closeButton
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: root.innerMargin
      height: Math.round(Math.min(68 * root.fontScale, card.height * 0.20))
      radius: Style.cornerRadius
      color: root.foreground

      Text {
        anchors.centerIn: parent
        text: "Close"
        color: root.panel
        font.family: root.sansFamily
        font.pixelSize: Math.round(22 * root.fontScale)
        font.weight: Font.DemiBold
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.closeRequested()
      }
    }
  }
}
