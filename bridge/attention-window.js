#!/usr/bin/env node
// Mark one of this host's decision windows as needing attention. Scottland's
// activation protocol can interpret a request from the shared window host as
// user-initiated focus, so use its per-window attention IPC instead.
import { compositor, matchWindow } from "./compositor.js";

const title = process.argv[2] || "";
const pid = Number(process.env.DR_WINDOW_PID || process.ppid);

async function main() {
  if (!title || compositor.name !== "scottland") return 2;
  for (let attempt = 0; attempt < 20; attempt++) {
    const window = matchWindow(await compositor.clients(), { title, pid });
    if (window) return await compositor.attendWindow(window) ? 0 : 1;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  console.error(`attention-window: no window titled ${JSON.stringify(title)} for pid ${pid}`);
  return 1;
}

main().then((code) => process.exit(code), (error) => {
  console.error(`attention-window: ${error.message}`);
  process.exit(1);
});
