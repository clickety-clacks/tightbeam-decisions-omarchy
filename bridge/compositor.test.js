import test from 'node:test';
import assert from 'node:assert/strict';
import { backends, detect, matchWindow } from './compositor.js';

test('the session picks the backend', () => {
  assert.equal(detect({ XDG_CURRENT_DESKTOP: 'Scottland:Wayfire:wlroots' }).name, 'scottland');
  assert.equal(detect({ XDG_CURRENT_DESKTOP: 'Hyprland' }).name, 'hyprland');
  assert.equal(detect({}).name, 'hyprland');
});

test('a window matches by exact title and owning pid', () => {
  const list = [
    { title: 'Scottland widget: Decision request — dr_1', pid: 7, address: '0x1' },
    { title: 'Decision request — dr_1', pid: 9, address: '0x2' },
    { title: 'Decision request — dr_1', pid: 7, address: '0x3' },
  ];
  assert.equal(matchWindow(list, { title: 'Decision request — dr_1', pid: 7 }).address, '0x3');
  assert.equal(matchWindow(list, { title: 'Decision request — dr_2', pid: 7 }), null);
});

test('Scottland presents by window id', async () => {
  const calls = [];
  const ok = await backends.scottland.presentWindow({ address: '0x5c070000023a', stableId: '0000023a' },
    async (method, data) => { calls.push([method, data]); return { result: 'ok' }; });
  assert.equal(ok, true);
  assert.deepEqual(calls, [['scottland/present', { window: 0x23a }]]);
});

test('an address that is not hexadecimal never reaches the compositor', async () => {
  assert.equal(await backends.scottland.presentWindow({ address: '0x1; rm', stableId: '1' },
    async () => { throw new Error('called'); }), false);
  assert.equal(await backends.hyprland.presentWindow({ address: 'nope' }), false);
});
