import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons

// Agent settings and scroll motion (Ctrl+,). A real window, so it can be
// moved, and on Scottland scaled or turned into a widget like any other.
FloatingWindow {
  id: root
  visible: false
  title: "Tightbeam Decisions settings"
  color: Color.menu.background
  implicitWidth: Style.space(560)
  implicitHeight: Style.space(850)
  minimumSize: Qt.size(Style.space(420), Style.space(360))

  property real impulse: 335
  property real deceleration: 608
  readonly property real duration: impulse / deceleration
  readonly property real distance: impulse * impulse / (2 * deceleration)
  signal motionChanged(real impulse, real deceleration)
  signal resetRequested()

  function open() {
    visible = true
    agentSettings.reload()
    curve.requestPaint()
  }

  function setFromEndpoint(seconds, pixels) {
    var t = Math.max(0.08, Math.min(2.5, seconds))
    var d = Math.max(4, Math.min(600, pixels))
    // s(t) = v₀t - ½at², with v(t)=0 at the endpoint.
    // Therefore v₀=2s/t and a=2s/t².
    motionChanged(2 * d / t, 2 * d / (t * t))
  }

  Shortcut { sequence: "Escape"; onActivated: root.visible = false }
  Shortcut { sequence: "Ctrl+,"; onActivated: root.visible = false }

  Rectangle {
    id: tunerCard
    anchors.fill: parent
    color: Color.menu.background

    Flickable {
      anchors.fill: parent
      anchors.margins: Style.space(28)
      anchors.topMargin: Style.space(28) + closeButton.height
      clip: true
      contentHeight: settingsColumn.implicitHeight
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: settingsColumn
        width: parent.width
        spacing: Style.space(14)

      ModelSettings { id: agentSettings; width: parent.width }
      Rectangle { width: parent.width; height: 1; color: Color.menu.border }

      Text {
        width: parent.width
        text: "Decision scroll motion"
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Text {
        width: parent.width
        text: "Drag the endpoint. Right means a longer coast; up means farther travel. The curve is the decision transcript’s position after one navigation-key impulse."
        color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.62)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
      }

      Rectangle {
        id: graph
        width: parent.width
        height: Style.space(250)
        color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.035)
        border.color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.14)
        border.width: 1
        radius: Style.cornerRadius

        Canvas {
          id: curve
          anchors.fill: parent
          property real leftPad: Style.space(48)
          property real rightPad: Style.space(24)
          property real topPad: Style.space(24)
          property real bottomPad: Style.space(42)
          readonly property real plotWidth: width - leftPad - rightPad
          readonly property real plotHeight: height - topPad - bottomPad
          readonly property real endX: leftPad + Math.min(1, root.duration / 2.5) * plotWidth
          readonly property real endY: height - bottomPad - Math.min(1, root.distance / 600) * plotHeight

          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          Connections {
            target: root
            function onImpulseChanged() { curve.requestPaint() }
            function onDecelerationChanged() { curve.requestPaint() }
          }

          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var bottom = height - bottomPad
            var right = width - rightPad

            ctx.lineWidth = 1
            ctx.strokeStyle = Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.18)
            ctx.beginPath()
            ctx.moveTo(leftPad, topPad)
            ctx.lineTo(leftPad, bottom)
            ctx.lineTo(right, bottom)
            ctx.stroke()

            ctx.lineWidth = Math.max(2, Style.space(2))
            ctx.strokeStyle = Color.accent
            ctx.beginPath()
            for (var index = 0; index <= 48; index++) {
              var u = index / 48
              var seconds = root.duration * u
              var pixels = root.impulse * seconds
                - 0.5 * root.deceleration * seconds * seconds
              var x = leftPad + (seconds / 2.5) * plotWidth
              var y = bottom - (pixels / 600) * plotHeight
              if (index === 0) ctx.moveTo(x, y)
              else ctx.lineTo(x, y)
            }
            ctx.stroke()

            ctx.fillStyle = Color.accent
            ctx.beginPath()
            ctx.arc(endX, endY, Style.space(7), 0, Math.PI * 2)
            ctx.fill()
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onPressed: function(mouse) { update(mouse.x, mouse.y) }
            onPositionChanged: function(mouse) { if (pressed) update(mouse.x, mouse.y) }
            function update(x, y) {
              var seconds = (x - curve.leftPad) / curve.plotWidth * 2.5
              var pixels = (curve.height - curve.bottomPad - y) / curve.plotHeight * 600
              root.setFromEndpoint(seconds, pixels)
            }
          }
        }

        Text {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.leftMargin: Style.space(10)
          anchors.bottomMargin: Style.space(10)
          text: "distance"
          color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.42)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Text {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: Style.space(12)
          anchors.bottomMargin: Style.space(10)
          text: "time →"
          color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.42)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(22)

        Text {
          text: "impulse  " + Math.round(root.impulse) + " px/s"
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Text {
          text: "friction  " + Math.round(root.deceleration) + " px/s²"
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Text {
          text: root.distance.toFixed(0) + " px · " + root.duration.toFixed(2) + " s"
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }

        Rectangle {
          width: resetLabel.implicitWidth + Style.space(22)
          height: Style.space(34)
          radius: Style.cornerRadius
          color: resetMouse.containsMouse
            ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
            : "transparent"
          border.color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.22)
          Text {
            id: resetLabel
            anchors.centerIn: parent
            text: "Reset"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          MouseArea {
            id: resetMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.resetRequested()
          }
        }
      }
    }
    Button {
      id: closeButton
      objectName: "closeSettings"
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Style.space(14)
      anchors.rightMargin: Style.space(14)
      width: Style.space(32)
      height: width
      padding: 0
      z: 10
      Accessible.name: "Close settings"
      background: Rectangle {
        radius: width / 2
        color: closeButton.hovered ? Color.accent : Color.menu.background
        border.color: Color.menu.text
        border.width: Math.max(1, Style.space(2))
      }
      contentItem: Item {
        Repeater {
          model: [45, -45]
          Rectangle {
            required property real modelData
            anchors.centerIn: parent
            width: Style.space(14)
            height: Style.space(2)
            rotation: modelData
            color: closeButton.hovered ? Color.menu.background : Color.menu.text
          }
        }
      }
      onClicked: root.visible = false
    }
  }
}
