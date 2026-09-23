import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { writeFile } from 'node:fs/promises';

const providers = ['codex', 'claude'];
async function probe(provider, model = '', discover = false, reasoningEffort = '') {
  return new Promise(resolve => {
    const child = spawn(process.execPath, [new URL('./bridge.js', import.meta.url).pathname], {
      env: { ...process.env, DR_TEST_PROVIDER: provider, DR_TEST_MODEL: model, DR_TEST_EFFORT: reasoningEffort, DR_INSPECT_CONFIG: '1', DR_CWD: '/tmp' },
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    let text = '', options = [], result, errors = '';
    const finish = value => {
      if (result) return;
      result = value;
      child.stdin.write(JSON.stringify({ type: 'close' }) + '\n');
    };
    const timer = setTimeout(() => { finish({ provider, model, ok: false, error: 'timeout' }); child.kill('SIGTERM'); }, 90000);
    child.stderr.on('data', chunk => { errors += chunk; });
    createInterface({ input: child.stdout }).on('line', line => {
      let event; try { event = JSON.parse(line); } catch { return; }
      if (event.type === 'config_options') options = event.configOptions;
      if (event.type === 'ready') {
        if (discover) finish({ provider, options });
        else child.stdin.write(JSON.stringify({ type: 'prompt', text: 'Reply with exactly MODEL_OK. Do not use tools or read files.' }) + '\n');
      }
      if (event.type === 'text') text += event.text;
      if (event.type === 'done') finish({ provider, model, ok: text.trim() === 'MODEL_OK', text });
      if (event.type === 'error' || event.type === 'fatal') finish({ provider, model, ok: false, error: event.message });
    });
    child.on('exit', () => { clearTimeout(timer); resolve(result || { provider, model, ok: false, error: errors.slice(-1000) }); });
  });
}
const results = [];
if (process.argv.includes('--discover')) {
  for (const provider of providers) { const result = await probe(provider, '', true); console.log(JSON.stringify(result)); }
} else {
  for (const arg of process.argv.slice(2)) {
    const [provider, model, effort] = arg.split(':');
    const result = await probe(provider, model, false, effort || '');
    if (effort) result.reasoningEffort = effort;
    results.push(result); console.log(JSON.stringify(result));
  }
  await writeFile(new URL('./model-probe-results.json', import.meta.url), JSON.stringify(results, null, 2) + '\n');
}
