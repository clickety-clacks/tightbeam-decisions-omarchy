import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons

Item {
  id: root
  property color foreground: Color.menu.text
  property var catalog: ({})
  property var thinkingLevels: ({})
  property string pendingEffort: ""
  property string errorText: ""
  property bool saving: false
  property bool reading: false
  property string pendingProvider: ""
  property string pendingModel: ""
  property bool responseReceived: false
  readonly property string script: Qt.resolvedUrl("bridge/model-settings.js").toString().replace(/^file:\/\//, "")
  readonly property string node: Qt.resolvedUrl("bridge/node.sh").toString().replace(/^file:\/\//, "")
  implicitHeight: contentColumn.implicitHeight
  function reload() {
    if (settingsProcess.running) return
    errorText = ""
    reading = true
    responseReceived = false
    settingsProcess.command = [node, script, "read"]
    settingsProcess.running = true
  }
  function rememberSelection() {
    if (modelPicker.currentIndex < 0) return
    pendingProvider = harness.currentIndex === 0 ? "codex" : "claude"
    pendingModel = models()[modelPicker.currentIndex].id
    pendingEffort = effortPicker.currentValue || ""
    errorText = "Saving…"
    saveTimer.restart()
  }
  Timer {
    id: saveTimer
    interval: 100
    onTriggered: {
      if (settingsProcess.running) { restart(); return }
      if (!root.pendingModel) return
      root.reading = false
      root.saving = true
      root.responseReceived = false
      settingsProcess.command = [root.node, root.script, "save", root.pendingProvider, root.pendingModel, root.pendingEffort]
      root.pendingModel = ""
      settingsProcess.running = true
    }
  }
  function models() { return catalog[harness.currentIndex === 0 ? "codex" : "claude"] || [] }
  Process {
    id: settingsProcess
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0 || exitStatus !== 0) {
        root.errorText = "Agent settings were not saved/read successfully. Check the settings file and Node installation."
        root.saving = false
      }
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.responseReceived = true
        try {
          var reply = JSON.parse(text)
          if (reply.error) { root.errorText = reply.error; root.saving = false; return }
          if (root.reading) {
            root.catalog = reply.catalog
            root.thinkingLevels = reply.thinkingLevels
            harness.currentIndex = reply.selected.provider === "codex" ? 0 : 1
            var entries = root.models()
            var selectedIndex = -1
            for (var i = 0; i < entries.length; i++) if (entries[i].id === reply.selected.model) selectedIndex = i
            modelPicker.currentIndex = selectedIndex
            effortPicker.currentIndex = Math.max(0, effortPicker.model.indexOf(reply.selected.reasoningEffort || ""))
          }
          root.errorText = root.pendingModel ? "Saving…" : root.saving ? "Saved for all windows. Re-summarize to switch this conversation." : ""
          root.saving = false
        } catch (error) { root.errorText = "Could not read agent settings: " + error; root.saving = false }
      }
    }
  }
    Column {
      id: contentColumn
      width: root.width
      spacing: Style.space(8)
      Label { text: "Agent"; color: root.foreground; font.bold: true; font.family: Style.font.family; font.pixelSize: Style.font.title }
      Label { text: "Harness"; color: root.foreground }
      ComboBox {
        id: harness
        objectName: "agentHarness"
        width: parent.width
        model: ["Codex", "Claude"]
        enabled: !root.reading || root.responseReceived
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        palette.button: Color.menu.background
        palette.buttonText: root.foreground
        palette.base: Color.menu.background
        palette.text: root.foreground
        onActivated: { modelPicker.currentIndex = 0; effortPicker.currentIndex = 0; root.rememberSelection() }
      }
      Label { text: "Model"; color: root.foreground }
      ComboBox {
        id: modelPicker
        objectName: "agentModel"
        width: parent.width
        model: root.models()
        textRole: "label"
        enabled: !root.reading || root.responseReceived
        onActivated: { effortPicker.currentIndex = 0; root.rememberSelection() }
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        palette.button: Color.menu.background
        palette.buttonText: root.foreground
        palette.base: Color.menu.background
        palette.text: root.foreground
      }
      Label { text: "Thinking level"; color: root.foreground }
      ComboBox {
        id: effortPicker
        objectName: "agentEffort"
        width: parent.width
        model: modelPicker.currentIndex >= 0 ? (root.thinkingLevels[root.models()[modelPicker.currentIndex].id] || [""]) : [""]
        displayText: currentValue ? currentValue.charAt(0).toUpperCase() + currentValue.slice(1) : "Model default"
        delegate: ItemDelegate {
          required property string modelData
          width: effortPicker.width
          text: modelData ? modelData.charAt(0).toUpperCase() + modelData.slice(1) : "Model default"
        }
        enabled: !root.reading || root.responseReceived
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        palette.button: Color.menu.background
        palette.buttonText: root.foreground
        palette.base: Color.menu.background
        palette.text: root.foreground
        onActivated: root.rememberSelection()
      }
      Label {
        width: parent.width
        wrapMode: Text.Wrap
        text: modelPicker.currentIndex >= 0 ? (root.models()[modelPicker.currentIndex].testNote || "") : ""
        visible: text !== ""
        color: root.foreground
      }
      Label {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Shared by every window and both summarizers. Existing conversations stay unchanged until re-summarized. Tools always use YOLO."
        color: root.foreground
      }
      Label { width: parent.width; wrapMode: Text.Wrap; text: root.errorText; visible: text !== ""; color: root.foreground }
    }
}
