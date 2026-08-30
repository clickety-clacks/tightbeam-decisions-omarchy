import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

ShellRoot {
  id: root
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "").replace(/\/$/, "")
  readonly property string settingsPath: Quickshell.env("HOME") + "/.config/omarchy/tightbeam-decisions.json"
  property string tbHost: ""
  property string tbAsUser: ""
  property var allRequests: []
  property var detailWindows: []
  property var pendingIds: []

  readonly property color foreground: Color.foreground
  readonly property color urgent: Color.urgent
  readonly property color surface: Color.menu.background
  readonly property color dim: mixColor(surface, foreground, 0.85)
  readonly property string fontFamily: Style.font.family
  readonly property real minFontScale: 0.7
  readonly property real maxFontScale: 2
  property real fontScale: 1
  property real keyboardLineImpulse: 335
  property real keyboardDeceleration: 608
  readonly property real keyboardPageImpulse: keyboardLineImpulse * (740 / 360)
  readonly property int captionSize: Math.round(Style.font.caption * fontScale)
  readonly property int bodySize: Math.round(Style.font.body * fontScale)
  readonly property int titleSize: Math.round(Style.font.title * fontScale)
  readonly property bool motionTunerOpen: motionTuner.visible

  function mixColor(from, to, amount) {
    return Qt.rgba(from.r + (to.r - from.r) * amount,
                   from.g + (to.g - from.g) * amount,
                   from.b + (to.b - from.b) * amount, 1)
  }
  function script(name) { return pluginDir + "/" + name }
  function poForRequest(request) {
    var raiser = String(request && request.raiserId ? request.raiserId : "")
    var slug = ""
    var marker = "agent:product-owner:"
    if (raiser.indexOf(marker) === 0) slug = raiser.substring(marker.length)
    else if (raiser.indexOf("process:") === 0) slug = raiser.substring("process:".length)
    else {
      var embedded = raiser.indexOf("product-owner:")
      if (embedded >= 0) slug = raiser.substring(embedded + "product-owner:".length)
    }
    slug = slug.replace(/-(codex|claude)(-.*)?$/i, "")
    return slug === "" ? "UNASSIGNED" : slug.replace(/[-_]+/g, " ").trim().toUpperCase()
  }
  function copyToClipboard(value) {
    if (String(value || "") !== "")
      Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(String(value)) + " | wl-copy"])
  }
  function handleFontKey(event) {
    if ((event.modifiers & Qt.ControlModifier) === 0) return false
    if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) { adjustFontScale(0.1); return true }
    if (event.key === Qt.Key_Minus || event.key === Qt.Key_Underscore) { adjustFontScale(-0.1); return true }
    if (event.key === Qt.Key_0) { setFontScale(1); return true }
    return false
  }
  function setFontScale(value) {
    fontScale = Math.max(minFontScale, Math.min(maxFontScale, Math.round(value * 100) / 100))
    saveSettings.restart()
  }
  function adjustFontScale(step) { setFontScale(fontScale + step) }
  function setKeyboardMotion(impulse, deceleration) {
    keyboardLineImpulse = Math.round(Math.max(80, Math.min(2000, impulse)))
    keyboardDeceleration = Math.round(Math.max(100, Math.min(5000, deceleration)))
    saveSettings.restart()
  }
  function openMotionTuner() { motionTuner.open() }
  function configure(host, asUser) {
    var changed = tbHost !== String(host || "") || tbAsUser !== String(asUser || "")
    tbHost = String(host || "")
    tbAsUser = String(asUser || "")
    if (changed || allRequests.length === 0) refreshNow()
  }
  function openRequestObject(request) {
    if (!request || !request.id) return false
    var detail = detailFactory.createObject(root, { owner: root, request: request })
    if (!detail) return false
    detail.detailClosed.connect(root.removeDetailWindow)
    detailWindows = detailWindows.concat([detail])
    detail.open()
    return true
  }
  function openRequestJson(payload) {
    try { return openRequestObject(JSON.parse(String(payload || ""))) }
    catch (error) { return false }
  }
  function openRequestById(id) {
    for (var index = 0; index < allRequests.length; index++)
      if (String(allRequests[index].id) === String(id)) return openRequestObject(allRequests[index])
    pendingIds = pendingIds.concat([String(id)])
    refreshNow()
    return true
  }
  function removeDetailWindow(window) {
    var remaining = []
    for (var index = 0; index < detailWindows.length; index++)
      if (detailWindows[index] !== window) remaining.push(detailWindows[index])
    detailWindows = remaining
    if (remaining.length === 0) motionTuner.visible = false
    Qt.callLater(function() { window.destroy() })
  }
  function refreshNow() {
    if (fetchProcess.running) return
    fetchProcess.command = [script("fetch.sh"), tbHost, tbAsUser]
    fetchProcess.running = true
  }
  function applyPayload(raw) {
    try {
      var payload = JSON.parse(String(raw || ""))
      allRequests = payload.requests || []
      for (var wi = 0; wi < detailWindows.length; wi++) {
        var found = false
        for (var ri = 0; ri < allRequests.length; ri++)
          if (detailWindows[wi] && String(detailWindows[wi].request.id) === String(allRequests[ri].id)) { found = true; break }
        if (detailWindows[wi] && !found) detailWindows[wi].markHandled()
      }
      var queued = pendingIds
      pendingIds = []
      for (var qi = 0; qi < queued.length; qi++) {
        var opened = false
        for (var ii = 0; ii < allRequests.length; ii++)
          if (String(allRequests[ii].id) === String(queued[qi])) { openRequestObject(allRequests[ii]); opened = true; break }
        if (!opened) console.warn("Decision request is no longer open:", queued[qi])
      }
    } catch (error) { console.warn("Could not parse Tightbeam decisions:", error) }
  }
  function loadSettings(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      if (isFinite(Number(data.fontScale))) fontScale = Math.max(minFontScale, Math.min(maxFontScale, Number(data.fontScale)))
      if (isFinite(Number(data.keyboardLineImpulse))) keyboardLineImpulse = Number(data.keyboardLineImpulse)
      if (isFinite(Number(data.keyboardDeceleration))) keyboardDeceleration = Number(data.keyboardDeceleration)
    } catch (error) {}
  }
  function flushSettings() {
    var data = {}
    try { data = JSON.parse(settingsFile.text() || "{}") } catch (error) { data = {} }
    data.fontScale = fontScale
    data.keyboardLineImpulse = keyboardLineImpulse
    data.keyboardDeceleration = keyboardDeceleration
    settingsFile.setText(JSON.stringify(data, null, 2) + "\n")
  }

  FileView { id: settingsFile; path: root.settingsPath; atomicWrites: true; printErrors: false; onLoaded: root.loadSettings(text()) }
  Timer { id: saveSettings; interval: 200; onTriggered: root.flushSettings() }
  Timer { interval: 30000; running: true; repeat: true; onTriggered: root.refreshNow() }
  Process {
    id: fetchProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyPayload(text) }
  }
  MotionTuner {
    id: motionTuner
    impulse: root.keyboardLineImpulse
    deceleration: root.keyboardDeceleration
    onMotionChanged: function(impulse, deceleration) { root.setKeyboardMotion(impulse, deceleration) }
    onResetRequested: root.setKeyboardMotion(335, 608)
  }
  Component { id: detailFactory; DecisionWindow {} }
  IpcHandler {
    target: "mike.tightbeam-decision-windows"
    function ping(): string { return "ok" }
    function configure(host: string, asUser: string): string { root.configure(host, asUser); return "ok" }
    function openJson(payload: string, host: string, asUser: string): string {
      root.configure(host, asUser)
      return root.openRequestJson(payload) ? "ok" : "invalid-request"
    }
    function openId(id: string, host: string, asUser: string): string {
      root.configure(host, asUser)
      return root.openRequestById(id) ? "ok" : "not-found"
    }
  }
}
