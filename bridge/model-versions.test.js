import test from 'node:test';
import assert from 'node:assert/strict';
import { versionedName, labelWithVersion, claudeModelVersions, claudeVersionLabels } from './model-versions.js';

test('versionedName reads the version from the harness description', () => {
  assert.equal(versionedName('Opus 5.5 with 1M context · Best for everyday, complex tasks'), 'Opus 5.5');
  assert.equal(versionedName('Opus 5.5 (1M context)'), 'Opus 5.5');
  assert.equal(versionedName('Haiku 4.5 · Fastest for quick answers'), 'Haiku 4.5');
  assert.equal(versionedName('Opus (1M context)'), '');
  assert.equal(versionedName(undefined), '');
});

test('labelWithVersion shows the resolved version and keeps the 1M marker', () => {
  const versions = { 'opus[1m]': 'Opus 5.5', sonnet: 'Sonnet 5' };
  assert.deepEqual(labelWithVersion({ id: 'opus[1m]', label: 'Opus (1M)', testNote: 'n' }, versions),
    { id: 'opus[1m]', label: 'Opus 5.5 (1M)', testNote: 'n' });
  assert.equal(labelWithVersion({ id: 'sonnet', label: 'Sonnet' }, versions).label, 'Sonnet 5');
  assert.equal(labelWithVersion({ id: 'haiku', label: 'Haiku' }, versions).label, 'Haiku');
  assert.equal(labelWithVersion({ id: 'opus[1m]', label: 'Opus (1M)' }, { opus: 'Opus 5.5' }).label, 'Opus 5.5 (1M)');
});

test('Claude model display names supply version numbers when descriptions do not', () => {
  assert.deepEqual(claudeVersionLabels([
    { value: 'opus[1m]', name: 'Opus 5.5 (1M context)', description: 'Best for complex tasks' },
    { value: 'sonnet', name: 'Sonnet 5', description: 'Fast and capable' },
    { value: 'default', name: 'Default', description: 'Opus 5.5' },
  ]), { 'opus[1m]': 'Opus 5.5', sonnet: 'Sonnet 5' });
});

test('claudeModelVersions falls back to no versions when the harness is missing', async () => {
  const env = { ...process.env, CLAUDE_CODE_EXECUTABLE: '/nonexistent/claude', DR_MODEL_VERSIONS_PATH: '/nonexistent/versions.json' };
  assert.deepEqual(await claudeModelVersions(env), {});
});
