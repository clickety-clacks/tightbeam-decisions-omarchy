// The only place this plugin talks to the compositor. Adapted from Ask's
// bridge/compositor.js (omarchy-ask); keep the two in step until they share a
// package. Hyprland and Scottland are both supported: window records keep
// Hyprland's client shape (address, stableId, pid, title), which Scottland's
// Omarchy adapter serves through its Hyprland IPC shim, so one lookup works
// on both. Only the "present" verb differs.

import { execFile } from "node:child_process";
import { createConnection } from "node:net";
import { join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const addressPattern = /^0x[0-9a-f]+$/i;

async function clients() {
  const { stdout } = await execFileAsync("hyprctl", ["clients", "-j"], {
    timeout: 1200,
    maxBuffer: 2 * 1024 * 1024,
  });
  const parsed = JSON.parse(stdout);
  return Array.isArray(parsed) ? parsed : [];
}

// A window this process tree owns, by its exact title. The pid narrows it to
// the window host so another app's window with the same title never matches.
export function matchWindow(list, { title, pid }) {
  return list.find((client) => String(client.title || "") === String(title)
    && (!pid || Number(client.pid) === Number(pid))) || null;
}

// The only interpolation is a validated hexadecimal address.
function focusCommand(address) {
  return `hl.dsp.focus({ window = "address:${address}" })`;
}

// presentWindow: the user picked it ("I want to see this now"), so show it,
// wherever and in whatever form it is.
const hyprland = {
  name: "hyprland",
  clients,
  // Hyprland's focus already switches to the window's workspace.
  async presentWindow(window) {
    const address = String(window?.address || "");
    if (!addressPattern.test(address)) return false;
    await execFileAsync("hyprctl", ["eval", `hl.dispatch(${focusCommand(address)})`], { timeout: 1200 });
    return true;
  },
};

function wayfireSocket(env = process.env) {
  if (env.WAYFIRE_SOCKET) return env.WAYFIRE_SOCKET;
  if (env.XDG_RUNTIME_DIR && env.WAYLAND_DISPLAY)
    return join(env.XDG_RUNTIME_DIR, `wayfire-${env.WAYLAND_DISPLAY}-.socket`);
  return "";
}

// One request on Wayfire's IPC socket: a little-endian length, then JSON.
export function wayfireCall(method, data, socketPath = wayfireSocket(), timeoutMs = 1200) {
  return new Promise((resolve, reject) => {
    if (!socketPath) { reject(new Error("no Wayfire IPC socket")); return; }
    const socket = createConnection(socketPath);
    let buffer = Buffer.alloc(0);
    const timer = setTimeout(() => { socket.destroy(); reject(new Error("Wayfire IPC timed out")); }, timeoutMs);
    const done = (error, value) => { clearTimeout(timer); socket.destroy(); error ? reject(error) : resolve(value); };
    socket.on("connect", () => {
      const body = Buffer.from(JSON.stringify({ method, data }));
      const header = Buffer.alloc(4);
      header.writeUInt32LE(body.length);
      socket.write(Buffer.concat([header, body]));
    });
    socket.on("data", (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);
      if (buffer.length < 4) return;
      const size = buffer.readUInt32LE(0);
      if (buffer.length < 4 + size) return;
      try { done(null, JSON.parse(buffer.subarray(4, 4 + size).toString("utf8"))); }
      catch (error) { done(error); }
    });
    socket.on("error", (error) => done(error));
  });
}

// Scottland's present request (core L30) opens a widget back into its window
// and brings a side window to the middle at 100%, raised and focused. The
// shim's stableId is the Scottland window id in hex. A Scottland build
// without the request still gets the window focused through the shim, which
// answers `dispatch` but not `eval`.
const scottland = {
  name: "scottland",
  clients,
  async presentWindow(window, call = wayfireCall) {
    const address = String(window?.address || "");
    if (!addressPattern.test(address)) return false;
    try {
      const id = Number.parseInt(String(window?.stableId || ""), 16);
      if (Number.isSafeInteger(id) && id > 0) {
        const reply = await call("scottland/present", { window: id });
        if (reply && !reply.error && reply.result !== "error") return true;
      }
    } catch { }
    await execFileAsync("hyprctl", ["dispatch", focusCommand(address)], { timeout: 1200 });
    return true;
  },
};

export const backends = { hyprland, scottland };

// Chosen from the session this runs in, never by probing for the first
// compositor that answers.
export function detect(env = process.env) {
  const desktops = String(env.XDG_CURRENT_DESKTOP || "").split(":")
    .map((name) => name.trim().toLowerCase());
  if (desktops.includes("scottland")) return scottland;
  return hyprland;
}

export const compositor = detect();
