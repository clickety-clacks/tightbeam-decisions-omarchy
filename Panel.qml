import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "mike.tightbeam-decisions"
  ipcTarget: "mike.tightbeam-decisions"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // allRequests is the raw fetch; `requests` is the filtered view the panel
  // renders. Filtering lives here rather than in fetch.sh so a kind that is
  // switched off is still known about and can be switched back on.
  property var allRequests: []
  property var kinds: []
  // kind -> bool. A kind absent from this map uses the default below.
  property var enabledKinds: ({})
  property bool kindsLoaded: false
  // Blank host means this machine is itself an assimilated Tightbeam node and
  // the CLI runs locally; anything else is an ssh destination. The scripts
  // resolve the transport, so the panel only passes the settings through.
  readonly property string tbHost: String(setting("host", ""))
  // The Tightbeam identity. The older `user` key is still read so an existing
  // shell.json keeps working. Blank means the account the CLI runs as.
  readonly property string tbAsUser: String(setting("asUser", setting("user", "")))
  readonly property string hostName: tbHost === "" ? "this machine" : tbHost
  readonly property string kindSettingsPath: Quickshell.env("HOME") + "/.config/omarchy/tightbeam-decisions.json"
  property var requests: []
  property bool hasNew: false
  property bool refreshing: false
  // Set when a fetch fails, so the empty state does not read as "nothing to
  // do" when the truth is "cannot reach Tightbeam" or "not configured yet".
  property bool fetchFailed: false
  property bool replying: false
  property string statusText: ""
  property var detailRequest: null

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
  function script(name) { return Qt.resolvedUrl(name).toString().replace("file://", "") }
  function refreshNow() {
    if (fetchProcess.running) return
    refreshing = true
    fetchProcess.command = [script("fetch.sh"), root.tbHost, root.tbAsUser]
    fetchProcess.running = true
  }
  // effort requests are high-volume and were hardcoded out of fetch.sh before
  // these toggles existed; keeping them off by default preserves that view.
  function kindEnabled(kind) {
    var value = enabledKinds ? enabledKinds[kind] : undefined
    return value === undefined || value === null ? kind !== "effort" : !!value
  }
  function toggleKind(kind) {
    var next = {}
    for (var key in enabledKinds) next[key] = enabledKinds[key]
    next[kind] = !kindEnabled(kind)
    enabledKinds = next
    applyFilter()
    if (kindsLoaded) kindSaveTimer.restart()
  }
  function countForKind(kind) {
    var total = 0
    for (var index = 0; index < allRequests.length; index++)
      if (allRequests[index].kind === kind) total++
    return total
  }
  function applyFilter() {
    var visible = []
    var anyNew = false
    for (var index = 0; index < allRequests.length; index++) {
      var request = allRequests[index]
      if (!kindEnabled(request.kind)) continue
      visible.push(request)
      if (request.isNew) anyNew = true
    }
    requests = visible
    hasNew = anyNew
    if (requests.length > 0 && requestList.currentIndex < 0) requestList.currentIndex = 0
    if (requestList.currentIndex >= requests.length) requestList.currentIndex = Math.max(0, requests.length - 1)
    if (detailWindow.visible && detailRequest && !hasRequest(detailRequest.id))
      detailWindow.visible = false
  }
  function loadKindSettings(raw) {
    var data = {}
    try { data = JSON.parse(raw || "{}") } catch (error) { data = {} }
    if (!data || typeof data !== "object") data = {}
    enabledKinds = (data.enabledKinds && typeof data.enabledKinds === "object") ? data.enabledKinds : {}
    kindsLoaded = true
    applyFilter()
  }
  function flushKindSettings() {
    if (!kindsLoaded) return
    kindSettingsFile.setText(JSON.stringify({ enabledKinds: enabledKinds }, null, 2) + "\n")
  }
  function applyPayload(text) {
    try {
      var payload = JSON.parse(String(text || ""))
      allRequests = payload.requests || []
      kinds = payload.kinds || []
      fetchFailed = false
      applyFilter()
      statusText = ""
      if (opened) Qt.callLater(function() { markSeen() })
    } catch (error) { statusText = "Could not read Tightbeam response" }
  }
  // The scripts write one purposeful, actionable line -- a missing CLI names
  // what to install, ssh names what it could not reach. Replacing that with a
  // generic sentence threw away the only text that told you what to do. ssh
  // can be chattier, so keep the last non-empty line: the one that says what
  // actually failed.
  function describeError(raw) {
    var lines = String(raw || "").split("\n")
    for (var index = lines.length - 1; index >= 0; index--) {
      var line = lines[index].trim()
      if (line !== "") return line.length > 240 ? line.substring(0, 237) + "…" : line
    }
    return ""
  }
  function hasRequest(id) {
    for (var index = 0; index < requests.length; index++)
      if (requests[index].id === id) return true
    return false
  }
  function markSeen() {
    if (requests.length === 0) { hasNew = false; return }
    var command = [script("mark-seen.sh")]
    for (var index = 0; index < requests.length; index++)
      command.push(String(requests[index].id))
    seenProcess.command = command
    seenProcess.running = true
    hasNew = false
  }
  function submitChoice(choiceNumber) {
    if (!detailRequest || replying) return
    replying = true
    statusText = "Recording decision…"
    replyProcess.command = [script("reply.sh"), root.tbHost, root.tbAsUser, detailRequest.id, String(choiceNumber)]
    replyProcess.running = true
  }
  function openRequest(index) {
    if (index < 0 || index >= requests.length) return
    requestList.currentIndex = index
    detailRequest = requests[index]
    detailWindow.visible = true
    root.close()
    chat.request = detailRequest
    chat.start()
    Qt.callLater(function() { detailFocus.forceActiveFocus() })
  }
  function moveListPage(direction) {
    if (requests.length === 0) return
    var rowHeight = requestList.currentItem ? requestList.currentItem.height + requestList.spacing : Style.space(42)
    var step = Math.max(1, Math.floor(requestList.height / Math.max(1, rowHeight) / 2))
    requestList.currentIndex = Math.max(0, Math.min(requests.length - 1, requestList.currentIndex + direction * step))
    requestList.positionViewAtIndex(requestList.currentIndex, ListView.Contain)
  }
  function scrollDetail(amount) {
    var flick = detailScroll.contentItem
    if (!flick) return
    flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + amount))
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  Component.onCompleted: refreshNow()

  FileView {
    id: kindSettingsFile
    path: root.kindSettingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadKindSettings(text())
    // First run: the file does not exist yet. Without this the toggles would
    // never be marked loaded and a change would never be written.
    onLoadFailed: root.loadKindSettings("")
    onFileChanged: reload()
  }

  Timer {
    id: kindSaveTimer
    interval: 200
    repeat: false
    onTriggered: root.flushKindSettings()
  }
  onOpenedChanged: if (opened) { refreshNow(); Qt.callLater(function() { markSeen(); listKeys.forceActiveFocus() }) }

  Timer { interval: Math.max(10, Number(root.setting("refreshIntervalSec", 30))) * 1000; running: true; repeat: true; onTriggered: root.refreshNow() }
  Process {
    id: fetchProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyPayload(text) }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var described = root.describeError(text)
        if (described !== "") { root.statusText = described; root.fetchFailed = true }
      }
    }
    onExited: function(code) {
      root.refreshing = false
      if (code !== 0) {
        root.fetchFailed = true
        if (root.statusText === "") root.statusText = "Could not reach Tightbeam on " + root.hostName
      }
    }
  }
  Process { id: seenProcess }
  Process {
    id: replyProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.statusText = String(text || "").trim() }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: if (String(text || "").trim() !== "") root.statusText = String(text).trim() }
    onExited: function(code) {
      root.replying = false
      if (code === 0) { detailWindow.visible = false; root.refreshNow() }
    }
  }
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰭙"
    labelVisible: true
    horizontalMargin: 12
    verticalPadding: 8.75
    tooltipText: root.refreshing
      ? "Refreshing Tightbeam…"
      : root.requests.length + " decision request" + (root.requests.length === 1 ? "" : "s") + " on " + root.hostName
    onPressed: function(buttonCode) { if (buttonCode === Qt.MiddleButton) root.refreshNow(); else root.toggle() }
    Rectangle {
      visible: root.hasNew
      width: 8; height: 8; radius: 4
      color: root.urgent
      anchors.top: parent.top; anchors.right: parent.right
      anchors.topMargin: 3; anchors.rightMargin: 3
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: listKeys
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(listColumn.implicitHeight, Style.space(620))

    VimPanelKeyCatcher {
      id: listKeys
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dx < 0) { root.close(); return }
        if (dx > 0) { root.openRequest(requestList.currentIndex); return }
        if (dy !== 0 && root.requests.length > 0) {
          requestList.currentIndex = Math.max(0, Math.min(root.requests.length - 1, requestList.currentIndex + dy))
          requestList.positionViewAtIndex(requestList.currentIndex, ListView.Contain)
        }
      }
      onPageRequested: function(direction) { root.moveListPage(direction) }
      onActivateRequested: root.openRequest(requestList.currentIndex)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: listColumn
        width: parent.width
        spacing: Style.space(12)
        PanelHero {
          width: parent.width
          title: root.requests.length + " decision request" + (root.requests.length === 1 ? "" : "s")
          meta: "Tightbeam · " + root.hostName + (root.refreshing ? " · refreshing…" : "")
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component { Text { text: "󰄬"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.display } }
          trailingControl: Component {
            Button {
              iconText: "󰑐"
              text: "Reload"
              tooltipText: root.refreshing ? "Reloading…" : "Reload all open requests, including seen"
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconSpinning: root.refreshing
              horizontalPadding: Style.spacing.controlGap
              verticalPadding: Style.spacing.labelGap
              bordered: true
              enabled: !root.refreshing
              onClicked: root.refreshNow()
            }
          }
        }

        // One toggle per kind the org is currently raising. Built from
        // `kinds` rather than from the visible requests, so switching a kind
        // off does not remove the control that switches it back on.
        Flow {
          width: parent.width
          spacing: Style.space(6)
          visible: root.kinds.length > 0
          Repeater {
            model: root.kinds
            delegate: Button {
              required property var modelData
              readonly property bool on: root.kindEnabled(modelData)
              text: modelData + " " + root.countForKind(modelData)
              tooltipText: (on ? "Hide" : "Show") + " " + modelData + " decision requests"
              foreground: on ? root.foreground : root.dim
              fontFamily: root.fontFamily
              bordered: on
              horizontalPadding: Style.spacing.controlGap
              verticalPadding: Style.spacing.labelGap
              onClicked: root.toggleKind(modelData)
            }
          }
        }

        ListView {
          id: requestList
          width: parent.width
          height: Math.min(contentHeight, Style.space(500))
          model: root.requests
          spacing: Style.space(6)
          clip: true
          currentIndex: root.requests.length > 0 ? 0 : -1
          delegate: Rectangle {
            required property var modelData
            required property int index
            width: requestList.width
            height: rowText.implicitHeight + Style.space(18)
            radius: Style.cornerRadius
            color: ListView.isCurrentItem ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
            Text {
              id: rowText
              anchors.fill: parent; anchors.margins: Style.space(9)
              text: (modelData.isNew ? "●  " : "") + modelData.question
              color: modelData.isNew ? root.urgent : root.foreground
              font.family: root.fontFamily; font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: requestList.currentIndex = index
              onClicked: root.openRequest(index)
            }
          }
        }

        Text {
          visible: root.requests.length === 0 && !root.fetchFailed
          width: parent.width
          text: root.allRequests.length > 0
            ? "No requests in the kinds you have switched on."
            : "No open decision requests."
          color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body
        }
        Text { visible: root.statusText !== ""; width: parent.width; text: root.statusText; color: root.statusText.indexOf("Recorded:") === 0 ? root.foreground : root.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
      }
    }
  }

  // The detail window is anchored to the window, not nested in a ScrollView.
  // The previous layout put a `width: parent.width` Column inside a ScrollView,
  // where `parent` is the flickable content item — so the content sized itself
  // from its children instead of the window and never tracked a resize.
  FloatingWindow {
    id: detailWindow
    visible: false
    title: root.detailRequest ? "Decision request — " + root.detailRequest.id : "Decision request"
    color: Color.background
    implicitWidth: 820
    implicitHeight: 760
    minimumSize: Qt.size(560, 480)
    onVisibleChanged: if (!visible) chat.stop()
    // `visible` is what we asked for; `backingWindowVisible` is what the
    // compositor actually has. Closing the window from its titlebar tears down
    // the backing window WITHOUT clearing `visible`, so a later `visible = true`
    // is a no-op and the window never reopens. Sync the request back to reality
    // — that also lets onVisibleChanged shut the agent session down.
    onBackingWindowVisibleChanged: if (visible && !backingWindowVisible) visible = false

    FocusScope {
      id: detailFocus
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          detailWindow.visible = false
          event.accepted = true
        }
      }

      Item {
        anchors.fill: parent
        anchors.margins: Style.space(24)

        Column {
          id: detailHeader
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(6)

          Text {
            text: "DECISION REQUEST"
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.5
          }
          Text {
            width: detailHeader.width
            text: root.detailRequest ? root.detailRequest.question : ""
            color: Color.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            lineHeight: 1.2
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
          }
          Text {
            width: detailHeader.width
            text: root.detailRequest
              ? root.detailRequest.id + (root.detailRequest.assignmentId ? "  ·  " + root.detailRequest.assignmentId : "")
              : ""
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
          Text {
            width: detailHeader.width
            visible: root.detailRequest && root.detailRequest.note !== ""
            text: root.detailRequest ? root.detailRequest.note : ""
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            topPadding: Style.space(4)
          }
        }

        PanelSeparator {
          id: detailRule
          anchors.top: detailHeader.bottom
          anchors.topMargin: Style.space(14)
          anchors.left: parent.left
          anchors.right: parent.right
          foreground: Color.foreground
        }

        DecisionChat {
          id: chat
          anchors.top: detailRule.bottom
          anchors.topMargin: Style.space(14)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          host: root.tbHost
          user: root.tbAsUser
          messageScript: root.script("message.sh")
          onRuleRequested: function(choiceNumber) { root.submitChoice(choiceNumber) }
        }
      }
    }
  }
}
