#!/usr/bin/env node

import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const provider = process.env.ASK_AGENT === "codex" ? "codex" : "claude";
let choice = {};
try {
  const config = JSON.parse(readFileSync(join(here, "summarizers.json"), "utf8"));
  choice = config.main?.[provider] || {};
} catch {}

const child = spawn("node", [join(here, "..", "clickety-clacks.ask", "bridge", "bridge.js")], {
  env: {
    ...process.env,
    ASK_MODEL: provider === "codex" ? String(choice.model || "") : "",
    ASK_REASONING_EFFORT: String(choice.reasoningEffort || ""),
    ANTHROPIC_MODEL: provider === "claude" ? String(choice.model || "") : (process.env.ANTHROPIC_MODEL || ""),
  },
  stdio: ["inherit", "inherit", "inherit"],
});

for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => child.kill(signal));
}
child.on("exit", (code, signal) => {
  if (signal) process.kill(process.pid, signal);
  else process.exit(code ?? 1);
});
