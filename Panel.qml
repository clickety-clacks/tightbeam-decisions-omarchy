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
  // Secondary text is derived from the theme's own surface and foreground
  // instead of read from the shell's muted role. Omarchy falls back to color8
  // when a theme omits `muted`, and color8 is terminal "bright black" -- a dim
  // value that assumes a dark background. Under a light theme it lands next to
  // the surface: 1.4:1 here, which is unreadable. Mixing the surface toward the
  // foreground is correct in both directions -- about 3.8:1 on a light theme
  // and 8.6:1 on a dark one -- and stays clearly weaker than full foreground.
  function mixColor(from, to, amount) {
    return Qt.rgba(from.r + (to.r - from.r) * amount,
                   from.g + (to.g - from.g) * amount,
                   from.b + (to.b - from.b) * amount,
                   1)
  }
  readonly property color surface: Color.menu.background
  readonly property color dim: mixColor(surface, foreground, 0.85)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // allRequests is the raw fetch; `requests` is the filtered view the panel
  // renders. Filtering lives here rather than in fetch.sh so a kind that is
  // switched off is still known about and can be switched back on.
  property var allRequests: []
  property var kinds: []
  // kind -> bool. A kind absent from this map uses the default below.
  property var enabledKinds: ({})
  // Text size for the dropdown and the detail window alike, so one Ctrl +/-
  // anywhere resizes both and the two surfaces cannot drift apart.
  readonly property real minFontScale: 0.7
  readonly property real maxFontScale: 2
  property real fontScale: 1
  property real keyboardLineImpulse: 335
  property real keyboardDeceleration: 608
  readonly property real keyboardPageImpulse: keyboardLineImpulse * (740 / 360)
  // Rounded once here rather than at every use site.
  readonly property int captionSize: Math.round(Style.font.caption * fontScale)
  readonly property int bodySize: Math.round(Style.font.body * fontScale)
  readonly property int titleSize: Math.round(Style.font.title * fontScale)
  readonly property int displaySize: Math.round(Style.font.display * fontScale)
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
  property bool fetchedOnce: false
  // Set when a fetch fails, so the empty state does not read as "nothing to
  // do" when the truth is "cannot reach Tightbeam" or "not configured yet".
  property bool fetchFailed: false
  property string statusText: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
  function poForRequest(request) {
    var raiser = String(request && request.raiserId ? request.raiserId : "")
    var slug = ""
    var poMarker = "agent:product-owner:"
    if (raiser.indexOf(poMarker) === 0) slug = raiser.substring(poMarker.length)
    else if (raiser.indexOf("process:") === 0) slug = raiser.substring("process:".length)
    else {
      var embeddedPo = raiser.indexOf("product-owner:")
      if (embeddedPo >= 0) slug = raiser.substring(embeddedPo + "product-owner:".length)
    }
    // Harness and relief-role suffixes describe the particular PO session,
    // not the top-level product organization it owns.
    slug = slug.replace(/-(codex|claude)(-.*)?$/i, "")
    if (slug === "") return "UNASSIGNED"
    return slug.replace(/[-_]+/g, " ").trim().toUpperCase()
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
  // Shared so the window, and any TextEdit that has claimed focus inside it,
  // resize through the same path. Returns true when the key was consumed.
  function handleFontKey(event) {
    if ((event.modifiers & Qt.ControlModifier) === 0) return false
    if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) { adjustFontScale(0.1); return true }
    if (event.key === Qt.Key_Minus || event.key === Qt.Key_Underscore) { adjustFontScale(-0.1); return true }
    if (event.key === Qt.Key_0) { setFontScale(1); return true }
    return false
  }
  function setFontScale(value) {
    var next = Math.max(minFontScale, Math.min(maxFontScale, Math.round(value * 100) / 100))
    if (next === fontScale) return
    fontScale = next
    if (kindsLoaded) kindSaveTimer.restart()
  }
  function adjustFontScale(step) { setFontScale(fontScale + step) }
  function setKeyboardMotion(impulse, deceleration) {
    var nextImpulse = Math.round(Math.max(80, Math.min(2000, impulse)))
    var nextDeceleration = Math.round(Math.max(100, Math.min(5000, deceleration)))
    if (nextImpulse === keyboardLineImpulse && nextDeceleration === keyboardDeceleration) return
    keyboardLineImpulse = nextImpulse
    keyboardDeceleration = nextDeceleration
    if (kindsLoaded) kindSaveTimer.restart()
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
      // Group by the top-level product owner, not by the assignment subject.
      // Copy rather than decorate the fetched object in place.
      var listed = {}
      for (var key in request) listed[key] = request[key]
      listed.poSection = poForRequest(request)
      listed.sourceOrder = index
      visible.push(listed)
      if (request.isNew) anyNew = true
    }
    visible.sort(function(left, right) {
      var byPo = left.poSection.localeCompare(right.poSection, undefined, { sensitivity: "base" })
      return byPo !== 0 ? byPo : left.sourceOrder - right.sourceOrder
    })
    requests = visible
    hasNew = anyNew
    if (requests.length > 0 && requestList.currentIndex < 0) requestList.currentIndex = 0
    if (requestList.currentIndex >= requests.length) requestList.currentIndex = Math.max(0, requests.length - 1)
  }
  function loadKindSettings(raw) {
    var data = {}
    try { data = JSON.parse(raw || "{}") } catch (error) { data = {} }
    if (!data || typeof data !== "object") data = {}
    enabledKinds = (data.enabledKinds && typeof data.enabledKinds === "object") ? data.enabledKinds : {}
    var scale = Number(data.fontScale)
    fontScale = (isFinite(scale) && scale > 0)
      ? Math.max(minFontScale, Math.min(maxFontScale, scale))
      : 1
    var impulse = Number(data.keyboardLineImpulse)
    keyboardLineImpulse = isFinite(impulse)
      ? Math.round(Math.max(80, Math.min(2000, impulse)))
      : 335
    var deceleration = Number(data.keyboardDeceleration)
    keyboardDeceleration = isFinite(deceleration)
      ? Math.round(Math.max(100, Math.min(5000, deceleration)))
      : 608
    kindsLoaded = true
    applyFilter()
  }
  function flushKindSettings() {
    if (!kindsLoaded) return
    kindSettingsFile.setText(JSON.stringify({
      enabledKinds: enabledKinds,
      fontScale: fontScale,
      keyboardLineImpulse: keyboardLineImpulse,
      keyboardDeceleration: keyboardDeceleration
    }, null, 2) + "\n")
  }
  function notifyNewRequests(added) {
    if (!added || added.length === 0) return
    for (var index = 0; index < added.length; index++) {
      var question = String(added[index].question || "Decision requested").replace(/\s+/g, " ").trim()
      if (question.length > 150) question = question.substring(0, 147) + "…"
      Quickshell.execDetached([
        "omarchy", "notification", "send",
        "--app-name", "Tightbeam Decisions",
        "-g", "󰗑", "-u", "normal",
        "New " + poForRequest(added[index]) + " decision request", question,
        "--exec", script("decision-window-host.sh"), "open-id", root.tbHost, root.tbAsUser, String(added[index].id)
      ])
    }
  }
  function applyPayload(text) {
    try {
      var payload = JSON.parse(String(text || ""))
      var incoming = payload.requests || []
      if (fetchedOnce) {
        var priorIds = {}
        for (var oldIndex = 0; oldIndex < allRequests.length; oldIndex++)
          priorIds[String(allRequests[oldIndex].id)] = true
        var added = []
        for (var newIndex = 0; newIndex < incoming.length; newIndex++)
          if (!priorIds[String(incoming[newIndex].id)]) added.push(incoming[newIndex])
        notifyNewRequests(added)
      }
      allRequests = incoming
      kinds = payload.kinds || []
      fetchedOnce = true
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
  function copyToClipboard(value) {
    if (String(value || "") === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(String(value)) + " | wl-copy"])
  }
  function hasOpenRequest(id) {
    for (var index = 0; index < allRequests.length; index++)
      if (allRequests[index].id === id) return true
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
  function openRequest(index) {
    if (index < 0 || index >= requests.length) return
    requestList.currentIndex = index
    openRequestObject(requests[index])
  }
  function openRequestById(id) {
    for (var index = 0; index < allRequests.length; index++) {
      if (String(allRequests[index].id) === String(id)) {
        openRequestObject(allRequests[index])
        return true
      }
    }
    return false
  }
  function openRequestObject(request) {
    Quickshell.execDetached([script("decision-window-host.sh"), "open-json", root.tbHost, root.tbAsUser, JSON.stringify(request)])
    root.close()
  }

 function moveListPage(direction) {
    if (requests.length === 0) return
    var rowHeight = requestList.currentItem ? requestList.currentItem.height + requestList.spacing : Style.space(42)
    var step = Math.max(1, Math.floor(requestList.height / Math.max(1, rowHeight) / 2))
    requestList.currentIndex = Math.max(0, Math.min(requests.length - 1, requestList.currentIndex + direction * step))
    requestList.positionViewAtIndex(requestList.currentIndex, ListView.Contain)
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  Component.onCompleted: {
    Quickshell.execDetached([script("decision-window-host.sh"), "ensure", root.tbHost, root.tbAsUser])
    startupRefresh.restart()
  }
  onSettingsChanged: {
    Quickshell.execDetached([script("decision-window-host.sh"), "ensure", root.tbHost, root.tbAsUser])
    startupRefresh.restart()
  }

  Timer {
    id: startupRefresh
    interval: 100
    repeat: false
    onTriggered: root.refreshNow()
  }

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
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function openRequestId(id: string): string {
      return root.openRequestById(id) ? "ok" : "not-found"
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰗑  " + (root.fetchedOnce ? root.allRequests.length : "…")
    labelVisible: true
    horizontalMargin: 12
    verticalPadding: 8.75
    tooltipText: root.refreshing
      ? "Refreshing Tightbeam…"
      : root.allRequests.length + " decision request" + (root.allRequests.length === 1 ? "" : "s") + " on " + root.hostName
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
    // Scale the box with the text. At 2x a fixed width just elides harder,
    // which is the opposite of what asking for bigger text means. fitted*
    // still clamps to what the screen can actually show.
    contentWidth: panel.fittedContentWidth(Math.round(Style.space(500) * root.fontScale))
    contentHeight: panel.fittedContentHeight(listColumn.implicitHeight, Math.round(Style.space(620) * root.fontScale))

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
      onFontStepRequested: function(step) { root.adjustFontScale(step) }
      onFontResetRequested: root.setFontScale(1)

      Column {
        id: listColumn
        width: parent.width
        spacing: Style.space(12)
        PanelHero {
          width: parent.width
          title: root.requests.length === root.allRequests.length
            ? root.allRequests.length + " decision request" + (root.allRequests.length === 1 ? "" : "s")
            : root.requests.length + " of " + root.allRequests.length + " decision requests"
          meta: "Tightbeam · " + root.hostName + (root.refreshing ? " · refreshing…" : "")
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component { Text { text: "󰗑"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: root.displaySize } }
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
              text: (on ? "☑  " : "☐  ") + modelData + " " + root.countForKind(modelData)
              tooltipText: (on ? "Hide" : "Show") + " " + modelData + " decision requests"
              foreground: on ? root.foreground : root.dim
              fontFamily: root.fontFamily
              bordered: true
              horizontalPadding: Style.spacing.controlGap
              verticalPadding: Style.spacing.labelGap
              onClicked: root.toggleKind(modelData)
            }
          }
        }

        ListView {
          id: requestList
          width: parent.width
          height: Math.min(contentHeight, Math.round(Style.space(500) * root.fontScale))
          model: root.requests
          spacing: Style.space(6)
          clip: true
          currentIndex: root.requests.length > 0 ? 0 : -1
          section.property: "poSection"
          section.criteria: ViewSection.FullString
          section.labelPositioning: ViewSection.InlineLabels
          section.delegate: Item {
            required property string section
            width: requestList.width
            height: poTitle.implicitHeight + Style.space(14)

            Text {
              id: poTitle
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.leftMargin: Style.space(4)
              anchors.rightMargin: Style.space(4)
              anchors.bottomMargin: Style.space(4)
              text: section
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: root.captionSize
              font.bold: true
              font.letterSpacing: 0.6
              elide: Text.ElideRight
            }
          }
          delegate: Rectangle {
            required property var modelData
            required property int index
            width: requestList.width
            height: rowColumn.implicitHeight + Style.space(18)
            radius: Style.cornerRadius
            color: ListView.isCurrentItem ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
            Column {
              id: rowColumn
              anchors.left: parent.left; anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(9)
              spacing: Style.space(2)
              Text {
                id: rowText
                width: parent.width
                text: (modelData.isNew ? "●  " : "") + modelData.question
                color: modelData.isNew ? root.urgent : root.foreground
                font.family: root.fontFamily; font.pixelSize: root.captionSize
                elide: Text.ElideRight
              }
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
          color: root.dim; font.family: root.fontFamily; font.pixelSize: root.bodySize
        }
        Text { visible: root.statusText !== ""; width: parent.width; text: root.statusText; color: root.statusText.indexOf("Recorded:") === 0 ? root.foreground : root.urgent; font.family: root.fontFamily; font.pixelSize: root.captionSize; wrapMode: Text.WordWrap }
      }
    }
  }

}
