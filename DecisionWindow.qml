import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "kinds.js" as Kinds

FloatingWindow {
  id: root

  visible: false
  required property var owner
  required property var request
  required property string tbHost
  required property string tbAsUser
  signal detailClosed(var window)

  property bool openedOnce: false
  property bool closing: false
  property bool replying: false
  property string selectedChoice: ""
  property string decisionStatus: ""
  property bool handled: false
  property string handledStatus: "handled"
  property string handledActor: ""
  property string handledDetermination: "Loading the recorded outcome…"
  property string projectSummary: ""
  property string parentSummary: ""
  property string noteSummary: ""
  property string questionSummary: ""
  property var choiceLabels: []
  property var summaryChoiceEffects: []
  property string summaryRaw: ""
  property int armedChoice: -1
  property int focusedChoice: -1
  property int proposedChoice: -1
  property int hoveredChoice: -1
  property bool choiceFocusActive: false
  property bool minimumAskRevealed: false
  property var choiceData: []

  readonly property real fontScale: owner.fontScale
  readonly property color ground: Color.background
  readonly property color ink: Color.foreground
  readonly property color secondary: mixColor(Color.background, Color.foreground, 0.65)
  readonly property color faint: mixColor(Color.background, Color.foreground, 0.50)
  readonly property color panel: mixColor(Color.background, Color.foreground, 0.05)
  readonly property color hairline: mixColor(Color.background, Color.foreground, 0.14)
  readonly property color keyBorder: mixColor(Color.background, Color.foreground, 0.30)
  readonly property color urgent: Color.urgent
  readonly property string newsreaderFamily: owner.decisionNewsreaderFamily
  readonly property string newsreaderItalicFamily: owner.decisionNewsreaderItalicFamily
  readonly property string sansFamily: owner.decisionPlexSansFamily
  readonly property string sansItalicFamily: owner.decisionPlexSansItalicFamily
  readonly property string monoFamily: owner.decisionPlexMonoFamily
  readonly property string monoMediumFamily: owner.decisionPlexMonoMediumFamily

  readonly property bool minimumLayout: root.height < 360
  readonly property bool wideLayout: !root.minimumLayout && root.width >= 720
  readonly property bool narrowLayout: !root.minimumLayout && !root.wideLayout
  readonly property bool footerRoom: !root.minimumLayout && root.height >= 480
  readonly property bool headerIdsVisible: !root.footerRoom
  readonly property int headlineLines: root.minimumLayout ? 3
    : root.narrowLayout ? 4 : (root.height < 560 ? 1 : 3)
  readonly property real headerContentHeight: headerColumn.implicitHeight
    + Math.round((root.wideLayout ? 22 : root.narrowLayout ? 18 : 16) * root.fontScale)
    + Math.round((root.wideLayout ? 20 : root.narrowLayout ? 14 : 12) * root.fontScale)
  readonly property real footerHeight: root.footerRoom ? Math.round(34 * root.fontScale) : 0
  readonly property real decideWidth: root.wideLayout
    ? Math.min(340 * root.fontScale, Math.max(300 * root.fontScale, root.width * 0.38)) : 0
  readonly property real contentAreaHeight: Math.max(0,
    root.height - root.headerHeight - root.footerHeight)
  readonly property real headerHeight: root.minimumLayout
    ? Math.max(0, root.height - (root.handled ? minimumOutcome.height : minimumStrip.height)
      - (root.minimumAskRevealed ? chat.askLineHeight : 0))
    : root.headerContentHeight
  readonly property real decidePanelHeight: root.contentAreaHeight
  readonly property real decidePadding: Math.round((root.height < 480 ? 8 : 18) * root.fontScale)
  readonly property real decideHeadingHeight: Math.round(22 * root.fontScale)
  readonly property real decideContentWidth: Math.max(0, root.decideWidth - root.decidePadding * 2)
  readonly property bool decisionErrorVisible: decisionStatus !== ""
    && decisionStatus.indexOf("Recording “") !== 0
  readonly property real decisionStatusHeight: root.decisionErrorVisible
    ? Math.round(22 * root.fontScale) : 0
  readonly property real decisionChoiceRoom: Math.max(0, root.decidePanelHeight
    - root.decidePadding * 2 - root.decideHeadingHeight - root.decisionStatusHeight)
  readonly property string choiceDensity: root.measureRepeaterHeight(fullMeasureRepeater) <= root.decisionChoiceRoom
    ? "full" : root.measureRepeaterHeight(clampedMeasureRepeater) <= root.decisionChoiceRoom
      ? "clamped" : "compact"
  readonly property string questionText: root.questionSummary !== ""
    ? root.questionSummary
    : root.request && String(root.request.subject || "") !== ""
      ? String(root.request.subject)
      : root.request ? String(root.request.question || "Decision requested") : "Decision requested"
  readonly property string projectText: root.displayProject()

  implicitWidth: Math.round(820 * root.fontScale)
  implicitHeight: Math.round(760 * root.fontScale)
  minimumSize: Qt.size(320, 300)
  color: root.ground
  title: root.request ? "Decision request — " + root.request.id : "Decision request"

  function mixColor(from, to, amount) {
    return Qt.rgba(from.r + (to.r - from.r) * amount,
                   from.g + (to.g - from.g) * amount,
                   from.b + (to.b - from.b) * amount, 1)
  }

  function measureRepeaterHeight(repeater) {
    var total = 0
    for (var index = 0; index < repeater.count; index++) {
      var item = repeater.itemAt(index)
      if (item) total += Math.max(0, Number(item.height || item.implicitHeight || 0))
    }
    return total
  }

  function stackOffset(repeater, index, spacing) {
    var offset = 0
    for (var row = 0; row < index; row++) {
      var item = repeater.itemAt(row)
      if (item) offset += Math.max(0, Number(item.height || item.implicitHeight || 0))
    }
    return offset + Math.max(0, index) * Math.max(0, spacing)
  }

  function rowOffset(repeater, index, spacing) {
    var offset = 0
    for (var column = 0; column < index; column++) {
      var item = repeater.itemAt(column)
      if (item) offset += Math.max(0, Number(item.width || 0))
    }
    return offset + Math.max(0, index) * Math.max(0, spacing)
  }

  function measureRepeaterWidth(repeater) {
    var total = 0
    for (var index = 0; index < repeater.count; index++) {
      var item = repeater.itemAt(index)
      if (item) total += Math.max(0, Number(item.width || 0))
    }
    return total
  }

  function script(name) { return owner.script(name) }
  function handleFontKey(event) { return owner.handleFontKey(event) }
  function copyToClipboard(value) { owner.copyToClipboard(value) }

  function cleanSummary(value, limit) {
    var text = String(value || "").replace(/\s+/g, " ").trim()
    return text.length > limit ? text.substring(0, limit - 1).trim() + "…" : text
  }

  function cleanWords(value, maximum) {
    var words = String(value || "").replace(/\s+/g, " ").trim().split(" ")
    if (words.length === 1 && words[0] === "") return ""
    return words.length > maximum ? words.slice(0, maximum).join(" ") + "…" : words.join(" ")
  }

  function summaryPrompt() {
    return [
      "You are a fast UI summarizer for one Tightbeam decision request. Do not use tools.",
      "Return ONLY one JSON object on one line; do not wrap it in Markdown.",
      "Schema: {\"project\":\"1-3 words\",\"question\":\"a plain question, at most 25 words\",\"parent\":\"2-6 plain words\",\"notes\":\"one short line\",\"choices\":[{\"label\":\"2-7 plain words\",\"effect\":\"one sentence describing what choosing it causes\"}]}",
      "The choices array MUST have exactly one object per input option, in the same order.",
      "Do not alter, combine, reorder, recommend, or omit options. Do not put ids in labels.",
      "If a choice cannot be rewritten safely, use its raw option word for label and an empty effect.",
      "Use an empty string for any unavailable field. Keep the question as a question.",
      "REQUEST JSON:", JSON.stringify(request || {}),
      "INPUT OPTIONS:", JSON.stringify(request && request.options ? request.options : [])
    ].join("\n")
  }

  function applySummaryResult(result) {
    projectSummary = cleanWords(result.project, 3)
    questionSummary = cleanWords(result.question, 25)
    parentSummary = cleanWords(result.parent, 6)
    noteSummary = cleanSummary(result.notes, 140)
    var options = request && request.options ? request.options : []
    var labels = []
    var effects = []
    var valid = Array.isArray(result.choices) && result.choices.length === options.length
    for (var index = 0; index < options.length; index++) {
      var raw = String(options[index])
      var entry = valid ? result.choices[index] : null
      var validEntry = entry && typeof entry === "object" && !Array.isArray(entry)
      var label = validEntry ? cleanWords(entry.label, 7) : ""
      var effect = validEntry ? cleanSummary(entry.effect, 180) : ""
      labels.push(label === "" ? raw : label)
      effects.push(effect)
    }
    choiceLabels = labels
    summaryChoiceEffects = effects
    refreshChoiceData()
  }

  function handleSummaryLine(rawLine) {
    var line = String(rawLine || "").trim()
    if (line === "") return
    try {
      var event = JSON.parse(line)
      if (event.type === "ready") {
        summaryProcess.write(JSON.stringify({ type: "prompt", text: summaryPrompt() }) + "\n")
      } else if (event.type === "text") {
        summaryRaw += String(event.text || "")
      } else if (event.type === "done") {
        var start = summaryRaw.indexOf("{")
        var end = summaryRaw.lastIndexOf("}")
        if (start >= 0 && end > start) {
          var result = JSON.parse(summaryRaw.substring(start, end + 1))
          applySummaryResult(result)
        }
      }
    } catch (error) {}
  }

  function displayProject() {
    var raiser = String(root.request && root.request.raiserId || "")
    var inferred = owner.poForRequest(root.request)
    var nonOwnerProcess = raiser.indexOf("process:") === 0
    if (!nonOwnerProcess && inferred !== "" && inferred !== "UNASSIGNED") return inferred
    if (root.projectSummary !== "") return root.projectSummary.toUpperCase()
    return inferred !== "" && inferred !== "UNASSIGNED" ? inferred : "TIGHTBEAM"
  }

  function formatRaisedAt(value) {
    var date = new Date(value)
    if (isNaN(date.getTime())) return ""
    var hour = date.getHours()
    var suffix = hour >= 12 ? "PM" : "AM"
    hour = hour % 12
    if (hour === 0) hour = 12
    var minute = String(date.getMinutes()).padStart(2, "0")
    var time = hour + ":" + minute + " " + suffix
    var now = new Date()
    var sameDay = date.getFullYear() === now.getFullYear()
      && date.getMonth() === now.getMonth() && date.getDate() === now.getDate()
    if (sameDay) return time
    return (date.getMonth() + 1) + "/" + date.getDate() + " · " + time
  }

  function shortId(value) {
    var text = String(value || "")
    return text.length > 14 ? text.substring(0, 12) + "…" : text
  }

  function planUrl() {
    return String(root.request && (root.request.planUrl || root.request.workItemUrl || root.request.url) || "")
  }

  function hasPlanUrl() { return root.planUrl() !== "" }

  function shortPlan(value, opens) {
    var text = String(value || "").replace(/\s+/g, " ").trim()
    var suffix = opens ? " ↗" : ""
    return text.length > 32 ? text.substring(0, 32 - suffix.length - 1).trim() + "…" + suffix : text + suffix
  }

  function identifierEntries() {
    var result = []
    var workItem = String(root.request && root.request.workItemId || "")
    if (workItem !== "") result.push({
      label: "plan", value: workItem,
      display: shortPlan(root.request.subject || root.parentSummary || "work item", root.hasPlanUrl()),
      opens: root.hasPlanUrl()
    })
    var requestId = String(root.request && root.request.id || "")
    var assignmentId = String(root.request && root.request.assignmentId || "")
    if (requestId !== "") result.push({ label: "request", value: requestId, display: shortId(requestId), opens: false })
    if (assignmentId !== "") result.push({ label: "assignment", value: assignmentId, display: shortId(assignmentId), opens: false })
    if (workItem !== "") result.push({ label: "work item", value: workItem, display: shortId(workItem), opens: false })
    return result
  }

  function hasIdentifiers() { return identifierEntries().length > 0 }

  function openPlan() {
    var target = root.planUrl()
    if (target !== "") Qt.openUrlExternally(target)
  }

  function rulingChoices() {
    var result = []
    var options = request && request.options ? request.options : []
    for (var index = 0; index < options.length; index++) {
      var label = String(options[index])
      if (request && request.kind === "effort" && label !== "continue" && label !== "dismiss") continue
      result.push(label)
    }
    return result
  }

  function effectForOption(originalIndex, raw) {
    var explainer = chat.choiceEffects || []
    if (originalIndex < explainer.length && String(explainer[originalIndex] || "").trim() !== "")
      return String(explainer[originalIndex]).trim()
    if (originalIndex < summaryChoiceEffects.length && String(summaryChoiceEffects[originalIndex] || "").trim() !== "")
      return String(summaryChoiceEffects[originalIndex]).trim()
    return ""
  }

  function refreshChoiceData() {
    var options = rulingChoices()
    var allOptions = request && request.options ? request.options : []
    var result = []
    for (var index = 0; index < options.length; index++) {
      var raw = options[index]
      var originalIndex = -1
      for (var rawIndex = 0; rawIndex < allOptions.length; rawIndex++)
        if (String(allOptions[rawIndex]) === raw) { originalIndex = rawIndex; break }
      var label = originalIndex >= 0 && originalIndex < choiceLabels.length
        ? String(choiceLabels[originalIndex] || "") : ""
      result.push({
        rawOption: raw,
        label: label === "" ? raw : label,
        effect: effectForOption(originalIndex, raw),
        originalIndex: originalIndex,
        number: index + 1
      })
    }
    choiceData = result
  }

  function choiceIndexForRaw(raw) {
    for (var index = 0; index < choiceData.length; index++)
      if (String(choiceData[index].rawOption) === String(raw)) return index
    return -1
  }

  function submitChoiceByIndex(index) {
    if (index < 0 || index >= choiceData.length) return
    submitChoice(choiceData[index].rawOption)
  }

  function submitChoice(choiceLabel) {
    if (handled) return
    if (replying) {
      decisionStatus = "Already recording a decision…"
      return
    }
    replying = true
    selectedChoice = String(choiceLabel)
    decisionStatus = "Recording “" + displayLabelForOption(choiceLabel) + "”…"
    replyProcess.command = [script("reply.sh"), tbHost, tbAsUser, request.id, String(choiceLabel)]
    replyProcess.running = true
  }

  function displayLabelForOption(option) {
    for (var index = 0; index < choiceData.length; index++)
      if (String(choiceData[index].rawOption) === String(option)) return choiceData[index].label
    return String(option)
  }

  function armChoice(index, recordOnRepeat) {
    if (handled || replying || index < 0 || index >= choiceData.length) return
    focusedChoice = index
    choiceFocusActive = true
    if (recordOnRepeat !== false && armedChoice === index) submitChoiceByIndex(index)
    else armedChoice = index
    detailFocus.forceActiveFocus()
  }

  function focusChoice(index) {
    if (choiceData.length === 0) return
    focusedChoice = Math.max(0, Math.min(choiceData.length - 1, index))
    armedChoice = focusedChoice
    choiceFocusActive = true
    detailFocus.forceActiveFocus()
  }

  function handleRuleProposal(number) {
    if (number < 1) {
      proposedChoice = -1
      return
    }
    var options = request && request.options ? request.options : []
    if (number > options.length) return
    var index = choiceIndexForRaw(options[number - 1])
    if (index < 0) return
    proposedChoice = index
    armChoice(index, false)
  }

  function cycleFocus(backwards) {
    var hasChoices = choiceData.length > 0 && !handled
    if (backwards) {
      if (chat.askActive) {
        if (hasChoices) focusChoice(focusedChoice >= 0 ? focusedChoice : choiceData.length - 1)
        else chat.focusBody()
      } else if (choiceFocusActive) {
        choiceFocusActive = false
        focusedChoice = -1
        chat.focusBody()
      } else chat.focusAsk()
    } else if (!choiceFocusActive && !chat.askActive) {
      if (hasChoices) focusChoice(focusedChoice >= 0 ? focusedChoice : 0)
      else chat.focusAsk()
    } else if (choiceFocusActive) {
      choiceFocusActive = false
      focusedChoice = -1
      chat.focusAsk()
    } else chat.focusBody()
  }

  function leaveAsk() {
    choiceFocusActive = false
    focusedChoice = -1
    chat.focusBody()
  }

  function handleKey(event) {
    if (handleFontKey(event) || chat.handleMotionTunerKey(event)) return true
    if (chat.askActive) {
      if (event.key === Qt.Key_Tab) cycleFocus((event.modifiers & Qt.ShiftModifier) !== 0)
      return event.key === Qt.Key_Tab
    }
    if (event.key === Qt.Key_Tab) {
      cycleFocus((event.modifiers & Qt.ShiftModifier) !== 0)
      return true
    }
    if (event.key === Qt.Key_Slash) {
      if (root.minimumLayout) {
        minimumAskRevealed = true
        Qt.callLater(chat.focusAsk)
      } else chat.focusAsk()
      return true
    }
    var modifiers = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier)
    if (modifiers === 0 && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
      var numberIndex = event.key - Qt.Key_1
      if (numberIndex < choiceData.length) {
        armChoice(numberIndex)
        return true
      }
    }
    if (choiceFocusActive && !handled) {
      if (event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
        var previous = (focusedChoice <= 0 ? choiceData.length : focusedChoice) - 1
        focusChoice(previous)
        armedChoice = previous
        return true
      }
      if (event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
        var next = (focusedChoice + 1) % choiceData.length
        focusChoice(next)
        armedChoice = next
        return true
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        submitChoiceByIndex(focusedChoice >= 0 ? focusedChoice : armedChoice)
        return true
      }
    }
    return chat.handleScrollKey(event, false)
  }

  function resetSummary() {
    projectSummary = ""
    parentSummary = ""
    noteSummary = ""
    questionSummary = ""
    choiceLabels = []
    summaryChoiceEffects = []
    summaryRaw = ""
    refreshChoiceData()
  }

  function open() {
    openedOnce = true
    closing = false
    handled = false
    replying = false
    selectedChoice = ""
    decisionStatus = ""
    armedChoice = -1
    focusedChoice = -1
    proposedChoice = -1
    hoveredChoice = -1
    choiceFocusActive = false
    minimumAskRevealed = false
    resetSummary()
    visible = true
    summaryProcess.running = true
    chat.request = request
    chat.start()
    Qt.callLater(function() { detailFocus.forceActiveFocus() })
  }

  function resummarize() {
    if (replying || handled) return
    resetSummary()
    summaryProcess.running = false
    summaryProcess.running = true
    chat.resummarize()
  }

  function closeWindow() { visible = false }

  function markHandled() {
    if (handled) return
    replying = false
    selectedChoice = ""
    handled = true
    hoveredChoice = -1
    decisionStatus = ""
    chat.handled = true
    chat.stop(false, false)
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
    command: ["env", "HUGINN_INTERNAL=1", root.script("bridge/node.sh"), root.script("bridge/bridge.js"), "--summary"]
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.handleSummaryLine(line) } }
  }

  Process {
    id: replyProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.decisionStatus = String(text).trim()
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.decisionStatus = String(text).trim()
    }
    onExited: function(code) {
      if (code === 0) root.owner.refreshNow()
      else {
        root.replying = false
        root.selectedChoice = ""
        if (root.decisionStatus === "" || root.decisionStatus.indexOf("Recording “") === 0)
          root.decisionStatus = "Could not record that decision."
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

  component IdentifierButton: Item {
    id: identifier
    required property string label
    required property string value
    required property string display
    property bool opens: false
    property bool menuMode: false
    property bool copied: false
    readonly property real scale: root.fontScale
    readonly property real labelWidth: labelText.implicitWidth
    width: menuMode ? (parent ? parent.width : 0)
      : Math.max(90 * scale, labelText.implicitWidth + valueText.implicitWidth + 14 * scale)
    height: Math.round(30 * scale)

    Text {
      id: labelText
      x: 0
      anchors.verticalCenter: parent.verticalCenter
      text: identifier.label
      color: root.faint
      font.family: root.monoFamily
      font.pixelSize: Math.round(11 * root.fontScale)
      elide: Text.ElideRight
    }

    Text {
      id: valueText
      x: labelText.width + Math.round(6 * root.fontScale)
      anchors.verticalCenter: parent.verticalCenter
      width: identifier.menuMode ? Math.max(0, parent.width - x) : implicitWidth
      text: identifier.copied ? "copied" : identifier.display
      color: root.secondary
      font.family: root.monoFamily
      font.pixelSize: Math.round(11 * root.fontScale)
      elide: identifier.menuMode ? Text.ElideRight : Text.ElideNone
    }

    MouseArea {
      id: identifierMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        root.copyToClipboard(identifier.value)
        identifier.copied = true
        copiedReset.restart()
        if (identifier.opens) root.openPlan()
      }
    }

    PanelToolTip {
      visible: identifierMouse.containsMouse
      text: identifier.opens ? "Open plan · copy " + identifier.value : "Copy " + identifier.value
      fontFamily: root.monoFamily
      delay: 500
    }

    Timer {
      id: copiedReset
      interval: 1200
      onTriggered: identifier.copied = false
    }
  }

  FocusScope {
    id: detailFocus
    anchors.fill: parent
    focus: true

    Keys.onPressed: function(event) {
      if (root.handleKey(event)) event.accepted = true
    }
  }

  Item {
    id: detailHeader
    x: 0
    y: 0
    width: root.width
    height: root.headerHeight
    clip: true

    Rectangle {
      anchors.fill: parent
      color: root.ground
    }

    Column {
      id: headerColumn
      x: Math.round((root.wideLayout ? 28 : root.narrowLayout ? 20 : 16) * root.fontScale)
      y: Math.round((root.wideLayout ? 22 : root.narrowLayout ? 18 : 16) * root.fontScale)
      width: Math.max(0, parent.width - x * 2)
      spacing: Math.round((root.wideLayout ? 10 : root.narrowLayout ? 8 : 8) * root.fontScale)

      Item {
        id: eyebrow
        width: parent.width
        height: Math.round(22 * root.fontScale)

        Rectangle {
          id: needsYouDot
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(8 * root.fontScale)
          height: width
          radius: width / 2
          color: root.urgent
        }

        Text {
          id: projectLabel
          anchors.left: needsYouDot.right
          anchors.leftMargin: Math.round(10 * root.fontScale)
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(180 * root.fontScale, implicitWidth,
            Math.max(0, parent.width - x - eyebrowActions.width - eyebrowTime.width
              - Math.round(28 * root.fontScale)))
          text: root.projectText
          color: root.ink
          font.family: root.monoMediumFamily !== "" ? root.monoMediumFamily : root.monoFamily
          font.pixelSize: Math.round(11 * root.fontScale)
          font.weight: Font.Medium
          font.variableAxes: ({ "wght": 500 })
          font.letterSpacing: Math.round(1.3 * root.fontScale)
          elide: Text.ElideRight
        }

        Text {
          id: eyebrowKind
          anchors.left: projectLabel.right
          anchors.leftMargin: Math.round(10 * root.fontScale)
          anchors.right: eyebrowTime.left
          anchors.rightMargin: Math.round(8 * root.fontScale)
          anchors.verticalCenter: parent.verticalCenter
          text: "·  " + Kinds.info(root.request && root.request.kind).singular.toUpperCase()
          color: root.secondary
          font.family: root.monoMediumFamily !== "" ? root.monoMediumFamily : root.monoFamily
          font.pixelSize: Math.round(11 * root.fontScale)
          font.weight: Font.Medium
          font.variableAxes: ({ "wght": 500 })
          font.letterSpacing: Math.round(1.3 * root.fontScale)
          elide: Text.ElideRight
        }

        Text {
          id: eyebrowTime
          anchors.right: eyebrowActions.left
          anchors.rightMargin: Math.round(10 * root.fontScale)
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, Math.max(0, parent.width
            - eyebrowActions.width - Math.round(10 * root.fontScale)))
          text: "·  " + root.formatRaisedAt(root.request && root.request.raisedAt)
          color: root.secondary
          font.family: root.monoMediumFamily !== "" ? root.monoMediumFamily : root.monoFamily
          font.pixelSize: Math.round(11 * root.fontScale)
          font.weight: Font.Medium
          font.variableAxes: ({ "wght": 500 })
          font.letterSpacing: Math.round(1.3 * root.fontScale)
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignRight
        }

        Row {
          id: eyebrowActions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Math.round(8 * root.fontScale)

          Rectangle {
            id: resummarizeButton
            width: Math.round(28 * root.fontScale)
            height: width
            radius: width / 2
            color: resummarizeMouse.containsMouse
              ? root.mixColor(root.ground, root.ink, 0.08) : "transparent"

            Text {
              anchors.centerIn: parent
              text: "↻"
              color: root.secondary
              font.family: root.sansFamily
              font.pixelSize: Math.round(20 * root.fontScale)
            }

            MouseArea {
              id: resummarizeMouse
              anchors.fill: parent
              enabled: !root.replying && !root.handled
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.resummarize()
            }

            PanelToolTip {
              visible: resummarizeMouse.containsMouse
              text: "Re-summarize"
              fontFamily: root.monoFamily
              delay: 500
            }
          }

          Rectangle {
            id: idsButton
            visible: root.headerIdsVisible && root.hasIdentifiers()
            width: Math.round(62 * root.fontScale)
            height: Math.round(28 * root.fontScale)
            radius: height / 2
            color: idsMouse.containsMouse ? root.mixColor(root.ground, root.ink, 0.05) : "transparent"
            border.color: root.hairline
            border.width: 1

            Text {
              anchors.centerIn: parent
              text: "IDs ▾"
              color: root.secondary
              font.family: root.monoFamily
              font.pixelSize: Math.round(11 * root.fontScale)
            }

            MouseArea {
              id: idsMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: idsPopup.open()
            }
          }
        }
      }

      Text {
        id: headline
        width: parent.width
        height: Math.min(implicitHeight,
          Math.round(font.pixelSize * 1.25 * root.headlineLines))
        text: root.questionText
        color: root.ink
        font.family: root.newsreaderFamily
        font.pixelSize: Math.round((root.minimumLayout ? 21 : root.narrowLayout ? 22
          : root.headlineLines === 1 ? 21 : 27) * root.fontScale)
        font.weight: Font.Normal
        lineHeight: font.pixelSize * 1.25
        lineHeightMode: Text.FixedHeight
        wrapMode: Text.WordWrap
        maximumLineCount: root.headlineLines
        elide: Text.ElideRight

        HoverHandler { id: headlineHover }
        PanelToolTip {
          visible: headlineHover.hovered
          text: root.questionText
          fontFamily: root.newsreaderFamily
          delay: 500
        }
      }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: root.hairline
    }
  }

  Popup {
    id: idsPopup
    x: Math.max(8 * root.fontScale, root.width - width - 16 * root.fontScale)
    y: detailHeader.height - Math.round(8 * root.fontScale)
    width: Math.min(root.width - 16 * root.fontScale, 420 * root.fontScale)
    height: Math.min(idsContents.height + Math.round(20 * root.fontScale),
      Math.max(0, root.height - 24 * root.fontScale))
    padding: Math.round(10 * root.fontScale)
    modal: false
    focus: false
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
      color: root.ground
      border.color: root.hairline
      border.width: 1
      radius: Style.cornerRadius
    }

    contentItem: Flickable {
      clip: true
      contentWidth: width
      contentHeight: idsContents.height
      interactive: contentHeight > height
      flickableDirection: Flickable.VerticalFlick

      Item {
        id: idsContents
        width: parent.width
        height: root.measureRepeaterHeight(idsRepeater)
          + Math.max(0, idsRepeater.count - 1) * Math.round(4 * root.fontScale)

        Repeater {
          id: idsRepeater
          model: root.identifierEntries()
          delegate: IdentifierButton {
            required property var modelData
            required property int index
            width: idsContents.width
            y: root.stackOffset(idsRepeater, index, Math.round(4 * root.fontScale))
            label: String(modelData.label)
            value: String(modelData.value)
            display: String(modelData.display)
            opens: !!modelData.opens
            menuMode: true
          }
        }
      }
    }
  }

  Item {
    id: contentArea
    x: 0
    y: root.headerHeight
    width: root.width
    height: root.contentAreaHeight
  }

  DecisionChat {
    id: chat
    x: 0
    y: root.minimumLayout
      ? (root.handled ? minimumOutcome.y : minimumStrip.y)
        - (root.minimumAskRevealed ? askLineHeight : 0)
      : contentArea.y
    width: root.wideLayout ? Math.max(0, root.width - root.decideWidth) : root.width
    height: root.minimumLayout
      ? (root.minimumAskRevealed ? askLineHeight : 0) : Math.max(0, contentArea.height
        - (root.narrowLayout && root.handled ? narrowOutcome.height : 0))
    visible: !root.minimumLayout || root.minimumAskRevealed
    request: root.request
    host: root.tbHost
    user: root.tbAsUser
    messageScript: root.script("message.sh")
    fontScale: root.fontScale
    newsreaderFamily: root.newsreaderFamily
    newsreaderItalicFamily: root.newsreaderItalicFamily
    sansFamily: root.sansFamily
    sansItalicFamily: root.sansItalicFamily
    monoFamily: root.monoFamily
    monoMediumFamily: root.monoMediumFamily
    ground: root.ground
    foreground: root.ink
    secondary: root.secondary
    faint: root.faint
    hairline: root.hairline
    keyBorder: root.keyBorder
    accent: root.urgent
    rulingChoices: root.choiceData
    summaryChoiceLabels: root.choiceLabels
    summaryChoiceEffects: root.summaryChoiceEffects
    summaryParent: root.parentSummary
    summaryNotes: root.noteSummary
    armedChoice: root.armedChoice
    focusedChoice: root.focusedChoice
    proposedChoice: root.proposedChoice
    recording: root.replying
    recordingChoice: root.selectedChoice
    decisionStatus: root.decisionStatus
    handled: root.handled
    narrowLayout: root.narrowLayout
    minimumMode: root.minimumLayout
    compactAsk: !root.wideLayout
    showInlineChoices: root.narrowLayout && !root.handled
    keyAction: function(event) { return root.handleKey(event) }
    bodyVisible: !root.minimumLayout
    askVisible: !root.minimumLayout || root.minimumAskRevealed
    ruleAction: function(choiceLabel) { root.submitChoice(choiceLabel) }
    onChoiceFocused: function(index) { root.focusChoice(index) }
    onFocusCycleRequested: function(backwards) { root.cycleFocus(backwards) }
    onAskEscapeRequested: root.leaveAsk()
    onAssistantMessageFinished: {
      root.refreshChoiceData()
      var nativeWindow = root.contentItem.Window.window
      if (root.visible && nativeWindow && !nativeWindow.active) nativeWindow.requestActivate()
    }
    onFontStepRequested: function(step) { root.owner.adjustFontScale(step) }
    onFontResetRequested: root.owner.setFontScale(1)
    onMotionTunerRequested: root.owner.openMotionTuner()
  }

  Rectangle {
    id: decidePanel
    visible: root.wideLayout
    x: root.width - root.decideWidth
    y: contentArea.y
    width: root.decideWidth
    height: contentArea.height
    color: root.panel
    clip: true

    Column {
      id: decideContents
      x: root.decidePadding
      y: root.decidePadding
      width: Math.max(0, parent.width - root.decidePadding * 2)
      height: Math.max(0, parent.height - root.decidePadding * 2)
      spacing: 0

      Item {
        width: parent.width
        height: root.decideHeadingHeight

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "DECIDE"
          color: root.ink
          font.family: root.monoMediumFamily !== "" ? root.monoMediumFamily : root.monoFamily
          font.pixelSize: Math.round(11 * root.fontScale)
          font.weight: Font.Medium
          font.variableAxes: ({ "wght": 500 })
          font.letterSpacing: Math.round(1.3 * root.fontScale)
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.armedChoice >= 0 && root.armedChoice < root.choiceData.length
            ? "⏎ to record \"" + root.choiceData[root.armedChoice].label + "\""
            : "↑↓  ⏎ or a number"
          color: root.secondary
          font.family: root.monoFamily
          font.pixelSize: Math.round(11 * root.fontScale)
          elide: Text.ElideLeft
        }
      }

      Item {
        id: decideRows
        width: parent.width
        height: root.handled ? 0
          : Math.max(0, parent.height - root.decideHeadingHeight - root.decisionStatusHeight)
        clip: true
        visible: !root.handled

        Repeater {
          id: decideRepeater
          model: root.choiceData
          delegate: DecisionChoice {
            required property var modelData
            required property int index
            width: decideRows.width
            y: root.stackOffset(decideRepeater, index, 0)
            density: root.choiceDensity
            label: String(modelData.label || "")
            effect: String(modelData.effect || "")
            rawOption: String(modelData.rawOption || "")
            number: Number(modelData.number || index + 1)
            armed: root.armedChoice === index
            focused: root.focusedChoice === index
            focusActive: root.choiceFocusActive
            proposed: root.proposedChoice === index
            recording: root.replying && String(modelData.rawOption || "") === root.selectedChoice
            interactive: !root.replying && !root.handled
            fontScale: root.fontScale
            sansFamily: root.sansFamily
            sansMediumFamily: root.sansFamily
            monoFamily: root.monoFamily
            ground: root.ground
            ink: root.ink
            secondary: root.secondary
            faint: root.faint
            hairline: root.hairline
            keyBorder: root.keyBorder
            tooltipsEnabled: true
            onConsequenceHovered: function(hovered) {
              root.hoveredChoice = hovered ? index
                : (root.hoveredChoice === index ? -1 : root.hoveredChoice)
            }
            onFocusedByUser: root.focusChoice(index)
            onActivated: root.submitChoiceByIndex(index)
          }
        }
      }

      Text {
        id: decisionError
        width: parent.width
        height: root.handled ? 0 : root.decisionStatusHeight
        visible: root.decisionErrorVisible
        text: root.decisionStatus
        color: root.secondary
        font.family: root.monoFamily
        font.pixelSize: Math.round(11 * root.fontScale)
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
      }

      DecisionOutcome {
        visible: root.handled
        width: parent.width
        height: root.handled ? Math.max(0, parent.height - root.decideHeadingHeight) : 0
        status: root.handledStatus
        actor: root.handledActor
        determination: root.handledDetermination
        fontScale: root.fontScale
        sansFamily: root.sansFamily
        monoFamily: root.monoFamily
        foreground: root.ink
        secondary: root.secondary
        hairline: root.hairline
        background: root.panel
      }
    }
  }

  DecisionConsequenceTip {
    id: wideChoiceTip
    anchorItem: root.wideLayout && !root.replying && !root.handled
      && root.choiceDensity !== "full"
      && root.hoveredChoice >= 0 ? decideRepeater.itemAt(root.hoveredChoice) : null
    boundsItem: decidePanel
    consequence: root.hoveredChoice >= 0 && root.hoveredChoice < root.choiceData.length
      ? String(root.choiceData[root.hoveredChoice].effect || "") : ""
    sansFamily: root.sansFamily
    fontScale: root.fontScale
  }

  Item {
    id: fullMeasure
    opacity: 0
    x: -10000
    y: -10000
    width: root.decideContentWidth
    Repeater {
      id: fullMeasureRepeater
      model: root.choiceData
      delegate: DecisionChoice {
        required property var modelData
        required property int index
        width: fullMeasure.width
        density: "full"
        label: String(modelData.label || "")
        effect: String(modelData.effect || "")
        rawOption: String(modelData.rawOption || "")
        number: Number(modelData.number || index + 1)
        proposed: root.proposedChoice === index
        interactive: false
        tooltipsEnabled: false
        fontScale: root.fontScale
        sansFamily: root.sansFamily
        sansMediumFamily: root.sansFamily
        monoFamily: root.monoFamily
        ground: root.ground
        ink: root.ink
        secondary: root.secondary
        faint: root.faint
        hairline: root.hairline
        keyBorder: root.keyBorder
      }
    }
  }

  Item {
    id: clampedMeasure
    opacity: 0
    x: -10000
    y: -10000
    width: root.decideContentWidth
    Repeater {
      id: clampedMeasureRepeater
      model: root.choiceData
      delegate: DecisionChoice {
        required property var modelData
        required property int index
        width: clampedMeasure.width
        density: "clamped"
        label: String(modelData.label || "")
        effect: String(modelData.effect || "")
        rawOption: String(modelData.rawOption || "")
        number: Number(modelData.number || index + 1)
        interactive: false
        tooltipsEnabled: false
        fontScale: root.fontScale
        sansFamily: root.sansFamily
        sansMediumFamily: root.sansFamily
        monoFamily: root.monoFamily
        ground: root.ground
        ink: root.ink
        secondary: root.secondary
        faint: root.faint
        hairline: root.hairline
        keyBorder: root.keyBorder
      }
    }
  }

  DecisionCompactStrip {
    id: minimumStrip
    visible: root.minimumLayout && !root.handled
    x: 0
    y: root.height - height
    width: root.width
    columns: root.width >= 480 ? 3 : 2
    showLabel: true
    showExplain: false
    hint: root.decisionErrorVisible ? root.decisionStatus : "/ to ask · enlarge for the brief"
    choices: root.choiceData
    fontScale: root.fontScale
    armedIndex: root.armedChoice
    focusedIndex: root.focusedChoice
    proposedIndex: root.proposedChoice
    focusActive: root.choiceFocusActive
    recordingChoice: root.selectedChoice
    interactive: !root.replying
    sansFamily: root.sansFamily
    sansMediumFamily: root.sansFamily
    monoFamily: root.monoFamily
    monoMediumFamily: root.monoMediumFamily
    ground: root.ground
    panel: root.panel
    ink: root.ink
    secondary: root.secondary
    faint: root.faint
    hairline: root.hairline
    keyBorder: root.keyBorder
    onChoiceFocused: root.focusChoice(index)
    onChoiceActivated: root.submitChoiceByIndex(index)
  }

  DecisionOutcome {
    id: narrowOutcome
    visible: root.narrowLayout && root.handled
    x: 0
    y: contentArea.y + Math.max(0, contentArea.height - height)
    width: root.width
    height: root.handled
      ? Math.min(Math.max(96 * root.fontScale, implicitHeight), contentArea.height) : 0
    status: root.handledStatus
    actor: root.handledActor
    determination: root.handledDetermination
    fontScale: root.fontScale
    sansFamily: root.sansFamily
    monoFamily: root.monoFamily
    foreground: root.ink
    secondary: root.secondary
    hairline: root.hairline
    background: root.panel
  }

  DecisionOutcome {
    id: minimumOutcome
    visible: root.minimumLayout && root.handled
    x: 0
    y: root.height - height
    width: root.width
    height: root.handled
      ? Math.min(Math.max(96 * root.fontScale, implicitHeight), root.height) : 0
    status: root.handledStatus
    actor: root.handledActor
    determination: root.handledDetermination
    fontScale: root.fontScale
    sansFamily: root.sansFamily
    monoFamily: root.monoFamily
    foreground: root.ink
    secondary: root.secondary
    hairline: root.hairline
    background: root.panel
  }

  Item {
    id: footer
    visible: root.footerRoom
    x: 0
    y: root.height - root.footerHeight
    width: root.width
    height: root.footerHeight
    clip: true

    Rectangle { anchors.fill: parent; color: root.ground; border.color: root.hairline; border.width: 1 }

    Flickable {
      anchors.fill: parent
      anchors.leftMargin: Math.round(28 * root.fontScale)
      anchors.rightMargin: Math.round(28 * root.fontScale)
      contentWidth: footerRow.width
      contentHeight: height
      clip: true
      flickableDirection: Flickable.HorizontalFlick
      interactive: contentWidth > width

      Item {
        id: footerRow
        height: parent.height
        width: root.measureRepeaterWidth(footerRepeater)
          + Math.max(0, footerRepeater.count - 1) * Math.round(18 * root.fontScale)
        Repeater {
          id: footerRepeater
          model: root.identifierEntries()
          delegate: IdentifierButton {
            required property var modelData
            required property int index
            x: root.rowOffset(footerRepeater, index, Math.round(18 * root.fontScale))
            label: String(modelData.label)
            value: String(modelData.value)
            display: String(modelData.display)
            opens: !!modelData.opens
          }
        }
      }
    }
  }

  Connections {
    target: chat
    function onChoiceEffectsChanged() { root.refreshChoiceData() }
    function onProposedRuleChanged() { root.handleRuleProposal(chat.proposedRule) }
  }

  Component.onCompleted: root.refreshChoiceData()

  onVisibleChanged: if (!visible && openedOnce && !closing) {
    closing = true
    chat.stop(false, true)
    summaryProcess.running = false
    detailClosed(root)
  }
}
