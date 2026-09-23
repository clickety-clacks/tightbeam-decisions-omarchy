import { execFile, spawn } from 'node:child_process';
import { mkdir, readFile, writeFile, rename } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { resolveExecutable } from './harness-policy.js';

// Claude catalog entries such as opus[1m] are aliases that follow the installed
// Claude Code release. Ask the harness which version each alias names, once per
// release, so the picker can show it. No prompt is sent, so no tokens are used.
const here = dirname(fileURLToPath(import.meta.url));

export function versionedName(description) {
  const head = String(description || '').split(' · ')[0].replace(/\s+with\s+1M context$/i, '').trim();
  return /\d/.test(head.replace(/\([^)]*\)/g, '')) ? head : '';
}

export function labelWithVersion(entry, versions) {
  const name = versions[entry.id];
  return name ? { ...entry, label: name + (entry.id.endsWith('[1m]') ? ' (1M)' : '') } : entry;
}

async function harnessVersion(env) {
  const { stdout } = await promisify(execFile)(resolveExecutable('claude', env), ['--version'], { timeout: 5000 });
  return stdout.trim().split(/\s+/)[0];
}

function listModels(env, timeoutMs = 15000) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [join(here, 'bridge.js')], {
      env: { ...env, DR_TEST_PROVIDER: 'claude', DR_TEST_MODEL: '', DR_INSPECT_CONFIG: '1' },
      stdio: ['pipe', 'pipe', 'ignore'],
    });
    const finish = (error, versions) => { clearTimeout(timer); child.kill(); error ? reject(error) : resolve(versions); };
    const timer = setTimeout(() => finish(new Error('Timed out listing Claude models')), timeoutMs);
    let buffered = '';
    child.stdout.on('data', chunk => {
      buffered += chunk;
      let newline;
      while ((newline = buffered.indexOf('\n')) >= 0) {
        const line = buffered.slice(0, newline);
        buffered = buffered.slice(newline + 1);
        let event;
        try { event = JSON.parse(line); } catch { continue; }
        if (event.type === 'fatal') return finish(new Error(event.message));
        if (event.type !== 'config_options') continue;
        const models = event.configOptions.find(option => option.category === 'model')?.options || [];
        const versions = {};
        for (const { value, description } of models) {
          const name = versionedName(description);
          if (value !== 'default' && name) versions[value] = name;
        }
        return finish(null, versions);
      }
    });
    child.on('error', finish);
    child.on('exit', () => finish(new Error('Claude model listing ended early')));
  });
}

export async function claudeModelVersions(env = process.env) {
  const path = env.DR_MODEL_VERSIONS_PATH || join(env.HOME, '.local/state/omarchy-tightbeam-decisions/claude-model-versions.json');
  try {
    const cliVersion = await harnessVersion(env);
    let cached;
    try { cached = JSON.parse(await readFile(path, 'utf8')); } catch {}
    if (cached?.cliVersion === cliVersion) return cached.versions;
    const versions = await listModels(env);
    await mkdir(dirname(path), { recursive: true });
    const temporary = `${path}.${process.pid}.tmp`;
    await writeFile(temporary, JSON.stringify({ cliVersion, versions }, null, 2) + '\n');
    await rename(temporary, path);
    return versions;
  } catch {
    // Unknown is better than a stale version: fall back to the catalog label.
    return {};
  }
}
