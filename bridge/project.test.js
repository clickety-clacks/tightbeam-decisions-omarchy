import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import vm from 'node:vm';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const project = vm.createContext({});
vm.runInContext(readFileSync(join(root, 'project.js'), 'utf8').replace('.pragma library', ''), project);

test('product display uses recorded attribution and never agent or summary guesses', () => {
  assert.equal(project.label({project: ' Example product ', projectAttribution: 'known'}), 'EXAMPLE PRODUCT');
  for (const request of [null, {}, {project: 'Guess'}, {project: '', projectAttribution: 'known'},
    {project: 'Guess', projectAttribution: 'unresolved', raiserId: 'agent:product-owner:guess'}]) {
    assert.equal(project.label(request), 'PROJECT UNKNOWN');
    assert.ok(project.reason(request).length > 0);
  }
  assert.equal(project.reason({project: 'Example', projectAttribution: 'known'}), '');
  assert.equal(project.reason({projectUnresolvedReason: 'Assignment removed.'}), 'Assignment removed.');
});

test('fetch and handled preserve same-ID product after assignment removal and retain legacy rows', () => {
  const scratch = mkdtempSync(join(tmpdir(), 'decision-project-'));
  try {
    writeFileSync(join(scratch, 'tightbeam'), '#!/bin/sh\ncase "$1" in\n decision-requests) cat "$PROJECT_REQUEST_FIXTURE";;\n assignments) printf \'{"assignments":[]}\\n\';;\n *) exit 1;;\nesac\n', { mode: 0o755 });
    const fixture = join(scratch, 'requests.json');
    const known = {id: 'dr_recorded', kind: 'operator', question: 'Proceed?', project: 'Example',
      projectAttribution: 'known', projectUnresolvedReason: null, workItemId: 'wi_recorded',
      assignmentId: 'asg_removed', associationStatus: 'assignment-removed', options: [{label: 'accept'}]};
    const legacy = {id: 'dr_legacy', kind: 'effort', question: 'Continue?', project: null,
      projectAttribution: 'unresolved', projectUnresolvedReason: 'No project was recorded; assignment removed.'};
    const env = {...process.env, PATH: `${scratch}:${process.env.PATH}`, XDG_STATE_HOME: scratch,
      PROJECT_REQUEST_FIXTURE: fixture};
    const run = (script, args = []) => JSON.parse(execFileSync('bash', [join(root, script), '', '', ...args], {env, encoding: 'utf8'}));
    writeFileSync(fixture, JSON.stringify({decisionRequests: [known, legacy]}));
    const open = run('fetch.sh');
    assert.equal(open.count, 2);
    assert.equal(open.requests[0].project, 'Example');
    assert.equal(open.requests[0].workItemId, 'wi_recorded');
    assert.equal(open.requests[0].associationStatus, 'assignment-removed');
    assert.equal(project.label(open.requests[0]), 'EXAMPLE');
    assert.equal(project.label(open.requests[1]), 'PROJECT UNKNOWN');
    assert.match(project.reason(open.requests[1]), /assignment removed/);
    for (const status of ['withdrawn', 'ruled', 'superseded', 'consumed']) {
      writeFileSync(fixture, JSON.stringify({decisionRequests: [{...known, status, decision: 'accept', withdrawnReason: 'No longer needed.'}, legacy]}));
      const handled = run('handled.sh', [known.id]);
      assert.equal(handled.status, status);
      assert.equal(project.label(handled), project.label(open.requests[0]));
      if (status === 'withdrawn') assert.equal(handled.determination, 'No longer needed.');
    }
  } finally { rmSync(scratch, {recursive: true, force: true}); }
});
