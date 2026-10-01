#!/usr/bin/env node
// present-window.js <title>: show one of the window host's own windows
// ("I want to see this now"). Run by the host as a direct child, so the
// parent pid identifies the host's windows. A window that was just created
// may not be mapped yet, so look for it briefly before giving up.
import { compositor, matchWindow } from "./compositor.js";

const title = process.argv[2] || "";
const pid = Number(process.env.DR_WINDOW_PID || process.ppid);

async function main() {
  if (!title) { console.error("usage: present-window.js <title>"); return 2; }
  for (let attempt = 0; attempt < 20; attempt++) {
    const window = matchWindow(await compositor.clients(), { title, pid });
    if (window) return await compositor.presentWindow(window) ? 0 : 1;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  console.error(`present-window: no window titled ${JSON.stringify(title)} for pid ${pid}`);
  return 1;
}

main().then((code) => process.exit(code), (error) => {
  console.error(`present-window (${compositor.name}): ${error.message}`);
  process.exit(1);
});
