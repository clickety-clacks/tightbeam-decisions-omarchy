import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readSelection, saveSelection, effectiveSelection, levelsFor } from './model-settings.js';
const catalog = JSON.parse(await readFile(new URL('./model-catalog.json', import.meta.url)));
test('thinking levels persist, reach both roles, and reject unsupported model combinations', async () => {
  const path = join(await mkdtemp(join(tmpdir(), 'dr-effort-test-')), 'selection.json');
  for (const [provider, models] of Object.entries(catalog)) for (const {id: model} of models) {
    for (const effort of levelsFor(provider, model)) {
      const saved = await saveSelection(path, provider, model, catalog, effort);
      assert.deepEqual(await readSelection(path, {}, catalog), saved);
      for (const role of ['main', 'parentNotes']) assert.equal(effectiveSelection(saved, {}, role).reasoningEffort || '', effort);
    }
  }
  await assert.rejects(saveSelection(path, 'codex', 'gpt-5.6-luna', catalog, 'ultra'));
  await assert.rejects(saveSelection(path, 'codex', 'gpt-5.5', catalog, 'max'));
  await assert.rejects(saveSelection(path, 'claude', 'sonnet', catalog, 'ultra'));
});
for (const [provider, models] of Object.entries(catalog)) test(`${provider}: every offered identifier has a successful real bridge probe`, async () => {
  const file = provider === 'codex' ? './model-probe-results-codex-plumbus.json' : './model-probe-results-claude-osanwe.json';
  const results = JSON.parse(await readFile(new URL(file, import.meta.url)));
  for (const model of models) {
    const result = results.find(r => r.provider === provider && r.model === model.id);
    assert.ok(result, `${provider}:${model.id}`);
    assert.equal(result.ok, true, `${provider}:${model.id}: ${result.error || result.text || 'no successful reply'}`);
    assert.equal(result.text.trim(), 'MODEL_OK', `${provider}:${model.id}: unexpected reply`);
  }
});
test('shared choice overrides both roles, legacy defaults and provider environment', () => {
  const fallback = { provider: 'claude', main: { claude: { model: 'opus' } }, parentNotes: { claude: { model: 'haiku' } } };
  for (const role of ['main', 'parentNotes']) {
    assert.deepEqual(effectiveSelection({ provider: 'codex', model: 'gpt-5.6-luna' }, fallback, role, { DR_AGENT: 'claude' }), { provider: 'codex', model: 'gpt-5.6-luna' });
  }
  assert.deepEqual(effectiveSelection({}, fallback, 'parentNotes'), { provider: 'claude', model: 'haiku' });
});
test('selection persists across readers and both harnesses; rejects unknown IDs', async () => {
  const path = join(await mkdtemp(join(tmpdir(), 'dr-settings-test-')), 'selection.json');
  for (const [provider, models] of Object.entries(catalog)) for (const { id: model } of models) {
    await saveSelection(path, provider, model, catalog);
    assert.deepEqual(await readSelection(path, {}, catalog), { provider, model });
  }
  const previous = await readFile(path, 'utf8');
  await assert.rejects(saveSelection(path, 'claude', 'opus-4.8', catalog));
  await assert.rejects(saveSelection(path, 'bogus', 'anything', catalog));
  assert.equal(await readFile(path, 'utf8'), previous);
  await writeFile(path, '{');
  await assert.rejects(readSelection(path, {}, catalog));
});
