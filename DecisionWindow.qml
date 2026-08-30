import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

FloatingWindow {
    id: root
    visible: false
    required property var owner
  required property var request
  signal detailClosed(var window)
  property bool openedOnce: false
  property bool closing: false
  property real headerSplit: -1
  readonly property real headerSplitMin: Style.space(44)
  readonly property real headerSplitMax: Math.round(root.height * 0.75)
  readonly property real headerAutoHeight: Math.min(detailHeader.implicitHeight, Math.round(root.height * 0.45))
  readonly property real headerHeight: headerSplit < 0 ? headerAutoHeight : Math.max(headerSplitMin, Math.min(headerSplitMax, headerSplit))
  readonly property color foreground: owner.foreground
  readonly property color urgent: owner.urgent
  readonly property color dim: owner.dim
  readonly property string fontFamily: owner.fontFamily
  readonly property int captionSize: owner.captionSize
  readonly property int bodySize: owner.bodySize
  readonly property int titleSize: owner.titleSize
  readonly property real fontScale: owner.fontScale
  readonly property string tbHost: owner.tbHost
  readonly property string tbAsUser: owner.tbAsUser
  property string parentSummary: ""
  property string noteSummary: ""
  property string summaryRaw: ""
  property bool replying: false
  property string selectedChoice: ""
  property string statusText: ""
  property bool handled: false
  property string handledStatus: "handled"
  property string handledActor: ""
  property string handledDetermination: "Loading the recorded outcome…"

  function mixColor(from, to, amount) { return owner.mixColor(from, to, amount) }
  function script(name) { return owner.script(name) }
  function handleFontKey(event) { return owner.handleFontKey(event) }
  function handleHeaderKey(event) { return handleFontKey(event) || chat.handleMotionTunerKey(event) || chat.handleScrollKey(event, false) }
  function copyToClipboard(value) { owner.copyToClipboard(value) }
  function summaryPrompt() {
    return ["Summarize two UI fields. Do not use tools. Return ONLY one JSON object on one line.",
      "Schema: {\"parent\":\"2-6 plain words\",\"notes\":\"one short line, at most 12 words\"}",
      "Use an empty string when a field is empty. Do not include ids or labels.",
      "PARENT:", String(request.subject || ""), "NOTES:", String(request.note || "")].join("\n")
  }
  function cleanSummary(value, limit) {
    var text = String(value || "").replace(/\s+/g, " ").trim()
    return text.length > limit ? text.substring(0, limit - 1).trim() + "…" : text
  }
  function handleSummaryLine(rawLine) {
    var line = String(rawLine || "").trim()
    if (line === "") return
    try {
      var event = JSON.parse(line)
      if (event.type === "ready") summaryProcess.write(JSON.stringify({ type: "prompt", text: summaryPrompt() }) + "\n")
      else if (event.type === "text") summaryRaw += String(event.text || "")
      else if (event.type === "done") {
        var start = summaryRaw.indexOf("{")
        var end = summaryRaw.lastIndexOf("}")
        if (start >= 0 && end > start) {
          var result = JSON.parse(summaryRaw.substring(start, end + 1))
          parentSummary = cleanSummary(result.parent, 80)
          noteSummary = cleanSummary(result.notes, 140)
        }
      }
    } catch (error) {}
  }
  function submitChoice(choiceLabel) {
    if (replying) {
      chat.decisionStatus = "Already recording a decision…"
      return
    }
    replying = true
    selectedChoice = String(choiceLabel)
    chat.decisionStatus = "Recording “" + String(choiceLabel) + "”…"
    replyProcess.command = [script("reply.sh"), tbHost, tbAsUser, request.id, String(choiceLabel)]
    replyProcess.running = true
  }
  function open() {
    openedOnce = true
    visible = true
    summaryProcess.running = true
    chat.request = request
    chat.start()
    Qt.callLater(function() { detailFocus.forceActiveFocus() })
  }
  function closeWindow() { visible = false }
  function markHandled() {
    if (handled) return
    replying = false
    handled = true
    chat.stop()
    summaryProcess.running = false
    handledProcess.command = [script("handled.sh"), tbHost, tbAsUser, request.id]
    handledProcess.running = true
  }
  function applyHandledPayload(raw) {
    try {
      var payload = JSON.parse(String(raw || ""))
      handledStatus = String(payload.status || "handled")
      handledActor = String(payload.actor || "")
      handledDetermination = String(payload.determination || "The request is no longer open.")
    } catch (error) {
      handledDetermination = "The request is no longer open; its recorded outcome could not be loaded."
    }
  }

  Process {
    id: summaryProcess
    command: ["env", "HUGINN_INTERNAL=1", "node", root.script("summary-bridge.js")]
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.handleSummaryLine(line) } }
  }
  Process {
    id: replyProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") chat.decisionStatus = String(text).trim()
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") chat.decisionStatus = String(text).trim()
    }
    onExited: function(code) {
      if (code === 0) root.owner.refreshNow()
      else {
        root.replying = false
        if (chat.decisionStatus === "" || chat.decisionStatus.indexOf("Recording “") === 0)
          chat.decisionStatus = "Could not record that decision."
      }
    }
  }
  Process {
    id: handledProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyHandledPayload(text) }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "")
        root.handledDetermination = "The request is no longer open; its recorded outcome could not be loaded."
    }
  }

  title: root.request ? "Decision request — " + root.request.id : "Decision request"
    color: Color.background
    implicitWidth: Math.round(820 * root.fontScale)
    implicitHeight: Math.round(760 * root.fontScale)
    minimumSize: Qt.size(560, 480)
    onVisibleChanged: if (!visible && openedOnce && !closing) {
      closing = true
      chat.stop()
      summaryProcess.running = false
      detailClosed(root)
    }
    // Hyprland can briefly withdraw the backing surface while it reloads.
    // Keep the QML window alive; `visible` changing above is the real close.

  component IdPill: Rectangle {
    id: idPill
    required property string label
    required property string value
    property bool copied: false

    visible: value !== ""
    width: idLabel.implicitWidth + Style.space(24)
    height: Style.space(34)
    radius: height / 2
    color: idMouse.containsMouse
      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.13)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)

    Text {
      id: idLabel
      anchors.centerIn: parent
      text: idPill.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: root.captionSize
      font.bold: true
    }

    MouseArea {
      id: idMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.ArrowCursor
      onEntered: {
        idHoverClose.stop()
        idHoverOpen.restart()
      }
      onExited: {
        idHoverOpen.stop()
        idHoverClose.restart()
      }
    }

    function placePopup() {
      var point = idPill.mapToItem(detailFocus, 0, 0)
      var margin = Style.space(8)
      var minX = margin - point.x
      var maxX = detailFocus.width - margin - point.x - idHoverPopup.width
      idHoverPopup.x = Math.max(minX, Math.min(0, maxX))
      var below = idPill.height + Style.space(5)
      var wantedY = point.y + below + idHoverPopup.height <= detailFocus.height - margin
        ? below
        : -idHoverPopup.height - Style.space(5)
      var minY = margin - point.y
      var maxY = detailFocus.height - margin - point.y - idHoverPopup.height
      idHoverPopup.y = Math.max(minY, Math.min(wantedY, maxY))
    }

    Timer {
      id: idHoverOpen
      interval: 500
      onTriggered: if (idMouse.containsMouse) {
        idPill.placePopup()
        idHoverPopup.open()
        Qt.callLater(idPill.placePopup)
      }
    }

    Timer {
      id: idHoverClose
      interval: 180
      onTriggered: if (!idMouse.containsMouse && !idPopupHover.hovered) idHoverPopup.close()
    }

    Timer {
      id: copyReset
      interval: 1200
      repeat: false
      onTriggered: idPill.copied = false
    }

    Popup {
      id: idHoverPopup
      x: 0
      y: idPill.height + Style.space(5)
      width: Math.min(detailHeader.width, idHoverText.implicitWidth + Style.space(76))
      height: Style.space(46)
      padding: Style.space(10)
      modal: false
      focus: false
      closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

      background: Rectangle {
        color: Color.tooltip.background
        border.color: Color.tooltip.border
        border.width: 1
        radius: Style.cornerRadius
      }

      contentItem: Item {
        TextEdit {
          id: idHoverText
          anchors.left: copyTarget.right
          anchors.right: parent.right
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          height: contentHeight
          text: idPill.value
          color: Color.tooltip.text
          font.family: root.fontFamily
          font.pixelSize: root.captionSize
          readOnly: true
          selectByMouse: true
          activeFocusOnPress: true
          Keys.onPressed: function(event) { if (root.handleHeaderKey(event)) event.accepted = true }
        }

        Item {
          id: copyTarget
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(26)
          height: width

          Text {
            anchors.centerIn: parent
            text: "󰆏"
            color: Color.tooltip.text
            font.family: root.fontFamily
            font.pixelSize: root.bodySize
            opacity: idPill.copied ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 180 } }
          }

          Rectangle {
            anchors.centerIn: parent
            width: Style.space(21)
            height: width
            radius: width / 2
            color: "#35b968"
            opacity: idPill.copied ? 1 : 0
            scale: idPill.copied ? 1 : 0.78
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
            Text {
              anchors.centerIn: parent
              text: "󰄬"
              color: "white"
              font.family: root.fontFamily
              font.pixelSize: root.captionSize
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.copyToClipboard(idPill.value)
              idPill.copied = true
              copyReset.restart()
            }
          }
        }

        HoverHandler {
          id: idPopupHover
          onHoveredChanged: {
            if (hovered) idHoverClose.stop()
            else idHoverClose.restart()
          }
        }
      }
    }
  }

  component SummaryPill: Rectangle {
    id: summaryPill
    required property string icon
    required property string summary
    required property string fullText
    readonly property string displayText: icon + (summary === "" ? "" : "  " + summary)

    visible: fullText !== ""
    width: Math.max(height, Math.min(summaryLabel.implicitWidth + Style.space(24), detailHeader.width))
    height: Style.space(34)
    radius: height / 2
    color: summaryMouse.containsMouse
      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.13)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)

    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    Text {
      id: summaryLabel
      anchors.fill: parent
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      text: summaryPill.displayText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: root.captionSize
      font.bold: summaryPill.summary === ""
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
      maximumLineCount: 1
      opacity: summaryPill.summary === "" ? 0.72 : 1
      Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    MouseArea {
      id: summaryMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.ArrowCursor
      onEntered: {
        hoverClose.stop()
        hoverOpen.restart()
      }
      onExited: {
        hoverOpen.stop()
        hoverClose.restart()
      }
    }

    function placePopup() {
      var point = summaryPill.mapToItem(detailFocus, 0, 0)
      var margin = Style.space(8)
      var minX = margin - point.x
      var maxX = detailFocus.width - margin - point.x - hoverPopup.width
      hoverPopup.x = Math.max(minX, Math.min(0, maxX))
      var below = summaryPill.height + Style.space(5)
      var wantedY = point.y + below + hoverPopup.height <= detailFocus.height - margin
        ? below
        : -hoverPopup.height - Style.space(5)
      var minY = margin - point.y
      var maxY = detailFocus.height - margin - point.y - hoverPopup.height
      hoverPopup.y = Math.max(minY, Math.min(wantedY, maxY))
    }

    Timer {
      id: hoverOpen
      interval: 500
      onTriggered: if (summaryMouse.containsMouse) {
        summaryPill.placePopup()
        hoverPopup.open()
        Qt.callLater(summaryPill.placePopup)
      }
    }

    Timer {
      id: hoverClose
      interval: 180
      onTriggered: if (!summaryMouse.containsMouse && !popupHover.hovered) hoverPopup.close()
    }

    Popup {
      id: hoverPopup
      x: 0
      y: summaryPill.height + Style.space(5)
      width: Math.min(Style.space(560), detailHeader.width)
      height: Math.min(hoverContents.implicitHeight + Style.space(24),
                       detailFocus.height - Style.space(16))
      padding: Style.space(12)
      modal: false
      focus: false
      closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

      background: Rectangle {
        color: Color.tooltip.background
        border.color: Color.tooltip.border
        border.width: 1
        radius: Style.cornerRadius
      }

      contentItem: Flickable {
        id: hoverViewport
        clip: true
        contentWidth: width
        contentHeight: hoverContents.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: hoverContents
          width: hoverViewport.width
          spacing: Style.space(8)

          TextEdit {
            width: parent.width
            visible: summaryPill.summary !== ""
            height: visible ? contentHeight : 0
            text: summaryPill.summary
            color: Color.tooltip.text
            font.family: root.fontFamily
            font.pixelSize: root.captionSize
            font.italic: true
            wrapMode: TextEdit.Wrap
            readOnly: true
          }

          TextEdit {
            width: parent.width
            text: summaryPill.fullText
            color: Color.tooltip.text
            font.family: root.fontFamily
            font.pixelSize: root.captionSize
            wrapMode: TextEdit.Wrap
            readOnly: true
            selectByMouse: true
          }
        }
      }

      HoverHandler {
        id: popupHover
        onHoveredChanged: {
          if (hovered) hoverClose.stop()
          else hoverClose.restart()
        }
      }
    }
  }

    FocusScope {
      id: detailFocus
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (root.handleFontKey(event) || chat.handleMotionTunerKey(event) || chat.handleScrollKey(event, false)) event.accepted = true
      }

      Item {
        anchors.fill: parent
        anchors.margins: Style.space(24)

        // Capping each field and clipping meant a long question simply vanished
        // below the fold with no way to reach it. The fields size to their
        // content now and the header as a whole scrolls, bounded so it cannot
        // crowd out the conversation beneath it.
        Flickable {
          id: detailHeaderScroll
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.headerHeight
          contentHeight: detailHeader.implicitHeight
          clip: true
          // Preserve the pointer's release velocity instead of making a drag
          // feel as though it stops under the mouse. The lower deceleration
          // gives quick throws room to coast; StopAtBounds still prevents any
          // rubber-band travel beyond the header.
          maximumFlickVelocity: 6000
          flickDeceleration: 650
          boundsBehavior: Flickable.StopAtBounds
          onDraggingChanged: if (dragging) headerTrackpadCoast.stop()

          NumberAnimation {
            id: headerTrackpadCoast
            target: detailHeaderScroll
            property: "contentY"
            easing.type: Easing.OutQuint
          }

          WheelHandler {
            id: headerTrackpad
            target: null
            blocking: true
            acceptedButtons: Qt.NoButton
            // Qt/Wayland may expose a touchpad's two-finger scroll stream as
            // either device class. Pixel deltas distinguish it from a wheel.
            acceptedDevices: PointerDevice.TouchPad | PointerDevice.Mouse
            property double lastSampleTime: 0
            property real releaseVelocityY: 0
            function coast() {
              releaseTimer.stop()
              headerTrackpadCoast.stop()
              var speed = Math.min(detailHeaderScroll.maximumFlickVelocity,
                Math.abs(releaseVelocityY))
              if (speed > 40) {
                var direction = releaseVelocityY > 0 ? -1 : 1
                var distance = speed * speed / (2 * detailHeaderScroll.flickDeceleration)
                var maxY = Math.max(0, detailHeaderScroll.contentHeight - detailHeaderScroll.height)
                var destination = Math.max(0, Math.min(maxY,
                  detailHeaderScroll.contentY + direction * distance))
                if (Math.abs(destination - detailHeaderScroll.contentY) > 1) {
                  headerTrackpadCoast.from = detailHeaderScroll.contentY
                  headerTrackpadCoast.to = destination
                  headerTrackpadCoast.duration = Math.max(900, Math.min(2800,
                    Math.round(speed * 1800 / detailHeaderScroll.flickDeceleration)))
                  headerTrackpadCoast.start()
                }
              }
              lastSampleTime = 0
              releaseVelocityY = 0
            }
            onWheel: function(wheel) {
              if (wheel.pixelDelta.x === 0 && wheel.pixelDelta.y === 0) {
                var steps = wheel.angleDelta.y / 120
                var maxWheelY = Math.max(0, detailHeaderScroll.contentHeight - detailHeaderScroll.height)
                detailHeaderScroll.contentY = Math.max(0, Math.min(maxWheelY,
                  detailHeaderScroll.contentY - steps * Style.space(132)))
                wheel.accepted = true
                return
              }
              headerTrackpadCoast.stop()
              detailHeaderScroll.cancelFlick()
              var now = Date.now()
              var firstSample = wheel.phase === Qt.ScrollBegin || lastSampleTime === 0
              if (firstSample) {
                lastSampleTime = now
                releaseVelocityY = 0
              }
              if (wheel.phase === Qt.ScrollEnd) {
                coast()
                wheel.accepted = true
                return
              }
              var elapsed = firstSample ? 16 : Math.max(1, Math.min(80, now - lastSampleTime))
              var dy = wheel.pixelDelta.y
              var maxY = Math.max(0, detailHeaderScroll.contentHeight - detailHeaderScroll.height)
              detailHeaderScroll.contentY = Math.max(0, Math.min(maxY, detailHeaderScroll.contentY - dy))
              releaseVelocityY = releaseVelocityY * 0.55 + dy * 1000 / elapsed * 0.45
              lastSampleTime = now
              releaseTimer.restart()
              wheel.accepted = true
            }
          }

          Timer { id: releaseTimer; interval: 55; onTriggered: headerTrackpad.coast() }

        Column {
          id: detailHeader
          width: detailHeaderScroll.width
          spacing: Style.space(6)

          Text {
            text: (root.request ? root.owner.poForRequest(root.request) : "UNASSIGNED")
              + " DECISION REQUEST"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.captionSize
            font.bold: true
            font.letterSpacing: 1.5
          }
          TextEdit {
            width: detailHeader.width
            text: root.request ? root.request.question : ""
            color: Color.foreground
            font.family: root.fontFamily
            font.pixelSize: root.titleSize
            font.bold: true
            wrapMode: TextEdit.Wrap
            readOnly: true
            selectByMouse: true
            clip: true
            activeFocusOnPress: true
            Keys.onPressed: function(event) { if (root.handleHeaderKey(event)) event.accepted = true }
          }
          Flow {
            width: detailHeader.width
            spacing: Style.space(6)

            SummaryPill {
              icon: "󰙅"
              summary: root.parentSummary
              fullText: root.request ? String(root.request.subject || "") : ""
            }
            SummaryPill {
              icon: "󰎞"
              summary: root.noteSummary
              fullText: root.request ? String(root.request.note || "") : ""
            }
            IdPill {
              id: decisionIdPill
              label: "decision request"
              value: root.request ? String(root.request.id || "") : ""
            }
            IdPill {
              id: assignmentIdPill
              label: "assignment"
              value: root.request ? String(root.request.assignmentId || "") : ""
            }
            IdPill {
              id: workItemIdPill
              label: "work item"
              value: root.request ? String(root.request.workItemId || "") : ""
            }
          }
        }
        }

        // The fixed header reads as its own surface rather than as content
        // above a line. Negative margins cancel the content inset so the band
        // meets the window edges; z keeps it behind the header text.
        Rectangle {
          id: detailHeaderBand
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: -Style.space(24)
          anchors.leftMargin: -Style.space(24)
          anchors.rightMargin: -Style.space(24)
          height: detailHeaderScroll.height + Style.space(24) + Style.space(16)
          color: root.mixColor(Color.background, root.foreground, 0.07)
          z: -1
        }

        // Drag to move the split; double-click to hand it back to auto.
        MouseArea {
          id: splitGrip
          anchors.top: detailHeaderBand.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: -Style.space(24)
          anchors.rightMargin: -Style.space(24)
          anchors.topMargin: -Style.space(5)
          height: Style.space(10)
          cursorShape: Qt.SizeVerCursor
          hoverEnabled: true
          z: 2
          property real pressScreenY: 0
          property real pressHeight: 0
          onPressed: function(mouse) {
            pressScreenY = mapToItem(null, mouse.x, mouse.y).y
            pressHeight = root.headerHeight
          }
          onPositionChanged: function(mouse) {
            if (!pressed) return
            root.headerSplit = pressHeight + (mapToItem(null, mouse.x, mouse.y).y - pressScreenY)
          }
          onDoubleClicked: root.headerSplit = -1

          Rectangle {
            anchors.centerIn: parent
            width: Style.space(46)
            height: 2
            radius: 1
            color: splitGrip.containsMouse || splitGrip.pressed
              ? root.foreground
              : root.mixColor(Color.background, root.foreground, 0.28)
          }
        }

        DecisionChat {
          id: chat
          anchors.top: detailHeaderBand.bottom
          anchors.topMargin: Style.space(14)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          host: root.tbHost
          user: root.tbAsUser
          fontScale: root.fontScale
          keyboardLineImpulse: root.owner.keyboardLineImpulse
          keyboardPageImpulse: root.owner.keyboardPageImpulse
          keyboardDeceleration: root.owner.keyboardDeceleration
          motionTunerOpen: root.owner.motionTunerOpen
          decisionBusy: root.replying
          messageScript: root.script("message.sh")
          onRuleRequested: function(choiceLabel) { root.submitChoice(choiceLabel) }
          onFontStepRequested: function(step) { root.owner.adjustFontScale(step) }
          onFontResetRequested: root.owner.setFontScale(1)
          onMotionTunerRequested: root.owner.openMotionTuner()
        }

        Rectangle {
          anchors.fill: parent
          anchors.margins: -Style.space(24)
          visible: root.replying && !root.handled
          z: 90
          color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.78)

          MouseArea { anchors.fill: parent }

          Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - Style.space(40), Style.space(420))
            height: busyContents.implicitHeight + Style.space(48)
            radius: Style.cornerRadius
            color: Color.menu.background
            border.color: root.mixColor(Color.menu.background, root.foreground, 0.28)
            border.width: 1

            Column {
              id: busyContents
              anchors.centerIn: parent
              width: parent.width - Style.space(48)
              spacing: Style.space(14)

              BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: root.replying
              }
              Text {
                width: parent.width
                text: "Recording “" + root.selectedChoice + "”…"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: root.bodySize
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
              }
            }
          }
        }

        Rectangle {
          anchors.fill: parent
          anchors.margins: -Style.space(24)
          visible: root.handled
          z: 100
          color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.82)

          MouseArea { anchors.fill: parent }

          Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - Style.space(40), Style.space(520))
            implicitHeight: handledContents.implicitHeight + Style.space(48)
            height: implicitHeight
            radius: Style.cornerRadius
            color: Color.menu.background
            border.color: root.mixColor(Color.menu.background, root.foreground, 0.28)
            border.width: 1

            Column {
              id: handledContents
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(24)
              spacing: Style.space(14)

              Text {
                width: parent.width
                text: "Decision request handled"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: root.titleSize
                font.bold: true
                wrapMode: Text.Wrap
              }
              TextEdit {
                width: parent.width
                text: (root.handledActor === "" ? "" : root.handledActor + " · ")
                  + root.handledStatus + "\n\n" + root.handledDetermination
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: root.bodySize
                wrapMode: TextEdit.Wrap
                readOnly: true
                selectByMouse: true
              }
              Button {
                anchors.right: parent.right
                text: "Close"
                onClicked: root.closeWindow()
              }
            }
          }
        }
      }
    }
  }
