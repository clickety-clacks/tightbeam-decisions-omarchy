#!/usr/bin/env node

import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { Readable, Writable } from "node:stream";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { readFileSync } from "node:fs";
import {
  ClientSideConnection,
  PROTOCOL_VERSION,
  ndJsonStream,
} from "../clickety-clacks.ask/bridge/node_modules/@agentclientprotocol/sdk/dist/acp.js";

const here = dirname(fileURLToPath(import.meta.url));
const askBridge = join(here, "..", "clickety-clacks.ask", "bridge");
const agentName = process.env.ASK_AGENT === "codex" ? "codex" : "claude";
let configuredChoice = {};
try {
  const config = JSON.parse(readFileSync(join(here, "summarizers.json"), "utf8"));
  configuredChoice = config.parentNotes?.[agentName] || {};
} catch {}
const agentBinary = join(askBridge, "node_modules", ".bin",
  agentName === "codex" ? "codex-acp" : "claude-agent-acp");
const child = spawn(agentBinary, [], {
  cwd: process.env.ASK_CWD || process.env.HOME || process.cwd(),
  env: {
    ...process.env,
    HUGINN_INTERNAL: "1",
    ANTHROPIC_MODEL: agentName === "claude"
      ? String(configuredChoice.model || process.env.ANTHROPIC_MODEL || "")
      : (process.env.ANTHROPIC_MODEL || ""),
  },
  stdio: ["pipe", "pipe", "pipe"],
});

function emit(event) { process.stdout.write(`${JSON.stringify(event)}\n`); }
function messageText(content) {
  if (!content) return "";
  if (typeof content === "string") return content;
  return content.type === "text" ? content.text || "" : "";
}
function flatOptions(options) {
  const result = [];
  for (const option of options || []) {
    if (Array.isArray(option.options)) result.push(...option.options);
    else result.push(option);
  }
  return result;
}
function preferredValue(config, patterns) {
  const options = flatOptions(config?.options);
  for (const pattern of patterns) {
    const found = options.find((option) => pattern.test(
      `${option.value || ""} ${option.name || ""}`.toLowerCase()));
    if (found) return found.value;
  }
  return "";
}

let connection = null;
let sessionId = null;
let shuttingDown = false;

const client = {
  sessionUpdate(params) {
    const update = params.update || {};
    if (update.sessionUpdate === "agent_message_chunk") {
      const text = messageText(update.content);
      if (text) emit({ type: "text", text });
    }
    return Promise.resolve();
  },
  requestPermission() {
    return Promise.resolve({ outcome: { outcome: "cancelled" } });
  },
};

async function chooseSmallModel(configOptions) {
  if (agentName === "claude") {
    emit({ type: "model", agent: agentName,
      value: String(configuredChoice.model || process.env.ANTHROPIC_MODEL || "default") });
    return;
  }
  const model = (configOptions || []).find((option) =>
    option.id === "model" || option.category === "model");
  const configuredModel = String(configuredChoice.model || "").toLowerCase();
  const patterns = configuredModel
    ? [new RegExp(configuredModel.replace(/[^a-z0-9]+/g, ".*"))]
    : agentName === "codex" ? [/luna/] : [/opus[- .]?4[.-]?8/];
  const value = preferredValue(model, patterns);
  if (model && value) {
    const response = await connection.setSessionConfigOption({
      sessionId,
      configId: model.id,
      value,
    });
    configOptions = response.configOptions || configOptions;
  }
  if (agentName === "codex") {
    const effort = (configOptions || []).find((option) =>
      option.id === "reasoning_effort" || option.category === "thought_level");
    const configuredEffort = String(configuredChoice.reasoningEffort || "xhigh").toLowerCase();
    const xhigh = preferredValue(effort, [new RegExp(`^${configuredEffort}$`)]);
    if (effort && xhigh) await connection.setSessionConfigOption({
      sessionId,
      configId: effort.id,
      value: xhigh,
    });
  }
  emit({ type: "model", agent: agentName, value: value || "default" });
}

async function start() {
  const stream = ndJsonStream(Writable.toWeb(child.stdin), Readable.toWeb(child.stdout));
  connection = new ClientSideConnection(() => client, stream);
  await connection.initialize({
    protocolVersion: PROTOCOL_VERSION,
    clientCapabilities: { session: { configOptions: {} } },
  });
  const session = await connection.newSession({
    cwd: process.env.ASK_CWD || process.env.HOME || process.cwd(),
    mcpServers: [],
  });
  sessionId = session.sessionId;
  await chooseSmallModel(session.configOptions || []);
  emit({ type: "ready", agent: agentName });
}

async function summarize(text) {
  const response = await connection.prompt({
    sessionId,
    prompt: [{ type: "text", text }],
  });
  emit({ type: "done", stopReason: response.stopReason || "end_turn" });
  await shutdown();
  process.exit(0);
}

async function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  try {
    if (connection && sessionId) await connection.closeSession({ sessionId });
  } catch {}
  child.kill("SIGTERM");
  setTimeout(() => child.kill("SIGKILL"), 500).unref();
}

const input = createInterface({ input: process.stdin, crlfDelay: Infinity });
input.on("line", (line) => {
  let message;
  try { message = JSON.parse(line); } catch { return; }
  if (message.type === "prompt") summarize(String(message.text || "")).catch((error) => {
    emit({ type: "error", message: error.message || String(error) });
    shutdown().finally(() => process.exit(1));
  });
});

child.on("error", (error) => emit({ type: "error", message: error.message }));
child.on("exit", (code, signal) => {
  if (!shuttingDown) emit({ type: "error", message: `ACP agent exited (${signal || code})` });
});
process.on("SIGTERM", () => shutdown().finally(() => process.exit(0)));
process.on("SIGINT", () => shutdown().finally(() => process.exit(0)));

start().catch((error) => {
  emit({ type: "error", message: error.message || String(error) });
  child.kill("SIGTERM");
  process.exit(1);
});
