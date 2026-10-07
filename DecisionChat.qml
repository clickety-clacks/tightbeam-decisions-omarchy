import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The conversation owns the ACP session and the reading column. The ruling
// controls live in DecisionWindow, so asking can grow below the brief without
// ever moving or covering a choice.
Item {
  id: root

  property var request: null
  property string host: ""
  property string user: ""
  property string messageScript: ""
  property real fontScale: 1
  property string newsreaderFamily: ""
  property string newsreaderItalicFamily: ""
  property string sansFamily: ""
  property string sansItalicFamily: ""
  property string monoFamily: ""
  property string monoMediumFamily: ""
  property color ground: Color.background
  property color foreground: Color.foreground
  property color secondary: Color.foreground
  property color faint: Color.foreground
  property color hairline: Color.foreground
  property color keyBorder: Color.foreground
  property color accent: Color.urgent

  // DecisionWindow supplies the filtered ruling options. The raw option is
  // authoritative; labels and effects are display-only content.
  property var rulingChoices: []
  property var summaryChoiceLabels: []
  property var summaryChoiceEffects: []
  property string summaryParent: ""
  property string summaryNotes: ""
  property int armedChoice: -1
  property int focusedChoice: -1
  property int proposedChoice: -1
  property bool recording: false
  property bool handled: false
  property bool rulingClicksEnabled: true
  property bool narrowLayout: false
  property bool minimumMode: false
  property bool compactAsk: false
  property bool showInlineChoices: false
  // One column with the choices in the body; false only in Minimum.
  property bool singleColumn: false
  property int dockColumns: 2
  // Keep the reading measure near 70 characters on wide windows.
  readonly property real readingMaxWidth: Math.round(800 * root.fontScale)
  property bool bodyVisible: true
  property bool askVisible: true
  property string recordingChoice: ""
  property var keyAction: null
  property var ruleAction: null

  signal ruleRequested(string choiceLabel)
  signal headerSummaryReady(string summary)
  signal assistantMessageFinished()
  signal choiceFocused(int index)
  signal focusCycleRequested(bool backwards)
  signal askEscapeRequested()
  signal fontStepRequested(real step)
  signal fontResetRequested()
  signal motionTunerRequested()

  readonly property int bodySize: Math.round(19 * fontScale)
  readonly property int captionSize: Math.round(13 * fontScale)
  readonly property int humanMessageSize: Math.max(Math.round(25 * fontScale),
    Math.round(21 * fontScale) + 4)
  // The window's height, for capping the ask box at two thirds of it.
  property real windowHeight: 0
  // Two thirds of the window, but never so tall that the docked choices
  // would be pushed out of this area (tier 1 stays on screen).
  readonly property real maxAskHeight: Math.max(root.askLineHeight, Math.min(root.windowHeight * 2 / 3,
    root.height - (root.singleColumn && !root.handled && root.rulingChoices.length > 0
      ? dock.implicitHeight : 0)))
  readonly property real askLineHeight: Math.round((root.compactAsk ? 64 : 72) * root.fontScale)
  readonly property real bodyHorizontalPadding: Math.round((root.narrowLayout ? 20 : 28) * root.fontScale)
  readonly property real bodyTopPadding: Math.round((root.narrowLayout ? 16 : 22) * root.fontScale)
  readonly property string hostLabel: host === "" ? "this machine" : "the " + host + " gateway"
  readonly property string quotedHost: host === "" ? "\"\"" : host
  readonly property string quotedUser: user === "" ? "\"\"" : user
  readonly property string lookupCommand: (host === "" ? "tightbeam" : "ssh " + host + " tightbeam")
    + (user === "" ? "" : " --as-user " + user)
  readonly property string bridgePath: Qt.resolvedUrl("bridge/bridge.js").toString().replace(/^file:\/\//, "")
  readonly property string nodePath: Qt.resolvedUrl("bridge/node.sh").toString().replace(/^file:\/\//, "")
  readonly property bool askActive: input.activeFocus

  property bool bridgeMissing: false
  property bool bridgeReady: false
  property bool waiting: false
  property bool steeringSupported: false
  property bool steeringPending: false
  property bool restartPending: false
  property bool sessionLost: false
  property string statusText: ""
  property string decisionStatus: ""
  property int activeReply: -1
  property string activeReplyMessageId: ""
  property string queuedPrompt: ""
  property string pendingPermissionId: ""
  property string pendingPermissionTitle: ""
  property int proposedRule: -1
  property int submittedPromptIndex: -1
  property bool submittedPromptSpaceActive: false
  property real submittedPromptY: 0
  property string briefTldr: ""
  property string briefRecommendation: ""
  property string headerSummary: ""
  property var choiceEffects: []
  property bool originalExpanded: false
  property bool dockedChoicesVisible: false
  property real keyboardVelocityY: 0
  property double keyboardSampleTime: 0

  function bridgeCommand() { return ["env", "HUGINN_INTERNAL=1", nodePath, bridgePath] }
  function handleGlobalKey(event) {
    return typeof root.keyAction === "function" && root.keyAction(event)
  }

  function choiceStackHeight(repeater, gap) {
    var total = 0
    for (var index = 0; index < repeater.count; index++) {
      var item = repeater.itemAt(index)
      if (item) total += Math.max(0, Number(item.height || item.implicitHeight || 0))
    }
    return total + Math.max(0, repeater.count - 1) * Math.max(0, gap)
  }

  function choiceStackOffset(repeater, index, gap) {
    var offset = 0
    for (var row = 0; row < index; row++) {
      var item = repeater.itemAt(row)
      if (item) offset += Math.max(0, Number(item.height || item.implicitHeight || 0))
    }
    return offset + Math.max(0, index) * Math.max(0, gap)
  }

  FileView {
    path: root.bridgePath
    printErrors: false
    onLoaded: root.bridgeMissing = false
    onLoadFailed: root.bridgeMissing = true
  }

  function mixColor(from, to, amount) {
    return Qt.rgba(from.r + (to.r - from.r) * amount,
                   from.g + (to.g - from.g) * amount,
                   from.b + (to.b - from.b) * amount, 1)
  }

  function handleFontKey(event) {
    if ((event.modifiers & Qt.ControlModifier) === 0) return false
    if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
      fontStepRequested(0.1)
      return true
    }
    if (event.key === Qt.Key_Minus || event.key === Qt.Key_Underscore) {
      fontStepRequested(-0.1)
      return true
    }
    if (event.key === Qt.Key_0) {
      fontResetRequested()
      return true
    }
    return false
  }

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
    var effectsExample = []
    for (var optionIndex = 0; optionIndex < options.length; optionIndex++)
      effectsExample.push((optionIndex + 1) + ". one sentence explaining the consequence of choosing " + options[optionIndex])
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
        ? "Its work item is " + request.workItemId + ". Read that item first — it is the"
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
      "```header-summary",
      "A 4-10 word plain-language label for the decision. This goes in internal",
      "conversation metadata; make it much shorter than the TL;DR. No ids or jargon.",
      "```",
      "## TL;DR",
      "One or two short sentences in plain words. Say what happened and what is at stake.",
      "No Tightbeam jargon or ids.",
      "## Recommendation",
      "State your recommendation directly, followed by any real uncertainty.",
      "```choice-effects",
      effectsExample.length > 0 ? effectsExample.join("\n") : "<number>. one sentence explaining the consequence",
      "```",
      "The choice-effects block MUST contain exactly one '<number>. <one sentence>'",
      "line per option, in order. Do not add a 'What the options mean' section: the",
      "choice buttons already carry those consequences.",
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
      "is a ruling option. Only write an exact label when clicking it should settle",
      "the request. If you are merely asking about an option, word it as a question",
      "so it stays a conversation.",
      "",
      "RECORDING THE ANSWER: a human or its explicit delegate closes the row. By default",
      "that is him. When you and he have agreed, end your message with a fenced block",
      "tagged `rule` containing ONLY the option number. That arms the matching choice",
      "for his confirmation; it does not record the ruling itself.",
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
    if (agent.running) stop(false, true)
    messages.clear()
    messages.append({ role: "Claude", body: "", choices: "[]" })
    briefTldr = ""
    briefRecommendation = ""
    headerSummary = ""
    choiceEffects = []
    proposedRule = -1
    submittedPromptIndex = -1
    submittedPromptSpaceActive = false
    submittedPromptY = 0
    originalExpanded = false
    bridgeReady = false
    steeringSupported = false
    steeringPending = false
    sessionLost = false
    activeReply = 0
    activeReplyMessageId = ""
    statusText = "Reading the request…"
    decisionStatus = ""
    waiting = true
    queuedPrompt = briefing()
    agent.running = true
  }

  function stop(restart, clearContent) {
    restartPending = restart === true
    if (agent.running) agent.write(JSON.stringify({ type: "close" }) + "\n")
    agent.running = false
    bridgeReady = false
    waiting = false
    steeringSupported = false
    steeringPending = false
    queuedPrompt = ""
    statusText = ""
    decisionStatus = ""
    proposedRule = -1
    submittedPromptIndex = -1
    submittedPromptSpaceActive = false
    submittedPromptY = 0
    keyboardVelocityY = 0
    keyboardCoast.stop()
    trackpadCoast.stop()
    if (clearContent !== false) {
      choiceEffects = []
      briefTldr = ""
      briefRecommendation = ""
      headerSummary = ""
      messages.clear()
    }
  }

  function resummarize() {
    if (restartPending) return
    if (agent.running) stop(true, true)
    else start()
  }

  function send(text) {
    var value = String(text || "").trim()
    if (value === "" || sessionLost) return false
    if (waiting) {
      if (!steeringSupported || steeringPending || !bridgeReady || !agent.running) return false
      steeringPending = true
      statusText = "Steering…"
      messages.append({ role: "You", body: value, choices: "[]" })
      submittedPromptIndex = messages.count - 1
      submittedPromptSpaceActive = true
      submittedPromptY = 0
      messages.append({ role: "Claude", body: "", choices: "[]" })
      activeReply = messages.count - 1
      activeReplyMessageId = ""
      agent.write(JSON.stringify({ type: "steer", text: value }) + "\n")
      revealLatestTimer.restart()
      return true
    }
    proposedRule = -1
    waiting = true
    statusText = "Thinking…"
    messages.append({ role: "You", body: value, choices: "[]" })
    submittedPromptIndex = messages.count - 1
    submittedPromptSpaceActive = true
    submittedPromptY = 0
    messages.append({ role: "Claude", body: "", choices: "[]" })
    activeReply = messages.count - 1
    activeReplyMessageId = ""
    queuedPrompt = value
    revealLatestTimer.restart()
    if (bridgeReady) flush()
    return true
  }

  function activateChoice(index) {
    if (index < 0 || index >= rulingChoices.length || root.recording || root.handled) return
    var choice = rulingChoices[index]
    var raw = String(choice.rawOption || "")
    if (typeof ruleAction === "function") ruleAction(raw)
    else ruleRequested(raw)
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
      messages.append({ role: "Claude", body: "", choices: "[]" })
      activeReply = messages.count - 1
    }
    if (next !== "") activeReplyMessageId = next
    var body = (messages.get(activeReply).body || "") + text
    messages.setProperty(activeReply, "body", body)
    if (submittedPromptIndex < 0 && activeReply === 0) updateStreamingBrief(body)
  }

  function plainBrief(text) { return String(text || "").trim() }

  function optionIndexFor(label) {
    var options = request && request.options ? request.options : []
    var wanted = String(label || "").trim().toLowerCase()
    for (var i = 0; i < options.length; i++)
      if (String(options[i]).trim().toLowerCase() === wanted) return i
    return -1
  }

  function extractBriefSection(body, title) {
    var expression = new RegExp("(?:^|\\n)##\\s*" + title + "\\s*\\n([\\s\\S]*?)(?=\\n##\\s|$)", "i")
    var match = expression.exec(body)
    return match ? plainBrief(match[1]) : ""
  }

  function stripControlBlocks(value, includeOpen) {
    var text = String(value || "")
    var complete = /```(?:header-summary|choice-effects|choices|rule)[ \t]*\r?\n[\s\S]*?```/gi
    text = text.replace(complete, "")
    if (includeOpen) {
      var open = /```(?:header-summary|choice-effects|choices|rule)[ \t]*\r?\n[\s\S]*$/gi
      text = text.replace(open, "")
    }
    return text
  }

  function liveBriefSection(body, title) {
    return stripControlBlocks(extractBriefSection(stripControlBlocks(body, true), title), true)
      .trim()
  }

  function updateStreamingBrief(body) {
    briefTldr = liveBriefSection(body, "TL;DR")
    briefRecommendation = liveBriefSection(body, "Recommendation")
  }

  function renderMessageBody(body, initialReply) {
    var value = stripControlBlocks(body, true)
    if (initialReply) {
      var briefSections = /(?:^|\n)##\s*(?:TL;DR|Recommendation)\s*\n[\s\S]*?(?=\n##\s|$)/gi
      value = value.replace(briefSections, "").trim()
    }
    return spacedMarkdown(value)
  }

  // Finished replies are the boundary at which fenced controls become UI.
  // The initial TL;DR and recommendation move into the pinned reading brief;
  // later answers remain in the conversation in their original order.
  function harvestBlocks(initialReply) {
    if (activeReply < 0 || activeReply >= messages.count) return
    var body = String(messages.get(activeReply).body || "")
    var changed = false
    var headerPattern = /```header-summary[ \t]*\r?\n[\s\S]*?```/gi
    var headerMatch = headerPattern.exec(body)
    if (headerMatch) {
      var headerBody = /```header-summary[ \t]*\r?\n([\s\S]*?)```/i.exec(headerMatch[0])
      headerSummary = String(headerBody ? headerBody[1] : "").replace(/\s+/g, " ").trim()
      headerSummaryReady(headerSummary)
      changed = true
      body = body.replace(headerPattern, "")
    }

    var effects = []
    var effectsFound = false
    var conversationChoices = []
    var rule = -1
    var controls = /```(choices|choice-effects|rule)[ \t]*\r?\n([\s\S]*?)```/gi
    var match
    while ((match = controls.exec(body)) !== null) {
      changed = true
      var tag = String(match[1]).toLowerCase()
      var lines = String(match[2]).split("\n")
      if (tag === "choices") {
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim()
          if (line !== "" && optionIndexFor(line) < 0) conversationChoices.push(line)
        }
      } else if (tag === "choice-effects") {
        effectsFound = true
        for (var effectIndex = 0; effectIndex < lines.length; effectIndex++) {
          var effectMatch = /^\s*(\d+)\.\s+(.+?)\s*$/.exec(lines[effectIndex])
          if (!effectMatch) continue
          var number = Number(effectMatch[1])
          if (number > 0) effects[number - 1] = effectMatch[2].trim()
        }
      } else {
        var parsed = parseInt(String(match[2]).trim(), 10)
        if (!isNaN(parsed)) rule = parsed
      }
    }
    if (changed) body = body.replace(controls, "").trim()
    var sanitizedBody = stripControlBlocks(body, true).trim()
    if (sanitizedBody !== body) changed = true
    body = sanitizedBody

    if (initialReply) {
      briefTldr = extractBriefSection(body, "TL;DR")
      briefRecommendation = extractBriefSection(body, "Recommendation")
      var briefSections = /(?:^|\n)##\s*(?:TL;DR|Recommendation)\s*\n[\s\S]*?(?=\n##\s|$)/gi
      var withoutBrief = body.replace(briefSections, "").trim()
      if (withoutBrief !== body) changed = true
      body = withoutBrief
    }
    if (effectsFound) choiceEffects = effects
    if (activeReply >= 0 && activeReply < messages.count)
      messages.setProperty(activeReply, "choices", JSON.stringify(conversationChoices))
    proposedRule = rule
    if (changed || conversationChoices.length > 0 || effectsFound || rule >= 0)
      messages.setProperty(activeReply, "body", body)
  }

  function handleMotionTunerKey(event) {
    if ((event.modifiers & Qt.ControlModifier) === 0 || event.key !== Qt.Key_Comma) return false
    motionTunerRequested()
    return true
  }

  function scrollBy(dx, dy) {
    if (!log.visible || log.height <= 0) return
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
    submittedPromptY = Math.max(0, promptItem.y + promptItem.promptLeading
      - root.humanMessageSize * 2.5)
    Qt.callLater(function() {
      promptRevealAnimation.from = log.contentY
      promptRevealAnimation.to = root.submittedPromptY
      promptRevealAnimation.start()
    })
  }

  function scrollLine(dx, dy) { scrollBy(dx * 44 * fontScale, dy * 44 * fontScale) }

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
    if (dx !== 0) scrollBy(dx * 44 * fontScale, 0)
    if (dy === 0) return
    log.cancelFlick()
    trackpadCoast.stop()
    promptRevealAnimation.stop()
    var impulse = page ? 689 : 335
    keyboardVelocityY = Math.max(-log.maximumFlickVelocity,
      Math.min(log.maximumFlickVelocity, keyboardVelocityY + dy * impulse))
    keyboardSampleTime = Date.now()
    keyboardCoast.start()
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
        steeringSupported = event.steeringSupported === true
        flush()
      } else if (event.type === "text") {
        appendReply(String(event.text || ""), String(event.messageId || ""))
        statusText = "Replying…"
      } else if (event.type === "done") {
        var initialReply = submittedPromptIndex < 0
        waiting = false
        steeringPending = false
        statusText = ""
        harvestBlocks(initialReply)
        activeReplyMessageId = ""
        assistantMessageFinished()
      } else if (event.type === "steered") {
        steeringPending = false
        statusText = "Thinking…"
        Qt.callLater(function() { input.forceActiveFocus() })
      } else if (event.type === "steering_error") {
        steeringPending = false
        statusText = String(event.message || "Could not steer the active turn")
        Qt.callLater(function() { input.forceActiveFocus() })
      } else if (event.type === "status") {
        statusText = String(event.text || "Working…")
      } else if (event.type === "tool") {
        statusText = String(event.status || "") === "completed"
          ? "Thinking…" : String(event.title || "Using a tool")
      } else if (event.type === "permission") {
        pendingPermissionId = String(event.id || "")
        pendingPermissionTitle = String(event.title || "Use a tool")
      } else if (event.type === "error") {
        waiting = false
        steeringPending = false
        statusText = String(event.message || "Agent error")
      } else if (event.type === "fatal") {
        bridgeReady = false
        sessionLost = true
        waiting = false
        steeringPending = false
        statusText = String(event.message || "Session lost") + " · reopen to retry"
      }
    } catch (error) {}
  }

  function updateDockedChoices() {
    if (!root.singleColumn || !root.showInlineChoices || !root.bodyVisible || !choiceBlock.visible) {
      dockedChoicesVisible = false
      return
    }
    var top = choiceBlock.y
    var bottom = top + choiceBlock.height
    var viewTop = log.contentY
    var viewBottom = viewTop + Math.max(0, log.height)
    var fullyVisible = top >= viewTop - 1 && bottom <= viewBottom + 1
    if (fullyVisible) dockedChoicesVisible = false
    else dockedChoicesVisible = true
  }

  function revealChoices() {
    if (!choiceBlock.visible) return
    var maxY = Math.max(0, log.contentHeight - log.height)
    log.contentY = Math.max(0, Math.min(maxY, choiceBlock.y))
    Qt.callLater(updateDockedChoices)
  }

  function focusBody() {
    if (root.bodyVisible) log.forceActiveFocus()
  }

  function focusAsk() {
    if (!root.askVisible) return
    input.forceActiveFocus()
    input.cursorPosition = input.length
  }

  ListModel { id: messages }

  Process {
    id: agent
    command: root.bridgeCommand()
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.handleLine(line) } }
    onExited: {
      root.bridgeReady = false
      root.steeringSupported = false
      root.steeringPending = false
      if (root.restartPending) {
        root.restartPending = false
        Qt.callLater(root.start)
        return
      }
      if (!root.sessionLost && root.waiting) {
        root.waiting = false
        root.sessionLost = true
        root.statusText = root.bridgeMissing
          ? "The decision-request ACP bridge is missing at " + root.bridgePath
          : "ACP session ended · reopen to retry"
      }
    }
  }

  Flickable {
    id: log
    visible: root.bodyVisible
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: root.bodyHorizontalPadding
    anchors.rightMargin: Math.max(root.bodyHorizontalPadding,
      parent.width - root.bodyHorizontalPadding - root.readingMaxWidth)
    anchors.topMargin: root.bodyTopPadding
    height: root.bodyVisible ? Math.max(0, parent.height - root.bodyTopPadding
      - (root.dockedChoicesVisible ? dock.height : composer.height)) : 0
    contentWidth: width
    contentHeight: Math.max(0, transcript.implicitHeight)
    clip: true
    focus: true
    interactive: contentHeight > height
    flickableDirection: Flickable.VerticalFlick
    maximumFlickVelocity: 6000
    flickDeceleration: 650
    boundsBehavior: Flickable.StopAtBounds
    Keys.onPressed: function(event) {
      if (root.handleGlobalKey(event)) event.accepted = true
    }
    onContentYChanged: root.updateDockedChoices()
    onHeightChanged: Qt.callLater(root.updateDockedChoices)
    onDraggingChanged: {
      if (!dragging) return
      root.keyboardVelocityY = 0
      keyboardCoast.stop()
      trackpadCoast.stop()
      promptRevealAnimation.stop()
    }

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
        var loss = 608 * elapsed
        if (Math.abs(velocity) <= loss) {
          root.keyboardVelocityY = 0
          stop()
        } else root.keyboardVelocityY = velocity > 0 ? velocity - loss : velocity + loss
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
          if (steps !== 0 || sideways !== 0) root.scrollLine(-sideways * 3, -steps * 3)
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
      width: Math.max(0, log.width)
      spacing: Math.round(18 * root.fontScale)

      Column {
        id: briefSection
        width: parent.width
        spacing: Math.round(8 * root.fontScale)
        visible: root.bodyVisible

        Text {
          width: parent.width
          text: "BRIEF"
          color: root.foreground
          font.family: root.monoMediumFamily !== "" ? root.monoMediumFamily : root.monoFamily
          font.pixelSize: root.captionSize
          font.weight: Font.Medium
          font.letterSpacing: Math.round(1.3 * root.fontScale)
        }

        Text {
          width: parent.width
          visible: root.briefTldr !== ""
          text: root.spacedMarkdown(root.briefTldr)
          color: root.foreground
          font.family: root.sansFamily
          font.pixelSize: root.bodySize
          wrapMode: Text.Wrap
          textFormat: Text.MarkdownText
          lineHeight: font.pixelSize * 1.6
          lineHeightMode: Text.FixedHeight
          Keys.onPressed: function(event) {
            if (root.handleFontKey(event) || root.handleMotionTunerKey(event)
                || root.handleScrollKey(event, false) || root.handleGlobalKey(event)) event.accepted = true
          }
          onLinkActivated: function(link) { Qt.openUrlExternally(link) }
        }

        Text {
          width: parent.width
          visible: root.briefRecommendation !== ""
          text: root.spacedMarkdown(root.briefRecommendation)
          color: root.foreground
          font.family: root.sansFamily
          font.pixelSize: root.bodySize
          wrapMode: Text.Wrap
          textFormat: Text.MarkdownText
          lineHeight: font.pixelSize * 1.6
          lineHeightMode: Text.FixedHeight
          Keys.onPressed: function(event) {
            if (root.handleFontKey(event) || root.handleMotionTunerKey(event)
                || root.handleScrollKey(event, false) || root.handleGlobalKey(event)) event.accepted = true
          }
          onLinkActivated: function(link) { Qt.openUrlExternally(link) }
        }

        Text {
          width: parent.width
          visible: root.briefTldr === "" && root.briefRecommendation === ""
          text: root.summaryNotes !== "" ? root.summaryNotes
            : (root.summaryParent !== "" ? root.summaryParent : "Reading the request…")
          color: root.secondary
          font.family: root.sansFamily
          font.pixelSize: root.bodySize
          wrapMode: Text.Wrap
          lineHeight: font.pixelSize * 1.6
          lineHeightMode: Text.FixedHeight
          Keys.onPressed: function(event) {
            if (root.handleFontKey(event) || root.handleMotionTunerKey(event)
                || root.handleScrollKey(event, false) || root.handleGlobalKey(event)) event.accepted = true
          }
        }
      }

      Item {
        id: choiceHeading
        width: parent.width
        height: Math.round(24 * root.fontScale)
        visible: choiceBlock.visible && root.showInlineChoices

        Text {
          id: choiceHeadingLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "DECIDE"
          color: root.foreground
          font.family: root.monoMediumFamily !== "" ? root.monoMediumFamily : root.monoFamily
          font.pixelSize: root.captionSize
          font.weight: Font.Medium
          font.variableAxes: ({ "wght": 500 })
          font.letterSpacing: Math.round(1.3 * root.fontScale)
        }

        Text {
          anchors.left: choiceHeadingLabel.right
          anchors.leftMargin: Math.round(12 * root.fontScale)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          text: root.armedChoice >= 0 && root.armedChoice < root.rulingChoices.length
            ? "⏎ to record \"" + root.rulingChoices[root.armedChoice].label + "\""
            : "↑↓  ⏎ or a number"
          color: root.secondary
          font.family: root.monoFamily
          font.pixelSize: root.captionSize
          elide: Text.ElideRight
        }
      }

      Item {
        id: choiceBlock
        width: parent.width
        property real choiceGap: Math.round(2 * root.fontScale)
        visible: root.singleColumn && !root.minimumMode && root.rulingChoices.length > 0
        height: root.showInlineChoices
          ? root.choiceStackHeight(choiceRepeater, choiceGap) : 0
        onHeightChanged: Qt.callLater(root.updateDockedChoices)

        Repeater {
          id: choiceRepeater
          model: root.rulingChoices
          delegate: DecisionChoice {
            required property var modelData
            required property int index
            width: choiceBlock.width
            y: root.choiceStackOffset(choiceRepeater, index, choiceBlock.choiceGap)
            density: "full"
            label: String(modelData.label || "")
            effect: String(modelData.effect || "")
            rawOption: String(modelData.rawOption || "")
            number: Number(modelData.number || index + 1)
            armed: root.armedChoice === index
            focused: root.focusedChoice === index
            focusActive: root.focusedChoice >= 0
            proposed: root.proposedChoice === index
            recording: root.recording && String(modelData.rawOption || "") === root.recordingChoice
            interactive: !root.recording && !root.handled
            activationAllowed: root.rulingClicksEnabled
            fontScale: root.fontScale
            sansFamily: root.sansFamily
            sansMediumFamily: root.sansFamily
            monoFamily: root.monoFamily
            ground: root.ground
            ink: root.foreground
            secondary: root.secondary
            faint: root.faint
            hairline: root.hairline
            keyBorder: root.keyBorder
            onFocusedByUser: root.choiceFocused(index)
            onActivated: root.activateChoice(index)
          }
        }
      }

      Text {
        width: parent.width
        visible: root.singleColumn && root.decisionStatus !== ""
          && root.decisionStatus.indexOf("Recording “") !== 0
        text: root.decisionStatus
        color: root.secondary
        font.family: root.monoFamily
        font.pixelSize: root.captionSize
        elide: Text.ElideRight
      }

      Repeater {
        id: messageRepeater
        model: messages
        delegate: Item {
          required property int index
          required property string role
          required property string body
          required property var choices
          readonly property bool human: role === "You"
          readonly property real promptLeading: human
            ? Math.round(root.humanMessageSize * 1.25) : 0
          width: transcript.width
          height: messageContents.implicitHeight

          Column {
            id: messageContents
            width: parent.width
            spacing: Math.round(8 * root.fontScale)

            Text {
              width: parent.width
              visible: body !== ""
              text: human ? body : root.renderMessageBody(body,
                index === root.activeReply && root.submittedPromptIndex < 0)
              color: human ? root.accent : root.foreground
              font.family: human
                ? (root.newsreaderItalicFamily !== "" ? root.newsreaderItalicFamily : root.newsreaderFamily)
                : root.sansFamily
              font.pixelSize: human ? root.humanMessageSize : root.bodySize
              font.italic: human
              wrapMode: Text.Wrap
              textFormat: human ? Text.PlainText : Text.MarkdownText
              lineHeight: font.pixelSize * (human ? 1.25 : 1.6)
              lineHeightMode: Text.FixedHeight
              Keys.onPressed: function(event) {
                if (root.handleFontKey(event) || root.handleMotionTunerKey(event)
                    || root.handleScrollKey(event, false) || root.handleGlobalKey(event)) event.accepted = true
              }
              onLinkActivated: function(link) { Qt.openUrlExternally(link) }
            }

            Item {
              id: conversationChoices
              width: parent.width
              // Stored as JSON: a ListModel turns an array role into a nested
              // model, which has no length and would never show its buttons.
              property var messageChoices: {
                try { var parsed = JSON.parse(String(choices || "[]")); return Array.isArray(parsed) ? parsed : [] }
                catch (error) { return [] }
              }
              property real choiceGap: Math.round(6 * root.fontScale)
              visible: messageChoices.length > 0
              height: visible ? messageChoices.length * Math.round(32 * root.fontScale)
                + Math.max(0, messageChoices.length - 1) * choiceGap : 0

              Repeater {
                model: conversationChoices.messageChoices
                delegate: Rectangle {
                  required property var modelData
                  required property int index
                  x: 0
                  y: index * (height + conversationChoices.choiceGap)
                  width: Math.min(conversationChoices.width,
                    choiceLabel.implicitWidth + Math.round(24 * root.fontScale))
                  height: Math.round(32 * root.fontScale)
                  color: "transparent"
                  border.color: root.hairline
                  border.width: 1
                  radius: Math.round(4 * root.fontScale)

                  Text {
                    id: choiceLabel
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Math.round(10 * root.fontScale)
                    anchors.rightMargin: Math.round(10 * root.fontScale)
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(modelData)
                    color: root.foreground
                    font.family: root.sansFamily
                    font.pixelSize: Math.round(15 * root.fontScale)
                    font.weight: Font.Medium
                    font.variableAxes: ({ "wght": 500 })
                    elide: Text.ElideRight
                  }

                  MouseArea {
                    anchors.fill: parent
                    enabled: !root.waiting && !root.recording && !root.handled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.send(modelData)
                  }
                }
              }
            }
          }
        }
      }

      Item {
        width: parent.width
        visible: root.pendingPermissionId !== ""
        height: visible ? permissionContents.implicitHeight : 0

        Column {
          id: permissionContents
          width: parent.width
          spacing: Math.round(6 * root.fontScale)

          Text {
            width: parent.width
            text: "Allow: " + root.pendingPermissionTitle
            color: root.secondary
            font.family: root.sansFamily
            font.pixelSize: root.captionSize
            elide: Text.ElideRight
          }

          Row {
            spacing: Math.round(8 * root.fontScale)

            Rectangle {
              width: allowLabel.implicitWidth + Math.round(20 * root.fontScale)
              height: Math.round(32 * root.fontScale)
              color: "transparent"
              border.color: root.hairline
              border.width: 1
              radius: Math.round(4 * root.fontScale)
              Text { id: allowLabel; anchors.centerIn: parent; text: "Allow"; color: root.foreground; font.family: root.sansFamily; font.pixelSize: root.captionSize }
              MouseArea { anchors.fill: parent; onClicked: root.answerPermission(true) }
            }

            Rectangle {
              width: denyLabel.implicitWidth + Math.round(20 * root.fontScale)
              height: Math.round(32 * root.fontScale)
              color: "transparent"
              border.color: root.hairline
              border.width: 1
              radius: Math.round(4 * root.fontScale)
              Text { id: denyLabel; anchors.centerIn: parent; text: "Deny"; color: root.secondary; font.family: root.sansFamily; font.pixelSize: root.captionSize }
              MouseArea { anchors.fill: parent; onClicked: root.answerPermission(false) }
            }
          }
        }
      }

      Text {
        width: parent.width
        visible: root.statusText !== ""
        text: root.statusText
        color: root.secondary
        font.family: root.monoFamily
        font.pixelSize: root.captionSize
        elide: Text.ElideRight
      }

      Item {
        id: submittedPromptSpace
        width: transcript.width
        height: root.submittedPromptSpaceActive
          ? Math.max(0, root.submittedPromptY + log.height - y) : 0
      }

      Column {
        id: originalRequest
        width: parent.width
        spacing: Math.round(8 * root.fontScale)

        Rectangle {
          width: parent.width
          height: Math.round(26 * root.fontScale)
          color: "transparent"

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "ORIGINAL REQUEST"
            color: root.secondary
            font.family: root.monoMediumFamily !== "" ? root.monoMediumFamily : root.monoFamily
            font.pixelSize: root.captionSize
            font.weight: Font.Medium
            font.letterSpacing: Math.round(1.3 * root.fontScale)
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.originalExpanded ? "▾" : "▸"
            color: root.secondary
            font.family: root.monoFamily
            font.pixelSize: root.captionSize
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.originalExpanded = !root.originalExpanded
              // It opens below the fold; bring it into view so the click shows something.
              if (root.originalExpanded) Qt.callLater(function() {
                log.cancelFlick()
                log.contentY = Math.max(0, Math.min(log.contentHeight - log.height, originalRequest.y))
              })
            }
          }
        }

        Column {
          width: parent.width
          visible: root.originalExpanded
          spacing: Math.round(6 * root.fontScale)

          Text {
            width: parent.width
            text: "question\n" + String(root.request && root.request.question || "")
              + "\n\nsubject\n" + String(root.request && root.request.subject || "")
              + "\n\nnote\n" + String(root.request && root.request.note || "")
            color: root.secondary
            font.family: root.monoFamily
            font.pixelSize: root.captionSize
            wrapMode: Text.Wrap
            Keys.onPressed: function(event) {
              if (root.handleFontKey(event) || root.handleMotionTunerKey(event)
                  || root.handleScrollKey(event, false) || root.handleGlobalKey(event)) event.accepted = true
            }
          }

          Text {
            width: parent.width
            text: {
              var options = root.request && root.request.options ? root.request.options : []
              var lines = ["options"]
              for (var optionIndex = 0; optionIndex < options.length; optionIndex++)
                lines.push((optionIndex + 1) + ". " + options[optionIndex])
              return lines.join("\n")
            }
            color: root.secondary
            font.family: root.monoFamily
            font.pixelSize: root.captionSize
            wrapMode: Text.Wrap
            Keys.onPressed: function(event) {
              if (root.handleFontKey(event) || root.handleMotionTunerKey(event)
                  || root.handleScrollKey(event, false) || root.handleGlobalKey(event)) event.accepted = true
            }
          }
        }
      }
    }
  }

  DecisionCompactStrip {
    id: dock
    visible: root.singleColumn && !root.minimumMode && root.dockedChoicesVisible
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: composer.top
    width: parent.width
    choices: root.rulingChoices
    columns: root.dockColumns
    // Same left edge as the body and the ask box.
    horizontalPadding: root.bodyHorizontalPadding
    showLabel: true
    showExplain: true
    hint: root.decisionStatus !== ""
      && root.decisionStatus.indexOf("Recording “") !== 0 ? root.decisionStatus : ""
    fontScale: root.fontScale
    armedIndex: root.armedChoice
    focusedIndex: root.focusedChoice
    proposedIndex: root.proposedChoice
    focusActive: root.focusedChoice >= 0
    interactive: !root.recording && !root.handled
    activationAllowed: root.rulingClicksEnabled
    sansFamily: root.sansFamily
    sansMediumFamily: root.sansFamily
    monoFamily: root.monoFamily
    monoMediumFamily: root.monoMediumFamily
    ground: root.ground
    panel: root.mixColor(root.ground, root.foreground, 0.05)
    ink: root.foreground
    secondary: root.secondary
    faint: root.faint
    hairline: root.hairline
    keyBorder: root.keyBorder
    onChoiceActivated: root.activateChoice(index)
    onChoiceFocused: root.choiceFocused(index)
    onExplainRequested: root.revealChoices()
  }

  Rectangle {
    id: composer
    visible: root.askVisible
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    // Grows with the question, like the old composer, up to two thirds of
    // the window; past that the text scrolls inside it.
    readonly property real verticalPadding: Math.round(16 * root.fontScale)
    height: Math.max(root.askLineHeight, Math.min(root.maxAskHeight,
      input.implicitHeight + verticalPadding * 2))
    color: root.ground
    border.color: root.hairline
    border.width: 1

    Flickable {
      id: inputScroll
      anchors.left: parent.left
      anchors.right: askKeycap.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      // Line the text up with the body text above it.
      anchors.leftMargin: root.bodyHorizontalPadding
      anchors.rightMargin: Math.round(10 * root.fontScale)
      anchors.topMargin: composer.verticalPadding
      anchors.bottomMargin: composer.verticalPadding
      contentWidth: width
      contentHeight: input.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      TextArea {
        id: input
        width: inputScroll.width
        // Keep the caret in view once the text outgrows the box.
        onCursorRectangleChanged: {
          var top = cursorRectangle.y
          var bottom = top + cursorRectangle.height
          if (top < inputScroll.contentY) inputScroll.contentY = top
          else if (bottom > inputScroll.contentY + inputScroll.height)
            inputScroll.contentY = bottom - inputScroll.height
        }
        topPadding: 0
        bottomPadding: 0
        leftPadding: 0
        rightPadding: 0
        color: root.accent
        placeholderTextColor: root.secondary
        placeholderText: "Ask about this request…"
        font.family: root.newsreaderItalicFamily !== ""
          ? root.newsreaderItalicFamily : root.newsreaderFamily
        font.pixelSize: Math.round(34 * root.fontScale)
        font.italic: true
        wrapMode: TextEdit.Wrap
        selectByMouse: true
        enabled: !root.handled && !root.sessionLost && (!root.waiting
          || (root.steeringSupported && !root.steeringPending))
        opacity: root.steeringPending ? 0.45 : 1
        background: null

        Keys.onPressed: function(event) {
          if (root.handleFontKey(event) || root.handleMotionTunerKey(event)
              || root.handleScrollKey(event, true)) {
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Tab) {
            root.focusCycleRequested((event.modifiers & Qt.ShiftModifier) !== 0)
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            root.askEscapeRequested()
            event.accepted = true
          } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                     && !(event.modifiers & Qt.ShiftModifier)) {
            if (root.send(input.text)) input.text = ""
            event.accepted = true
          } else if (event.key === Qt.Key_Y && root.pendingPermissionId !== ""
                     && input.text === "") {
            root.answerPermission(true)
            event.accepted = true
          } else if (event.key === Qt.Key_N && root.pendingPermissionId !== ""
                     && input.text === "") {
            root.answerPermission(false)
            event.accepted = true
          }
        }
      }
    }

    Text {
      id: askKeycap
      anchors.right: parent.right
      anchors.rightMargin: root.bodyHorizontalPadding
      // Stays on the first line's row while the box grows.
      anchors.top: parent.top
      anchors.topMargin: composer.verticalPadding
        + Math.round((input.font.pixelSize * 1.3 - height) / 2)
      width: Math.round(24 * root.fontScale)
      height: width
      text: "/"
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
  }

  Component.onCompleted: Qt.callLater(root.updateDockedChoices)
}
