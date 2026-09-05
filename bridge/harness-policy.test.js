import test from 'node:test';
import assert from 'node:assert/strict';
import { resolveHarness, resolveExecutable } from './harness-policy.js';

test('decision-request provider overrides unrelated Ask environment', () => {
  assert.equal(resolveHarness({ DR_AGENT: 'codex', ASK_AGENT: 'claude' }), 'codex');
});
test('missing system executable fails without bundled fallback', () => {
  assert.throws(() => resolveExecutable('codex', { PATH: '/nonexistent', CODEX_PATH: '/nonexistent/codex' }), /missing or not executable/);
});
test('explicit executable is resolved and validated', () => {
  assert.equal(resolveExecutable('codex', { CODEX_PATH: process.execPath }), process.execPath);
});
