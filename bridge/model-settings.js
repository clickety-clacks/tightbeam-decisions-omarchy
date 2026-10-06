import { mkdir, readFile, writeFile, rename } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolveHarness } from './harness-policy.js';
import { claudeModelVersions, codexModelCatalog, labelWithVersion } from './model-versions.js';

export function effectiveSelection(shared, fallback, role, env = process.env) {
  const provider = resolveHarness({ ...env, DR_AGENT: shared.provider || fallback.provider || env.DR_AGENT });
  return { provider, ...(shared.provider ? shared : fallback[role]?.[provider] || {}) };
}

export async function readSelection(path, fallback, catalog) {
  let selected;
  try { selected = JSON.parse(await readFile(path, 'utf8')); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (selected) return selected;
  const provider = fallback.provider || resolveHarness();
  const choice = fallback.main?.[provider] || {};
  return { provider, model: choice.model || catalog[provider][0].id, ...(choice.reasoningEffort ? {reasoningEffort: choice.reasoningEffort} : {}) };
}

export const thinkingLevels = { codex: ['', 'low', 'medium', 'high', 'xhigh', 'max', 'ultra'], claude: ['', 'low', 'medium', 'high', 'xhigh', 'max'] };
export function levelsFor(provider, model) {
  if (provider === 'codex' && ['gpt-5.5', 'gpt-5.3-codex-spark'].includes(model)) return thinkingLevels.codex.slice(0, 5);
  if (provider === 'codex' && model === 'gpt-5.6-luna') return thinkingLevels.codex.slice(0, 6);
  return thinkingLevels[provider] || [''];
}

export async function saveSelection(path, provider, model, catalog, reasoningEffort = '') {
  if (!catalog[provider]?.some(item => item.id === model)) throw new Error('Choose a tested harness/model combination.');
  if (!levelsFor(provider, model).includes(reasoningEffort)) throw new Error('Choose a supported thinking level.');
  const selected = { provider, model, ...(reasoningEffort ? { reasoningEffort } : {}) };
  await mkdir(dirname(path), { recursive: true });
  const temporary = `${path}.${process.pid}.tmp`;
  await writeFile(temporary, JSON.stringify(selected, null, 2) + '\n', { mode: 0o600 });
  await rename(temporary, path);
  return selected;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const catalog = JSON.parse(await readFile(new URL('./model-catalog.json', import.meta.url), 'utf8'));
    const fallback = JSON.parse(await readFile(new URL('../summarizers.json', import.meta.url), 'utf8'));
    const path = process.env.DR_MODEL_SETTINGS_PATH || join(process.env.HOME, '.config/omarchy/tightbeam-decisions-model.json');
    if (process.argv[2] !== 'save' || process.argv[3] === 'codex')
      catalog.codex = await codexModelCatalog(catalog.codex);
    const selected = process.argv[2] === 'save'
      ? await saveSelection(path, process.argv[3], process.argv[4], catalog, process.argv[5] || '')
      : await readSelection(path, fallback, catalog);
    if (process.argv[2] !== 'save' && catalog.claude) {
      const versions = await claudeModelVersions();
      catalog.claude = catalog.claude.map(entry => labelWithVersion(entry, versions));
    }
    const levelsByModel = Object.fromEntries(Object.entries(catalog).flatMap(([provider, models]) => models.map(({id}) => [id, levelsFor(provider, id)])));
    console.log(JSON.stringify({ selected, catalog, thinkingLevels: levelsByModel }));
  } catch (error) { console.log(JSON.stringify({ error: error.message })); process.exitCode = 1; }
}
