import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// A conversation about ONE decision request, driven by the local ACP agent.
//
// The agent explains the request and proposes an answer; it never records the
// ruling itself. It asks for a choice by emitting a fenced block:
//
//   ```choices          ```rule
//   option one          2
//   option two          ```
//   ```
//
// A `choices` line that names one of the request's options is a RULING button:
// clicking it calls ruleRequested(label) and the panel records it. Any other line is
// conversation and is sent back as the next prompt. `rule` produces the same
// ruling button when the agent wants to propose one after discussion. The agent
// never records anything itself — the click does.
Item {
  id: root

  property var request: null
  // Blank host: the CLI runs on this machine. Blank user: whatever account
  // the CLI runs as. Both are resolved by tightbeam.sh, not assumed here.
  property string host: ""
  property string user: ""
  property string messageScript: ""
  property bool decisionBusy: false
  // Driven by the panel so the window and the dropdown always match.
  property real fontScale: 1
  readonly property int captionSize: Math.round(Style.font.caption * fontScale)
  readonly property int bodySize: Math.round(Style.font.body * fontScale)
  readonly property int titleSize: Math.round(Style.font.title * fontScale)
  readonly property int displaySize: Math.round(Style.font.display * fontScale)
  readonly property int humanMessageSize: Math.max(titleSize, Math.round(bodySize * 1.5))
  readonly property string hostLabel: host === "" ? "this machine" : "the " + host + " gateway"
  readonly property string quotedHost: host === "" ? "\"\"" : host
  readonly property string quotedUser: user === "" ? "\"\"" : user
  // Read-only lookups: run the CLI directly when this machine is the node,
  // otherwise hop over ssh. --as-user is only pinned when it was configured.
  readonly property string lookupCommand: (host === "" ? "tightbeam" : "ssh " + host + " tightbeam")
    + (user === "" ? "" : " --as-user " + user)
  // The ACP bridge shipped with the Ask plugin: a standalone Node script
  // speaking NDJSON over stdio. Reused as-is rather than vendored.
  readonly property string bridgePath: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/mike.tightbeam-decisions/configured-chat-bridge.js"

  // The bridge ships with the Ask plugin, in a different repo, so it can
  // disappear without anything here changing. Detect that rather than letting
  // the process just exit -- the generic "session ended" message would send
  // you looking in the wrong place entirely.
  property bool bridgeMissing: false

  FileView {
    path: root.bridgePath
    printErrors: false
    onLoaded: root.bridgeMissing = false
    onLoadFailed: root.bridgeMissing = true
  }

  signal ruleRequested(string choiceLabel)
  // The panel owns the scale; the chat only asks for a change. Routed as
  // signals because a focused TextEdit or TextArea claims Ctrl +/- before any
  // window-level handler sees it.
  signal fontStepRequested(real step)
  signal fontResetRequested()
  signal motionTunerRequested()
  property real keyboardLineImpulse: 335
  property real keyboardPageImpulse: 689
  property real keyboardDeceleration: 608
  property bool motionTunerOpen: false
  onMotionTunerOpenChanged: if (!motionTunerOpen && visible)
    Qt.callLater(function() { input.forceActiveFocus() })
  property real keyboardVelocityY: 0
  property double keyboardSampleTime: 0

  function handleFontKey(event) {
    if ((event.modifiers & Qt.ControlModifier) === 0) return false
    if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) { fontStepRequested(0.1); return true }
    if (event.key === Qt.Key_Minus || event.key === Qt.Key_Underscore) { fontStepRequested(-0.1); return true }
    if (event.key === Qt.Key_0) { fontResetRequested(); return true }
    return false
  }

  property bool bridgeReady: false
  property bool waiting: false
  property bool sessionLost: false
  property string statusText: ""
  property string decisionStatus: ""
  property int activeReply: -1
  property string activeReplyMessageId: ""
  property string queuedPrompt: ""
  property string pendingPermissionId: ""
  property string pendingPermissionTitle: ""
  property var choices: []
  property int proposedRule: -1
  property int submittedPromptIndex: -1
  property bool submittedPromptSpaceActive: false
  property real submittedPromptY: 0

  readonly property color foreground: Color.foreground
  readonly property color accent: Color.accent
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
  readonly property color surface: Color.background
  readonly property color muted: mixColor(surface, foreground, 0.85)

  // Qt collapses ordinary Markdown paragraph gaps. Preserve them for display
  // without changing the message stored in the conversation model.
  function spacedMarkdown(text) {
    var value = String(text || "")
    if (value.indexOf("\n") < 0) return value
    var lines = value.split("\n")
    var out = []
    var fenced = false
    var pendingBreak = false
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      var fence = /^\s{0,3}(```|~~~)/.test(line)
      if (fence) fenced = !fenced
      if (!fenced && !fence && line.trim() === "") {
        if (out.length > 0) pendingBreak = true
        continue
      }
      if (pendingBreak) {
        pendingBreak = false
        if (/^\s*([-*+]|\d+[.)])\s/.test(line)) out.push("")
        else out.push("", "\u00a0", "")
      }
      out.push(line)
    }
    return out.join("\n")
  }

  function briefing() {
    var options = request && request.options ? request.options : []
    var numbered = []
    for (var i = 0; i < options.length; i++) numbered.push((i + 1) + ". " + options[i])
    return [
      "You are explaining one Tightbeam decision request to Mike, on his desktop.",
      "",
      "WHAT TIGHTBEAM IS: an agent-coordination substrate. Agent sessions hold",
      "assignments, attest to work they claim, and record artifacts pointing at what",
      "they produced. It runs on " + hostLabel + ". When an agent hits a question",
      "only its human owner can settle, it files an operator decision request — this",
      "one. Recording a ruling wakes the agent that asked and it proceeds.",
      "",
      "WHAT THIS REQUEST BELONGS TO: " + (request && request.subject ? request.subject : "unstated"),
      (request && request.workItemId
        ? "Its work item is " + request.workItemId + ". Read that item first -- it is the"
        : "No work item is linked. Establish from the assignment what work this serves"),
      (request && request.workItemId
        ? "fastest way to learn which project this is and why the question exists."
        : "before answering, and say so if you cannot."),
      "",
      "WHO YOU ARE TALKING TO: Mike owns this org but does NOT have the context these",
      "requests assume. They are written by agents deep in a task, in that task's",
      "jargon. Your job is to make this one legible, then help him decide.",
      "",
      "GO AND LOOK BEFORE YOU EXPLAIN. The context is on " + hostLabel + ", not in this prompt.",
      "Run read-only lookups over ssh:",
      "  " + lookupCommand + " <cmd>",
      "Do not announce that you are about to look. Look first, then answer; never",
      "open with a line about what you are going to do.",
      "Useful commands: attests, artifacts, work-item-get, work-item-trace, topline,",
      "transcript, assignments, decision-requests. Id prefixes: att_ attestation,",
      "art_ artifact, asg_ assignment, wi_ work item, dr_ decision request. Follow",
      "every id and URL the request mentions. Read PRs with gh if one is linked.",
      "",
      "THEN ANSWER AS CLEAN, POLISHED MARKDOWN IN EXACTLY THIS SHAPE:",
      "## TL;DR",
      "A two-or-three sentence summary in plain words. No Tightbeam jargon or ids.",
      "## What the options mean",
      "Use one concise bullet per option. Bold the option label, then explain what",
      "choosing it actually causes — consequences and tradeoffs, not a restatement.",
      "## Recommendation",
      "State your recommendation directly, followed by any real uncertainty.",
      "Use short paragraphs, helpful bold emphasis, and lists where appropriate.",
      "Do not output raw JSON, HTML, a preamble, or a heading for the request itself.",
      "Keep it short. He is reading this in a small window, not a report.",
      "",
      "ASKING HIM THINGS: when you want him to pick between things, end your message",
      "with a fenced block tagged `choices`, one option per line, plain text. It",
      "renders as buttons. Use it for your own questions too, not just the request's",
      "options — 'shall I read the PR diff?' is a fine use.",
      "",
      "IMPORTANT: a line that exactly matches one of the request's option labels",
      "RECORDS that ruling the moment he clicks it. So only write an exact label when",
      "clicking it should settle the request. If you are merely asking about an option,",
      "word it as a question ('lean toward accept?') so it stays a conversation.",
      "",
      "RECORDING THE ANSWER: a human or its explicit delegate closes the row. By default",
      "that is him. When you and he have agreed, end your message with a fenced block",
      "tagged `rule` containing ONLY the option number. That gives him a confirm button.",
      "Never emit `rule` before he has actually agreed.",
      "",
      "He may instead delegate the recording to you. If he does so explicitly, in the",
      "same exchange, naming an unambiguous outcome for THIS row, record it yourself:",
      "  " + lookupCommand + " --as-user " + quotedUser + " operator-rule " + (request ? request.id : "") + " --decision <label> --rationale \"<text>\"",
      "The --rationale MUST say that he delegated the recording and quote the instruction",
      "that did it, so a later reader can tell a relayed ruling from one he typed. Do not",
      "infer delegation from impatience, from a general 'just handle it', or from your own",
      "reading of what he would want. Absent that, the button is his to press.",
      "",
      "SENDING A NOTE WITHOUT RULING: if he wants to ask the raising agent something,",
      "or hand it context, without resolving the request, run:",
      "  " + messageScript + " " + quotedHost + " " + quotedUser + " " + (request ? request.id : "") + " \"<text>\"",
      "Agree the exact wording with him first.",
      "",
      "THE REQUEST:",
      JSON.stringify(request, null, 2),
      "",
      "ITS OPTIONS, BY NUMBER (this numbering is what `rule` refers to):",
      numbered.join("\n"),
      "",
      "Start now: look things up, then explain."
    ].join("\n")
  }

  function start() {
    if (!request) return
    // Never stack a second bridge on a live one.
    if (agent.running) stop()
    messages.clear()
    choices = []
    proposedRule = -1
    submittedPromptIndex = -1
    submittedPromptSpaceActive = false
    submittedPromptY = 0
    bridgeReady = false
    sessionLost = false
    activeReply = -1
    activeReplyMessageId = ""
    statusText = "Reading the request…"
    waiting = true
    messages.append({ role: "Claude", body: "" })
    activeReply = 0
    queuedPrompt = briefing()
    agent.running = true
  }

  function stop() {
    if (agent.running) agent.write(JSON.stringify({ type: "close" }) + "\n")
    agent.running = false
    bridgeReady = false
    waiting = false
    queuedPrompt = ""
    statusText = ""
    decisionStatus = ""
    choices = []
    proposedRule = -1
    submittedPromptIndex = -1
    submittedPromptSpaceActive = false
    submittedPromptY = 0
    keyboardVelocityY = 0
    keyboardCoast.stop()
    trackpadCoast.stop()
    messages.clear()
  }

  function send(text) {
    var value = String(text || "").trim()
    if (value === "" || waiting || sessionLost) return
    choices = []
    proposedRule = -1
    waiting = true
    statusText = "Thinking…"
    messages.append({ role: "You", body: value })
    submittedPromptIndex = messages.count - 1
    submittedPromptSpaceActive = true
    submittedPromptY = 0
    messages.append({ role: "Claude", body: "" })
    activeReply = messages.count - 1
    activeReplyMessageId = ""
    queuedPrompt = value
    revealLatestTimer.restart()
    if (bridgeReady) flush()
  }

  function flush() {
    if (queuedPrompt === "" || !agent.running || !bridgeReady) return
    agent.write(JSON.stringify({ type: "prompt", text: queuedPrompt }) + "\n")
    queuedPrompt = ""
  }

  function appendReply(text, messageId) {
    if (activeReply < 0 || activeReply >= messages.count || text === "") return
    var next = String(messageId || "")
    if (next !== "" && activeReplyMessageId !== "" && next !== activeReplyMessageId) {
      messages.append({ role: "Claude", body: "" })
      activeReply = messages.count - 1
    }
    if (next !== "") activeReplyMessageId = next
    messages.setProperty(activeReply, "body", (messages.get(activeReply).body || "") + text)
  }

  // Pull the fenced control blocks out of a finished reply and hide them from
  // the rendered markdown — they are UI, not prose.
  function harvestBlocks() {
    if (activeReply < 0 || activeReply >= messages.count) return
    var body = String(messages.get(activeReply).body || "")
    var pattern = /```(choices|rule)[ \t]*\n([\s\S]*?)```/g
    var found = []
    var rule = -1
    var match
    while ((match = pattern.exec(body)) !== null) {
      if (match[1] === "choices") {
        var lines = String(match[2]).split("\n")
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim()
          if (line !== "") found.push(line)
        }
      } else {
        var parsed = parseInt(String(match[2]).trim(), 10)
        if (!isNaN(parsed)) rule = parsed
      }
    }
    if (found.length === 0 && rule < 0) return
    messages.setProperty(activeReply, "body", body.replace(pattern, "").trim())
    choices = found
    proposedRule = rule
  }

  // A chip whose text IS one of the request's options rules directly — clicking
  // "dismiss" should dismiss, not start another round of confirmation.
  function optionIndexFor(label) {
    var options = request && request.options ? request.options : []
    var wanted = String(label || "").trim().toLowerCase()
    for (var i = 0; i < options.length; i++)
      if (String(options[i]).trim().toLowerCase() === wanted) return i + 1
    return -1
  }

  function rulingChoices() {
    // The request already carries its authoritative ruling options. Render
    // those immediately instead of waiting for the summarizer to echo them
    // back in its optional `choices` block.
    var result = []
    var options = request && request.options ? request.options : []
    for (var i = 0; i < options.length; i++) {
      var label = String(options[i])
      if (request && request.kind === "effort" && label !== "continue" && label !== "dismiss") continue
      result.push(label)
    }
    return result
  }

  function conversationChoices() {
    var result = []
    for (var i = 0; i < choices.length; i++)
      if (optionIndexFor(choices[i]) < 0) result.push(choices[i])
    return result
  }

  // Keyboard scrolling for the transcript, same shape as Ask's conversation so
  // the two panes answer to the same keys: arrows and Ctrl+hjkl by line,
  // PageUp/PageDown and Ctrl+u/d by page.
  //
  // requireModifier is set by the composer: while typing, bare arrows have to
  // keep moving the caret, so only the Ctrl and Page forms scroll there.
  function scrollBy(dx, dy) {
    keyboardVelocityY = 0
    keyboardCoast.stop()
    trackpadCoast.stop()
    promptRevealAnimation.stop()
    log.cancelFlick()
    var maxY = Math.max(0, log.contentHeight - log.height)
    log.contentY = Math.max(0, Math.min(maxY, log.contentY + dy))
    var maxX = Math.max(0, log.contentWidth - log.width)
    log.contentX = Math.max(0, Math.min(maxX, log.contentX + dx))
  }

  function positionSubmittedPromptAtTop() {
    if (!submittedPromptSpaceActive || submittedPromptIndex < 0) return
    var promptItem = messageRepeater.itemAt(submittedPromptIndex)
    if (!promptItem) { revealLatestTimer.restart(); return }
    keyboardVelocityY = 0
    keyboardCoast.stop()
    trackpadCoast.stop()
    promptRevealAnimation.stop()
    log.cancelFlick()
    // Keep a line and a half of the preceding conversation peeking above the
    // prompt so its position in the transcript remains visually obvious.
    submittedPromptY = Math.max(0, promptItem.y - root.humanMessageSize * 1.5)
    Qt.callLater(function() {
      promptRevealAnimation.from = log.contentY
      promptRevealAnimation.to = root.submittedPromptY
      promptRevealAnimation.start()
    })
  }

  function scrollLine(dx, dy) {
    scrollBy(dx * Style.space(44), dy * Style.space(44))
  }

  function coastVertically(velocity) {
    promptRevealAnimation.stop()
    trackpadCoast.stop()
    var speed = Math.min(log.maximumFlickVelocity, Math.abs(velocity))
    if (speed <= 40) return
    var direction = velocity < 0 ? -1 : 1
    var distance = speed * speed / (2 * log.flickDeceleration)
    var maxY = Math.max(0, log.contentHeight - log.height)
    var destination = Math.max(0, Math.min(maxY, log.contentY + direction * distance))
    if (Math.abs(destination - log.contentY) <= 1) return
    trackpadCoast.from = log.contentY
    trackpadCoast.to = destination
    trackpadCoast.duration = Math.max(900, Math.min(2800,
      Math.round(speed * 1800 / log.flickDeceleration)))
    trackpadCoast.start()
  }

  function scrollKeyImpulse(dx, dy, page) {
    if (dx !== 0) scrollBy(dx * Style.space(44), 0)
    if (dy === 0) return
    log.cancelFlick()
    trackpadCoast.stop()
    promptRevealAnimation.stop()
    var impulse = page ? keyboardPageImpulse : keyboardLineImpulse
    keyboardVelocityY = Math.max(-log.maximumFlickVelocity,
      Math.min(log.maximumFlickVelocity, keyboardVelocityY + dy * impulse))
    keyboardSampleTime = Date.now()
    keyboardCoast.start()
  }

  function handleMotionTunerKey(event) {
    if ((event.modifiers & Qt.ControlModifier) === 0 || event.key !== Qt.Key_Comma) return false
    motionTunerRequested()
    return true
  }

  function handleScrollKey(event, requireModifier) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    if (ctrl && event.key === Qt.Key_K) { scrollKeyImpulse(0, -1, false); return true }
    if (ctrl && event.key === Qt.Key_J) { scrollKeyImpulse(0, 1, false); return true }
    if (ctrl && event.key === Qt.Key_H) { scrollKeyImpulse(-1, 0, false); return true }
    if (ctrl && event.key === Qt.Key_L) { scrollKeyImpulse(1, 0, false); return true }
    if (event.key === Qt.Key_PageUp || (ctrl && event.key === Qt.Key_U)) { scrollKeyImpulse(0, -1, true); return true }
    if (event.key === Qt.Key_PageDown || (ctrl && event.key === Qt.Key_D)) { scrollKeyImpulse(0, 1, true); return true }
    if (requireModifier) return false
    if (event.key === Qt.Key_Up) { scrollKeyImpulse(0, -1, false); return true }
    if (event.key === Qt.Key_Down) { scrollKeyImpulse(0, 1, false); return true }
    if (event.key === Qt.Key_Left) { scrollKeyImpulse(-1, 0, false); return true }
    if (event.key === Qt.Key_Right) { scrollKeyImpulse(1, 0, false); return true }
    return false
  }
  function answerPermission(allow) {
    if (pendingPermissionId === "") return
    agent.write(JSON.stringify({ type: "permission", id: pendingPermissionId, allow: allow }) + "\n")
    pendingPermissionId = ""
    pendingPermissionTitle = ""
    statusText = allow ? "Working…" : "Tool denied"
  }

  function handleLine(rawLine) {
    var line = String(rawLine || "").trim()
    if (line === "") return
    try {
      var event = JSON.parse(line)
      if (event.type === "ready") {
        bridgeReady = true
        flush()
      } else if (event.type === "text") {
        appendReply(String(event.text || ""), String(event.messageId || ""))
        statusText = "Replying…"
      } else if (event.type === "done") {
        waiting = false
        statusText = ""
        harvestBlocks()
        activeReplyMessageId = ""
      } else if (event.type === "status") {
        statusText = String(event.text || "Working…")
      } else if (event.type === "tool") {
        statusText = String(event.status || "") === "completed"
          ? "Thinking…"
          : String(event.title || "Using a tool")
      } else if (event.type === "permission") {
        pendingPermissionId = String(event.id || "")
        pendingPermissionTitle = String(event.title || "Use a tool")
      } else if (event.type === "error") {
        waiting = false
        statusText = String(event.message || "Agent error")
      } else if (event.type === "fatal") {
        bridgeReady = false
        sessionLost = true
        waiting = false
        statusText = String(event.message || "Session lost") + " · reopen to retry"
      }
    } catch (error) {}
  }

  ListModel { id: messages }

  Process {
    id: agent
    command: ["env", "HUGINN_INTERNAL=1", "node", root.bridgePath]
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.handleLine(line) } }
    onExited: {
      root.bridgeReady = false
      if (!root.sessionLost && root.waiting) {
        root.waiting = false
        root.sessionLost = true
        root.statusText = root.bridgeMissing
          ? "Chat needs the Ask plugin: its ACP bridge is missing at " + root.bridgePath
          : "ACP session ended · reopen to retry"
      }
    }
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(10)

    Flickable {
      id: log
      width: parent.width
      height: parent.height - composer.height - choiceFlow.height - Style.space(20)
      contentHeight: transcript.height
      clip: true
      interactive: contentHeight > height
      flickableDirection: Flickable.VerticalFlick
      maximumFlickVelocity: 6000
      flickDeceleration: 650
      boundsBehavior: Flickable.StopAtBounds
      onDraggingChanged: {
        if (!dragging) return
        root.keyboardVelocityY = 0
        keyboardCoast.stop()
        trackpadCoast.stop()
        promptRevealAnimation.stop()
      }

      // Submission creates a viewport of space below the new prompt, then
      // places that prompt at the top. Assistant output fills that space;
      // streaming itself never changes contentY.
      Timer {
        id: revealLatestTimer
        interval: 1
        repeat: false
        onTriggered: {
          root.keyboardVelocityY = 0
          keyboardCoast.stop()
          trackpadCoast.stop()
          log.cancelFlick()
          root.positionSubmittedPromptAtTop()
        }
      }

      Timer {
        id: keyboardCoast
        interval: 16
        repeat: true
        onTriggered: {
          var now = Date.now()
          var elapsed = Math.max(1, Math.min(40, now - root.keyboardSampleTime)) / 1000
          root.keyboardSampleTime = now
          var velocity = root.keyboardVelocityY
          var maxY = Math.max(0, log.contentHeight - log.height)
          var nextY = Math.max(0, Math.min(maxY, log.contentY + velocity * elapsed))
          log.contentY = nextY
          if ((nextY <= 0 && velocity < 0) || (nextY >= maxY && velocity > 0)) {
            root.keyboardVelocityY = 0
            stop()
            return
          }
          var loss = root.keyboardDeceleration * elapsed
          if (Math.abs(velocity) <= loss) {
            root.keyboardVelocityY = 0
            stop()
          } else {
            root.keyboardVelocityY = velocity > 0 ? velocity - loss : velocity + loss
          }
        }
      }

      NumberAnimation {
        id: promptRevealAnimation
        target: log
        property: "contentY"
        duration: 420
        easing.type: Easing.OutCubic
      }

      NumberAnimation {
        id: trackpadCoast
        target: log
        property: "contentY"
        easing.type: Easing.OutQuint
      }

      WheelHandler {
        id: trackpadWheel
        target: null
        blocking: true
        acceptedButtons: Qt.NoButton
        acceptedDevices: PointerDevice.TouchPad | PointerDevice.Mouse
        property double lastSampleTime: 0
        property real releaseVelocityY: 0

        function coast() {
          coastTimer.stop()
          root.coastVertically(-releaseVelocityY)
          lastSampleTime = 0
          releaseVelocityY = 0
        }

        onWheel: function(wheel) {
          if (wheel.pixelDelta.x === 0 && wheel.pixelDelta.y === 0) {
            var steps = wheel.angleDelta.y / 120
            var sideways = wheel.angleDelta.x / 120
            if (steps !== 0 || sideways !== 0)
              root.scrollLine(-sideways * 3, -steps * 3)
            wheel.accepted = true
            return
          }

          root.keyboardVelocityY = 0
          keyboardCoast.stop()
          trackpadCoast.stop()
          promptRevealAnimation.stop()
          log.cancelFlick()
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
          releaseVelocityY = releaseVelocityY * 0.55 + dy * 1000 / elapsed * 0.45
          lastSampleTime = now

          var maxY = Math.max(0, log.contentHeight - log.height)
          log.contentY = Math.max(0, Math.min(maxY, log.contentY - dy))
          coastTimer.restart()
          wheel.accepted = true
        }
      }

      Timer { id: coastTimer; interval: 55; onTriggered: trackpadWheel.coast() }

      Column {
        id: transcript
        width: log.width
        spacing: Style.space(10)

        Repeater {
          id: messageRepeater
          model: messages
          Item {
            required property int index
            required property string role
            required property string body
            readonly property bool human: role === "You"
            width: transcript.width
            height: body === "" ? 0 : entry.contentHeight

            TextEdit {
              id: entry
              width: parent.width
              height: contentHeight
              text: human ? body : root.spacedMarkdown(body)
              color: human ? root.accent : root.foreground
              font.family: Style.font.family
              font.pixelSize: human ? root.humanMessageSize : root.bodySize
              font.italic: human
              wrapMode: TextEdit.Wrap
              textFormat: human ? TextEdit.PlainText : TextEdit.MarkdownText
              readOnly: true
              selectByMouse: true
              Keys.onPressed: function(event) { if (root.handleFontKey(event) || root.handleMotionTunerKey(event) || root.handleScrollKey(event, false)) event.accepted = true }
              onLinkActivated: function(link) { Qt.openUrlExternally(link) }
            }
          }
        }

        Text {
          width: transcript.width
          visible: root.decisionStatus !== "" || root.statusText !== ""
          text: root.decisionStatus !== "" ? root.decisionStatus : root.statusText
          color: root.muted
          font.family: Style.font.family
          font.pixelSize: root.captionSize
          wrapMode: Text.WordWrap
        }

        Item {
          id: submittedPromptSpace
          width: transcript.width
          height: root.submittedPromptSpaceActive
            ? Math.max(0, root.submittedPromptY + log.height - y)
            : 0
        }
      }
    }

    Column {
      id: choiceFlow
      width: parent.width
      spacing: Style.space(8)
      height: visible ? implicitHeight : 0
      visible: !root.decisionBusy && (root.pendingPermissionId !== "" || root.proposedRule > 0
        || root.choices.length > 0 || root.rulingChoices().length > 0
      )

      // A tool wants to run. Reads are the common case; the ruling never
      // arrives through here, so allowing is low-stakes.
      Flow {
        width: parent.width
        visible: root.pendingPermissionId !== ""
        height: visible ? implicitHeight : 0
        spacing: Style.space(8)
        Rectangle {
          width: permissionLabel.implicitWidth + Style.space(24)
          height: Style.space(42)
          radius: Style.cornerRadius
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.24)
          Text {
            id: permissionLabel
            anchors.centerIn: parent
            text: "Allow: " + root.pendingPermissionTitle
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: root.captionSize
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.answerPermission(true)
          }
        }
        Rectangle {
          width: denyLabel.implicitWidth + Style.space(24)
          height: Style.space(42)
          radius: Style.cornerRadius
          color: "transparent"
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.24)
          Text {
            id: denyLabel
            anchors.centerIn: parent
            text: "Deny"
            color: root.muted
            font.family: Style.font.family
            font.pixelSize: root.captionSize
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.answerPermission(false)
          }
        }
      }

      // Rulings always occupy the first row. They change Tightbeam state and
      // remain visually distinct from the conversation starters below.
      Flow {
        width: parent.width
        visible: root.pendingPermissionId === ""
          && (root.proposedRule > 0 || root.rulingChoices().length > 0)
        height: visible ? implicitHeight : 0
        spacing: Style.space(8)

        Rectangle {
          visible: root.proposedRule > 0 && root.rulingChoices().length === 0
          width: ruleLabel.implicitWidth + Style.space(30)
          height: Style.space(42)
          radius: Style.cornerRadius
          color: ruleMouse.containsMouse ? root.accent : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.20)
          border.color: root.accent
          Text {
            id: ruleLabel
            anchors.centerIn: parent
            text: {
              var options = root.request && root.request.options ? root.request.options : []
              var index = root.proposedRule - 1
              return "Record: " + (index >= 0 && index < options.length ? options[index] : "option " + root.proposedRule)
            }
            color: ruleMouse.containsMouse ? Color.background : root.foreground
            font.family: Style.font.family
            font.pixelSize: root.bodySize
            font.bold: true
          }
          MouseArea {
            id: ruleMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var options = root.request && root.request.options ? root.request.options : []
              var index = root.proposedRule - 1
              if (index >= 0 && index < options.length) root.ruleRequested(String(options[index]))
            }
          }
        }

        Repeater {
          model: root.rulingChoices()
          Rectangle {
            id: rulingButton
            required property var modelData
            width: rulingLabel.implicitWidth + Style.space(30)
            height: Style.space(42)
            radius: Style.cornerRadius
            color: rulingMouse.containsMouse ? root.accent : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.20)
            border.color: root.accent
            Text {
              id: rulingLabel
              anchors.centerIn: parent
              text: modelData
              color: rulingMouse.containsMouse ? Color.background : root.foreground
              font.family: Style.font.family
              font.pixelSize: root.bodySize
              font.bold: true
            }
            MouseArea {
              id: rulingMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              enabled: true
              onClicked: root.ruleRequested(String(rulingButton.modelData))
            }
          }
        }
      }

      // Conversation starters always begin on a fresh row and use a message
      // glyph to make it clear that they send text rather than record a rule.
      Flow {
        width: parent.width
        visible: root.pendingPermissionId === "" && root.conversationChoices().length > 0
        height: visible ? implicitHeight : 0
        spacing: Style.space(8)
        Repeater {
          model: root.conversationChoices()
          Rectangle {
            required property var modelData
            width: conversationLabel.implicitWidth + Style.space(24)
            height: Style.space(42)
            radius: Style.cornerRadius
            color: conversationMouse.containsMouse
              ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
            Text {
              id: conversationLabel
              anchors.centerIn: parent
              text: "󰍡  " + modelData
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: root.captionSize
            }
            MouseArea {
              id: conversationMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              enabled: !root.waiting
              onClicked: root.send(modelData)
            }
          }
        }
      }
    }

    Rectangle {
      id: composer
      width: parent.width
      // Follows both the text scale and the wrapped content. A fixed box
      // clipped its own text as soon as the font grew, and clipped multi-line
      // input at any size. input.implicitHeight is content-derived, so it does
      // not depend on this height and cannot form a loop.
      height: Math.max(Math.round(Style.space(46) * root.fontScale),
                       input.implicitHeight + Style.space(20))
      radius: Style.cornerRadius
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
      border.color: input.activeFocus ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)

      TextArea {
        id: input
        // Width-anchored rather than filled, so the height stays implicit and
        // the box above can size itself from it.
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: root.bodySize
        placeholderText: root.waiting ? "" : "Ask about this decision…"
        placeholderTextColor: root.muted
        wrapMode: TextEdit.Wrap
        enabled: !root.waiting && !root.sessionLost
        background: null
        Keys.onPressed: function(event) {
          if (root.handleFontKey(event) || root.handleMotionTunerKey(event) || root.handleScrollKey(event, true)) { event.accepted = true; return }
          if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
              && !(event.modifiers & Qt.ShiftModifier)) {
            root.send(input.text)
            input.text = ""
            event.accepted = true
          } else if (event.key === Qt.Key_Y && root.pendingPermissionId !== "" && input.text === "") {
            root.answerPermission(true); event.accepted = true
          } else if (event.key === Qt.Key_N && root.pendingPermissionId !== "" && input.text === "") {
            root.answerPermission(false); event.accepted = true
          }
        }
      }
    }
  }
}
