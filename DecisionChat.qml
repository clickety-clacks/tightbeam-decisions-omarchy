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
// clicking it calls ruleRequested(n) and the panel records it. Any other line is
// conversation and is sent back as the next prompt. `rule` produces the same
// ruling button when the agent wants to propose one after discussion. The agent
// never records anything itself — the click does.
Item {
  id: root

  property var request: null
  property string host: "gibson"
  property string user: "mike"
  property string messageScript: ""
  // The ACP bridge shipped with the Ask plugin: a standalone Node script
  // speaking NDJSON over stdio. Reused as-is rather than vendored.
  readonly property string bridgePath: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/clickety-clacks.ask/bridge/bridge.js"

  signal ruleRequested(int choiceNumber)

  property bool bridgeReady: false
  property bool waiting: false
  property bool sessionLost: false
  property string statusText: ""
  property int activeReply: -1
  property string activeReplyMessageId: ""
  property string queuedPrompt: ""
  property string pendingPermissionId: ""
  property string pendingPermissionTitle: ""
  property var choices: []
  property int proposedRule: -1

  readonly property color foreground: Color.foreground
  readonly property color accent: Color.accent
  readonly property color muted: Color.muted

  function briefing() {
    var options = request && request.options ? request.options : []
    var numbered = []
    for (var i = 0; i < options.length; i++) numbered.push((i + 1) + ". " + options[i])
    return [
      "You are explaining one Tightbeam decision request to Mike, on his desktop.",
      "",
      "WHAT TIGHTBEAM IS: an agent-coordination substrate. Agent sessions hold",
      "assignments, attest to work they claim, and record artifacts pointing at what",
      "they produced. It runs on the " + host + " gateway. When an agent hits a question",
      "only its human owner can settle, it files an operator decision request — this",
      "one. Recording a ruling wakes the agent that asked and it proceeds.",
      "",
      "WHO YOU ARE TALKING TO: Mike owns this org but does NOT have the context these",
      "requests assume. They are written by agents deep in a task, in that task's",
      "jargon. Your job is to make this one legible, then help him decide.",
      "",
      "GO AND LOOK BEFORE YOU EXPLAIN. The context is on " + host + ", not in this prompt.",
      "Run read-only lookups over ssh:",
      "  ssh " + user + "@" + host + " /home/" + user + "/.local/bin/tightbeam <cmd> --as-user " + user,
      "Do not announce that you are about to look. Look first, then answer; never",
      "open with a line about what you are going to do.",
      "Useful commands: attests, artifacts, work-item-get, work-item-trace, topline,",
      "transcript, assignments, decision-requests. Id prefixes: att_ attestation,",
      "art_ artifact, asg_ assignment, wi_ work item, dr_ decision request. Follow",
      "every id and URL the request mentions. Read PRs with gh if one is linked.",
      "",
      "THEN ANSWER IN THIS SHAPE:",
      "1. A two-or-three sentence tl;dr in plain words. No Tightbeam jargon, no ids.",
      "2. What each option actually CAUSES — consequences, not restatements.",
      "3. Your recommendation, and what you are unsure about.",
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
      "RECORDING THE ANSWER: you cannot. When you and he have agreed, end your message",
      "with a fenced block tagged `rule` containing ONLY the option number. That gives",
      "him a confirm button. Never emit `rule` before he has actually agreed.",
      "",
      "SENDING A NOTE WITHOUT RULING: if he wants to ask the raising agent something,",
      "or hand it context, without resolving the request, run:",
      "  " + messageScript + " " + host + " " + user + " " + (request ? request.id : "") + " \"<text>\"",
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
    choices = []
    proposedRule = -1
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
    messages.append({ role: "Claude", body: "" })
    activeReply = messages.count - 1
    activeReplyMessageId = ""
    queuedPrompt = value
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
    Qt.callLater(scrollToEnd)
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

  function scrollToEnd() { log.contentY = Math.max(0, log.contentHeight - log.height) }

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
        Qt.callLater(scrollToEnd)
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
        root.statusText = "ACP session ended · reopen to retry"
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
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: transcript
        width: log.width
        spacing: Style.space(10)

        Repeater {
          model: messages
          Item {
            required property string role
            required property string body
            readonly property bool human: role === "You"
            width: transcript.width
            height: body === "" ? 0 : entry.contentHeight

            TextEdit {
              id: entry
              width: parent.width
              height: contentHeight
              text: body
              color: human ? root.accent : root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.italic: human
              wrapMode: TextEdit.Wrap
              textFormat: human ? TextEdit.PlainText : TextEdit.MarkdownText
              readOnly: true
              selectByMouse: true
              onLinkActivated: function(link) { Qt.openUrlExternally(link) }
            }
          }
        }

        Text {
          width: transcript.width
          visible: root.statusText !== ""
          text: root.statusText
          color: root.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }

    Flow {
      id: choiceFlow
      width: parent.width
      spacing: Style.space(8)
      height: visible ? implicitHeight : 0
      visible: root.pendingPermissionId !== "" || root.proposedRule > 0 || root.choices.length > 0

      // A tool wants to run. Reads are the common case; the ruling never
      // arrives through here, so allowing is low-stakes.
      Rectangle {
        visible: root.pendingPermissionId !== ""
        width: permissionLabel.implicitWidth + Style.space(24)
        height: Style.space(38)
        radius: Style.cornerRadius
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.24)
        Text {
          id: permissionLabel
          anchors.centerIn: parent
          text: "Allow: " + root.pendingPermissionTitle
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.answerPermission(true)
        }
      }
      Rectangle {
        visible: root.pendingPermissionId !== ""
        width: denyLabel.implicitWidth + Style.space(24)
        height: Style.space(38)
        radius: Style.cornerRadius
        color: "transparent"
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.24)
        Text {
          id: denyLabel
          anchors.centerIn: parent
          text: "Deny"
          color: root.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.answerPermission(false)
        }
      }

      // The agreed ruling. This is the only control that changes anything on
      // the Tightbeam host, and it takes a deliberate click.
      Rectangle {
        visible: root.proposedRule > 0 && root.pendingPermissionId === ""
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
          font.pixelSize: Style.font.body
          font.bold: true
        }
        MouseArea {
          id: ruleMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.ruleRequested(root.proposedRule)
        }
      }

      Repeater {
        model: root.pendingPermissionId === "" ? root.choices : []
        Rectangle {
          required property var modelData
          // > 0 when this chip names a real option: clicking it is the ruling.
          readonly property int ruleIndex: root.optionIndexFor(modelData)
          readonly property bool rules: ruleIndex > 0
          width: chipLabel.implicitWidth + Style.space(rules ? 30 : 24)
          height: Style.space(rules ? 42 : 38)
          radius: Style.cornerRadius
          color: rules
            ? (chipMouse.containsMouse ? root.accent : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.20))
            : (chipMouse.containsMouse
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08))
          border.color: rules ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
          Text {
            id: chipLabel
            anchors.centerIn: parent
            text: modelData
            color: rules && chipMouse.containsMouse ? Color.background : root.foreground
            font.family: Style.font.family
            font.pixelSize: rules ? Style.font.body : Style.font.caption
            font.bold: rules
          }
          MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !root.waiting
            onClicked: rules ? root.ruleRequested(ruleIndex) : root.send(modelData)
          }
        }
      }
    }

    Rectangle {
      id: composer
      width: parent.width
      height: Style.space(46)
      radius: Style.cornerRadius
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
      border.color: input.activeFocus ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)

      TextArea {
        id: input
        anchors.fill: parent
        anchors.margins: Style.space(10)
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        placeholderText: root.waiting ? "" : "Ask about this decision…"
        placeholderTextColor: root.muted
        wrapMode: TextEdit.Wrap
        enabled: !root.waiting && !root.sessionLost
        background: null
        Keys.onPressed: function(event) {
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
